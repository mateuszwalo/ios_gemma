import SwiftUI

struct EvalView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var evalRunner = EvalRunner()
    @State private var showShareSheet = false
    @State private var reportURL: URL?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                statusSection
                if let report = evalRunner.lastReport {
                    summarySection(report: report)
                    detailSection(report: report)
                }
                exportSection
            }
            .padding()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 48))
                .foregroundColor(.indigo)

            Text("Automatic Evaluation")
                .font(.title2.bold())

            Text("\(evalRunner.allQuestions.count) questions \u{00B7} 2 modes (text-only + images)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                startButton
                cancelButton
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }

    private var startButton: some View {
        Button(action: startEval) {
            Label(evalRunner.phase == .idle ? "Start Evaluation" : "Running...",
                  systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(canStart ? Color.indigo : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
        }
        .disabled(!canStart)
    }

    private var cancelButton: some View {
        Button(action: { evalRunner.cancel() }) {
            Label("Cancel", systemImage: "stop.fill")
                .font(.headline)
                .padding()
                .background(isRunning ? Color.red.opacity(0.8) : Color.gray.opacity(0.3))
                .foregroundColor(.white)
                .cornerRadius(12)
        }
        .disabled(!isRunning)
    }

    private var canStart: Bool {
        appState.pipeline != nil && !isRunning
    }

    private var isRunning: Bool {
        switch evalRunner.phase {
        case .idle, .done, .error: return false
        default: return true
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(spacing: 8) {
            switch evalRunner.phase {
            case .idle:
                EmptyView()
            case .warmup:
                ProgressView("Warmup pass...")
            case .runningTextOnly(let current, let total):
                phaseProgress(label: "Text-only", current: current, total: total)
            case .runningWithImages(let current, let total):
                phaseProgress(label: "With images", current: current, total: total)
            case .saving:
                ProgressView("Saving report...")
            case .done(let path):
                Label("Done! Report saved.", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .error(let msg):
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.subheadline)
            }

            if isRunning && !evalRunner.currentQuestion.isEmpty {
                Text(evalRunner.currentQuestion)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(isRunning ? Color.indigo.opacity(0.05) : Color.clear)
        .cornerRadius(12)
    }

    private func phaseProgress(label: String, current: Int, total: Int) -> some View {
        VStack(spacing: 6) {
            Text("\(label): \(current)/\(total)")
                .font(.headline)
            ProgressView(value: Float(current), total: Float(total))
                .tint(.indigo)
        }
    }

    // MARK: - Summary

    private func summarySection(report: EvalReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Results Summary")
                .font(.title3.bold())

            deviceInfoRow(report.deviceInfo)

            HStack(spacing: 12) {
                summaryCard(title: "Text-Only", summary: report.summaryTextOnly, color: .blue)
                summaryCard(title: "With Images", summary: report.summaryWithImages, color: .purple)
            }
        }
    }

    private func deviceInfoRow(_ info: DeviceInfo) -> some View {
        HStack(spacing: 16) {
            Label(info.model, systemImage: "ipad")
            Label("\(info.systemVersion)", systemImage: "gear")
            Label(String(format: "%.1f GB RAM", info.physicalMemoryGB), systemImage: "memorychip")
            Label("\(info.processorCount) cores", systemImage: "cpu")
            Label(info.thermalState, systemImage: "thermometer")
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    private func summaryCard(title: String, summary: EvalRunSummary, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundColor(color)

            Group {
                metricRow("Success", "\(summary.successCount)/\(summary.questionCount)")
                metricRow("Errors", "\(summary.errorCount)")
                Divider()
                metricRow("TTFT mean", String(format: "%.0f ms", summary.ttftMean))
                metricRow("TTFT P95", String(format: "%.0f ms", summary.ttftP95))
                metricRow("Total mean", String(format: "%.0f ms", summary.totalTimeMean))
                metricRow("Total P95", String(format: "%.0f ms", summary.totalTimeP95))
                Divider()
                metricRow("TPS mean", String(format: "%.1f", summary.tpsMean))
                metricRow("TPS range", String(format: "%.1f-%.1f", summary.tpsMin, summary.tpsMax))
                metricRow("Retrieval P95", String(format: "%.0f ms", summary.retrievalTimeP95))
                metricRow("Confidence", String(format: "%.0f%%", summary.retrievalConfidenceMean * 100))
                metricRow("hit@k", String(format: "%.0f%%", summary.hitAtKRate * 100))
                metricRow("Peak RAM", String(format: "%.0f MB", summary.peakMemoryMB))
                metricRow("Duration", String(format: "%.1f s", summary.totalDurationSeconds))
            }
            .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    // MARK: - Detail

    private func detailSection(report: EvalReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Per-Question Results (Text-Only)")
                .font(.title3.bold())

            ForEach(Array(report.resultsTextOnly.enumerated()), id: \.offset) { _, result in
                questionResultRow(result)
            }

            Text("Per-Question Results (With Images)")
                .font(.title3.bold())
                .padding(.top, 8)

            ForEach(Array(report.resultsWithImages.enumerated()), id: \.offset) { _, result in
                questionResultRow(result)
            }
        }
    }

    private func questionResultRow(_ result: EvalQuestionResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(result.questionId)
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(result.hitAtK ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                    .cornerRadius(4)

                Text(result.category)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                if let err = result.errorMessage {
                    Label("Error", systemImage: "xmark.circle")
                        .font(.caption2)
                        .foregroundColor(.red)
                    let _ = err
                } else {
                    Text(String(format: "%.0fms | %.1f tok/s", result.totalTimeMs, result.tokensPerSecond))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }

            Text(result.question)
                .font(.caption)
                .lineLimit(2)

            if !result.modelAnswer.isEmpty {
                Text(result.modelAnswer)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .lineLimit(3)
            }

            if !result.expectedAnswer.isEmpty {
                Text("Expected: \(result.expectedAnswer)")
                    .font(.caption2)
                    .foregroundColor(.green)
                    .lineLimit(2)
            }

            if !result.returnedImages.isEmpty {
                Text("Images: \(result.returnedImages.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundColor(.purple)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    // MARK: - Export

    private var exportSection: some View {
        VStack(spacing: 12) {
            if case .done(let path) = evalRunner.phase {
                Button(action: { shareReport(path: path) }) {
                    Label("Share Report JSON", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.indigo)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                Text("Report is also in Files > GemmaRAG > eval_reports/")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = reportURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Actions

    private func startEval() {
        guard let pipeline = appState.pipeline else { return }
        Task {
            await evalRunner.run(pipeline: pipeline, config: appState.config)
        }
    }

    private func shareReport(path: String) {
        reportURL = URL(fileURLWithPath: path)
        showShareSheet = true
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
