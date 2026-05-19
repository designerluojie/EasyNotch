import SwiftUI

struct ClipboardModuleView: View {
    let context: NotchModuleContext
    @ObservedObject var viewModel: ClipboardViewModel
    var onSuccessfulPaste: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clipboard")
                .font(.title3.weight(.semibold))

            Group {
                if viewModel.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.title2)
                            .foregroundStyle(.tertiary)

                        Text("你还没有剪贴板内容")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(viewModel.cards) { card in
                                ClipboardCardView(card: card) {
                                    viewModel.paste(itemID: card.id, onSuccess: onSuccessfulPaste)
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .frame(minHeight: 146)
                }
            }

            if let lastPasteError = viewModel.lastPasteError {
                Text(lastPasteError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.20, blue: 0.25),
                            Color(red: 0.11, green: 0.12, blue: 0.16),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        }
        .onAppear {
            viewModel.refresh()
        }
    }
}
