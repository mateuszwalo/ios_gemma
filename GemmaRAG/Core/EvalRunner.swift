import Foundation

struct EvalQuestion: Codable, Identifiable {
    let id: String
    let question: String
    let expectedAnswer: String
    let relevantChunkIds: [String]
    let category: String
    let requiresImage: Bool
    let difficulty: String

    enum CodingKeys: String, CodingKey {
        case id, question, category, difficulty
        case expectedAnswer = "expected_answer"
        case relevantChunkIds = "relevant_chunk_ids"
        case requiresImage = "requires_image"
    }
}

struct EvalQuestionResult: Codable {
    let questionId: String
    let question: String
    let expectedAnswer: String
    let modelAnswer: String
    let category: String
    let difficulty: String
    let includeImages: Bool

    let ttftMs: Float
    let totalTimeMs: Float
    let tokensPerSecond: Float
    let tokensGenerated: Int
    let promptTokens: Int
    let retrievalTimeMs: Float
    let embeddingTimeMs: Float
    let retrievalConfidence: Float

    let retrievedChunkIds: [String]
    let relevantChunkIds: [String]
    let hitAtK: Bool
    let returnedImages: [String]

    let memoryFootprintMB: Float
    let errorMessage: String?
}

struct EvalRunSummary: Codable {
    let mode: String
    let questionCount: Int
    let successCount: Int
    let errorCount: Int

    let ttftMean: Float
    let ttftP50: Float
    let ttftP95: Float
    let totalTimeMean: Float
    let totalTimeP50: Float
    let totalTimeP95: Float
    let tpsMean: Float
    let tpsMin: Float
    let tpsMax: Float
    let retrievalTimeMean: Float
    let retrievalTimeP95: Float
    let retrievalConfidenceMean: Float

    let hitAtKRate: Float
    let peakMemoryMB: Float
    let totalDurationSeconds: Float
}

struct EvalReport: Codable {
    let reportId: String
    let timestamp: String
    let deviceInfo: DeviceInfo
    let ragConfig: EvalRAGConfig
    let summaryTextOnly: EvalRunSummary
    let summaryWithImages: EvalRunSummary
    let resultsTextOnly: [EvalQuestionResult]
    let resultsWithImages: [EvalQuestionResult]
}

struct DeviceInfo: Codable {
    let model: String
    let systemName: String
    let systemVersion: String
    let processorCount: Int
    let physicalMemoryGB: Float
    let thermalState: String
}

struct EvalRAGConfig: Codable {
    let topK: Int
    let searchPoolK: Int
    let rerankAlpha: Float
    let maxContextChars: Int
    let maxContextChunks: Int
    let maxImages: Int
    let temperature: Float
    let topP: Float
    let topKSampling: Int
    let maxTokens: Int
    let nCtx: Int
    let nGpuLayers: Int
}

enum EvalPhase: Equatable {
    case idle
    case warmup
    case runningTextOnly(current: Int, total: Int)
    case runningWithImages(current: Int, total: Int)
    case saving
    case done(reportPath: String)
    case error(String)
}

@MainActor
class EvalRunner: ObservableObject {
    @Published var phase: EvalPhase = .idle
    @Published var currentQuestion: String = ""
    @Published var lastReport: EvalReport?
    @Published var isCancelled = false

    private var evalQuestions: [EvalQuestion] = []
    private var uiQuestions: [EvalQuestion] = []

    init() {
        loadQuestions()
    }

    private func loadQuestions() {
        guard let url = Bundle.main.url(forResource: "eval_set", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let questions = try? JSONDecoder().decode([EvalQuestion].self, from: data) else {
            return
        }
        evalQuestions = questions
        buildUIQuestions()
    }

    private func buildUIQuestions() {
        let uiTexts: [(String, String, Bool)] = [
            ("ui_p01", "In Platinum Groc, what is the 8.4 oz Shelf Discount and Case Cost?", false),
            ("ui_p02", "In Diamond Groc, what are the Shelf + Cold Cashier case costs for 8.4 oz and 12 oz?", false),
            ("ui_p03", "In Double Diamond Groc, what is the 8.4 oz Shelf + Cold Cashier Discount and Case Cost?", false),
            ("ui_p04", "In Triple Diamond Groc, what are the Shelf Program case costs for 8.4 oz and 12 oz?", false),
            ("ui_p05", "In Triple Diamond Conv, what are the three discount tiers and 8.4 oz case costs for each?", false),
            ("ui_p06", "In Platinum Liquor, what is the 8.4 oz Shelf Discount and Case Cost?", false),
            ("ui_p07", "What is the 16 oz EDLP Case Discount and resulting Case Cost?", false),
            ("ui_p08", "What are the Suggested Retail Prices for 8.4oz, 12oz, 16oz, and 20oz Red Bull?", false),
            ("ui_c01", "Compare Platinum, Diamond, and Double Diamond Groc: what are the 8.4 oz shelf discounts?", false),
            ("ui_c02", "Compare Triple Diamond Conv vs Triple Diamond Groc shelf case costs for 8.4 oz and 12 oz.", false),
            ("ui_c03", "Which tier has the lowest 8.4 oz case cost in the Shelf + Cold Cashier program?", false),
            ("ui_c04", "How many Linear Feet does each Grocery tier require? List Platinum, Diamond, Double Diamond, Triple Diamond.", false),
            ("ui_po1", "What is the Strike Zone requirement for Red Bull shelf placement?", false),
            ("ui_po2", "What are the EDLP price limits for 8.4oz, 12oz, and 16oz singles?", false),
            ("ui_po3", "What are the Premium Cold Cashier placement requirements?", false),
            ("ui_po4", "Is Red Bull North America Inc. a party to the VIP Opt-In Contract?", false),
            ("ui_po5", "Until when is the 2025 VIP Opt-In Contract effective?", false),
            ("ui_po6", "How many days notice is required to change participation level?", false),
            ("ui_po7", "How many days does a party have to cure a material breach?", false),
            ("ui_po8", "What size cold equipment is required for Premium Cold Cashier?", false),
        ]

        let existingQuestions = Set(evalQuestions.map { $0.question.lowercased().trimmingCharacters(in: .whitespaces) })

        uiQuestions = uiTexts.compactMap { (id, text, needsImage) in
            let normalized = text.lowercased().trimmingCharacters(in: .whitespaces)
            if existingQuestions.contains(normalized) { return nil }
            return EvalQuestion(
                id: id,
                question: text,
                expectedAnswer: "",
                relevantChunkIds: [],
                category: id.contains("_c") ? "comparison" : id.contains("_po") ? "policy" : "pricing",
                requiresImage: needsImage,
                difficulty: "medium"
            )
        }
    }

    var allQuestions: [EvalQuestion] {
        evalQuestions + uiQuestions
    }

    func run(pipeline: RAGPipeline, config: RAGConfig) async {
        isCancelled = false
        let questions = allQuestions
        guard !questions.isEmpty else {
            phase = .error("No eval questions loaded")
            return
        }

        let runStart = CFAbsoluteTimeGetCurrent()
        let reportId = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")

        phase = .warmup
        currentQuestion = "Warming up model..."
        do {
            let _ = try await pipeline.query(question: "What is the shelf discount?", includeImages: false)
        } catch {
            phase = .error("Warmup failed: \(error.localizedDescription)")
            return
        }

        if isCancelled { phase = .idle; return }

        var textResults: [EvalQuestionResult] = []
        var imageResults: [EvalQuestionResult] = []
        var peakMemText: Float = 0
        var peakMemImage: Float = 0

        for (idx, q) in questions.enumerated() {
            if isCancelled { phase = .idle; return }
            phase = .runningTextOnly(current: idx + 1, total: questions.count)
            currentQuestion = q.question
            let result = await runSingle(question: q, includeImages: false, pipeline: pipeline)
            textResults.append(result)
            peakMemText = max(peakMemText, result.memoryFootprintMB)
        }

        for (idx, q) in questions.enumerated() {
            if isCancelled { phase = .idle; return }
            phase = .runningWithImages(current: idx + 1, total: questions.count)
            currentQuestion = q.question
            let result = await runSingle(question: q, includeImages: true, pipeline: pipeline)
            imageResults.append(result)
            peakMemImage = max(peakMemImage, result.memoryFootprintMB)
        }

        let totalDuration = Float(CFAbsoluteTimeGetCurrent() - runStart)

        let textSummary = computeSummary(
            mode: "text_only",
            results: textResults,
            peakMemory: peakMemText,
            totalDuration: totalDuration / 2
        )
        let imageSummary = computeSummary(
            mode: "with_images",
            results: imageResults,
            peakMemory: peakMemImage,
            totalDuration: totalDuration / 2
        )

        let report = EvalReport(
            reportId: reportId,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            deviceInfo: collectDeviceInfo(),
            ragConfig: EvalRAGConfig(
                topK: config.topK,
                searchPoolK: config.searchPoolK,
                rerankAlpha: config.rerankAlpha,
                maxContextChars: config.maxContextChars,
                maxContextChunks: config.maxContextChunks,
                maxImages: config.maxImages,
                temperature: config.temperature,
                topP: config.topP,
                topKSampling: config.topKSampling,
                maxTokens: config.maxTokens,
                nCtx: config.nCtx,
                nGpuLayers: config.nGpuLayers
            ),
            summaryTextOnly: textSummary,
            summaryWithImages: imageSummary,
            resultsTextOnly: textResults,
            resultsWithImages: imageResults
        )

        phase = .saving
        let path = saveReport(report, reportId: reportId)
        lastReport = report
        phase = .done(reportPath: path)
    }

    func cancel() {
        isCancelled = true
    }

    private func runSingle(
        question: EvalQuestion,
        includeImages: Bool,
        pipeline: RAGPipeline
    ) async -> EvalQuestionResult {
        let memBefore = currentMemoryMB()

        do {
            let response = try await pipeline.query(
                question: question.question,
                includeImages: includeImages
            )

            let memAfter = currentMemoryMB()
            let cleanedAnswer = AppState.cleanModelOutput(response.answer)

            let retrievedIds = response.retrievedChunks.map { $0.chunk.chunkId }
            let hitAtK = !question.relevantChunkIds.isEmpty &&
                question.relevantChunkIds.contains(where: { retrievedIds.contains($0) })

            return EvalQuestionResult(
                questionId: question.id,
                question: question.question,
                expectedAnswer: question.expectedAnswer,
                modelAnswer: cleanedAnswer,
                category: question.category,
                difficulty: question.difficulty,
                includeImages: includeImages,
                ttftMs: response.ttftMs,
                totalTimeMs: response.totalTimeMs,
                tokensPerSecond: response.tokensPerSecond,
                tokensGenerated: response.tokensGenerated,
                promptTokens: response.promptTokens,
                retrievalTimeMs: response.retrievalTimeMs,
                embeddingTimeMs: response.embeddingTimeMs,
                retrievalConfidence: response.retrievalConfidence,
                retrievedChunkIds: retrievedIds,
                relevantChunkIds: question.relevantChunkIds,
                hitAtK: hitAtK,
                returnedImages: response.associatedImages,
                memoryFootprintMB: max(memBefore, memAfter),
                errorMessage: nil
            )
        } catch {
            return EvalQuestionResult(
                questionId: question.id,
                question: question.question,
                expectedAnswer: question.expectedAnswer,
                modelAnswer: "",
                category: question.category,
                difficulty: question.difficulty,
                includeImages: includeImages,
                ttftMs: 0, totalTimeMs: 0, tokensPerSecond: 0,
                tokensGenerated: 0, promptTokens: 0,
                retrievalTimeMs: 0, embeddingTimeMs: 0,
                retrievalConfidence: 0,
                retrievedChunkIds: [], relevantChunkIds: question.relevantChunkIds,
                hitAtK: false, returnedImages: [],
                memoryFootprintMB: currentMemoryMB(),
                errorMessage: error.localizedDescription
            )
        }
    }

    private func computeSummary(
        mode: String,
        results: [EvalQuestionResult],
        peakMemory: Float,
        totalDuration: Float
    ) -> EvalRunSummary {
        let successful = results.filter { $0.errorMessage == nil }
        let errors = results.count - successful.count

        let ttfts = successful.map(\.ttftMs).sorted()
        let totals = successful.map(\.totalTimeMs).sorted()
        let tps = successful.map(\.tokensPerSecond)
        let retrievals = successful.map(\.retrievalTimeMs).sorted()
        let confidences = successful.map(\.retrievalConfidence)

        let evalSetResults = successful.filter { $0.questionId.hasPrefix("q") }
        let hitCount = evalSetResults.filter(\.hitAtK).count
        let hitRate = evalSetResults.isEmpty ? 0 : Float(hitCount) / Float(evalSetResults.count)

        return EvalRunSummary(
            mode: mode,
            questionCount: results.count,
            successCount: successful.count,
            errorCount: errors,
            ttftMean: mean(ttfts),
            ttftP50: percentile(ttfts, p: 0.50),
            ttftP95: percentile(ttfts, p: 0.95),
            totalTimeMean: mean(totals),
            totalTimeP50: percentile(totals, p: 0.50),
            totalTimeP95: percentile(totals, p: 0.95),
            tpsMean: mean(tps),
            tpsMin: tps.min() ?? 0,
            tpsMax: tps.max() ?? 0,
            retrievalTimeMean: mean(retrievals),
            retrievalTimeP95: percentile(retrievals, p: 0.95),
            retrievalConfidenceMean: mean(confidences),
            hitAtKRate: hitRate,
            peakMemoryMB: peakMemory,
            totalDurationSeconds: totalDuration
        )
    }

    private func collectDeviceInfo() -> DeviceInfo {
        let device = ProcessInfo.processInfo
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 256) {
                String(cString: $0)
            }
        }

        let thermalState: String
        switch device.thermalState {
        case .nominal: thermalState = "nominal"
        case .fair: thermalState = "fair"
        case .serious: thermalState = "serious"
        case .critical: thermalState = "critical"
        @unknown default: thermalState = "unknown"
        }

        return DeviceInfo(
            model: machine,
            systemName: "iPadOS",
            systemVersion: device.operatingSystemVersionString,
            processorCount: device.processorCount,
            physicalMemoryGB: Float(device.physicalMemory) / (1024 * 1024 * 1024),
            thermalState: thermalState
        )
    }

    private func currentMemoryMB() -> Float {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            return Float(info.resident_size) / (1024 * 1024)
        }
        return Float(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024)
    }

    @Published var statusMessage: String = ""

    private func saveReport(_ report: EvalReport, reportId: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            self.statusMessage = "Failed to save report: could not resolve documents directory"
            return "error: could not resolve documents directory"
        }
        let evalDir = docsDir.appendingPathComponent("eval_reports")
        let filename = "eval_\(reportId).json"
        let fileURL = evalDir.appendingPathComponent(filename)

        do {
            try FileManager.default.createDirectory(at: evalDir, withIntermediateDirectories: true)
            let data = try encoder.encode(report)
            try data.write(to: fileURL)
            self.statusMessage = "Report saved: \(fileURL.lastPathComponent)"
        } catch {
            self.statusMessage = "Failed to save report: \(error.localizedDescription)"
        }

        return fileURL.path
    }

    private func mean(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Float(values.count)
    }

    private func percentile(_ sorted: [Float], p: Float) -> Float {
        guard !sorted.isEmpty else { return 0 }
        let idx = Int(Float(sorted.count - 1) * p)
        return sorted[min(idx, sorted.count - 1)]
    }
}
