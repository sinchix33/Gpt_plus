import SwiftUI

// MARK: - Navigation Sidebar Drawer

public struct SidebarView: View {
    @Bindable public var listViewModel: ConversationListViewModel
    @State private var authManager = AuthenticationManager.shared

    public let onSelectConversation: (String) -> Void
    public let onNewChat: () -> Void
    public let onOpenSettings: () -> Void
    public var onOpenLogin: (() -> Void)?

    public init(
        listViewModel: ConversationListViewModel,
        onSelectConversation: @escaping (String) -> Void,
        onNewChat: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenLogin: (() -> Void)? = nil
    ) {
        self.listViewModel = listViewModel
        self.onSelectConversation = onSelectConversation
        self.onNewChat = onNewChat
        self.onOpenSettings = onOpenSettings
        self.onOpenLogin = onOpenLogin
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerView
            conversationHistoryView
            Divider()
            profileFooterView
        }
        .task {
            await listViewModel.loadConversations()
        }
    }

    private var headerView: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $listViewModel.searchQuery)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(uiColor: .tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button(action: onNewChat) {
                Image(systemName: "square.and.pencil")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .padding(8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var conversationHistoryView: some View {
        List {
            Section {
                ForEach(listViewModel.filteredConversations) { conversation in
                    conversationRow(
                        id: conversation.id,
                        title: conversation.title
                    )
                }
            } header: {
                Text("Recent Chats")
            }
        }
        .listStyle(.plain)
    }

    private func conversationRow(id: String, title: String) -> some View {
        Button {
            onSelectConversation(id)
        } label: {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task {
                    await listViewModel.deleteConversation(id: id)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var profileFooterView: some View {
        HStack(spacing: 12) {
            accountButton
            Spacer()
            settingsButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var accountButton: some View {
        Button {
            if authManager.isAuthenticated {
                onOpenSettings()
            } else {
                onOpenLogin?()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: accountIconName)
                    .font(.title2)
                    .foregroundStyle(accountIconColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(accountTitle)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(accountPlanTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var settingsButton: some View {
        Button(action: onOpenSettings) {
            Image(systemName: "ellipsis")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(8)
        }
    }

    private var accountIconName: String {
        authManager.isAuthenticated
            ? "person.crop.circle.fill"
            : "person.crop.circle.badge.plus"
    }

    private var accountIconColor: Color {
        authManager.isAuthenticated ? .secondary : Color.accentColor
    }

    private var accountTitle: String {
        authManager.isAuthenticated ? "Signed In" : "Sign In"
    }

    private var accountPlanTitle: String {
        authManager.isAuthenticated ? "Account" : "Tap to log in"
    }
}
