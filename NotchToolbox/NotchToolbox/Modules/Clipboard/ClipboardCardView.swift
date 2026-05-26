import AppKit
import SwiftUI

struct ClipboardCardView: View {
    let card: ClipboardCardViewState
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                headerRow
                previewContent
            }
            .padding(.horizontal, ClipboardCardLayout.cardPadding.width)
            .padding(.vertical, ClipboardCardLayout.cardPadding.height)
            .frame(
                width: ClipboardCardLayout.cardSize.width,
                height: ClipboardCardLayout.cardSize.height,
                alignment: .topLeading
            )
        }
        .buttonStyle(
            ClipboardCardButtonStyle(
                isHovered: isHovered,
                isEnabled: card.isPastebackSupported
            )
        )
        .onHover { hovered in
            isHovered = hovered
        }
        .disabled(card.isPastebackSupported == false)
        .opacity(card.isPastebackSupported ? 1 : 0.55)
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 6) {
            sourceIcon

            Spacer(minLength: 4)

            Text(card.relativeTimeText)
                .font(.system(size: ClipboardCardLayout.timeFontSize, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.5))
                .lineLimit(1)
        }
        .frame(width: ClipboardCardLayout.previewSize.width, alignment: .leading)
    }

    @ViewBuilder
    private var previewContent: some View {
        switch card.previewState {
        case .textOnly:
            previewText(lineLimit: 5)
        case let .thumbnail(thumbnail):
            thumbnailPreview(thumbnail, showsMissingReferenceBadge: false)
        case let .thumbnailWithMissingReference(thumbnail):
            thumbnailPreview(thumbnail, showsMissingReferenceBadge: true)
        case .missingReferencePlaceholder:
            missingReferencePlaceholder
        }
    }

    private func previewText(lineLimit: Int) -> some View {
        Text(card.previewText)
            .font(.system(size: ClipboardCardLayout.previewFontSize, weight: .regular))
            .foregroundStyle(Color.white)
            .lineSpacing(ClipboardCardLayout.previewLineSpacing)
            .multilineTextAlignment(.leading)
            .lineLimit(lineLimit)
            .frame(
                width: ClipboardCardLayout.previewSize.width,
                height: ClipboardCardLayout.previewSize.height,
                alignment: .topLeading
            )
    }

    private func thumbnailPreview(
        _ thumbnail: ClipboardCardThumbnail,
        showsMissingReferenceBadge: Bool
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            thumbnailImage(for: thumbnail)
                .frame(
                    width: ClipboardCardLayout.previewSize.width,
                    height: ClipboardCardLayout.previewSize.height,
                    alignment: .center
                )
                .background(
                    RoundedRectangle(
                        cornerRadius: ClipboardCardLayout.previewCornerRadius,
                        style: .continuous
                    )
                    .fill(Color.white.opacity(0.03))
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: ClipboardCardLayout.previewCornerRadius,
                        style: .continuous
                    )
                )

            if showsMissingReferenceBadge {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white, Color.orange)
                    .padding(4)
            }
        }
    }

    @ViewBuilder
    private func thumbnailImage(for thumbnail: ClipboardCardThumbnail) -> some View {
        if let image = NSImage(contentsOf: thumbnail.url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
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
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(
                cornerRadius: ClipboardCardLayout.previewCornerRadius,
                style: .continuous
            )
            .fill(Color.white.opacity(0.05))
            .frame(
                width: ClipboardCardLayout.previewSize.width,
                height: ClipboardCardLayout.previewSize.height
            )
            .overlay {
                Image(systemName: "questionmark.folder")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white, Color.orange)
                .padding(4)
        }
    }

    @ViewBuilder
    private var sourceIcon: some View {
        if let appIcon = sourceApplicationIcon {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .frame(
                    width: ClipboardCardLayout.sourceIconSize,
                    height: ClipboardCardLayout.sourceIconSize
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(
                    width: ClipboardCardLayout.sourceIconSize,
                    height: ClipboardCardLayout.sourceIconSize
                )
                .overlay {
                    Image(systemName: fallbackSourceSymbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.78))
                }
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

    private var fallbackSourceSymbol: String {
        switch card.contentType {
        case .plainText, .richText, .figmaText:
            return "text.alignleft"
        case .image, .svg, .figmaGraphic:
            return "photo"
        case .file:
            return "doc"
        }
    }

    private var sourceApplicationIcon: NSImage? {
        if let bundleID = card.sourceAppBundleID,
           let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        {
            return NSWorkspace.shared.icon(forFile: applicationURL.path(percentEncoded: false))
        }

        return nil
    }
}

private struct ClipboardCardButtonStyle: ButtonStyle {
    let isHovered: Bool
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isInteractive = isEnabled && (isHovered || configuration.isPressed)

        return configuration.label
            .background {
                ClipboardCardInteractionBackground(isVisible: isInteractive)
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: ClipboardCardLayout.cardCornerRadius,
                    style: .continuous
                )
            )
            .contentShape(
                RoundedRectangle(
                    cornerRadius: ClipboardCardLayout.cardCornerRadius,
                    style: .continuous
                )
            )
    }
}

private struct ClipboardCardInteractionBackground: View {
    let isVisible: Bool

    var body: some View {
        RoundedRectangle(
            cornerRadius: ClipboardCardLayout.cardCornerRadius,
            style: .continuous
        )
        .fill(
            isVisible
            ? Color.white.opacity(ClipboardCardLayout.interactionFillOpacity)
            : Color.clear
        )
        .animation(
            .easeOut(duration: ClipboardCardLayout.hoverAnimationDuration),
            value: isVisible
        )
    }
}
