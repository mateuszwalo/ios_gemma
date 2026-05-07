import SwiftUI

struct SampleQuery: Identifiable {
    let id = UUID()
    let text: String
    let needsImages: Bool
}

private let textQueries: [SampleQuery] = [
    SampleQuery(text: "What are the Shelf + Cold Cashier case costs for 8.4 oz and 12 oz in RBDC Platinum Groc?", needsImages: false),
    SampleQuery(text: "What are the EDLP price limits for 8.4oz, 12oz, and 16oz singles?", needsImages: false),
    SampleQuery(text: "What is the Strike Zone requirement for Red Bull shelf placement?", needsImages: false),
    SampleQuery(text: "Is Red Bull North America Inc. a party to the VIP Opt-In Contract?", needsImages: false),
    SampleQuery(text: "Compare Platinum, Diamond, and Double Diamond: what are the 8.4 oz shelf discounts and case costs?", needsImages: false),
    SampleQuery(text: "What are the Suggested Retail Prices for 8.4oz, 12oz, 16oz, and 20oz?", needsImages: false),
    SampleQuery(text: "In Triple Diamond Conv, what are the three pricing tiers and their 8.4 oz case costs?", needsImages: false),
    SampleQuery(text: "What is the 16 oz EDLP Case Discount and resulting Case Cost?", needsImages: false),
    SampleQuery(text: "What are the Premium Cold Cashier placement requirements?", needsImages: false),
]

private let imageQueries: [SampleQuery] = [
    SampleQuery(text: "Show the Platinum Liquor product assortment and list the 8.4 oz shelf discount and case cost.", needsImages: true),
    SampleQuery(text: "Show Red Bull product images and explain the EDLP pricing limits for all sizes.", needsImages: true),
    SampleQuery(text: "Show evidence images and compare Triple Diamond Groc vs Double Diamond Groc shelf case costs.", needsImages: true),
    SampleQuery(text: "Show product images from the Platinum Liquor contract and list all required cooler SKU assortment.", needsImages: true),
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
