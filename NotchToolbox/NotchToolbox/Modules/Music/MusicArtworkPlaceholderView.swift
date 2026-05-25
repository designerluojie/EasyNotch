import SwiftUI

struct MusicArtworkPlaceholderView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.29, green: 0.22, blue: 0.13),
                            Color(red: 0.16, green: 0.12, blue: 0.09)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 18, height: 18)

            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                .frame(width: 28, height: 28)
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
