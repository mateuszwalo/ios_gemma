import SwiftUI

struct SampleQuery: Identifiable {
    let id = UUID()
    let text: String
    let needsImages: Bool
}

private let textQueries: [SampleQuery] = [
    SampleQuery(text: "In RBDC Platinum Groc - Static, what are the Shelf + Cold Cashier case costs for 8.4 oz and 12 oz?", needsImages: false),
    SampleQuery(text: "What are the EDLP limits for 8.4oz, 12oz, and 16oz singles according to the 2025 VIP Opt-In contracts?", needsImages: false),
    SampleQuery(text: "What is the Strike Zone requirement for Red Bull shelf placement?", needsImages: false),
    SampleQuery(text: "Is Red Bull North America a party to the VIP Opt-In Contract?", needsImages: false),
    SampleQuery(text: "Tell me about the recommended Red Bull Platinum Groc shelf layout and explain it briefly", needsImages: false),
    SampleQuery(text: "Compare Platinum, Diamond, and Triple Diamond: what are the 8.4 oz and 12 oz case costs in the Shelf Program?", needsImages: false),
    SampleQuery(text: "In RBDC Trpl Diamond Groc - Static, what are the Shelf + Cold Cashier case costs for 8.4 oz and 12 oz?", needsImages: false),
]

private let imageQueries: [SampleQuery] = [
    SampleQuery(text: "Show one evidence image from RBDC Platinum Groc - Static and state the Shelf + Cold Cashier case costs for 8.4 oz and 12 oz.", needsImages: true),
    SampleQuery(text: "Show one evidence image from RBDC Diamond Groc - Static and list the Suggested Retail Prices for 8.4oz and 12oz singles.", needsImages: true),
    SampleQuery(text: "Show one evidence image from RBDC Platinum Liquor - Static and state the 8.4 oz shelf discount and case cost.", needsImages: true),
    SampleQuery(text: "Show an image from the contract page where the EDLP limits (2/$5, 2/$6, 2/$8) are visible and explain them briefly.", needsImages: true),
    SampleQuery(text: "Show a picture from the Diamond or Triple Diamond contract where the Strike Zone (4-6 ft from ground) is stated and summarize the requirement.", needsImages: true),
    SampleQuery(text: "Based on the documents, show a visual example of premium cold cashier placement for Red Bull.", needsImages: true),
]

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @State private var inputText = ""
    @State private var includeImages = false
    @State private var showSamples = true
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        sampleQueriesSection

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

            VStack(spacing: 8) {
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

    private var sampleQueriesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation { showSamples.toggle() } }) {
                HStack {
                    Image(systemName: "list.bullet.rectangle")
                    Text("Sample queries")
                        .font(.caption.bold())
                    Spacer()
                    Image(systemName: showSamples ? "chevron.up" : "chevron.down")
                }
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if showSamples {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Text only")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    FlowLayout(spacing: 6) {
                        ForEach(textQueries) { q in
                            SampleQueryButton(query: q, disabled: appState.isGenerating) {
                                tappedQuery(q)
                            }
                        }
                    }
                    .padding(.horizontal)

                    Text("With evidence images")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    FlowLayout(spacing: 6) {
                        ForEach(imageQueries) { q in
                            SampleQueryButton(query: q, disabled: appState.isGenerating) {
                                tappedQuery(q)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 12)
            }
        }
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(8)
        .padding(.horizontal, 8)
    }

    private func tappedQuery(_ query: SampleQuery) {
        includeImages = query.needsImages
        Task {
            await appState.sendQuery(query.text, includeImages: query.needsImages)
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

struct SampleQueryButton: View {
    let query: SampleQuery
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: query.needsImages ? "photo" : "text.bubble")
                    .font(.caption2)
                Text(query.text)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(query.needsImages ? Color.purple.opacity(0.1) : Color.blue.opacity(0.1))
            .foregroundColor(query.needsImages ? .purple : .blue)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(query.needsImages ? Color.purple.opacity(0.3) : Color.blue.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            sizes.append(size)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return LayoutResult(
            size: CGSize(width: maxWidth, height: y + rowHeight),
            positions: positions,
            sizes: sizes
        )
    }

    struct LayoutResult {
        var size: CGSize
        var positions: [CGPoint]
        var sizes: [CGSize]
    }
}
