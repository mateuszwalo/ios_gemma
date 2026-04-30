import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Status bar
                StatusBar(appState: appState)

                // Main content
                if appState.modelState == .loaded {
                    ChatView()
                } else {
                    SetupView()
                }
            }
            .navigationTitle("Gemma RAG")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct StatusBar: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            // Data status
            HStack(spacing: 4) {
                Circle()
                    .fill(appState.dataLoaded ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text("\(appState.chunkStore.count) chunks")
                    .font(.caption)
            }

            // Vector store status
            HStack(spacing: 4) {
                Circle()
                    .fill(appState.vectorStore.isLoaded ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(appState.vectorStore.isLoaded ? "Dense+Lexical" : "Lexical only")
                    .font(.caption)
            }

            Spacer()

            // Model status
            HStack(spacing: 4) {
                Circle()
                    .fill(appState.modelState == .loaded ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(modelStatusText)
                    .font(.caption)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
    }

    private var modelStatusText: String {
        switch appState.modelState {
        case .notLoaded: return "No model"
        case .loading(let progress): return progress
        case .loaded: return "Gemma ready"
        case .error(let msg): return "Error: \(msg.prefix(30))"
        }
    }
}
