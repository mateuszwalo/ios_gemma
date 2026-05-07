import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: AppTab = .chat

    enum AppTab {
        case chat
        case eval
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                StatusBar(appState: appState)

                if appState.modelState == .loaded {
                    tabBar
                    switch selectedTab {
                    case .chat:
                        ChatView()
                    case .eval:
                        EvalView()
                    }
                } else {
                    SetupView()
                }
            }
            .navigationTitle("Gemma RAG")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(tab: .chat, icon: "bubble.left.and.bubble.right", label: "Chat")
            tabButton(tab: .eval, icon: "chart.bar.doc.horizontal", label: "Evaluation")
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color(.systemGray6))
    }

    private func tabButton(tab: AppTab, icon: String, label: String) -> some View {
        Button(action: { selectedTab = tab }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(label)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(selectedTab == tab ? Color.indigo.opacity(0.15) : Color.clear)
            .foregroundColor(selectedTab == tab ? .indigo : .secondary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct StatusBar: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Circle()
                    .fill(appState.dataLoaded ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text("\(appState.chunkStore.count) chunks")
                    .font(.caption)
            }

            HStack(spacing: 4) {
                Circle()
                    .fill(appState.vectorStore.isLoaded ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(appState.vectorStore.isLoaded ? "Dense+Lexical" : "Lexical only")
                    .font(.caption)
            }

            Spacer()

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
