import SwiftUI

struct MessageView: View {
    let message: ChatMessage
    let resolveImage: (String) -> URL?

    @State private var showThinking = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .assistant || message.role == .system {
                roleIcon
            }
            if message.role == .user { Spacer() }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if let thinking = message.thinking, !thinking.isEmpty {
                    Button(action: { showThinking.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: showThinking ? "brain.head.profile.fill" : "brain.head.profile")
                            Text(showThinking ? "Hide reasoning" : "Show reasoning")
                        }
                        .font(.caption2)
                        .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)

                    if showThinking {
                        Text(thinking)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(8)
                            .background(Color.orange.opacity(0.08))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                            )
                    }
                }

                Text(message.text)
                    .font(message.role == .system ? .caption : .body)
                    .foregroundColor(message.role == .system ? .secondary : .primary)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(bubbleBackground)
                    .cornerRadius(12)

                if !message.images.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Evidence Images")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)

                        ForEach(message.images, id: \.self) { imagePath in
                            EvidenceImageView(
                                imagePath: imagePath,
                                resolveURL: resolveImage
                            )
                        }
                    }
                }

                if let metrics = message.metrics {
                    MetricsView(metrics: metrics)
                }
            }
            .frame(maxWidth: 600, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .user { roleIcon }
            if message.role == .assistant || message.role == .system { Spacer() }
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var roleIcon: some View {
        switch message.role {
        case .user:
            Image(systemName: "person.circle.fill")
                .foregroundColor(.blue)
                .font(.title3)
        case .assistant:
            Image(systemName: "brain.head.profile")
                .foregroundColor(.purple)
                .font(.title3)
        case .system:
            Image(systemName: "info.circle")
                .foregroundColor(.gray)
                .font(.caption)
        }
    }

    private var bubbleBackground: Color {
        switch message.role {
        case .user: return Color.blue.opacity(0.15)
        case .assistant: return Color(.systemGray6)
        case .system: return Color(.systemGray5).opacity(0.5)
        }
    }
}

struct EvidenceImageView: View {
    let imagePath: String
    let resolveURL: (String) -> URL?

    @State private var showFullscreen = false

    private var filename: String {
        (imagePath as NSString).lastPathComponent
    }

    var body: some View {
        if let url = resolveURL(imagePath), let uiImage = UIImage(contentsOfFile: url.path) {
            VStack(alignment: .leading, spacing: 4) {
                Button(action: { showFullscreen = true }) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption)
                                .padding(6)
                                .background(.ultraThinMaterial)
                                .cornerRadius(6)
                                .padding(6)
                        }
                }
                .buttonStyle(.plain)

                Text(filename)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .fullScreenCover(isPresented: $showFullscreen) {
                FullscreenImageView(image: uiImage, filename: filename)
            }
        } else {
            HStack {
                Image(systemName: "photo.badge.exclamationmark")
                Text(imagePath)
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
            .padding(6)
            .background(Color(.systemGray6))
            .cornerRadius(6)
        }
    }
}

struct FullscreenImageView: View {
    let image: UIImage
    let filename: String

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(filename)
                            .font(.caption.bold())
                            .foregroundColor(.white)
                        Text("Pinch to zoom \u{00B7} Double-tap to reset")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                    }

                    Spacer()

                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding()
                .background(Color.black.opacity(0.5))

                GeometryReader { geo in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = lastScale * value
                                }
                                .onEnded { value in
                                    lastScale = scale
                                    if scale < 1.0 {
                                        withAnimation { scale = 1.0 }
                                        lastScale = 1.0
                                    }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation {
                                if scale > 1.5 {
                                    scale = 1.0
                                    lastScale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 3.0
                                    lastScale = 3.0
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

struct MetricsView: View {
    let metrics: ChatMessage.MessageMetrics

    var body: some View {
        HStack(spacing: 12) {
            MetricPill(
                icon: "speedometer",
                value: String(format: "%.1f tok/s", metrics.tokensPerSecond)
            )
            MetricPill(
                icon: "clock",
                value: String(format: "TTFT %.0fms", metrics.ttftMs)
            )
            MetricPill(
                icon: "number",
                value: "\(metrics.tokensGenerated) tokens"
            )
            MetricPill(
                icon: "magnifyingglass",
                value: String(format: "conf %.0f%%", metrics.retrievalConfidence * 100)
            )
        }
        .font(.caption2)
    }
}

private struct MetricPill: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
            Text(value)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(.systemGray5))
        .cornerRadius(4)
        .foregroundColor(.secondary)
    }
}
