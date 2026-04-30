import Foundation
import Accelerate

/// Brute-force cosine similarity vector store.
/// Loads pre-computed corpus embeddings (float32 binary) and does exact nearest-neighbor search.
/// Uses Apple Accelerate (vDSP) for fast SIMD dot products on M4.
///
/// This replaces FAISS/SQLite-VSS/usearch from the Python PoC.
/// For 1756 vectors x 384 dimensions, search takes <1ms on M4.
class VectorStore {
    private var embeddings: [Float] = []
    private var chunkIds: [String] = []
    private var dimension: Int = 384
    private var count: Int = 0

    var isLoaded: Bool { count > 0 }

    /// Load pre-computed corpus embeddings from raw float32 binary file.
    /// File format: N x D float32 values in row-major order (matching numpy .tobytes()).
    func load(embeddingsURL: URL, chunkIds: [String], dimension: Int = 384) throws {
        self.dimension = dimension
        self.chunkIds = chunkIds

        let data = try Data(contentsOf: embeddingsURL)
        let expectedCount = chunkIds.count
        let expectedBytes = expectedCount * dimension * MemoryLayout<Float>.size

        guard data.count >= expectedBytes else {
            throw VectorStoreError.sizeMismatch(
                "Expected \(expectedBytes) bytes for \(expectedCount) vectors, got \(data.count)"
            )
        }

        self.count = expectedCount
        self.embeddings = [Float](repeating: 0, count: count * dimension)

        data.withUnsafeBytes { rawPtr in
            let floatPtr = rawPtr.bindMemory(to: Float.self)
            for i in 0..<(count * dimension) {
                self.embeddings[i] = floatPtr[i]
            }
        }

        // L2-normalize all vectors for cosine similarity via dot product
        for i in 0..<count {
            normalizeVector(at: i)
        }
    }

    /// Search for top-k most similar vectors to the query embedding.
    /// Returns results sorted by descending cosine similarity.
    func search(queryEmbedding: [Float], topK: Int = 3) -> [VectorSearchResult] {
        guard isLoaded, queryEmbedding.count == dimension else { return [] }

        // Normalize query
        var query = queryEmbedding
        var norm: Float = 0
        vDSP_dotpr(query, 1, query, 1, &norm, vDSP_Length(dimension))
        norm = sqrtf(norm)
        if norm > 0 {
            var invNorm = 1.0 / norm
            vDSP_vsmul(query, 1, &invNorm, &query, 1, vDSP_Length(dimension))
        }

        // Compute dot products (= cosine similarity since both are normalized)
        var scores = [Float](repeating: 0, count: count)

        scores.withUnsafeMutableBufferPointer { sBuf in
            query.withUnsafeBufferPointer { qBuf in
                embeddings.withUnsafeBufferPointer { eBuf in
                    guard let sPtr = sBuf.baseAddress,
                          let qPtr = qBuf.baseAddress,
                          let ePtr = eBuf.baseAddress else { return }
                    for i in 0..<self.count {
                        vDSP_dotpr(
                            qPtr, 1,
                            ePtr.advanced(by: i * self.dimension), 1,
                            sPtr.advanced(by: i),
                            vDSP_Length(self.dimension)
                        )
                    }
                }
            }
        }

        // Partial sort for top-k (faster than full sort for small k)
        let k = min(topK, count)
        let indexed = scores.enumerated()
            .sorted { $0.element > $1.element }
            .prefix(k)

        return indexed.enumerated().map { rank, item in
            VectorSearchResult(
                chunkId: chunkIds[item.offset],
                score: item.element,
                rank: rank
            )
        }
    }

    /// Get the embedding vector for a specific chunk by index.
    func embedding(forChunkIndex index: Int) -> [Float]? {
        guard index >= 0, index < count else { return nil }
        let start = index * dimension
        return Array(embeddings[start..<start + dimension])
    }

    /// Get the embedding vector for a specific chunk ID.
    func embedding(forChunkId chunkId: String) -> [Float]? {
        guard let index = chunkIds.firstIndex(of: chunkId) else { return nil }
        return embedding(forChunkIndex: index)
    }

    /// Create a pseudo query embedding by averaging embeddings of keyword-matched chunks.
    /// Used when no on-device embedding model is available.
    func pseudoQueryEmbedding(fromChunkIds matchedIds: [String], weights: [Float]) -> [Float] {
        guard !matchedIds.isEmpty else {
            return [Float](repeating: 0, count: dimension)
        }

        var result = [Float](repeating: 0, count: dimension)
        var totalWeight: Float = 0

        for (chunkId, weight) in zip(matchedIds, weights) {
            guard let emb = embedding(forChunkId: chunkId) else { continue }
            var w = weight
            vDSP_vsma(emb, 1, &w, result, 1, &result, 1, vDSP_Length(dimension))
            totalWeight += weight
        }

        if totalWeight > 0 {
            var invWeight = 1.0 / totalWeight
            vDSP_vsmul(result, 1, &invWeight, &result, 1, vDSP_Length(dimension))
        }

        // Normalize
        var norm: Float = 0
        vDSP_dotpr(result, 1, result, 1, &norm, vDSP_Length(dimension))
        norm = sqrtf(norm)
        if norm > 0 {
            var invNorm = 1.0 / norm
            vDSP_vsmul(result, 1, &invNorm, &result, 1, vDSP_Length(dimension))
        }

        return result
    }

    // MARK: - Private

    private func normalizeVector(at index: Int) {
        let start = index * dimension
        var norm: Float = 0
        embeddings.withUnsafeBufferPointer { buf in
            guard let ptr = buf.baseAddress else { return }
            vDSP_dotpr(
                ptr.advanced(by: start), 1,
                ptr.advanced(by: start), 1,
                &norm,
                vDSP_Length(dimension)
            )
        }
        norm = sqrtf(norm)
        guard norm > 0 else { return }
        var invNorm = 1.0 / norm
        embeddings.withUnsafeMutableBufferPointer { buf in
            guard let ptr = buf.baseAddress else { return }
            vDSP_vsmul(
                ptr.advanced(by: start), 1,
                &invNorm,
                ptr.advanced(by: start), 1,
                vDSP_Length(dimension)
            )
        }
    }
}

enum VectorStoreError: LocalizedError {
    case sizeMismatch(String)

    var errorDescription: String? {
        switch self {
        case .sizeMismatch(let msg): return msg
        }
    }
}
