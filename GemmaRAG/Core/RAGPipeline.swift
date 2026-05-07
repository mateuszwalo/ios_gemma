import Foundation

class RAGPipeline {
    let chunkStore: ChunkStore
    let vectorStore: VectorStore
    let llamaRunner: LlamaRunner
    let config: RAGConfig

    init(
        chunkStore: ChunkStore,
        vectorStore: VectorStore,
        llamaRunner: LlamaRunner,
        config: RAGConfig = RAGConfig()
    ) {
        self.chunkStore = chunkStore
        self.vectorStore = vectorStore
        self.llamaRunner = llamaRunner
        self.config = config
    }

    @MainActor
    func query(question: String, includeImages: Bool = false) async throws -> RAGResponse {
        let overallStart = CFAbsoluteTimeGetCurrent()

        let (normalizedQuestion, factualQuestion) = KeywordSearch.normalizeQuestion(question)
        let allowImages = includeImages && config.maxImages > 0

        // 1. Keyword search for initial candidates
        let embeddingStart = CFAbsoluteTimeGetCurrent()
        let keywordResults = KeywordSearch.search(
            query: factualQuestion,
            chunks: chunkStore.chunks,
            chunkIds: chunkStore.orderedChunkIds,
            topK: config.searchPoolK
        )
        let embeddingTimeMs = Float((CFAbsoluteTimeGetCurrent() - embeddingStart) * 1000)

        // 2. Build pseudo query embedding from keyword matches
        let retrievalStart = CFAbsoluteTimeGetCurrent()
        var retrievalPool: [RetrievalCandidate] = []

        if vectorStore.isLoaded && !keywordResults.isEmpty {
            let matchedIds = keywordResults.map { $0.chunkId }
            let weights = keywordResults.map { $0.lexicalScore + $0.sourceScore }
            let queryEmbedding = vectorStore.pseudoQueryEmbedding(
                fromChunkIds: matchedIds,
                weights: weights
            )

            let denseResults = vectorStore.search(
                queryEmbedding: queryEmbedding,
                topK: config.searchPoolK
            )

            for denseResult in denseResults {
                guard let chunk = chunkStore.chunk(for: denseResult.chunkId) else { continue }
                let lexical = KeywordSearch.lexicalScore(query: factualQuestion, chunkText: chunk.text)
                let source = KeywordSearch.sourceMatchScore(
                    question: normalizedQuestion,
                    sourceFile: chunk.sourceFile
                )
                let hybrid = config.rerankAlpha * denseResult.score
                    + (1.0 - config.rerankAlpha) * lexical
                    + config.sourceBoost * source

                retrievalPool.append(RetrievalCandidate(
                    chunkId: denseResult.chunkId,
                    chunk: chunk,
                    denseScore: denseResult.score,
                    lexicalScore: lexical,
                    sourceScore: source,
                    hybridScore: hybrid
                ))
            }
        }

        if retrievalPool.isEmpty {
            for kw in keywordResults {
                guard let chunk = chunkStore.chunk(for: kw.chunkId) else { continue }
                retrievalPool.append(RetrievalCandidate(
                    chunkId: kw.chunkId,
                    chunk: chunk,
                    denseScore: 0,
                    lexicalScore: kw.lexicalScore,
                    sourceScore: kw.sourceScore,
                    hybridScore: kw.lexicalScore + config.sourceBoost * kw.sourceScore
                ))
            }
        }

        // Source-focused filtering
        var effectivePool = retrievalPool
        if !retrievalPool.isEmpty {
            let maxSourceScore = retrievalPool.map(\.sourceScore).max() ?? 0
            if maxSourceScore >= 0.8 {
                let focused = retrievalPool.filter { $0.sourceScore >= maxSourceScore }
                if !focused.isEmpty {
                    effectivePool = focused
                }
            }
        }

        effectivePool.sort { $0.hybridScore > $1.hybridScore }
        let selectedItems = Array(effectivePool.prefix(config.topK))

        let srcConsistency = KeywordSearch.sourceConsistency(
            sourceFiles: selectedItems.map { $0.chunk.sourceFile }
        )
        let confidence = KeywordSearch.retrievalConfidence(
            topItems: selectedItems.map { (denseScore: $0.denseScore, lexicalScore: $0.lexicalScore) },
            sourceConsistency: srcConsistency
        )

        let retrievalTimeMs = Float((CFAbsoluteTimeGetCurrent() - retrievalStart) * 1000)

        // 3. Build context
        var contextParts: [String] = []
        var retrievedChunks: [RetrievedChunk] = []
        var associatedImages: [String] = []
        var imageCandidates: [(path: String, score: Float, ocrMatch: Float)] = []
        var currentContextChars = 0
        let separator = "\n\n---\n\n"
        var selectedSourceFiles: Set<String> = []

        for (rank, item) in selectedItems.enumerated() {
            if Self.isGarbageChunk(item.chunk.text) { continue }

            var chunkText = item.chunk.text
            var sourceInfo = "[Source: \(item.chunk.sourceFile)"
            if let page = item.chunk.pageNumber {
                sourceInfo += ", page \(page + 1)"
            }
            sourceInfo += "]"
            chunkText = "\(sourceInfo)\n\(chunkText)"

            let extra = chunkText.count + (contextParts.isEmpty ? 0 : separator.count)
            let remaining = config.maxContextChars - currentContextChars
            if remaining <= 0 { break }
            if extra > remaining {
                let truncateTo = max(0, remaining - (contextParts.isEmpty ? 0 : separator.count))
                chunkText = String(chunkText.prefix(truncateTo)).trimmingCharacters(in: .whitespaces)
                if chunkText.isEmpty { break }
            }

            if contextParts.count >= config.maxContextChunks { break }

            contextParts.append(chunkText)
            currentContextChars += chunkText.count + (contextParts.count > 1 ? separator.count : 0)
            selectedSourceFiles.insert(item.chunk.sourceFile)

            retrievedChunks.append(RetrievedChunk(
                chunk: item.chunk,
                denseScore: item.denseScore,
                lexicalScore: item.lexicalScore,
                sourceScore: item.sourceScore,
                hybridScore: item.hybridScore,
                rank: rank
            ))

            if allowImages {
                collectImageCandidates(
                    from: item.chunk,
                    rank: rank,
                    sameSource: item.chunk.sourceFile == selectedItems.first?.chunk.sourceFile,
                    denseScore: item.denseScore,
                    factualQuestion: factualQuestion,
                    into: &imageCandidates
                )
            }
        }

        // Source-based image fallback: if top chunks had no images,
        // find sibling chunks from the same source that DO have images
        if allowImages && imageCandidates.isEmpty && !selectedSourceFiles.isEmpty {
            let topSource = selectedItems.first?.chunk.sourceFile ?? ""
            for chunkId in chunkStore.orderedChunkIds {
                guard let chunk = chunkStore.chunk(for: chunkId),
                      chunk.sourceFile == topSource,
                      !chunk.associatedImages.isEmpty else { continue }
                collectImageCandidates(
                    from: chunk,
                    rank: selectedItems.count,
                    sameSource: true,
                    denseScore: 0.5,
                    factualQuestion: factualQuestion,
                    into: &imageCandidates
                )
                if imageCandidates.count >= config.maxImages { break }
            }
        }

        // Select best evidence images
        if allowImages && !imageCandidates.isEmpty && confidence >= config.imageMinConfidence {
            var dedup: [String: (path: String, score: Float, ocrMatch: Float)] = [:]
            for img in imageCandidates {
                if dedup[img.path] == nil || img.score > dedup[img.path]!.score {
                    dedup[img.path] = img
                }
            }
            let ranked = dedup.values.sorted { $0.score > $1.score }
            let filtered = ranked.filter { $0.ocrMatch >= config.minImageOcrMatch }
            associatedImages = filtered.prefix(config.maxImages).map { $0.path }
        }

        let context = contextParts.joined(separator: separator)

        // 4. Build prompt
        let prompt = config.promptTemplate
            .replacingOccurrences(of: "{context}", with: context)
            .replacingOccurrences(of: "{question}", with: factualQuestion)

        // 5. Generate (with retry on empty)
        var genResult = try await llamaRunner.generate(prompt: prompt)

        if genResult.tokensGenerated == 0 {
            let retryPrompt = prompt + "Answer: "
            genResult = try await llamaRunner.generate(
                prompt: retryPrompt,
                temperatureOverride: config.retryTemperature
            )
        }

        let totalTimeMs = Float((CFAbsoluteTimeGetCurrent() - overallStart) * 1000)

        return RAGResponse(
            question: question,
            answer: genResult.text,
            retrievedChunks: retrievedChunks,
            associatedImages: associatedImages,
            tokensGenerated: genResult.tokensGenerated,
            promptTokens: genResult.promptTokens,
            tokensPerSecond: genResult.tokensPerSecond,
            ttftMs: genResult.ttftMs,
            totalTimeMs: totalTimeMs,
            retrievalTimeMs: retrievalTimeMs,
            embeddingTimeMs: embeddingTimeMs,
            retrievalConfidence: confidence
        )
    }

    private func collectImageCandidates(
        from chunk: ChunkData,
        rank: Int,
        sameSource: Bool,
        denseScore: Float,
        factualQuestion: String,
        into candidates: inout [(path: String, score: Float, ocrMatch: Float)]
    ) {
        for img in chunk.associatedImages {
            let ocrMatch: Float
            if let ocr = img.ocrSnippet, !ocr.isEmpty {
                ocrMatch = KeywordSearch.lexicalScore(query: factualQuestion, chunkText: ocr)
            } else {
                ocrMatch = 0
            }

            let rankBonus = Float(1.0 / (1.0 + Float(rank))) * 40_000.0
            let sourceBonus: Float = sameSource ? 60_000.0 : 0
            let denseBonus = denseScore * 30_000.0
            let ocrBonus = ocrMatch * 50_000.0
            let hasOcrPenalty: Float = (img.ocrSnippet?.isEmpty ?? true) ? -30_000.0 : 0
            let densityBonus = Float(img.textDensity ?? 0) * 20_000.0

            let score = rankBonus + sourceBonus + denseBonus + ocrBonus + hasOcrPenalty + densityBonus

            candidates.append((path: img.path, score: score, ocrMatch: ocrMatch))
        }
    }

    static func isGarbageChunk(_ text: String) -> Bool {
        if text.count < 150 { return true }
        if text.count >= 300 { return false }
        var letterCount = 0
        for c in text where c.isLetter { letterCount += 1 }
        return Float(letterCount) / Float(text.count) < 0.3
    }
}

private struct RetrievalCandidate {
    let chunkId: String
    let chunk: ChunkData
    let denseScore: Float
    let lexicalScore: Float
    let sourceScore: Float
    var hybridScore: Float
}
