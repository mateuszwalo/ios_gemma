import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @State private var inputText = ""
    @State private var includeImages = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(appState.messages) { message in
                            MessageView(
                                message: message,
                                resolveImage: { appState.chunkStore.resolveImageURL($0) }
                            )
                            .id(message.id)
                        }

                        if appState.isGenerating {
                            HStack {
                                ProgressView()
                                Text("Generating...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .id("generating")
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: appState.messages.count) {
                    if let last = appState.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: appState.isGenerating) {
                    if appState.isGenerating {
                        withAnimation {
                            proxy.scrollTo("generating", anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input bar
            VStack(spacing: 8) {
                // Image toggle
                HStack {
                    Toggle(isOn: $includeImages) {
                        Label("Include evidence images", systemImage: "photo")
                            .font(.caption)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                .padding(.horizontal)

                HStack(spacing: 8) {
                    TextField("Ask about product standards...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .focused($isInputFocused)
                        .onSubmit { sendMessage() }

                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || appState.isGenerating)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .background(Color(.systemBackground))
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        isInputFocused = false

        Task {
            await appState.sendQuery(text, includeImages: includeImages)
        }
    }
}
