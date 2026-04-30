import Foundation
import llama

/// Swift wrapper for llama.cpp GGUF inference.
/// Uses Metal GPU acceleration on iPad M4.
@MainActor
class LlamaRunner: ObservableObject {
    @Published var isLoaded = false
    @Published var loadProgress: String = ""

    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var sampler: OpaquePointer?
    private var batch: llama_batch?

    private var config: RAGConfig

    init(config: RAGConfig = RAGConfig()) {
        self.config = config
        llama_backend_init()
    }

    deinit {
        unload()
        llama_backend_free()
    }

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

            let v = llama_model_get_vocab(m)

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

            let b = llama_batch_init(Int32(self.config.nCtx), 0, 1)

            await MainActor.run {
                self.model = m
                self.context = ctx
                self.vocab = v
                self.sampler = chain
                self.batch = b
                self.isLoaded = true
                self.loadProgress = "Model loaded"
            }
        }.value
    }

    func generate(prompt: String) async throws -> GenerationOutput {
        guard let model = model,
              let context = context,
              let vocab = vocab,
              let sampler = sampler,
              var batch = batch else {
            throw LlamaError.notLoaded
        }

        return try await Task.detached(priority: .userInitiated) {
            let startTime = CFAbsoluteTimeGetCurrent()
            var firstTokenTime: CFAbsoluteTime?

            let promptCStr = prompt.cString(using: .utf8)!
            let maxTokens = Int32(prompt.utf8.count + 128)
            var tokens = [llama_token](repeating: 0, count: Int(maxTokens))
            let nPromptTokens = llama_tokenize(
                vocab, promptCStr, Int32(promptCStr.count - 1),
                &tokens, maxTokens,
                true,
                false
            )
            guard nPromptTokens > 0 else {
                throw LlamaError.tokenizationFailed
            }
            tokens = Array(tokens.prefix(Int(nPromptTokens)))

            llama_memory_clear(llama_get_memory(context), true)

            batch.n_tokens = 0
            for i in 0..<Int(nPromptTokens) {
                batch.token[i] = tokens[i]
                batch.pos?[i] = Int32(i)
                batch.n_seq_id?[i] = 1
                batch.seq_id?[i]?[0] = 0
                batch.logits?[i] = 0
            }
            batch.logits?[Int(nPromptTokens) - 1] = 1
            batch.n_tokens = nPromptTokens

            let decodeResult = llama_decode(context, batch)
            guard decodeResult == 0 else {
                throw LlamaError.decodeFailed(Int(decodeResult))
            }

            var outputTokens: [llama_token] = []
            let maxGenTokens = self.config.maxTokens
            let stopStrings = ["<turn|>", "<|turn>user", "<|tool_call>"]
            var generatedText = ""
            var nCur = nPromptTokens

            for _ in 0..<maxGenTokens {
                let newToken = llama_sampler_sample(sampler, context, -1)

                if llama_vocab_is_eog(vocab, newToken) {
                    break
                }

                if firstTokenTime == nil {
                    firstTokenTime = CFAbsoluteTimeGetCurrent()
                }

                outputTokens.append(newToken)

                var buf = [CChar](repeating: 0, count: 256)
                let n = llama_token_to_piece(vocab, newToken, &buf, Int32(buf.count), 0, false)
                if n > 0 {
                    let piece = String(cString: buf.prefix(Int(n)) + [0])
                    generatedText += piece
                }

                let shouldStop = stopStrings.contains { generatedText.contains($0) }
                if shouldStop {
                    for stop in stopStrings {
                        if let range = generatedText.range(of: stop) {
                            generatedText = String(generatedText[..<range.lowerBound])
                        }
                    }
                    break
                }

                batch.n_tokens = 0
                batch.token[0] = newToken
                batch.pos?[0] = nCur
                batch.n_seq_id?[0] = 1
                batch.seq_id?[0]?[0] = 0
                batch.logits?[0] = 1
                batch.n_tokens = 1
                nCur += 1

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
        if var b = batch { llama_batch_free(b) }
        if let c = context { llama_free(c) }
        if let m = model { llama_model_free(m) }
        sampler = nil
        batch = nil
        context = nil
        model = nil
        vocab = nil
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
