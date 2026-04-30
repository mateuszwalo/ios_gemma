import SwiftUI

@main
struct GemmaRAGApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}

/// Central app state: manages model loading, chunk store, vector store, and pipeline.
@MainActor
class AppState: ObservableObject {
    @Published var modelState: ModelLoadState = .notLoaded
    @Published var dataLoaded = false
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false

    let chunkStore = ChunkStore()
    let vectorStore = VectorStore()
    let llamaRunner = LlamaRunner()
    var pipeline: RAGPipeline?
    var config = RAGConfig()

    init() {
        loadBundledData()
    }

    func loadBundledData() {
        do {
            try chunkStore.load()

            if let embURL = Bundle.main.url(forResource: "embeddings", withExtension: "bin") {
                try vectorStore.load(
                    embeddingsURL: embURL,
                    chunkIds: chunkStore.orderedChunkIds,
                    dimension: 384
                )
            }

            dataLoaded = true
            addSystemMessage("Data loaded: \(chunkStore.count) chunks, \(vectorStore.isLoaded ? "embeddings ready" : "keyword-only mode")")
        } catch {
            addSystemMessage("Failed to load data: \(error.localizedDescription)")
        }
    }

    func loadModel(url: URL) async {
        modelState = .loading(progress: "Loading GGUF...")
        do {
            try await llamaRunner.load(modelURL: url)
            modelState = .loaded
            pipeline = RAGPipeline(
                chunkStore: chunkStore,
                vectorStore: vectorStore,
                llamaRunner: llamaRunner,
                config: config
            )
            addSystemMessage("Model loaded. Ready to chat.")
        } catch {
            modelState = .error(error.localizedDescription)
            addSystemMessage("Model load failed: \(error.localizedDescription)")
        }
    }

    func sendQuery(_ question: String, includeImages: Bool) async {
        guard let pipeline = pipeline, !isGenerating else { return }

        messages.append(ChatMessage(
            role: .user,
            text: question,
            images: [],
            metrics: nil,
            timestamp: Date()
        ))

        isGenerating = true
        do {
            let response = try await pipeline.query(
                question: question,
                includeImages: includeImages
            )
            messages.append(ChatMessage(
                role: .assistant,
                text: response.answer,
                images: response.associatedImages,
                metrics: ChatMessage.MessageMetrics(
                    tokensPerSecond: response.tokensPerSecond,
                    ttftMs: response.ttftMs,
                    totalTimeMs: response.totalTimeMs,
                    retrievalTimeMs: response.retrievalTimeMs,
                    tokensGenerated: response.tokensGenerated,
                    retrievalConfidence: response.retrievalConfidence
                ),
                timestamp: Date()
            ))
        } catch {
            messages.append(ChatMessage(
                role: .system,
                text: "Error: \(error.localizedDescription)",
                images: [],
                metrics: nil,
                timestamp: Date()
            ))
        }
        isGenerating = false
    }

    private func addSystemMessage(_ text: String) {
        messages.append(ChatMessage(
            role: .system,
            text: text,
            images: [],
            metrics: nil,
            timestamp: Date()
        ))
    }
}
