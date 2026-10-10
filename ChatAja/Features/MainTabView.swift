import SwiftUI

// MARK: - Main Tab with Liquid Glass

struct MainTabView: View {
    @State private var selected = 0

    var body: some View {
        TabView(selection: $selected) {
            FeedView()
                .tabItem { Label("Utas", systemImage: "text.bubble") }
                .tag(0)

            ContactsView()
                .tabItem { Label("Chat", systemImage: "message") }
                .tag(1)

            NotificationsView()
                .tabItem { Label("Notifikasi", systemImage: "bell") }
                .tag(2)

            ProfileView()
                .tabItem { Label("Profil", systemImage: "person") }
                .tag(3)
        }
        // Liquid Glass (iOS 26+). Fallback otomatis ke blur di iOS lama.
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
    }
}

// MARK: - Placeholder Views

struct ContactsView: View {
    @State private var contacts: [Contact] = []
    var body: some View {
        NavigationStack {
            List(contacts) { c in
                HStack {
                    Text(c.partnerName.isEmpty ? c.userId.prefix(8) : c.partnerName)
                    Spacer()
                    if c.unreadCount > 0 {
                        Text("\(c.unreadCount)")
                            .font(.caption).bold()
                            .padding(6)
                            .background(.red)
                            .foregroundStyle(.white)
                            .clipShape(Circle())
                    }
                }
            }
            .navigationTitle("Chat")
            .task { await load() }
            .refreshable { await load() }
        }
    }
    func load() async {
        do {
            let res: APIResponse<ContactsData> = try await APIClient.shared.get("/chat/contacts")
            contacts = res.data?.contacts ?? []
        } catch { print("contacts error:", error) }
    }
}
struct ContactsData: Decodable { let contacts: [Contact] }

struct NotificationsView: View {
    @State private var notifs: [AppNotification] = []
    var body: some View {
        NavigationStack {
            List(notifs) { n in
                VStack(alignment: .leading) {
                    Text(n.title).bold()
                    Text(n.body).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Notifikasi")
            .task { await load() }
            .refreshable { await load() }
        }
    }
    func load() async {
        do {
            let res: APIResponse<NotifsData> = try await APIClient.shared.get("/chat/notifications")
            notifs = res.data?.notifications ?? []
        } catch { print("notifs error:", error) }
    }
}
struct NotifsData: Decodable { let notifications: [AppNotification]; let unreadCount: Int }

struct ProfileView: View {
    @State private var profile: Profile?
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let p = profile {
                    if !p.avatarUrl.isEmpty {
                        AsyncImage(url: URL(string: p.avatarUrl)) { $0.resizable() } placeholder: { Color.gray }
                            .frame(width: 80, height: 80).clipShape(Circle())
                    }
                    Text(p.displayName).font(.title2).bold()
                    if !p.bio.isEmpty { Text(p.bio).foregroundStyle(.secondary) }
                    if p.isVerified { Label("Verified", systemImage: "checkmark.seal.fill").foregroundStyle(.blue) }
                } else { ProgressView() }
                Spacer()
            }
            .padding()
            .navigationTitle("Profil")
            .task { await load() }
        }
    }
    func load() async {
        do {
            let res: APIResponse<ProfileData> = try await APIClient.shared.get("/account/profile")
            profile = res.data?.profile
        } catch { print("profile error:", error) }
    }
}
struct ProfileData: Decodable { let profile: Profile }
