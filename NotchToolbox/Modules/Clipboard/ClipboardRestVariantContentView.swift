import SwiftUI

enum ClipboardRestVariantPresentation {
    static let wideStripWidth: CGFloat = 300
    static let miniPanelWidth: CGFloat = 360
    static let miniPanelHeight: CGFloat = 136
    static let transientDuration: Duration = .seconds(3)

    static func persistentRequest(
        for moduleID: NotchModuleID,
        defaultKind: RestVariantKind
    ) -> RestVariantRequest {
        switch (moduleID, defaultKind) {
        case (.clipboard, .wideNotchStrip):
            return RestVariantRequest(
                moduleID: moduleID,
                kind: .wideNotchStrip,
                preferredWidth: wideStripWidth
            )
        default:
            return RestVariantRequest(moduleID: moduleID, kind: defaultKind)
        }
    }

    static func transientPastebackSuccessRequest() -> RestVariantRequest {
        RestVariantRequest(
            moduleID: .clipboard,
            kind: .headerlessMiniPanel,
            preferredWidth: miniPanelWidth,
            preferredHeight: miniPanelHeight,
            lifetime: .transient(
                token: UUID(),
                duration: transientDuration,
                declaredAt: Date()
            )
        )
    }
}

struct ClipboardRestVariantContentView: View {
    @ObservedObject var core: ClipboardCore
    let request: RestVariantRequest
    let appearance: OverlayPanelCollapsedAppearance

    private static let relativeTimeFormatter = RelativeDateTimeFormatter()

    private var latestItem: ClipboardHistoryItem? {
        core.history.first
    }

    var body: some View {
        switch appearance {
        case .wideNotchStrip:
            wideNotchStripContent
        case .headerlessMiniPanel:
            headerlessMiniPanelContent
        case .transparent:
            EmptyView()
        }
    }

    private var wideNotchStripContent: some View {
        HStack(spacing: 10) {
            iconBadge(size: 18)

            Text(summaryText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(relativeTimeText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var headerlessMiniPanelContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                iconBadge(size: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(sourceTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))
                        .lineLimit(1)

                    Text(relativeTimeText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text("已就绪")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(accentColor.opacity(0.22))
                    )
            }

            Text(summaryText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(2)

            Text("已放回系统剪贴板，可直接粘贴")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func iconBadge(size: CGFloat) -> some View {
        Image(systemName: iconName)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(accentColor)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(accentColor.opacity(0.2))
            )
    }

    private var summaryText: String {
        let raw = latestItem?.previewText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty == false {
            return raw
        }

        switch latestItem?.contentType {
        case .image:
            return "图片已准备好"
        case .svg:
            return "SVG 已准备好"
        case .figmaGraphic:
            return "Figma 图形已准备好"
        case .figmaText:
            return "Figma 文本已准备好"
        case .file:
            return "文件已准备好"
        case .richText:
            return "富文本已准备好"
        case .plainText:
            return "文本已准备好"
        case nil:
            return appearance == .wideNotchStrip
                ? "等待新的剪贴板内容"
                : "剪贴板暂时没有可展示的内容"
        }
    }

    private var sourceTitle: String {
        if let source = latestItem?.sourceAppName, source.isEmpty == false {
            return source
        }
        return "剪贴板"
    }

    private var relativeTimeText: String {
        guard let copiedAt = latestItem?.copiedAt else {
            return "刚刚"
        }

        return Self.relativeTimeFormatter.localizedString(
            for: copiedAt,
            relativeTo: Date()
        )
    }

    private var iconName: String {
        switch latestItem?.contentType {
        case .image:
            return "photo"
        case .svg:
            return "scribble.variable"
        case .figmaGraphic, .figmaText:
            return "square.on.square"
        case .file:
            return "folder"
        case .richText:
            return "textformat.alt"
        case .plainText:
            return "text.alignleft"
        case nil:
            return request.kind == .wideNotchStrip ? "doc.on.clipboard" : "checkmark.circle.fill"
        }
    }

    private var accentColor: Color {
        switch latestItem?.contentType {
        case .image:
            return .blue
        case .svg:
            return .mint
        case .figmaGraphic, .figmaText:
            return .pink
        case .file:
            return .orange
        case .richText:
            return .purple
        case .plainText:
            return .green
        case nil:
            return .white
        }
    }
}
