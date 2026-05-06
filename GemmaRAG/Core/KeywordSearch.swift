import Foundation

/// BM25-like keyword search for retrieval when no embedding model is available.
/// Mirrors the lexical scoring component from Python's RAGPipeline._lexical_score().
class KeywordSearch {

    /// Stopwords matching the Python pipeline.
    private static let stopwords: Set<String> = [
        "and", "the", "for", "with", "from", "this", "that", "are", "you", "your",
        "is", "it", "in", "to", "of", "a", "an", "on", "at", "by", "or", "be",
        "was", "were", "been", "has", "have", "had", "do", "does", "did", "will",
        "would", "could", "should", "may", "might", "can", "not", "no", "but",
    ]

    /// Visual intent keywords (mirrors Python _is_visual_intent).
    private static let visualHints: [String] = [
        "show", "image", "picture", "photo", "visual", "layout", "planogram",
        "where in image", "see in image", "what does it look like",
        "pokaz", "obraz", "obrazek", "zdjecie", "uklad",
    ]

    /// Visual wrapper patterns to strip before retrieval.
    private static let visualStripPatterns: [String] = [
        "show me", "show an", "show a", "show the", "display",
        "with an image", "with image", "with a picture",
        "include image", "include an image",
        "and image", "and an image",
        "z obrazkiem",
    ]

    /// Tokenize text into lowercased tokens of 3+ chars, excluding stopwords.
    /// Matches Python _tokenize().
    static func tokenize(_ text: String) -> Set<String> {
        let lowered = text.lowercased()
        let pattern = try! NSRegularExpression(pattern: "[a-z0-9]{2,}")
        let range = NSRange(lowered.startIndex..., in: lowered)
        let matches = pattern.matches(in: lowered, range: range)

        var tokens = Set<String>()
        for match in matches {
            if let r = Range(match.range, in: lowered) {
                let tok = String(lowered[r])
                if !stopwords.contains(tok) {
                    tokens.insert(tok)
                }
            }
        }
        return tokens
    }

    /// Check if the question has visual intent (user wants images).
    static func isVisualIntent(_ question: String) -> Bool {
        let normalized = question.lowercased().trimmingCharacters(in: .whitespaces)
        return visualHints.contains { normalized.contains($0) }
    }

    /// Strip visual wrappers from question for better retrieval.
    /// Returns (original_normalized, factual_question).
    static func normalizeQuestion(_ question: String) -> (original: String, factual: String) {
        let original = question.lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")

        var factual = original
        for pattern in visualStripPatterns {
            factual = factual.replacingOccurrences(of: pattern, with: " ")
        }
        factual = factual.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        if factual.isEmpty { factual = original }

        return (original, factual)
    }

    /// Compute lexical overlap score between query and chunk text.
    /// Matches Python _lexical_score().
    static func lexicalScore(query: String, chunkText: String) -> Float {
        let qTokens = tokenize(query)
        guard !qTokens.isEmpty else { return 0 }
        let cTokens = tokenize(chunkText)
        guard !cTokens.isEmpty else { return 0 }
        let overlap = qTokens.intersection(cTokens).count
        return Float(overlap) / Float(max(1, qTokens.count))
    }

    /// Compute source filename match score.
    /// Matches Python _source_match_score().
    static func sourceMatchScore(question: String, sourceFile: String) -> Float {
        let qTokens = tokenize(question)
        let sTokens = tokenize(sourceFile.replacingOccurrences(of: "-", with: " "))
        guard !qTokens.isEmpty, !sTokens.isEmpty else { return 0 }
        let overlap = qTokens.intersection(sTokens).count
        return Float(overlap) / Float(max(1, sTokens.count))
    }

    /// Compute source consistency across selected items.
    static func sourceConsistency(sourceFiles: [String]) -> Float {
        guard !sourceFiles.isEmpty else { return 0 }
        var counts: [String: Int] = [:]
        for src in sourceFiles {
            counts[src, default: 0] += 1
        }
        let best = counts.values.max() ?? 0
        return Float(best) / Float(sourceFiles.count)
    }

    /// Compute retrieval confidence score.
    /// Matches Python _compute_retrieval_confidence().
    static func retrievalConfidence(
        topItems: [(denseScore: Float, lexicalScore: Float)],
        sourceConsistency: Float
    ) -> Float {
        guard !topItems.isEmpty else { return 0 }
        let top1Dense = topItems[0].denseScore
        let top2Dense = topItems.count > 1 ? topItems[1].denseScore : top1Dense
        let topLexical = topItems[0].lexicalScore
        let margin = max(0, top1Dense - top2Dense)

        let denseComponent = min(1, max(0, (top1Dense - 0.22) / 0.55))
        let marginComponent = min(1, max(0, margin / 0.15))
        let lexicalComponent = min(1, max(0, topLexical))
        let srcComponent = min(1, max(0, sourceConsistency))

        let confidence = 0.35 * denseComponent
            + 0.45 * lexicalComponent
            + 0.10 * marginComponent
            + 0.10 * srcComponent

        return min(1, max(0, confidence))
    }

    /// Full keyword-based search across all chunks.
    /// Returns chunk IDs sorted by lexical relevance.
    static func search(
        query: String,
        chunks: [String: ChunkData],
        chunkIds: [String],
        topK: Int = 12
    ) -> [(chunkId: String, lexicalScore: Float, sourceScore: Float)] {
        let (_, factualQuery) = normalizeQuestion(query)

        var results: [(chunkId: String, lexicalScore: Float, sourceScore: Float)] = []
        for cid in chunkIds {
            guard let chunk = chunks[cid] else { continue }
            let lex = lexicalScore(query: factualQuery, chunkText: chunk.text)
            let src = sourceMatchScore(question: factualQuery, sourceFile: chunk.sourceFile)
            if lex > 0 || src > 0.3 {
                results.append((cid, lex, src))
            }
        }

        results.sort { ($0.lexicalScore + $0.sourceScore) > ($1.lexicalScore + $1.sourceScore) }
        return Array(results.prefix(topK))
    }
}
