import SwiftUI

struct SampleQuery: Identifiable {
    let id = UUID()
    let text: String
    let needsImages: Bool
}

// MARK: - Pricing queries (answers verifiable from contract data)
private let pricingQueries: [SampleQuery] = [
    SampleQuery(text: "In Platinum Groc, what is the 8.4 oz Shelf Discount and Case Cost?", needsImages: false),
    SampleQuery(text: "In Diamond Groc, what are the Shelf + Cold Cashier case costs for 8.4 oz and 12 oz?", needsImages: false),
    SampleQuery(text: "In Double Diamond Groc, what is the 8.4 oz Shelf + Cold Cashier Discount and Case Cost?", needsImages: false),
    SampleQuery(text: "In Triple Diamond Groc, what are the Shelf Program case costs for 8.4 oz and 12 oz?", needsImages: false),
    SampleQuery(text: "In Triple Diamond Conv, what are the three discount tiers and 8.4 oz case costs for each?", needsImages: false),
    SampleQuery(text: "In Platinum Liquor, what is the 8.4 oz Shelf Discount and Case Cost?", needsImages: false),
    SampleQuery(text: "What is the 16 oz EDLP Case Discount and resulting Case Cost?", needsImages: false),
    SampleQuery(text: "What are the Suggested Retail Prices for 8.4oz, 12oz, 16oz, and 20oz Red Bull?", needsImages: false),
    SampleQuery(text: "In Diamond Conv, what is the 12 oz Shelf case cost?", needsImages: false),
    SampleQuery(text: "In Double Diamond Conv, what are the Cold Cashier discounts for 8.4 oz and 12 oz?", needsImages: false),
    SampleQuery(text: "What is the 20 oz EDLP Case Discount?", needsImages: false),
    SampleQuery(text: "In Platinum Groc, what is the 12 oz Shelf + Cold Cashier case cost?", needsImages: false),
]

// MARK: - Comparison queries
private let comparisonQueries: [SampleQuery] = [
    SampleQuery(text: "Compare Platinum, Diamond, and Double Diamond Groc: what are the 8.4 oz shelf discounts?", needsImages: false),
    SampleQuery(text: "Compare Triple Diamond Conv vs Triple Diamond Groc shelf case costs for 8.4 oz and 12 oz.", needsImages: false),
    SampleQuery(text: "Which tier has the lowest 8.4 oz case cost in the Shelf + Cold Cashier program?", needsImages: false),
    SampleQuery(text: "How many Linear Feet does each Grocery tier require? List Platinum, Diamond, Double Diamond, Triple Diamond.", needsImages: false),
    SampleQuery(text: "Compare Diamond Groc vs Diamond Conv: which gives a bigger 8.4 oz shelf discount?", needsImages: false),
    SampleQuery(text: "Which is cheaper per case: Platinum Groc Shelf 8.4 oz or Platinum Liquor Shelf 8.4 oz?", needsImages: false),
    SampleQuery(text: "Rank all Grocery tiers by 12 oz Shelf case cost from cheapest to most expensive.", needsImages: false),
    SampleQuery(text: "How do Cold Cashier requirements differ between Convenience and Grocery tiers?", needsImages: false),
]

// MARK: - Policy & contract queries
private let policyQueries: [SampleQuery] = [
    SampleQuery(text: "What is the Strike Zone requirement for Red Bull shelf placement?", needsImages: false),
    SampleQuery(text: "What are the EDLP price limits for 8.4oz, 12oz, and 16oz singles?", needsImages: false),
    SampleQuery(text: "What are the Premium Cold Cashier placement requirements?", needsImages: false),
    SampleQuery(text: "Is Red Bull North America Inc. a party to the VIP Opt-In Contract?", needsImages: false),
    SampleQuery(text: "Until when is the 2025 VIP Opt-In Contract effective?", needsImages: false),
    SampleQuery(text: "How many days notice is required to change participation level?", needsImages: false),
    SampleQuery(text: "How many days does a party have to cure a material breach?", needsImages: false),
    SampleQuery(text: "What size cold equipment is required for Premium Cold Cashier?", needsImages: false),
    SampleQuery(text: "What is the minimum case purchase requirement for Triple Diamond?", needsImages: false),
    SampleQuery(text: "What happens if a retailer fails to meet shelf standards during an audit?", needsImages: false),
    SampleQuery(text: "Can a retailer participate in multiple tiers simultaneously?", needsImages: false),
    SampleQuery(text: "What are the required SKU assortments for Platinum Liquor coolers?", needsImages: false),
]

// MARK: - Image queries (evidence images from contracts)
private let imageQueries: [SampleQuery] = [
    SampleQuery(text: "Show product images from Platinum Liquor and list the 8.4 oz case cost.", needsImages: true),
    SampleQuery(text: "Show evidence images and state the EDLP limits for 8.4oz and 12oz singles.", needsImages: true),
    SampleQuery(text: "Show images from Double Diamond Groc and list the Shelf + Cold Cashier 8.4 oz case cost.", needsImages: true),
    SampleQuery(text: "Show images from Triple Diamond Groc and state the 12 oz shelf case cost.", needsImages: true),
    SampleQuery(text: "Show product images from Platinum Liquor and list the required cooler SKU assortment.", needsImages: true),
    SampleQuery(text: "Show evidence images from Diamond Groc and explain the Suggested Retail Prices.", needsImages: true),
    SampleQuery(text: "Show images from Diamond Conv and list all 8.4 oz discount tiers.", needsImages: true),
    SampleQuery(text: "Show evidence images for Strike Zone shelf placement requirements.", needsImages: true),
    SampleQuery(text: "Show images from Triple Diamond Conv and list Cold Cashier case costs.", needsImages: true),
    SampleQuery(text: "Show contract images and explain the Premium Cold Cashier equipment requirements.", needsImages: true),
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

                    Spacer()

                    Button(action: { appState.clearChat() }) {
                        Label("Clear", systemImage: "trash")
                            .font(.caption)
                    }
                    .disabled(appState.messages.isEmpty || appState.isGenerating)
                    .foregroundColor(.red)
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
                VStack(alignment: .leading, spacing: 10) {
                    querySection(title: "Pricing", queries: pricingQueries, color: .blue)
                    querySection(title: "Comparisons", queries: comparisonQueries, color: .teal)
                    querySection(title: "Policy & Contract", queries: policyQueries, color: .green)
                    querySection(title: "With evidence images", queries: imageQueries, color: .purple)
                }
                .padding(.bottom, 12)
            }
        }
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(8)
        .padding(.horizontal, 8)
    }

    private func querySection(title: String, queries: [SampleQuery], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.bold())
                .foregroundColor(color)
                .padding(.horizontal)

            FlowLayout(spacing: 6) {
                ForEach(queries) { q in
                    SampleQueryButton(query: q, color: color, disabled: appState.isGenerating) {
                        tappedQuery(q)
                    }
                }
            }
            .padding(.horizontal)
        }
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
    var color: Color = .blue
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
            .background(color.opacity(0.1))
            .foregroundColor(color)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color.opacity(0.3), lineWidth: 1)
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
