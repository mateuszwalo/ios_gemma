import SwiftUI

struct MessageView: View {
    let message: ChatMessage
    let resolveImage: (String) -> URL?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .assistant || message.role == .system {
                roleIcon
            }
            if message.role == .user { Spacer() }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Main text
                Text(message.text)
                    .font(message.role == .system ? .caption : .body)
                    .foregroundColor(message.role == .system ? .secondary : .primary)
                    .padding(10)
                    .background(bubbleBackground)
                    .cornerRadius(12)

                // Evidence images
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

                // Performance metrics
                if let metrics = message.metrics {
                    MetricsView(metrics: metrics)
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.8, alignment: message.role == .user ? .trailing : .leading)

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

    var body: some View {
        if let url = resolveURL(imagePath), let uiImage = UIImage(contentsOfFile: url.path) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 300)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
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
