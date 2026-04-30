import Foundation
import llama

private func llama_batch_clear(_ batch: inout llama_batch) {
    batch.n_tokens = 0
}

private func llama_batch_add(_ batch: inout llama_batch, _ id: llama_token, _ pos: llama_pos, _ seq_ids: [llama_seq_id], _ logits: Bool) {
    let idx = Int(batch.n_tokens)
    batch.token![idx] = id
    batch.pos![idx] = pos
    batch.n_seq_id![idx] = Int32(seq_ids.count)
    for i in 0..<seq_ids.count {
        batch.seq_id![idx]![i] = seq_ids[i]
    }
    batch.logits![idx] = logits ? 1 : 0
    batch.n_tokens += 1
}

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
        if let s = sampler { llama_sampler_free(s) }
        if let b = batch { llama_batch_free(b) }
        if let c = context { llama_free(c) }
        if let m = model { llama_model_free(m) }
        llama_backend_free()
    }

    func load(modelURL: URL) async throws {
        loadProgress = "Loading model..."

        let nGpuLayers = Int32(config.nGpuLayers)
        let nCtx = UInt32(config.nCtx)
        let nThreads = Int32(config.nThreads)
        let temperature = config.temperature
        let topP = config.topP
        let topKSampling = Int32(config.topKSampling)
        let batchSize = Int32(config.nCtx)
        let modelPath = modelURL.path
        let modelFilename = modelURL.lastPathComponent

        let result: (OpaquePointer, OpaquePointer, OpaquePointer?, OpaquePointer, llama_batch) = try await Task.detached(priority: .userInitiated) {
            var modelParams = llama_model_default_params()
            modelParams.n_gpu_layers = nGpuLayers

            guard let m = llama_model_load_from_file(modelPath, modelParams) else {
                throw LlamaError.modelLoadFailed("Failed to load: \(modelFilename)")
            }

            var ctxParams = llama_context_default_params()
            ctxParams.n_ctx = nCtx
            ctxParams.n_threads = nThreads
            ctxParams.n_threads_batch = nThreads

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
            llama_sampler_chain_add(chain, llama_sampler_init_temp(temperature))
            llama_sampler_chain_add(chain, llama_sampler_init_top_p(topP, 1))
            llama_sampler_chain_add(chain, llama_sampler_init_top_k(topKSampling))
            llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.max))

            let b = llama_batch_init(batchSize, 0, 1)

            return (m, ctx, v, chain, b)
        }.value

        self.model = result.0
        self.context = result.1
        self.vocab = result.2
        self.sampler = result.3
        self.batch = result.4
        self.isLoaded = true
        self.loadProgress = "Model loaded"
    }

    func generate(prompt: String) async throws -> GenerationOutput {
        guard let model = model,
              let context = context,
              let vocab = vocab,
              let sampler = sampler,
              let batch = batch else {
            throw LlamaError.notLoaded
        }

        let maxGenTokens = config.maxTokens

        return try await Task.detached(priority: .userInitiated) {
            var batch = batch
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

            llama_batch_clear(&batch)
            for i in 0..<Int(nPromptTokens) {
                let isLast = (i == Int(nPromptTokens) - 1)
                llama_batch_add(&batch, tokens[i], Int32(i), [0], isLast)
            }

            let decodeResult = llama_decode(context, batch)
            guard decodeResult == 0 else {
                throw LlamaError.decodeFailed(Int(decodeResult))
            }

            var outputTokens: [llama_token] = []
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

                llama_batch_clear(&batch)
                llama_batch_add(&batch, newToken, nCur, [0], true)
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
        if let b = batch { llama_batch_free(b) }
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
