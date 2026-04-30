import Foundation
import SwiftUI

// MARK: - Chunk Data (mirrors Python chunks.json schema)

struct ChunkData: Codable, Identifiable {
    let chunkId: String
    let text: String
    let sourceFile: String
    let pageNumber: Int?
    let chunkType: String
    let associatedImages: [ChunkImage]
    let metadata: ChunkMetadata?

    var id: String { chunkId }

    enum CodingKeys: String, CodingKey {
        case chunkId = "chunk_id"
        case text
        case sourceFile = "source_file"
        case pageNumber = "page_number"
        case chunkType = "chunk_type"
        case associatedImages = "associated_images"
        case metadata
    }
}

struct ChunkImage: Codable {
    let path: String
    let width: Int
    let height: Int
    let page: Int
    let index: Int
    let ocrSnippet: String?
    let textDensity: Double?

    enum CodingKeys: String, CodingKey {
        case path, width, height, page, index
        case ocrSnippet = "ocr_snippet"
        case textDensity = "text_density"
    }
}

struct ChunkMetadata: Codable {
    let chunkIndexInPage: Int?
    let charCount: Int?
    let tokenEstimate: Int?

    enum CodingKeys: String, CodingKey {
        case chunkIndexInPage = "chunk_index_in_page"
        case charCount = "char_count"
        case tokenEstimate = "token_estimate"
    }
}

// MARK: - Search Results

struct VectorSearchResult {
    let chunkId: String
    let score: Float
    let rank: Int
}

struct RetrievedChunk {
    let chunk: ChunkData
    let denseScore: Float
    let lexicalScore: Float
    let sourceScore: Float
    let hybridScore: Float
    let rank: Int
}

// MARK: - RAG Response

struct RAGResponse {
    let question: String
    let answer: String
    let retrievedChunks: [RetrievedChunk]
    let associatedImages: [String]  // image filenames
    let tokensGenerated: Int
    let tokensPerSecond: Float
    let ttftMs: Float
    let totalTimeMs: Float
    let retrievalTimeMs: Float
    let embeddingTimeMs: Float
    let retrievalConfidence: Float
}

// MARK: - Chat Message

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    let text: String
    let images: [String]
    let metrics: MessageMetrics?
    let timestamp: Date

    enum MessageRole {
        case user
        case assistant
        case system
    }

    struct MessageMetrics {
        let tokensPerSecond: Float
        let ttftMs: Float
        let totalTimeMs: Float
        let retrievalTimeMs: Float
        let tokensGenerated: Int
        let retrievalConfidence: Float
    }
}

// MARK: - App State

enum ModelLoadState: Equatable {
    case notLoaded
    case loading(progress: String)
    case loaded
    case error(String)
}

// MARK: - RAG Config (mirrors base.yaml RAG section)

struct RAGConfig {
    var topK: Int = 3
    var searchPoolK: Int = 12
    var rerankAlpha: Float = 0.65
    var sourceBoost: Float = 0.08
    var maxContextChars: Int = 1400
    var maxContextChunks: Int = 3
    var maxImages: Int = 1
    var minRetrievalConfidence: Float = 0.33
    var imageMinConfidence: Float = 0.52
    var minImageOcrMatch: Float = 0.02
    var nCtx: Int = 4096
    var nThreads: Int = 4
    var temperature: Float = 1.0
    var topP: Float = 0.95
    var topKSampling: Int = 64
    var maxTokens: Int = 512
    var nGpuLayers: Int = 99  // Use Metal on iPad (unlike Python CPU-only simulation)

    var promptTemplate: String = """
    <|turn>system
    You are a field assistant helping store employees with product standards and planograms.
    Answer ONLY based on the provided context.
    If the context does not contain the answer, say "I could not find the answer in the documents."
    Be concise and precise. Always respond in English.<turn|>
    <|turn>user
    CONTEXT:
    {context}

    QUESTION: {question}<turn|>
    <|turn>model

    """
}
