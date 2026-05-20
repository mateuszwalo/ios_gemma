import SwiftUI

@main
struct GemmaRAGApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        print("[Lifecycle] App became active")
                    case .inactive:
                        print("[Lifecycle] App became inactive")
                    case .background:
                        print("[Lifecycle] App moved to background")
                    @unknown default:
                        print("[Lifecycle] Unknown scene phase")
                    }
                }
        }
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var modelState: ModelLoadState = .notLoaded
    @Published var dataLoaded = false
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false

    let chunkStore = ChunkStore()
    let vectorStore = VectorStore()
    var config = RAGConfig()
    lazy var llamaRunner = LlamaRunner(config: config)
    var pipeline: RAGPipeline?

    init() {
        loadConfig()
        setupMemoryWarningObserver()
        loadBundledData()
        Task { await autoLoadModel() }
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

    func autoLoadModel() async {
        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: docsDir, includingPropertiesForKeys: [.fileSizeKey]) else { return }

        let ggufFiles = files.filter { $0.pathExtension.lowercased() == "gguf" }
        guard let modelURL = ggufFiles.first else { return }

        let fileSize = (try? modelURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard fileSize > 100_000_000 else { return }

        addSystemMessage("Found model: \(modelURL.lastPathComponent), loading...")
        await loadModel(url: modelURL)
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

            let cleanedAnswer = Self.cleanModelOutput(response.answer)
            let thinking = Self.extractThinking(response.answer)

            messages.append(ChatMessage(
                role: .assistant,
                text: cleanedAnswer,
                thinking: thinking,
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

    func clearChat() {
        messages.removeAll()
        addSystemMessage("Chat cleared. Model ready.")
    }

    static func extractThinking(_ text: String) -> String? {
        guard let startRange = text.range(of: "<think>"),
              let endRange = text.range(of: "</think>") else { return nil }
        let thinking = String(text[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return thinking.isEmpty ? nil : thinking
    }

    static func cleanModelOutput(_ text: String) -> String {
        var result = text

        if let thinkStart = result.range(of: "<think>"),
           let thinkEnd = result.range(of: "</think>") {
            result = String(result[thinkEnd.upperBound...])
        }

        let markers = [
            "<start_of_turn>model", "<start_of_turn>user",
            "<start_of_turn>", "<end_of_turn>",
            "</start_of_turn>", "</end_of_turn>",
            "<|turn>model", "<|turn>user",
            "<|turn>", "<turn|>",
            "<|tool_call>", "</think>", "<think>",
            "<bos>", "<eos>", "<pad>",
        ]
        for marker in markers {
            result = result.replacingOccurrences(of: marker, with: "")
        }

        let regex = try? NSRegularExpression(pattern: "<[/]?(?:start_of_turn|end_of_turn|turn|think|bos|eos)[^>]*>", options: [])
        if let regex = regex {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        if result.hasPrefix("model\n") {
            result = String(result.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if result.hasPrefix("model") && (result.count == 5 || result[result.index(result.startIndex, offsetBy: 5)].isWhitespace) {
            result = String(result.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        while result.hasPrefix("_response>") || result.hasPrefix("_turn>") || result.hasPrefix("_of_turn>") {
            if let idx = result.firstIndex(of: ">") {
                result = String(result[result.index(after: idx)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else { break }
        }

        return result
    }

    private func loadConfig() {
        if let configURL = Bundle.main.url(forResource: "config", withExtension: "json"),
           let configData = try? Data(contentsOf: configURL),
           let json = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] {
            if let rag = json["rag"] as? [String: Any] {
                if let v = rag["top_k"] as? Int { config.topK = v }
                if let v = rag["search_pool_k"] as? Int { config.searchPoolK = v }
                if let v = rag["rerank_alpha"] as? Double { config.rerankAlpha = Float(v) }
                if let v = rag["source_boost"] as? Double { config.sourceBoost = Float(v) }
                if let v = rag["max_context_chars"] as? Int { config.maxContextChars = v }
                if let v = rag["max_context_chunks"] as? Int { config.maxContextChunks = v }
                if let v = rag["max_images"] as? Int { config.maxImages = v }
                if let v = rag["min_retrieval_confidence"] as? Double { config.minRetrievalConfidence = Float(v) }
                if let v = rag["image_min_confidence"] as? Double { config.imageMinConfidence = Float(v) }
                if let v = rag["min_image_ocr_match"] as? Double { config.minImageOcrMatch = Float(v) }
            }
            if let llm = json["llm"] as? [String: Any] {
                if let v = llm["n_ctx"] as? Int { config.nCtx = v }
                if let v = llm["n_threads"] as? Int { config.nThreads = v }
                if let v = llm["temperature"] as? Double { config.temperature = Float(v) }
                if let v = llm["retry_temperature"] as? Double { config.retryTemperature = Float(v) }
                if let v = llm["top_p"] as? Double { config.topP = Float(v) }
                if let v = llm["top_k"] as? Int { config.topKSampling = v }
                if let v = llm["max_tokens"] as? Int { config.maxTokens = v }
                if let v = llm["n_gpu_layers"] as? Int { config.nGpuLayers = v }
            }
        }
    }

    private func setupMemoryWarningObserver() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
    }

    private func handleMemoryWarning() {
        addSystemMessage("Low memory warning — consider restarting if app becomes slow.")
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
