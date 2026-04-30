import Foundation
import llama

/// Swift wrapper for llama.cpp GGUF inference.
/// Mirrors Python's GemmaRunner — loads GGUF, tokenizes, generates with streaming TTFT measurement.
/// Uses Metal GPU acceleration on iPad M4 (unlike Python's CPU-only simulation).
@MainActor
class LlamaRunner: ObservableObject {
    @Published var isLoaded = false
    @Published var loadProgress: String = ""

    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var sampler: OpaquePointer?

    private var config: RAGConfig

    init(config: RAGConfig = RAGConfig()) {
        self.config = config
    }

    deinit {
        unload()
    }

    /// Load GGUF model from file URL.
    /// Call from background thread for large models.
    func load(modelURL: URL) async throws {
        loadProgress = "Loading model..."

        try await Task.detached(priority: .userInitiated) { [self] in
            var modelParams = llama_model_default_params()
            modelParams.n_gpu_layers = Int32(self.config.nGpuLayers)

            guard let m = llama_model_load_from_file(modelURL.path, modelParams) else {
                throw LlamaError.modelLoadFailed("Failed to load: \(modelURL.lastPathComponent)")
            }

            var ctxParams = llama_context_default_params()
            ctxParams.n_ctx = UInt32(self.config.nCtx)
            ctxParams.n_threads = Int32(self.config.nThreads)
            ctxParams.n_threads_batch = Int32(self.config.nThreads)

            guard let ctx = llama_init_from_model(m, ctxParams) else {
                llama_model_free(m)
                throw LlamaError.contextCreateFailed
            }

            // Build sampler chain
            let samplerChainParams = llama_sampler_chain_default_params()
            guard let chain = llama_sampler_chain_init(samplerChainParams) else {
                llama_free(ctx)
                llama_model_free(m)
                throw LlamaError.samplerCreateFailed
            }
            llama_sampler_chain_add(chain, llama_sampler_init_temp(self.config.temperature))
            llama_sampler_chain_add(chain, llama_sampler_init_top_p(self.config.topP, 1))
            llama_sampler_chain_add(chain, llama_sampler_init_top_k(Int32(self.config.topKSampling)))
            llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.max))

            await MainActor.run {
                self.model = m
                self.context = ctx
                self.sampler = chain
                self.isLoaded = true
                self.loadProgress = "Model loaded"
            }
        }.value
    }

    /// Generate text from a prompt, measuring TTFT and tokens/s.
    /// Mirrors Python GemmaRunner.generate() with streaming token measurement.
    func generate(prompt: String) async throws -> GenerationOutput {
        guard let model = model, let context = context, let sampler = sampler else {
            throw LlamaError.notLoaded
        }

        return try await Task.detached(priority: .userInitiated) {
            let startTime = CFAbsoluteTimeGetCurrent()
            var firstTokenTime: CFAbsoluteTime?

            // Tokenize prompt
            let promptCStr = prompt.cString(using: .utf8)!
            let maxTokens = Int32(prompt.utf8.count + 128)
            var tokens = [llama_token](repeating: 0, count: Int(maxTokens))
            let nPromptTokens = llama_tokenize(
                model, promptCStr, Int32(promptCStr.count - 1),
                &tokens, maxTokens,
                true,  // add_special (BOS)
                false  // parse_special
            )
            guard nPromptTokens > 0 else {
                throw LlamaError.tokenizationFailed
            }
            tokens = Array(tokens.prefix(Int(nPromptTokens)))

            // Clear KV cache for fresh generation
            llama_kv_cache_clear(context)

            // Decode prompt tokens
            var batch = llama_batch_get_one(&tokens, Int32(tokens.count))
            let decodeResult = llama_decode(context, batch)
            guard decodeResult == 0 else {
                throw LlamaError.decodeFailed(Int(decodeResult))
            }

            // Generate tokens one by one
            var outputTokens: [llama_token] = []
            let maxGenTokens = self.config.maxTokens
            let stopStrings = ["<turn|>", "<|turn>user", "<|tool_call>"]
            var generatedText = ""

            for _ in 0..<maxGenTokens {
                let newToken = llama_sampler_sample(sampler, context, -1)

                // Check for EOS
                if llama_vocab_is_eog(model, newToken) {
                    break
                }

                if firstTokenTime == nil {
                    firstTokenTime = CFAbsoluteTimeGetCurrent()
                }

                outputTokens.append(newToken)

                // Convert token to text
                var buf = [CChar](repeating: 0, count: 256)
                let n = llama_token_to_piece(model, newToken, &buf, Int32(buf.count), 0, false)
                if n > 0 {
                    let piece = String(cString: buf.prefix(Int(n)) + [0])
                    generatedText += piece
                }

                // Check for stop strings
                let shouldStop = stopStrings.contains { generatedText.contains($0) }
                if shouldStop {
                    // Trim stop string from output
                    for stop in stopStrings {
                        if let range = generatedText.range(of: stop) {
                            generatedText = String(generatedText[..<range.lowerBound])
                        }
                    }
                    break
                }

                // Prepare batch for next token
                var tokenArr = [newToken]
                batch = llama_batch_get_one(&tokenArr, 1)
                let res = llama_decode(context, batch)
                if res != 0 { break }
            }

            let endTime = CFAbsoluteTimeGetCurrent()
            let totalMs = Float((endTime - startTime) * 1000)
            let ttftMs: Float
            if let ftt = firstTokenTime {
                ttftMs = Float((ftt - startTime) * 1000)
            } else {
                ttftMs = totalMs
            }

            let genTime = firstTokenTime.map { endTime - $0 } ?? (endTime - startTime)
            let tps = genTime > 0 ? Float(outputTokens.count) / Float(genTime) : 0

            llama_sampler_reset(sampler)

            return GenerationOutput(
                text: generatedText.trimmingCharacters(in: .whitespacesAndNewlines),
                tokensGenerated: outputTokens.count,
                promptTokens: Int(nPromptTokens),
                ttftMs: ttftMs,
                totalTimeMs: totalMs,
                tokensPerSecond: tps
            )
        }.value
    }

    func unload() {
        if let s = sampler { llama_sampler_free(s) }
        if let c = context { llama_free(c) }
        if let m = model { llama_model_free(m) }
        sampler = nil
        context = nil
        model = nil
        isLoaded = false
        loadProgress = ""
    }

    func updateConfig(_ newConfig: RAGConfig) {
        self.config = newConfig
    }
}

struct GenerationOutput {
    let text: String
    let tokensGenerated: Int
    let promptTokens: Int
    let ttftMs: Float
    let totalTimeMs: Float
    let tokensPerSecond: Float
}

enum LlamaError: LocalizedError {
    case modelLoadFailed(String)
    case contextCreateFailed
    case samplerCreateFailed
    case notLoaded
    case tokenizationFailed
    case decodeFailed(Int)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let msg): return "Model load failed: \(msg)"
        case .contextCreateFailed: return "Failed to create llama context"
        case .samplerCreateFailed: return "Failed to create sampler"
        case .notLoaded: return "Model not loaded"
        case .tokenizationFailed: return "Tokenization failed"
        case .decodeFailed(let code): return "Decode failed with code \(code)"
        }
    }
}
