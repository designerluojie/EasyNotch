import SwiftUI

struct AIChatSessionListView: View {
    let sessions: [AIChatSession]
    let selectedSessionID: UUID?
    let onSelect: (UUID) -> Void
    let onStartNewConversation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("会话")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AIChatTheme.textTertiary)

                Spacer(minLength: 8)

                Button(action: onStartNewConversation) {
                    Label("新对话", systemImage: "square.and.pencil")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AIChatTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            ScrollView {
                VStack(spacing: 6) {
                    if sessions.isEmpty {
                        Text("暂无会话")
                            .font(.system(size: 12))
                            .foregroundStyle(AIChatTheme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                    } else {
                        ForEach(sessions) { session in
                            Button {
                                onSelect(session.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(sessionTitle(for: session))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(AIChatTheme.textPrimary)
                                        .lineLimit(1)

                                    Text(session.updatedAt, style: .time)
                                        .font(.system(size: 11))
                                        .foregroundStyle(AIChatTheme.textTertiary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(session.id == selectedSessionID ? AIChatTheme.selectedRail : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .frame(width: 148)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(AIChatTheme.rail)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func sessionTitle(for session: AIChatSession) -> String {
        if let title = session.title, !title.isEmpty {
            return title
        }

        return "新会话"
    }
}
