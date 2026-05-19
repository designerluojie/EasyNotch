import AppKit
import SwiftUI

struct ClipboardCardView: View {
    let card: ClipboardCardViewState
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(card.sourceTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(card.relativeTimeText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            previewContent
        }
        .padding(14)
        .frame(width: 180, height: 132, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: onTap)
        .disabled(card.isPastebackSupported == false)
        .opacity(card.isPastebackSupported ? 1 : 0.55)
    }

    @ViewBuilder
    private var previewContent: some View {
        switch card.previewState {
        case .textOnly:
            previewText(lineLimit: 5, font: .callout)
        case let .thumbnail(thumbnail):
            thumbnailPreview(thumbnail, showsMissingReferenceBadge: false)
        case let .thumbnailWithMissingReference(thumbnail):
            thumbnailPreview(thumbnail, showsMissingReferenceBadge: true)
        case .missingReferencePlaceholder:
            missingReferencePlaceholder
        }
    }

    private func previewText(lineLimit: Int, font: Font) -> some View {
        Text(card.previewText)
            .font(font)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .lineLimit(lineLimit)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func thumbnailPreview(
        _ thumbnail: ClipboardCardThumbnail,
        showsMissingReferenceBadge: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                thumbnailImage(for: thumbnail)
                    .frame(maxWidth: .infinity)
                    .frame(height: 74)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if showsMissingReferenceBadge {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white, Color.orange)
                        .padding(6)
                }
            }

            previewText(lineLimit: 2, font: .caption)
        }
    }

    @ViewBuilder
    private func thumbnailImage(for thumbnail: ClipboardCardThumbnail) -> some View {
        if let image = NSImage(contentsOf: thumbnail.url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay {
                    Image(systemName: fallbackSymbol(for: thumbnail.kind))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var missingReferencePlaceholder: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .frame(maxWidth: .infinity)
                .frame(height: 74)
                .overlay {
                    Image(systemName: "questionmark.folder")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }

            previewText(lineLimit: 2, font: .caption)
                .foregroundStyle(.secondary)
        }
    }

    private func fallbackSymbol(for kind: ClipboardThumbnailKind) -> String {
        switch kind {
        case .imagePreview:
            return "photo"
        case .filePreview:
            return "doc"
        case .folderPreview:
            return "folder"
        }
    }
}
