import SwiftUI

struct MusicEmptyContentView: View {
    let emptyState: MusicModuleViewModel.EmptyPresentation
    let viewModel: MusicModuleViewModel

    var body: some View {
        VStack(spacing: 11) {
            Text(emptyState.message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))

            HStack(spacing: 16) {
                ForEach(emptyState.launchTargets) { target in
                    launchTargetView(target)
                }
            }
        }
        .frame(width: 536, height: 56, alignment: .top)
    }

    @ViewBuilder
    private func launchTargetView(_ target: MusicModuleViewModel.LaunchTarget) -> some View {
        if target.isInteractive {
            Button {
                Task {
                    await viewModel.launch(target)
                }
            } label: {
                MusicPlayerIconView(asset: target.iconAsset, size: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Launch \(target.displayName)"))
        } else {
            MusicPlayerIconView(asset: target.iconAsset, size: 28)
                .accessibilityLabel(Text(target.displayName))
        }
    }
}
