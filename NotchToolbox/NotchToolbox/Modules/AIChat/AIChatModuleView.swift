import AppKit
import SwiftUI

nonisolated enum AIChatScreen: Equatable {
    case configuration
    case empty
    case conversation

    static func from(state: AIChatModuleState) -> AIChatScreen {
        switch state {
        case .unconfigured, .configuring:
            return .configuration
        case .configuredEmpty:
            return .empty
        case .composingText,
                .composingImage,
                .sending,
                .streamingVisible,
                .streamingBackground,
                .stopped,
                .failed,
                .imageUnsupported:
            return .conversation
        }
    }
}

nonisolated enum AIChatComposerLayout {
    static let plainHeight: CGFloat = 88
    static let composerHeight: CGFloat = 72
    static let bottomInset: CGFloat = 16
    static let attachmentHeight: CGFloat = 122
    static let inputWidth: CGFloat = 480
    static let singleLineInputHeight: CGFloat = 16
    static let maxInputHeight: CGFloat = 54
    static let horizontalPadding: CGFloat = 12
    static let topPadding: CGFloat = 12
    static let bottomPadding: CGFloat = 8
    static let toolbarHeight: CGFloat = 24
    static let expandedToolbarGap: CGFloat = 6
    static let attachmentRowHeight: CGFloat = 30
    static let attachmentRowSpacing: CGFloat = 6
    static let heightAnimation = Animation.easeOut(duration: 0.16)

    static func height(forAttachmentCount count: Int) -> CGFloat {
        count > 0 ? composerHeight(for: "", attachmentCount: count) : plainHeight
    }

    static func inputHeight(for text: String, attachmentCount: Int) -> CGFloat {
        guard !text.isEmpty else {
            return singleLineInputHeight
        }

        let font = NSFont(name: "PingFang SC", size: 13) ?? .systemFont(ofSize: 13)
        let measuredRect = (text as NSString).boundingRect(
            with: CGSize(width: inputWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        let measuredHeight = ceil(measuredRect.height)
        return min(max(measuredHeight, singleLineInputHeight), maxInputHeight)
    }

    static func composerHeight(for text: String, attachments: [ConversationAttachment]) -> CGFloat {
        composerHeight(
            for: text,
            attachmentDisplayNames: attachments.map(\.displayName)
        )
    }

    static func composerHeight(for text: String, attachmentDisplayNames: [String]) -> CGFloat {
        let attachmentBlockHeight = attachmentHeight(forAttachmentDisplayNames: attachmentDisplayNames)
        return measuredComposerHeight(
            for: text,
            attachmentCount: attachmentDisplayNames.count,
            attachmentBlockHeight: attachmentBlockHeight
        )
    }

    static func composerHeight(for text: String, attachmentCount: Int) -> CGFloat {
        let attachmentBlockHeight = attachmentHeight(forAttachmentCount: attachmentCount)
        return measuredComposerHeight(
            for: text,
            attachmentCount: attachmentCount,
            attachmentBlockHeight: attachmentBlockHeight
        )
    }

    private static func measuredComposerHeight(
        for text: String,
        attachmentCount: Int,
        attachmentBlockHeight: CGFloat
    ) -> CGFloat {
        let measuredHeight = topPadding
            + attachmentBlockHeight
            + (attachmentCount > 0 ? expandedToolbarGap : 0)
            + inputHeight(for: text, attachmentCount: attachmentCount)
            + expandedToolbarGap
            + toolbarHeight
            + bottomPadding

        if attachmentCount > 0 {
            return max(attachmentHeight, measuredHeight)
        }

        return max(composerHeight, measuredHeight)
    }

    static func attachmentHeight(forAttachmentCount count: Int) -> CGFloat {
        guard count > 0 else {
            return 0
        }

        let rows = ceil(CGFloat(count) / 2)
        return (rows * attachmentRowHeight) + (max(rows - 1, 0) * attachmentRowSpacing)
    }

    static func attachmentHeight(for attachments: [ConversationAttachment]) -> CGFloat {
        attachmentHeight(forAttachmentDisplayNames: attachments.map(\.displayName))
    }

    static func attachmentHeight(forAttachmentDisplayNames displayNames: [String]) -> CGFloat {
        let rowCount = attachmentRows(forAttachmentDisplayNames: displayNames)
        guard rowCount > 0 else {
            return 0
        }

        let rows = CGFloat(rowCount)
        return (rows * attachmentRowHeight) + (max(rows - 1, 0) * attachmentRowSpacing)
    }

    private static func attachmentRows(forAttachmentDisplayNames displayNames: [String]) -> Int {
        var rowCount = 1
        var currentRowWidth: CGFloat = 0

        for displayName in displayNames {
            let pillWidth = attachmentPillWidth(for: displayName)
            let proposedWidth = currentRowWidth == 0
                ? pillWidth
                : currentRowWidth + 6 + pillWidth

            if proposedWidth > inputWidth, currentRowWidth > 0 {
                rowCount += 1
                currentRowWidth = pillWidth
            } else {
                currentRowWidth = proposedWidth
            }
        }

        return displayNames.isEmpty ? 0 : rowCount
    }

    private static func attachmentPillWidth(for displayName: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 10)
        let measuredTextWidth = ceil(
            (displayName as NSString).boundingRect(
                with: CGSize(width: 128, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            ).width
        )
        let textWidth = min(max(measuredTextWidth, 1), 128)
        return 20 + 3 + textWidth + 3 + 14 + 14
    }
}

nonisolated enum AIChatModuleChromePresentation {
    static let drawsStandaloneContentFill = false
    static let contentContainerAlignment = Alignment.top
}

nonisolated enum AIChatTheme {
    static let contentWidth: CGFloat = AIChatPanelPresentation.contentSize.width
    static let contentHeight: CGFloat = AIChatPanelPresentation.contentSize.height
    static let conversationHeight: CGFloat = 252
    static let contentCornerRadius: CGFloat = 28

    static let panelBackground = Color(red: 0.09, green: 0.09, blue: 0.09)
    static let panelBorder = Color.white.opacity(0.10)
    static let panelShadow = Color.black.opacity(0.25)
    static let contentBackground = Color(red: 0.34, green: 0.67, blue: 0.89)
    static let contentBorder = Color.white.opacity(0.10)
    static let surface = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let surfaceBorder = Color.white.opacity(0.20)
    static let rail = Color.white.opacity(0.04)
    static let selectedRail = Color.white.opacity(0.08)
    static let overlayBackdrop = Color.black.opacity(0.12)
    static let overlayCardBackground = Color(red: 0.12, green: 0.12, blue: 0.12)
    static let overlayCardBorder = Color.white.opacity(0.20)
    static let overlayDivider = Color.white.opacity(0.10)
    static let secondaryButtonFill = Color.white.opacity(0.16)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.70)
    static let textTertiary = Color.white.opacity(0.50)
    static let textPlaceholder = Color.white.opacity(0.30)
    static let errorText = Color(red: 1.0, green: 0.82, blue: 0.82)

    static let titleFont = Font.custom("PingFang SC", size: 13)
    static let bodyFont = Font.custom("PingFang SC", size: 13)
    static let captionFont = Font.custom("PingFang SC", size: 12)
}

struct AIChatOverlayDismissLayer: View {
    var fill: Color = .clear
    let onDismiss: () -> Void

    var body: some View {
        fill
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
    }
}

struct AIChatModuleView: View {
    let context: NotchModuleContext
    @ObservedObject var model: AIChatModuleModel

    var body: some View {
        content
            .frame(width: AIChatTheme.contentWidth, height: AIChatTheme.contentHeight)
            .background {
                if AIChatModuleChromePresentation.drawsStandaloneContentFill {
                    AIChatTheme.contentBackground
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: AIChatTheme.contentCornerRadius, style: .continuous)
                    .stroke(AIChatTheme.contentBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AIChatTheme.contentCornerRadius, style: .continuous))
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: AIChatModuleChromePresentation.contentContainerAlignment
            )
            .onAppear {
                model.handleVisibilityChange(isVisible: true)
            }
            .onDisappear {
                model.handleVisibilityChange(isVisible: false)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch AIChatScreen.from(state: model.state) {
        case .configuration:
            AIChatConfigurationView(
                context: context,
                providers: model.configurationSummaries,
                onSummariesChanged: model.reloadProviderSummaries
            )
        case .empty, .conversation:
            AIChatConversationView(model: model)
        }
    }
}
