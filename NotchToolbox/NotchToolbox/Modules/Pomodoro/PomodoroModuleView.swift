import SwiftUI

struct PomodoroModuleView: View {
    let context: NotchModuleContext
    @ObservedObject var viewModel: PomodoroViewModel

    var body: some View {
        ZStack(alignment: .top) {
            PomodoroTimerRingView(
                presentation: viewModel.presentation,
                onPrimaryAction: viewModel.performPrimaryAction
            )
                .position(x: 268, y: 75)

            controlRow
                .position(x: 268, y: 166.5)

            Text(viewModel.presentation.footerText)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .position(x: 268, y: 204.5)
        }
        .frame(width: 536, height: 232)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            viewModel.setRefreshVisible(true)
        }
        .onDisappear {
            viewModel.setRefreshVisible(false)
        }
    }

    @ViewBuilder
    private var controlRow: some View {
        if viewModel.presentation.showsDurationOptions {
            PomodoroDurationPickerView(
                presentation: viewModel.presentation,
                onSelect: viewModel.selectDuration(seconds:)
            )
        } else {
            HStack(spacing: 10) {
                if viewModel.presentation.showsControlRowPrimaryAction {
                    PomodoroActionButton(
                        title: viewModel.presentation.primaryActionTitle,
                        width: 68,
                        height: 26,
                        background: .black,
                        foreground: .white.opacity(0.7),
                        action: viewModel.performPrimaryAction
                    )
                }

                if let secondaryActionTitle = viewModel.presentation.secondaryActionTitle {
                    PomodoroActionButton(
                        title: secondaryActionTitle,
                        width: 88,
                        height: 31,
                        background: .white.opacity(0.1),
                        foreground: Color(red: 1, green: 0.23, blue: 0.19).opacity(0.7),
                        action: viewModel.performSecondaryAction
                    )
                }
            }
            .frame(height: 31)
        }
    }
}

private struct PomodoroTimerRingView: View {
    let presentation: PomodoroPresentation
    let onPrimaryAction: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.2), lineWidth: 5)

            Circle()
                .trim(from: 0, to: presentation.progress)
                .stroke(
                    .white.opacity(0.72),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .opacity(presentation.progress > 0 ? 1 : 0)

            Text(presentation.timeText)
                .font(.system(size: PomodoroTimerTextMetrics.fontSize, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .monospacedDigit()
                .frame(height: PomodoroTimerTextMetrics.lineHeight)
                .position(x: 60, y: PomodoroTimerTextMetrics.centerY)

            if presentation.showsPrimaryAction {
                PomodoroActionButton(
                    title: presentation.primaryActionTitle,
                    width: 68,
                    height: 26,
                    background: Color(red: 0.102, green: 0.102, blue: 0.102),
                    foreground: .white.opacity(0.7),
                    action: onPrimaryAction
                )
                .position(x: 60, y: PomodoroTimerTextMetrics.buttonCenterY)
            }
        }
        .frame(width: 120, height: 120)
    }
}

private struct PomodoroDurationPickerView: View {
    let presentation: PomodoroPresentation
    let onSelect: (Int) -> Void

    @State private var hoveredSeconds: Int?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(presentation.durationOptions, id: \.self) { seconds in
                Button {
                    onSelect(seconds)
                } label: {
                    Text(PomodoroPresentation.durationOptionTitle(seconds: seconds))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .monospacedDigit()
                        .frame(
                            width: PomodoroDurationTabMetrics.segmentWidth(isLast: isLast(seconds)),
                            height: PomodoroDurationTabMetrics.segmentHeight
                        )
                        .background {
                            RoundedRectangle(
                                cornerRadius: PomodoroDurationTabMetrics.selectedCornerRadius,
                                style: .continuous
                            )
                            .fill(backgroundColor(for: seconds))
                        }
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    hoveredSeconds = isHovering ? seconds : (hoveredSeconds == seconds ? nil : hoveredSeconds)
                }
            }
        }
        .padding(PomodoroDurationTabMetrics.containerPadding)
        .frame(
            width: PomodoroDurationTabMetrics.containerWidth(optionCount: presentation.durationOptions.count),
            height: PomodoroDurationTabMetrics.containerHeight
        )
        .background {
            RoundedRectangle(
                cornerRadius: PomodoroDurationTabMetrics.containerCornerRadius,
                style: .continuous
            )
                .fill(.white.opacity(0.1))
        }
        .animation(.easeOut(duration: 0.12), value: hoveredSeconds)
    }

    private func isLast(_ seconds: Int) -> Bool {
        seconds == presentation.durationOptions.last
    }

    private func backgroundColor(for seconds: Int) -> Color {
        if seconds == presentation.selectedDurationSeconds {
            return .black
        }

        if hoveredSeconds == seconds {
            return .white.opacity(0.1)
        }

        return .clear
    }
}

private struct PomodoroActionButton: View {
    let title: String
    let width: CGFloat
    let height: CGFloat
    let background: Color
    let foreground: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(foreground)
                .lineLimit(1)
                .frame(width: width, height: height)
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: PomodoroButtonInteractionMetrics.cornerRadius,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(PomodoroActionButtonStyle(background: background, isHovered: isHovered))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: PomodoroButtonInteractionMetrics.animationDuration), value: isHovered)
    }
}

private struct PomodoroActionButtonStyle: ButtonStyle {
    let background: Color
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(
                    cornerRadius: PomodoroButtonInteractionMetrics.cornerRadius,
                    style: .continuous
                )
                .fill(background)
                .overlay {
                    RoundedRectangle(
                        cornerRadius: PomodoroButtonInteractionMetrics.cornerRadius,
                        style: .continuous
                    )
                    .fill(.white.opacity(overlayOpacity(isPressed: configuration.isPressed)))
                }
            }
    }

    private func overlayOpacity(isPressed: Bool) -> Double {
        if isPressed {
            return PomodoroButtonInteractionMetrics.activeOverlayOpacity
        }

        if isHovered {
            return PomodoroButtonInteractionMetrics.hoverOverlayOpacity
        }

        return 0
    }
}
