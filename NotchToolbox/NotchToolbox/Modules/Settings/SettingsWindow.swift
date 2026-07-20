import AppKit
import Combine
import SwiftUI

struct SettingsWindow: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var updateController: AppUpdateController
    let onClose: () -> Void

    @State private var selectedTab: SettingsTab = .general
    @State private var isTrafficHovered = false
    @StateObject private var dropdownCoordinator = SettingsDropdownCoordinator()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SettingsWindowMetrics.cornerRadius, style: .continuous)
                .fill(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsWindowMetrics.cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.40), radius: 20, y: 8)

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 200)
                content
                    .frame(width: 400)
            }
            .clipShape(RoundedRectangle(cornerRadius: SettingsWindowMetrics.cornerRadius, style: .continuous))

            trafficLights
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if viewModel.providerDraft != nil {
                SettingsProviderConfigurationOverlay(viewModel: viewModel)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            RoundedRectangle(cornerRadius: SettingsWindowMetrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .environmentObject(dropdownCoordinator)
        .overlayPreferenceValue(SettingsDropdownAnchorPreferenceKey.self) { anchors in
            GeometryReader { proxy in
                if let activeDropdown = dropdownCoordinator.activeDropdown,
                   let anchor = anchors[activeDropdown.id] {
                    let buttonFrame = proxy[anchor]
                    let menuSize = SettingsFloatingMenuMetrics.size(for: activeDropdown.items)

                    ZStack {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                dropdownCoordinator.dismiss()
                            }

                        SettingsFloatingMenu(
                            value: activeDropdown.value,
                            items: activeDropdown.items,
                            onSelect: { item in
                                item.action()
                                dropdownCoordinator.dismiss()
                            }
                        )
                        .frame(width: menuSize.width, height: menuSize.height, alignment: .topLeading)
                        .position(
                            SettingsFloatingMenuMetrics.position(
                                buttonFrame: buttonFrame,
                                menuSize: menuSize,
                                containerSize: proxy.size
                            )
                        )
                        .transition(
                            .asymmetric(
                                insertion: .offset(y: -8).combined(with: .opacity),
                                removal: .identity
                            )
                        )
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .zIndex(1_000)
                }
            }
        }
        .frame(width: SettingsWindowMetrics.windowSize.width, height: SettingsWindowMetrics.windowSize.height)
        .shadow(color: .black.opacity(0.40), radius: 20, y: 8)
        .frame(width: SettingsWindowMetrics.outerSize.width, height: SettingsWindowMetrics.outerSize.height)
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.12), value: viewModel.providerDraft)
    }

    private var sidebar: some View {
        VStack(spacing: 2) {
            ForEach(SettingsTab.allCases) { tab in
                SettingsTabButton(
                    tab: tab,
                    isSelected: selectedTab == tab
                ) {
                    selectedTab = tab
                }
                .padding(.horizontal, 12)
            }
            Spacer()
        }
        .padding(.top, 40)
        .padding(.bottom, 12)
        .background(
            ZStack {
                SettingsSidebarGlassBackground()
                Color(red: 43 / 255, green: 43 / 255, blue: 43 / 255)
                    .opacity(0.75)
                SettingsWindowDragHandle()
            }
        )
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            Color(red: 43 / 255, green: 43 / 255, blue: 43 / 255)

            switch selectedTab {
            case .general:
                SettingsGeneralPane(viewModel: viewModel)
            case .features:
                SettingsFeaturesPane(viewModel: viewModel)
            case .about:
                SettingsAboutPane(updateController: updateController, viewModel: viewModel)
            }
        }
    }

    private var trafficLights: some View {
        SettingsTrafficLight(
            color: Color(red: 1, green: 115 / 255, blue: 106 / 255),
            isRevealed: isTrafficHovered,
            action: onClose
        )
        .padding(1)
        .onHover { isTrafficHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isTrafficHovered)
        .padding(.leading, 11)
        .padding(.top, 11)
    }
}

private struct SettingsGeneralPane: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            SettingsCheckboxRow(
                title: "登录时打开",
                isOn: viewModel.settings.launchAtLogin,
                action: { viewModel.setLaunchAtLogin(!viewModel.settings.launchAtLogin) }
            )

            SettingsGlobalShortcutRow(viewModel: viewModel)

            SettingsDivider()

            SettingsCheckboxRow(
                title: "非刘海屏模拟Mac刘海",
                isOn: viewModel.settings.simulateNotchOnNonNotchScreen,
                action: { viewModel.setSimulateNotch(!viewModel.settings.simulateNotchOnNonNotchScreen) }
            )

            SettingsDivider()

            SettingsMenuRow(
                title: "展开动效效果",
                value: viewModel.settings.animationMode.displayTitle,
                items: viewModel.supportedAnimationModes.map { mode in
                    SettingsMenuItem(title: mode.displayTitle) {
                        viewModel.setAnimationMode(mode)
                    }
                }
            )

            SettingsMenuRow(
                title: "展开动效速度",
                value: viewModel.settings.animationSpeed.displayTitle,
                items: viewModel.supportedAnimationSpeeds.map { speed in
                    SettingsMenuItem(title: speed.displayTitle) {
                        viewModel.setAnimationSpeed(speed)
                    }
                }
            )

            Spacer()
        }
        .padding(.top, 40)
        .padding(.horizontal, 12)
    }
}

private struct SettingsFeaturesPane: View {
    @ObservedObject var viewModel: SettingsViewModel

    @State private var contentHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var isIndicatorVisible = false
    @State private var hideWorkItem: DispatchWorkItem?

    private let scrollSpaceName = "SettingsFeaturesScroll"
    private let topContentPadding: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    scrollMarker(.top)

                    SettingsSectionHeader("功能排序")
                    SettingsModuleOrderBox(viewModel: viewModel)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 9)

                    SettingsDivider()

                    SettingsSectionHeader("文件暂存")
                    SettingsMenuRow(
                        title: "自动清理暂存文件",
                        value: viewModel.settings.fileStashAutoCleanupPolicy.displayTitle,
                        items: viewModel.supportedCleanupPolicies.map { policy in
                            SettingsMenuItem(title: policy.displayTitle) {
                                viewModel.setFileStashCleanupPolicy(policy)
                            }
                        }
                    )

                    SettingsDivider()

                    SettingsSectionHeader("剪贴板")
                    SettingsMenuRow(
                        title: "最大保存数",
                        value: "\(viewModel.settings.clipboardMaxItems)",
                        items: viewModel.supportedClipboardMaxItems.map { maxItems in
                            SettingsMenuItem(title: "\(maxItems)") {
                                viewModel.setClipboardMaxItems(maxItems)
                            }
                        }
                    )
                    SettingsMenuRow(
                        title: "自动清理剪贴板内容",
                        value: viewModel.settings.clipboardAutoCleanupPolicy.displayTitle,
                        items: viewModel.supportedCleanupPolicies.map { policy in
                            SettingsMenuItem(title: policy.displayTitle) {
                                viewModel.setClipboardCleanupPolicy(policy)
                            }
                        }
                    )

                    SettingsDivider()

                    SettingsSectionHeader("AI Chat")
                    SettingsMenuRow(
                        title: "对话历史保留时长",
                        value: viewModel.settings.aiChatHistoryRetention.displayTitle,
                        items: viewModel.supportedAIChatHistoryRetentions.map { retention in
                            SettingsMenuItem(title: retention.displayTitle) {
                                viewModel.setAIChatHistoryRetention(retention)
                            }
                        }
                    )

                    SettingsDivider()

                    SettingsSectionHeader("AI 模型管理")
                    SettingsProviderRows(viewModel: viewModel)
                        .padding(.bottom, 20)

                    scrollMarker(.bottom)
                }
                .padding(.top, topContentPadding)
                .padding(.horizontal, 12)
            }
            .coordinateSpace(name: scrollSpaceName)
            .scrollIndicators(.never)
            .overlay(alignment: .trailing) {
                scrollIndicator(viewportHeight: geo.size.height)
                    .allowsHitTesting(false)
            }
            .onPreferenceChange(SettingsFeaturesScrollMetricsKey.self) { metrics in
                updateMetrics(metrics, viewportHeight: geo.size.height)
            }
        }
    }

    private func scrollMarker(_ edge: SettingsFeaturesScrollEdge, height: CGFloat = 0) -> some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named(scrollSpaceName))
            Color.clear.preference(
                key: SettingsFeaturesScrollMetricsKey.self,
                value: edge == .top
                    ? SettingsFeaturesScrollMetrics(topY: frame.minY, bottomY: nil)
                    : SettingsFeaturesScrollMetrics(topY: nil, bottomY: frame.maxY)
            )
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func scrollIndicator(viewportHeight: CGFloat) -> some View {
        let verticalInset: CGFloat = 8
        let trackHeight = max(0, viewportHeight - (verticalInset * 2))
        let maxScrollOffset = max(contentHeight - viewportHeight, 0)

        if contentHeight > viewportHeight + 1,
           isIndicatorVisible,
           trackHeight > 0,
           maxScrollOffset > 1 {
            let visibleRatio = min(max(viewportHeight / max(contentHeight, 1), 0), 1)
            let thumbHeight = min(trackHeight, max(24, floor(trackHeight * visibleRatio)))
            let travel = max(trackHeight - thumbHeight, 0)
            let progress = min(max(scrollOffset / maxScrollOffset, 0), 1)
            let thumbY = verticalInset + (travel * progress)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.30))
                .frame(width: 3, height: thumbHeight)
                .frame(maxHeight: .infinity, alignment: .top)
                .offset(y: thumbY)
                .padding(.trailing, 8)
        }
    }

    private func updateMetrics(_ metrics: SettingsFeaturesScrollMetrics, viewportHeight: CGFloat) {
        guard let topY = metrics.topY, let bottomY = metrics.bottomY else {
            return
        }

        let newContentHeight = max(0, bottomY - topY + topContentPadding)
        let newOffset = max(0, topContentPadding - topY)
        let heightChanged = abs(newContentHeight - contentHeight) > 0.5
        let offsetChanged = abs(newOffset - scrollOffset) > 0.5

        // Only write @State when the value meaningfully changed, otherwise sub-pixel
        // geometry jitter feeds an endless layout → preference → @State → layout loop.
        if heightChanged {
            contentHeight = newContentHeight
        }
        if offsetChanged {
            scrollOffset = newOffset
        }

        if offsetChanged, newContentHeight > viewportHeight + 1 {
            showIndicatorTemporarily()
        }
    }

    private func showIndicatorTemporarily() {
        hideWorkItem?.cancel()
        if !isIndicatorVisible {
            withAnimation(.easeOut(duration: 0.12)) {
                isIndicatorVisible = true
            }
        }

        let workItem = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.3)) {
                isIndicatorVisible = false
            }
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }
}

private enum SettingsFeaturesScrollEdge: Equatable {
    case top
    case bottom
}

private struct SettingsFeaturesScrollMetrics: Equatable {
    var topY: CGFloat?
    var bottomY: CGFloat?

    mutating func merge(_ other: SettingsFeaturesScrollMetrics) {
        topY = other.topY ?? topY
        bottomY = other.bottomY ?? bottomY
    }
}

private struct SettingsFeaturesScrollMetricsKey: PreferenceKey {
    static var defaultValue = SettingsFeaturesScrollMetrics()

    static func reduce(value: inout SettingsFeaturesScrollMetrics, nextValue: () -> SettingsFeaturesScrollMetrics) {
        value.merge(nextValue())
    }
}

private struct SettingsAboutPane: View {
    @ObservedObject var updateController: AppUpdateController
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var toast = PanelToastPresenter()

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image("AboutLogo")
                    .resizable()
                    .frame(width: 96, height: 96)

                VStack(spacing: 4) {
                    Text("EasyNotch")
                        .font(.system(size: 14, weight: .medium))
                        .frame(height: 19)
                    Text("版本：\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")")
                        .font(.system(size: 13, weight: .regular))
                        .frame(height: 18)
                }
                .foregroundStyle(.white)

                if updateController.supportsInAppUpdates {
                    SettingsUpdateButton(updateController: updateController)
                }
            }
            .frame(width: 344)
            .padding(.vertical, 17)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 16)

            HStack {
                Text("了解我们")
                    .font(SettingsWindowTheme.bodyFont)
                    .foregroundStyle(.white)
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        guard let websiteURL = URL(string: "https://easynotch.designbento.cn") else {
                            return
                        }
                        NSWorkspace.shared.open(websiteURL)
                    } label: {
                        SettingsValuePill(text: "官方网站")
                    }
                    .buttonStyle(.plain)

                    Button {
                        guard let githubURL = URL(string: "https://github.com/designerluojie/EasyNotch-website") else {
                            return
                        }
                        NSWorkspace.shared.open(githubURL)
                    } label: {
                        SettingsValuePill(text: "Github")
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 36)
            .padding(.top, 16)
            .padding(.horizontal, 16)

            HStack {
                Text("反馈问题")
                    .font(SettingsWindowTheme.bodyFont)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    SettingsFeedbackContact.copyEmailAddress()
                    toast.show(SettingsFeedbackContact.copiedToastText, emphasis: .success)
                } label: {
                    SettingsValuePill(text: SettingsFeedbackContact.emailAddress)
                }
                .buttonStyle(.plain)
            }
            .frame(height: 36)
            .padding(.horizontal, 16)

            SettingsAboutToggleRow(
                title: "优化改进计划",
                isOn: viewModel.settings.isAnalyticsEnabled,
                action: { viewModel.setAnalyticsEnabled(!viewModel.settings.isAnalyticsEnabled) }
            )

            Spacer()
        }
        .padding(.top, 40)
        .padding(.horizontal, 12)
        .overlay(alignment: .bottom) {
            PanelToastView(presenter: toast)
        }
    }
}

private struct SettingsUpdateButton: View {
    @ObservedObject var updateController: AppUpdateController

    @State private var isHovered = false

    var body: some View {
        Button(action: updateController.performPrimaryAction) {
            Text(updateController.buttonTitle)
                .font(SettingsWindowTheme.bodyFont)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(isHovered ? 0.08 : 0))
                )
                .overlay(alignment: .topTrailing) {
                    if updateController.isUpdateAvailable {
                        Circle()
                            .fill(Color(red: 1, green: 70 / 255, blue: 78 / 255))
                            .frame(width: 6, height: 6)
                            .overlay(Circle().stroke(Color(red: 43 / 255, green: 43 / 255, blue: 43 / 255), lineWidth: 1))
                            .offset(x: 3, y: -3)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(updateController.canCheckForUpdates == false)
        .opacity(updateController.canCheckForUpdates ? 1 : 0.45)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: SettingsControlInteractionMetrics.animationDuration), value: isHovered)
        .animation(.easeOut(duration: SettingsControlInteractionMetrics.animationDuration), value: updateController.isUpdateAvailable)
    }
}

private struct SettingsModuleOrderBox: View {
    @ObservedObject var viewModel: SettingsViewModel

    @State private var order: [NotchModuleID]
    @State private var draggingModule: NotchModuleID?

    private let rowHeight: CGFloat = 28
    private let coordinateSpaceName = "SettingsModuleOrderBox"

    init(viewModel: SettingsViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _order = State(initialValue: viewModel.sortableModuleOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(order, id: \.self) { moduleID in
                row(moduleID)
            }
        }
        .coordinateSpace(name: coordinateSpaceName)
        .padding(.vertical, 4)
        .frame(width: 344)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .onChange(of: viewModel.sortableModuleOrder) { _ in
            syncOrder()
        }
    }

    private func row(_ moduleID: NotchModuleID) -> some View {
        HStack {
            Text(moduleID.settingsTitle)
                .font(SettingsWindowTheme.bodyFont)
                .foregroundStyle(.white)
            Spacer()
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(draggingModule == moduleID ? 0.9 : 0.55))
                .frame(width: 28, height: 28, alignment: .trailing)
                .contentShape(Rectangle())
                .gesture(dragGesture(for: moduleID))
        }
        .frame(height: rowHeight)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(draggingModule == moduleID ? Color.white.opacity(0.06) : .clear)
        )
    }

    private func dragGesture(for moduleID: NotchModuleID) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                if draggingModule == nil {
                    draggingModule = moduleID
                }
                guard let dragging = draggingModule,
                      let fromIndex = order.firstIndex(of: dragging) else {
                    return
                }

                let targetIndex = min(max(Int(value.location.y / rowHeight), 0), order.count - 1)
                if targetIndex != fromIndex {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        let item = order.remove(at: fromIndex)
                        order.insert(item, at: targetIndex)
                    }
                }
            }
            .onEnded { _ in
                draggingModule = nil
                viewModel.setModuleOrder(order)
            }
    }

    private func syncOrder() {
        guard draggingModule == nil else {
            return
        }
        order = viewModel.sortableModuleOrder
    }
}

private struct SettingsProviderRows: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.providerSummaries) { summary in
                HStack(spacing: 8) {
                    Image(summary.provider.settingsLogoAssetName)
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)

                    Text(summary.provider.settingsTitle)
                        .font(SettingsWindowTheme.bodyFont)
                        .foregroundStyle(.white)

                    if let maskedKey = viewModel.maskedKeyPreview(for: summary.provider) {
                        Text(maskedKey)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 8)

                    SettingsTextButton(title: summary.status == .configured ? "移除" : "立即配置") {
                        if summary.status == .configured {
                            viewModel.removeProviderConfiguration(summary.provider)
                        } else {
                            viewModel.beginProviderConfiguration(summary.provider)
                        }
                    }
                    // Cancel the button's inner horizontal padding on the trailing
                    // side so the label's right edge lines up with the dropdown
                    // values above, while the hover highlight keeps its padding.
                    .padding(.trailing, -8)
                }
                .frame(height: 36)
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct SettingsProviderConfigurationOverlay: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .onTapGesture {
                    guard viewModel.isSavingProvider == false else {
                        return
                    }
                    viewModel.cancelProviderConfiguration()
                }

            // Reuse the exact configuration card from the in-module config phase
            // so both entry points stay in lockstep. It renders as an in-window
            // overlay here — never a nested popup window.
            if let presentation = viewModel.providerOverlayPresentation {
                AIChatConfigurationOverlayCardView(
                    presentation: presentation,
                    apiKey: Binding(
                        get: { viewModel.providerDraft?.apiKey ?? "" },
                        set: { viewModel.updateProviderDraft(apiKey: $0) }
                    ),
                    selectedModelIDs: Binding(
                        get: { viewModel.providerDraft?.selectedModelIDs ?? [] },
                        set: { viewModel.updateProviderDraft(selectedModelIDs: $0) }
                    ),
                    errorMessage: viewModel.lastErrorMessage,
                    isSaving: viewModel.isSavingProvider,
                    isSubmitEnabled: viewModel.canSaveProvider,
                    onSubmit: {
                        Task {
                            await viewModel.saveProviderConfiguration()
                        }
                    }
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: SettingsWindowMetrics.cornerRadius, style: .continuous))
    }
}

private struct SettingsWindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragHandleNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragHandleNSView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

private struct SettingsSidebarGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.appearance = NSAppearance(named: .darkAqua)
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.appearance = NSAppearance(named: .darkAqua)
        nsView.material = .hudWindow
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}

private struct SettingsTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(tab.iconAssetName)
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 14, height: 14)
                Text(tab.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
            }
            .frame(height: 36)
            .padding(.horizontal, 8)
        }
        .settingsInteractionButtonStyle(
            cornerRadius: 12,
            baseColor: isSelected ? Color.white.opacity(0.08) : .clear
        )
    }
}

private struct SettingsGlobalShortcutRow: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var isRecording = false
    @State private var draftShortcut: KeyboardShortcutDescriptor?
    @State private var message: String?
    @State private var wasGlobalShortcutEnabledBeforeRecording = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                guard !isRecording else {
                    return
                }

                viewModel.setGlobalShortcutEnabled(!viewModel.settings.isGlobalShortcutEnabled)
            } label: {
                SettingsCheckboxGlyph(isOn: displayedGlobalShortcutEnabled)
            }
            .buttonStyle(.plain)

            Text("全局快捷键启动")
                .font(SettingsWindowTheme.bodyFont)
                .foregroundStyle(.white)

            Spacer()

            Button {
                startRecording()
            } label: {
                SettingsValuePill(text: shortcutTitle)
            }
            .buttonStyle(.plain)
            .overlay {
                if isRecording {
                    SettingsShortcutCaptureView(
                        onShortcutChange: handleShortcutChange,
                        onCancel: cancelRecording
                    )
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                }
            }
        }
        .frame(height: 36)
        .padding(.horizontal, 16)
        .onDisappear {
            cancelRecording()
        }
    }

    private var shortcutTitle: String {
        if let message {
            return message
        }
        if let draftShortcut {
            return draftShortcut.displayTitle
        }
        if isRecording {
            return "请输入快捷键"
        }
        return viewModel.settings.globalShortcut.displayTitle
    }

    private var displayedGlobalShortcutEnabled: Bool {
        isRecording ? wasGlobalShortcutEnabledBeforeRecording : viewModel.settings.isGlobalShortcutEnabled
    }

    private func startRecording() {
        guard !isRecording else {
            return
        }

        wasGlobalShortcutEnabledBeforeRecording = viewModel.settings.isGlobalShortcutEnabled
        if wasGlobalShortcutEnabledBeforeRecording {
            viewModel.setGlobalShortcutEnabled(false)
        }
        draftShortcut = nil
        message = nil
        isRecording = true
    }

    private func handleShortcutChange(_ shortcut: KeyboardShortcutDescriptor) {
        draftShortcut = shortcut
        guard shortcut.modifiers.isEmpty == false,
              KeyboardShortcutCarbonMapper.canMap(shortcut),
              shortcut == viewModel.settings.globalShortcut || KeyboardShortcutConflictValidator.isAvailable(shortcut) else {
            message = "快捷键冲突，请重新输入"
            return
        }

        message = nil
        viewModel.setGlobalShortcut(shortcut)
        if wasGlobalShortcutEnabledBeforeRecording {
            viewModel.setGlobalShortcutEnabled(true)
        }
        isRecording = false
        draftShortcut = nil
    }

    private func cancelRecording() {
        if isRecording, wasGlobalShortcutEnabledBeforeRecording {
            viewModel.setGlobalShortcutEnabled(true)
        }
        isRecording = false
        draftShortcut = nil
        message = nil
    }
}

private struct SettingsShortcutCaptureView: NSViewRepresentable {
    let onShortcutChange: (KeyboardShortcutDescriptor) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onShortcutChange = onShortcutChange
        view.onCancel = onCancel
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        nsView.onShortcutChange = onShortcutChange
        nsView.onCancel = onCancel
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    final class ShortcutCaptureNSView: NSView {
        var onShortcutChange: ((KeyboardShortcutDescriptor) -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            guard event.keyCode != 53 else {
                onCancel?()
                return
            }

            guard let descriptor = KeyboardShortcutDescriptor(event: event) else {
                return
            }
            onShortcutChange?(descriptor)
        }

        override func resignFirstResponder() -> Bool {
            onCancel?()
            return super.resignFirstResponder()
        }
    }
}

private struct SettingsCheckboxGlyph: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isOn ? Color.black : Color.white.opacity(0.2))
                .frame(width: 18, height: 18)
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
    }
}

private struct SettingsCheckboxRow<Trailing: View>: View {
    let title: String
    let isOn: Bool
    let trailing: () -> Trailing
    let action: () -> Void

    init(
        title: String,
        isOn: Bool,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isOn = isOn
        self.trailing = trailing
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SettingsCheckboxGlyph(isOn: isOn)
                Text(title)
                    .font(SettingsWindowTheme.bodyFont)
                    .foregroundStyle(.white)
                Spacer()
                trailing()
            }
            .frame(height: 36)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

private struct SettingsMenuRow: View {
    let title: String
    let value: String
    let items: [SettingsMenuItem]

    var body: some View {
        HStack {
            Text(title)
                .font(SettingsWindowTheme.bodyFont)
                .foregroundStyle(.white)
            Spacer()
            SettingsDropdownButton(value: value, items: items)
        }
        .frame(height: 36)
        .padding(.horizontal, 16)
    }
}

private struct SettingsDropdownButton: View {
    let value: String
    let items: [SettingsMenuItem]
    @EnvironmentObject private var dropdownCoordinator: SettingsDropdownCoordinator
    @State private var dropdownID = UUID()

    private var isPresented: Bool {
        dropdownCoordinator.activeDropdown?.id == dropdownID
    }

    var body: some View {
        Button {
            dropdownCoordinator.toggle(
                SettingsDropdownPresentation(
                    id: dropdownID,
                    value: value,
                    items: items
                )
            )
        } label: {
            SettingsMenuPill(text: value, isPressed: isPresented)
        }
        .buttonStyle(.plain)
        .anchorPreference(key: SettingsDropdownAnchorPreferenceKey.self, value: .bounds) { anchor in
            [dropdownID: anchor]
        }
        .fixedSize(horizontal: true, vertical: false)
        .zIndex(isPresented ? 20 : 0)
    }
}

@MainActor
private final class SettingsDropdownCoordinator: ObservableObject {
    @Published var activeDropdown: SettingsDropdownPresentation?

    func toggle(_ dropdown: SettingsDropdownPresentation) {
        // Only the open is animated, and the animation is scoped to this state change
        // via withAnimation. A whole-tree `.animation(value:)` modifier here caused the
        // settings window to intermittently freeze input when toggled rapidly.
        if activeDropdown?.id == dropdown.id {
            activeDropdown = nil
        } else {
            withAnimation(SettingsFloatingMenuMetrics.presentationAnimation) {
                activeDropdown = dropdown
            }
        }
    }

    func dismiss() {
        activeDropdown = nil
    }
}

private struct SettingsDropdownPresentation: Identifiable {
    let id: UUID
    let value: String
    let items: [SettingsMenuItem]
}

private struct SettingsDropdownAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: Anchor<CGRect>] = [:]

    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private enum SettingsFloatingMenuMetrics {
    static let minWidth: CGFloat = 100
    static let maxWidth: CGFloat = 300
    static let rowHeight: CGFloat = 30
    static let rowSpacing: CGFloat = 0
    static let contentPadding: CGFloat = 3.5
    static let horizontalChromeWidth: CGFloat = 36
    static let anchorGap: CGFloat = 8
    static let cornerRadius: CGFloat = 12
    static let shadowRadius: CGFloat = 16
    static let shadowYOffset: CGFloat = 4
    static let presentationAnimation = Animation.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.16)

    static func width(for items: [SettingsMenuItem]) -> CGFloat {
        let font = NSFont(name: "PingFang SC", size: 13) ?? .systemFont(ofSize: 13)
        let contentWidth = items
            .map { ($0.title as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        let idealWidth = ceil(contentWidth + horizontalChromeWidth + 28)
        return min(maxWidth, max(minWidth, idealWidth))
    }

    static func height(for items: [SettingsMenuItem]) -> CGFloat {
        let rowCount = CGFloat(items.count)
        let spacingHeight = CGFloat(max(items.count - 1, 0)) * rowSpacing
        return rowCount * rowHeight + spacingHeight + contentPadding * 2
    }

    static func size(for items: [SettingsMenuItem]) -> CGSize {
        CGSize(width: width(for: items), height: height(for: items))
    }

    static func position(
        buttonFrame: CGRect,
        menuSize: CGSize,
        containerSize: CGSize
    ) -> CGPoint {
        let margin: CGFloat = 8
        let proposedX = buttonFrame.maxX - menuSize.width / 2
        let minX = menuSize.width / 2 + margin
        let maxX = containerSize.width - menuSize.width / 2 - margin
        let x = min(max(proposedX, minX), maxX)

        let yBelow = buttonFrame.maxY + anchorGap + menuSize.height / 2
        let yAbove = buttonFrame.minY - anchorGap - menuSize.height / 2
        let y: CGFloat
        if yBelow + menuSize.height / 2 <= containerSize.height - margin {
            y = yBelow
        } else if yAbove - menuSize.height / 2 >= margin {
            y = yAbove
        } else {
            let minY = menuSize.height / 2 + margin
            let maxY = containerSize.height - menuSize.height / 2 - margin
            y = min(max(yBelow, minY), maxY)
        }

        return CGPoint(x: x, y: y)
    }
}

private struct SettingsFloatingMenu: View {
    let value: String
    let items: [SettingsMenuItem]
    let onSelect: (SettingsMenuItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsFloatingMenuMetrics.rowSpacing) {
            ForEach(items) { item in
                SettingsFloatingMenuOptionButton(
                    action: { onSelect(item) },
                    isSelected: item.title == value
                ) {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(SettingsWindowTheme.bodyFont)
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if item.title == value {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 16, alignment: .trailing)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(SettingsFloatingMenuMetrics.contentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsFloatingMenuBackground())
        .clipShape(RoundedRectangle(cornerRadius: SettingsFloatingMenuMetrics.cornerRadius, style: .continuous))
    }
}

private struct SettingsFloatingMenuBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: SettingsFloatingMenuMetrics.cornerRadius, style: .continuous)
            .fill(Color(red: 46 / 255, green: 46 / 255, blue: 46 / 255))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsFloatingMenuMetrics.cornerRadius, style: .continuous)
                    .stroke(AIChatTheme.overlayCardBorder, lineWidth: 0.5)
            )
            .shadow(
                color: AIChatTheme.panelShadow,
                radius: SettingsFloatingMenuMetrics.shadowRadius,
                x: 0,
                y: SettingsFloatingMenuMetrics.shadowYOffset
            )
    }
}

private struct SettingsFloatingMenuOptionButton<Label: View>: View {
    let action: () -> Void
    var isSelected = false
    @ViewBuilder let label: () -> Label

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label()
                .padding(.horizontal, 12)
                .frame(height: SettingsFloatingMenuMetrics.rowHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(SettingsFloatingMenuOptionButtonStyle(isHovered: isHovered, isSelected: isSelected))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

private struct SettingsFloatingMenuOptionButtonStyle: ButtonStyle {
    let isHovered: Bool
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isSelected {
            return Color(red: 31 / 255, green: 31 / 255, blue: 31 / 255)
        }

        if isPressed {
            return Color.white.opacity(0.05)
        }

        if isHovered {
            return Color.white.opacity(0.08)
        }

        return .clear
    }
}

private struct SettingsMenuPill: View {
    let text: String
    var isPressed = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(SettingsWindowTheme.bodyFont)
                .foregroundStyle(.white)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .fixedSize(horizontal: true, vertical: false)
        .background {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(SettingsControlInteractionMetrics.baseFillOpacity))
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(overlayOpacity))
                }
        }
        .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: SettingsControlInteractionMetrics.animationDuration), value: isHovered)
        .animation(.easeOut(duration: SettingsControlInteractionMetrics.animationDuration), value: isPressed)
    }

    private var overlayOpacity: Double {
        if isPressed {
            return SettingsControlInteractionMetrics.activeOverlayOpacity
        }
        if isHovered {
            return SettingsControlInteractionMetrics.hoverOverlayOpacity
        }
        return 0
    }
}

private struct SettingsValuePill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(SettingsWindowTheme.bodyFont)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(
                Color.white.opacity(SettingsControlInteractionMetrics.baseFillOpacity),
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
    }
}

/// 「关于」页专用的开关行：标题在左，勾选控件在右。
/// 与该页其它行（了解我们 / 反馈问题）保持「左标题、右控件」的布局，
/// 而非通用的 SettingsCheckboxRow（那个是勾选框在左）。
///
/// 采集边界放在悬停提示里而非副标题：界面保持简洁，但用户想了解时仍能看到，
/// 这是本 App 唯一的埋点告知载体（官网不另设隐私说明页）。
private struct SettingsAboutToggleRow: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    @State private var isInfoHovered = false
    @State private var isTooltipVisible = false
    @State private var tooltipTask: Task<Void, Never>?

    private static let tooltipText = "仅统计功能使用次数，不含任何个人信息与聊天内容"

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 6) {
                Text(title)
                    .font(SettingsWindowTheme.bodyFont)
                    .foregroundStyle(.white)
                // 采集边界的告知载体（官网不另设隐私说明页）：悬停图标显示说明。
                // 系统 .help 在这个自定义面板窗口里不弹，改为自绘 tooltip——
                // 悬停 0.5s 后出现，配色与设置页下拉菜单一致。
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(isInfoHovered ? 0.9 : 0.4))
                    .animation(.easeOut(duration: 0.12), value: isInfoHovered)
                    .onHover { hovering in
                        isInfoHovered = hovering
                        tooltipTask?.cancel()
                        if hovering {
                            tooltipTask = Task {
                                try? await Task.sleep(for: .milliseconds(500))
                                guard Task.isCancelled == false else { return }
                                isTooltipVisible = true
                            }
                        } else {
                            isTooltipVisible = false
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if isTooltipVisible {
                            Text(Self.tooltipText)
                                .font(SettingsWindowTheme.bodyFont)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(SettingsFloatingMenuBackground())
                                .clipShape(RoundedRectangle(cornerRadius: SettingsFloatingMenuMetrics.cornerRadius, style: .continuous))
                                .fixedSize()
                                .offset(x: -12, y: -34)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeOut(duration: 0.12), value: isTooltipVisible)
                Spacer()
                SettingsCheckboxGlyph(isOn: isOn)
            }
            .frame(height: 36)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

private struct SettingsTextButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(SettingsWindowTheme.bodyFont)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(height: 24)
                // Weakened, text-first button: no persistent fill, just an 8%
                // white hover highlight — matches the notch's settings-entry
                // button pattern (design node 71:13745).
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(isHovered ? 0.08 : 0))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: SettingsControlInteractionMetrics.animationDuration), value: isHovered)
    }
}

private struct SettingsTrafficLight: View {
    let color: Color
    let isRevealed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .overlay(Circle().stroke(Color.black.opacity(0.1), lineWidth: 0.5))
                .overlay {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.5))
                        .opacity(isRevealed ? 1 : 0)
                }
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsSectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(SettingsWindowTheme.bodyFont)
            .foregroundStyle(Color.white.opacity(0.5))
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .padding(.horizontal, 16)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(height: 0.5)
            .padding(.vertical, 5)
    }
}

private struct SettingsInteractionButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat
    let baseColor: Color
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(baseColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(overlayOpacity(isPressed: configuration.isPressed)))
                    }
            }
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: SettingsControlInteractionMetrics.animationDuration), value: isHovered)
    }

    private func overlayOpacity(isPressed: Bool) -> Double {
        if isPressed {
            return SettingsControlInteractionMetrics.activeOverlayOpacity
        }
        if isHovered {
            return SettingsControlInteractionMetrics.hoverOverlayOpacity
        }
        return 0
    }
}

enum SettingsControlInteractionMetrics {
    static let baseFillOpacity = 0.08
    static let hoverOverlayOpacity = 0.10
    static let activeOverlayOpacity = 0.05
    static let animationDuration = 0.12
}

private extension View {
    func settingsInteractionButtonStyle(cornerRadius: CGFloat, baseColor: Color) -> some View {
        buttonStyle(SettingsInteractionButtonStyle(cornerRadius: cornerRadius, baseColor: baseColor))
    }
}

private enum SettingsWindowTheme {
    static let bodyFont = Font.system(size: 13, weight: .regular)
}

private enum SettingsTab: CaseIterable, Identifiable {
    case general
    case features
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general:
            return "通用"
        case .features:
            return "功能选项"
        case .about:
            return "关于我"
        }
    }

    var iconAssetName: String {
        switch self {
        case .general:
            return "SettingsTabSettingIcon"
        case .features:
            return "SettingsTabFunctionIcon"
        case .about:
            return "SettingsTabInfoIcon"
        }
    }
}

private struct SettingsMenuItem: Identifiable {
    let id = UUID()
    let title: String
    let action: () -> Void
}

private extension KeyboardShortcutDescriptor {
    init?(event: NSEvent) {
        guard let key = event.charactersIgnoringModifiers?.lowercased().first,
              key.isWhitespace == false else {
            return nil
        }

        var modifiers: [ShortcutModifier] = []
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            modifiers.append(.command)
        }
        if flags.contains(.option) {
            modifiers.append(.option)
        }
        if flags.contains(.control) {
            modifiers.append(.control)
        }
        if flags.contains(.shift) {
            modifiers.append(.shift)
        }

        self.init(
            keyEquivalent: String(key),
            modifiers: modifiers
        )
    }

    var displayTitle: String {
        let modifierTitle = modifiers.map(\.displayTitle).joined(separator: " + ")
        return "\(modifierTitle) + \(keyEquivalent.uppercased())"
    }
}

private extension ShortcutModifier {
    var displayTitle: String {
        switch self {
        case .command:
            return "Command"
        case .option:
            return "Option"
        case .control:
            return "Control"
        case .shift:
            return "Shift"
        }
    }
}

private extension AnimationMode {
    var displayTitle: String {
        switch self {
        case .natural:
            return "自然"
        case .springy:
            return "Q弹"
        }
    }
}

private extension AnimationSpeed {
    var displayTitle: String {
        switch self {
        case .slow:
            return "慢"
        case .normal:
            return "正常"
        case .fast:
            return "快"
        }
    }
}

private extension CleanupPolicy {
    var displayTitle: String {
        switch self {
        case .none:
            return "不自动清理"
        case .daily:
            return "每日"
        case .weekly:
            return "每周"
        case .monthly:
            return "每月"
        }
    }
}

private extension NotchModuleID {
    var settingsTitle: String {
        switch self {
        case .music:
            return "音乐"
        case .fileStash:
            return "文件"
        case .aiChat:
            return "AI Chat"
        case .clipboard:
            return "剪贴板"
        case .pomodoro:
            return "番茄钟"
        case .settings:
            return "设置"
        }
    }
}

private extension AIProviderKind {
    var settingsTitle: String {
        AIChatConfigurationPresentation.providerTitle(for: self)
    }

    var settingsLogoAssetName: String {
        switch self {
        case .deepseek:
            return "AIProviderDeepSeek"
        case .qwen:
            return "AIProviderQwen"
        case .chatgpt:
            return "AIProviderChatGPT"
        case .gemini:
            return "AIProviderGemini"
        }
    }
}
