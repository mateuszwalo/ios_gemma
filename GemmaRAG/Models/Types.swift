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
    let promptTokens: Int
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
    var thinking: String? = nil
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
    var topK: Int = 6
    var searchPoolK: Int = 20
    var rerankAlpha: Float = 0.65
    var sourceBoost: Float = 0.08
    var maxContextChars: Int = 5000
    var maxContextChunks: Int = 6
    var maxImages: Int = 2
    var minRetrievalConfidence: Float = 0.10
    var imageMinConfidence: Float = 0.10
    var minImageOcrMatch: Float = 0.0
    var nCtx: Int = 4096
    var nThreads: Int = 4
    var temperature: Float = 0.3
    var topP: Float = 0.90
    var topKSampling: Int = 40
    var maxTokens: Int = 512
    var nGpuLayers: Int = 99  // Use Metal on iPad (unlike Python CPU-only simulation)

    var retryTemperature: Float = 0.6

    var promptTemplate: String = "<start_of_turn>user\nYou are a contract data extraction assistant for Red Bull VIP Opt-In agreements. Your job is to find and quote exact data from the context below.\n\nRULES:\n1. The answer IS in the context. Read every source carefully before answering.\n2. Quote exact dollar amounts, percentages, case counts, and dates exactly as written.\n3. When multiple tiers or programs appear, match the EXACT tier name from the question — do not use numbers from a different tier or a different discount program.\n4. Never invent or estimate numbers. Only state values explicitly written in the context.\n5. Always answer directly. Do not say \"the context does not state\" unless the data is truly absent from ALL sources.\n6. For comparisons: first identify each tier's value separately by quoting the source, then state the difference. Double-check that each value belongs to the correct tier and the correct discount program (Shelf vs Shelf + Cold Cashier vs S.P.+P.C.C.+A.C. are DIFFERENT programs).\n7. Shelf Discount and Shelf + Cold Cashier Discount are two separate discount levels with different values. Never mix them.\n\nCONTEXT:\n{context}\n\nQUESTION: {question}<end_of_turn>\n<start_of_turn>model\n"
}
