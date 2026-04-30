import Foundation

/// End-to-end RAG pipeline for iOS.
/// Mirrors Python's RAGPipeline: query -> embed -> retrieve -> build prompt -> generate.
///
/// Retrieval strategy:
/// 1. Keyword search to find candidate chunks (BM25-like lexical matching)
/// 2. Build pseudo query embedding from keyword-matched chunks' pre-computed embeddings
/// 3. Dense vector search using pseudo embedding
/// 4. Hybrid re-ranking: alpha * dense_score + (1-alpha) * lexical_score + source_boost
/// 5. Build prompt with top-k context chunks
/// 6. Generate answer with llama.cpp (Gemma GGUF)
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

    /// Execute a full RAG query. Call from main actor context.
    @MainActor
    func query(question: String, includeImages: Bool = false) async throws -> RAGResponse {
        let overallStart = CFAbsoluteTimeGetCurrent()

        let visualIntent = KeywordSearch.isVisualIntent(question)
        let (normalizedQuestion, factualQuestion) = KeywordSearch.normalizeQuestion(question)
        let allowImages = includeImages && visualIntent && config.maxImages > 0

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
            // Create pseudo embedding from keyword-matched chunks
            let matchedIds = keywordResults.map { $0.chunkId }
            let weights = keywordResults.map { $0.lexicalScore + $0.sourceScore }
            let queryEmbedding = vectorStore.pseudoQueryEmbedding(
                fromChunkIds: matchedIds,
                weights: weights
            )

            // Dense search
            let denseResults = vectorStore.search(
                queryEmbedding: queryEmbedding,
                topK: config.searchPoolK
            )

            // Build retrieval pool with hybrid scores
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

        // If no dense results, fall back to pure keyword results
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

        // Source-focused filtering (matching Python logic)
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

        // Sort and select top-k
        effectivePool.sort { $0.hybridScore > $1.hybridScore }
        let selectedItems = Array(effectivePool.prefix(config.topK))

        // Compute confidence
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

        for (rank, item) in selectedItems.enumerated() {
            var chunkText = item.chunk.text
            // Add source metadata
            var sourceInfo = "[Source: \(item.chunk.sourceFile)"
            if let page = item.chunk.pageNumber {
                sourceInfo += ", page \(page + 1)"
            }
            sourceInfo += "]"
            chunkText = "\(sourceInfo)\n\(chunkText)"

            // Respect context char limit
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

            retrievedChunks.append(RetrievedChunk(
                chunk: item.chunk,
                denseScore: item.denseScore,
                lexicalScore: item.lexicalScore,
                sourceScore: item.sourceScore,
                hybridScore: item.hybridScore,
                rank: rank
            ))

            // Collect image candidates
            if allowImages {
                for img in item.chunk.associatedImages {
                    let ocrMatch: Float
                    if let ocr = img.ocrSnippet, !ocr.isEmpty {
                        ocrMatch = KeywordSearch.lexicalScore(query: factualQuestion, chunkText: ocr)
                    } else {
                        ocrMatch = 0
                    }

                    let area = Float(img.width * img.height)
                    let score = area
                        + Float(1.0 / (1.0 + Float(rank))) * 50_000.0
                        + item.denseScore * 25_000.0
                        + item.sourceScore * 40_000.0
                        + ocrMatch * 50_000.0
                        - (img.ocrSnippet?.isEmpty ?? true ? 35_000.0 : 0)
                        + Float(img.textDensity ?? 0) * 25_000.0

                    imageCandidates.append((path: img.path, score: score, ocrMatch: ocrMatch))
                }
            }
        }

        // Select best evidence images
        if allowImages && !imageCandidates.isEmpty && confidence >= config.imageMinConfidence {
            // Deduplicate by path (keep highest score)
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

        // 5. Generate
        let genResult = try await llamaRunner.generate(prompt: prompt)

        let totalTimeMs = Float((CFAbsoluteTimeGetCurrent() - overallStart) * 1000)

        return RAGResponse(
            question: question,
            answer: genResult.text,
            retrievedChunks: retrievedChunks,
            associatedImages: associatedImages,
            tokensGenerated: genResult.tokensGenerated,
            tokensPerSecond: genResult.tokensPerSecond,
            ttftMs: genResult.ttftMs,
            totalTimeMs: totalTimeMs,
            retrievalTimeMs: retrievalTimeMs,
            embeddingTimeMs: embeddingTimeMs,
            retrievalConfidence: confidence
        )
    }
}

// MARK: - Internal types

private struct RetrievalCandidate {
    let chunkId: String
    let chunk: ChunkData
    let denseScore: Float
    let lexicalScore: Float
    let sourceScore: Float
    var hybridScore: Float
}
