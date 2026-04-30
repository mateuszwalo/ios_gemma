import SwiftUI
import UniformTypeIdentifiers

/// Model setup screen — lets user pick a GGUF file from iPad's Files app.
/// The GGUF model is NOT bundled in the app (too large at 2.9GB).
/// User downloads it separately (PocketPal, HTTP server, cloud) then selects here.
struct SetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var showFilePicker = false
    @State private var selectedModelName: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundColor(.blue)

            Text("Load Gemma Model")
                .font(.title2.bold())

            Text("Select a GGUF model file from your iPad.\nRecommended: gemma-4-E2B-it-Q4_K_M.gguf")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if let name = selectedModelName {
                HStack {
                    Image(systemName: "doc.fill")
                    Text(name)
                        .font(.caption)
                        .lineLimit(1)
                }
                .padding(8)
                .background(Color(.systemGray5))
                .cornerRadius(8)
            }

            switch appState.modelState {
            case .loading(let progress):
                VStack(spacing: 8) {
                    ProgressView()
                    Text(progress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            case .error(let msg):
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

            default:
                EmptyView()
            }

            Button(action: { showFilePicker = true }) {
                Label("Select GGUF File", systemImage: "folder")
                    .font(.headline)
                    .frame(maxWidth: 280)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(appState.modelState == .loading(progress: ""))

            // Quick info
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(icon: "memorychip", text: "Model runs fully on-device via Metal GPU")
                InfoRow(icon: "wifi.slash", text: "No internet required after model download")
                InfoRow(icon: "speedometer", text: "Performance metrics shown in chat")
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal, 40)

            Spacer()
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.data, .item],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Start security-scoped access for sandboxed file
            guard url.startAccessingSecurityScopedResource() else {
                appState.modelState = .error("Cannot access file. Try copying it to Files > On My iPad first.")
                return
            }

            selectedModelName = url.lastPathComponent

            // Copy to app's documents directory for persistent access
            Task {
                do {
                    let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let destURL = docsDir.appendingPathComponent(url.lastPathComponent)

                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.copyItem(at: url, to: destURL)
                    url.stopAccessingSecurityScopedResource()

                    await appState.loadModel(url: destURL)
                } catch {
                    url.stopAccessingSecurityScopedResource()
                    appState.modelState = .error("File copy failed: \(error.localizedDescription)")
                }
            }

        case .failure(let error):
            appState.modelState = .error("File picker error: \(error.localizedDescription)")
        }
    }
}

private struct InfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
