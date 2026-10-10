import SwiftUI

// MARK: - Main Tab with Liquid Glass (PRD bagian 4)

struct MainTabView: View {
    @State private var selected = 0
    @State private var unreadNotif = 0

    var body: some View {
        TabView(selection: $selected) {
            FeedView()
                .tabItem { Label("Utas", systemImage: "text.bubble") }
                .tag(0)

            ContactsView()
                .tabItem { Label("Chat", systemImage: "message") }
                .tag(1)

            NotificationsView(unreadCount: $unreadNotif)
                .tabItem { Label("Notifikasi", systemImage: "bell") }
                .badge(unreadNotif > 0 ? Text("\(unreadNotif)") : nil)
                .tag(2)

            ProfileView()
                .tabItem { Label("Profil", systemImage: "person") }
                .tag(3)
        }
        // Liquid Glass: material blur untuk tab bar, fallback otomatis di iOS lama.
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .task { await refreshBadge() }
        .onChange(of: selected) { _, _ in Task { await refreshBadge() } }
    }

    func refreshBadge() async {
        // Tab notifikasi yang aktif memiliki datanya sendiri (load + tandai
        // dibaca); jangan timpa dari sini agar tidak balapan.
        guard selected != 2 else { return }
        do {
            let res: APIResponse<NotifsData> = try await APIClient.shared.get("/chat/notifications")
            unreadNotif = res.data?.unreadCount ?? 0
        } catch { /* badge abai saat offline */ }
    }
}

// MARK: - Chat Kontak (PRD 3.5)

struct ContactsView: View {
    @State private var contacts: [Contact] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    List {
                        ForEach(0..<5, id: \.self) { _ in
                            HStack(spacing: 12) {
                                Circle().fill(.quaternary).frame(width: 44, height: 44)
                                VStack(alignment: .leading, spacing: 6) {
                                    SkeletonBar(width: 140)
                                    SkeletonBar(width: 200)
                                }
                            }
                            .redacted(reason: .placeholder)
                        }
                    }
                    .listStyle(.plain)
                } else if let err = errorMessage, contacts.isEmpty {
                    ErrorStateView(pesan: err) { Task { await load() } }
                } else if contacts.isEmpty {
                    EmptyStateView(
                        icon: "message",
                        judul: "Belum ada chat",
                        pesan: "Chat muncul setelah kamu menyapa penulis utas."
                    )
                } else {
                    List(contacts) { c in
                        NavigationLink {
                            if let roomId = c.roomId, !roomId.isEmpty {
                                ChatRoomView(
                                    roomId: roomId,
                                    partnerName: displayName(for: c),
                                    myUserId: AuthManager.shared.uid ?? "",
                                    partnerUserId: c.userId
                                )
                            } else {
                                EmptyStateView(
                                    icon: "message",
                                    judul: "Room belum tersedia",
                                    pesan: "Kontak ini belum punya room chat. Coba lagi nanti."
                                )
                            }
                        } label: {
                            HStack(spacing: 12) {
                                avatar(for: c)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(displayName(for: c))
                                        .font(.subheadline).bold()
                                        .lineLimit(1)
                                    Text(c.lastMessage.isEmpty ? "Belum ada pesan" : c.lastMessage)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(waktuRelatif(c.lastMessageTime))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if c.unreadCount > 0 {
                                        Text("\(c.unreadCount)")
                                            .font(.caption2).bold()
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(Brand.indigo)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Chat")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    func displayName(for c: Contact) -> String {
        c.partnerName.isEmpty ? String(c.userId.prefix(8)) : c.partnerName
    }

    @ViewBuilder
    func avatar(for c: Contact) -> some View {
        if !c.partnerAvatar.isEmpty, c.partnerAvatar.hasPrefix("http") {
            AsyncImage(url: URL(string: c.partnerAvatar)) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: InitialAvatarView(nama: displayName(for: c))
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
        } else {
            InitialAvatarView(nama: displayName(for: c))
        }
    }

    func load() async {
        if contacts.isEmpty { isLoading = true }
        errorMessage = nil
        do {
            let res: APIResponse<ContactsData> = try await APIClient.shared.get("/chat/contacts")
            if let apiErr = res.error, res.success == false {
                errorMessage = apiErr
            } else {
                contacts = res.data?.contacts ?? []
            }
        } catch {
            if contacts.isEmpty {
                errorMessage = "Gagal memuat chat. Periksa koneksi lalu coba lagi."
            }
        }
        isLoading = false
    }
}

struct ContactsData: Decodable { let contacts: [Contact] }

// MARK: - Notifikasi (PRD 3.7)

struct NotificationsView: View {
    @Binding var unreadCount: Int
    @State private var notifs: [AppNotification] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    List {
                        ForEach(0..<5, id: \.self) { _ in
                            HStack(spacing: 12) {
                                Circle().fill(.quaternary).frame(width: 36, height: 36)
                                VStack(alignment: .leading, spacing: 6) {
                                    SkeletonBar(width: 180)
                                    SkeletonBar(width: 240)
                                }
                            }
                            .redacted(reason: .placeholder)
                        }
                    }
                    .listStyle(.plain)
                } else if let err = errorMessage, notifs.isEmpty {
                    ErrorStateView(pesan: err) { Task { await load() } }
                } else if notifs.isEmpty {
                    EmptyStateView(
                        icon: "bell",
                        judul: "Belum ada notifikasi",
                        pesan: "Like, balasan, dan pesan baru akan muncul di sini."
                    )
                } else {
                    List(notifs) { n in
                        NavigationLink {
                            destination(for: n)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                if !n.isRead {
                                    Circle().fill(Brand.indigo)
                                        .frame(width: 8, height: 8)
                                        .padding(.top, 6)
                                } else {
                                    Spacer().frame(width: 8)
                                }
                                Image(systemName: icon(for: n.type))
                                    .font(.body)
                                    .foregroundStyle(Brand.indigo)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(n.title).font(.subheadline).bold().lineLimit(2)
                                    Text(n.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                    Text(waktuRelatif(n.createdAt))
                                        .font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .listRowBackground(n.isRead ? nil : Brand.indigo.opacity(0.07))
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Notifikasi")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    func icon(for type: String) -> String {
        switch type.lowercased() {
        case "like": return "heart.fill"
        case "reply", "comment": return "bubble.right.fill"
        case "follow": return "person.fill"
        case "message", "chat": return "message.fill"
        default: return "bell.fill"
        }
    }

    @ViewBuilder
    func destination(for n: AppNotification) -> some View {
        if let roomId = n.roomId, !roomId.isEmpty {
            ChatRoomView(
                roomId: roomId,
                partnerName: n.title.isEmpty ? "Chat" : n.title,
                myUserId: AuthManager.shared.uid ?? ""
            )
            .onAppear { Task { await markOneRead(n) } }
        } else if let utasId = n.utasId, !utasId.isEmpty {
            ThreadView(postId: utasId)
                .onAppear { Task { await markOneRead(n) } }
        } else {
            EmptyStateView(icon: "bell", judul: "Notifikasi", pesan: n.body)
                .onAppear { Task { await markOneRead(n) } }
        }
    }

    func load() async {
        if notifs.isEmpty { isLoading = true }
        errorMessage = nil
        do {
            let res: APIResponse<NotifsData> = try await APIClient.shared.get("/chat/notifications")
            if let apiErr = res.error, res.success == false {
                errorMessage = apiErr
            } else {
                notifs = res.data?.notifications ?? []
                unreadCount = res.data?.unreadCount ?? 0
            }
        } catch {
            if notifs.isEmpty {
                errorMessage = "Gagal memuat notifikasi. Periksa koneksi lalu coba lagi."
            }
        }
        isLoading = false
    }

    /// Tandai SATU notifikasi dibaca saat tujuannya dibuka (PRD 3.7).
    func markOneRead(_ n: AppNotification) async {
        guard !n.isRead else { return }
        struct Body: Encodable { let notificationIds: [String] }
        struct D: Decodable { let ok: Bool? }
        do {
            let _: APIResponse<D> = try await APIClient.shared.post("/chat/notifications/read", body: Body(notificationIds: [n.id]))
            notifs = notifs.map { item in
                guard item.id == n.id else { return item }
                return AppNotification(id: item.id, type: item.type, title: item.title, body: item.body,
                                       roomId: item.roomId, utasId: item.utasId, isRead: true, createdAt: item.createdAt)
            }
            unreadCount = notifs.filter { !$0.isRead }.count
        } catch { /* badge tetap, coba lagi saat buka berikutnya */ }
    }
}

struct NotifsData: Decodable { let notifications: [AppNotification]; let unreadCount: Int }

// MARK: - Profil (PRD 3.8)

struct ProfileView: View {
    @State private var profile: Profile?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showEdit = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        Circle().fill(.quaternary).frame(width: 80, height: 80)
                        SkeletonBar(width: 160)
                        SkeletonBar(width: 220)
                    }
                    .redacted(reason: .placeholder)
                    .padding(.top, 32)
                    Spacer()
                } else if let err = errorMessage, profile == nil {
                    ErrorStateView(pesan: err) { Task { await load() } }
                } else if let p = profile {
                    List {
                        Section {
                            HStack(spacing: 16) {
                                if !p.avatarUrl.isEmpty, p.avatarUrl.hasPrefix("http") {
                                    AsyncImage(url: URL(string: p.avatarUrl)) { phase in
                                        switch phase {
                                        case .success(let img): img.resizable().scaledToFill()
                                        default: InitialAvatarView(nama: p.displayName, diameter: 80)
                                        }
                                    }
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                                } else {
                                    InitialAvatarView(nama: p.displayName, diameter: 80)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(p.displayName).font(.title2).bold().lineLimit(1)
                                        if p.isVerified {
                                            Image(systemName: "checkmark.seal.fill")
                                                .foregroundStyle(Brand.indigo)
                                        }
                                    }
                                    if !p.bio.isEmpty {
                                        Text(p.bio).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 8)

                            Button("Edit Profil") { showEdit = true }
                                .buttonStyle(.bordered)
                                .tint(Brand.indigo)
                        }
                    }
                    .listStyle(.insetGrouped)
                } else {
                    EmptyStateView(
                        icon: "person",
                        judul: "Profil tidak tersedia",
                        pesan: "Data profil tidak ditemukan."
                    )
                    Button("Coba lagi") { Task { await load() } }
                        .buttonStyle(.bordered)
                        .tint(Brand.indigo)
                }
            }
            .navigationTitle("Profil")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Pengaturan")
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .sheet(isPresented: $showEdit) {
                if let p = profile {
                    EditProfileView(profile: p) { updated in
                        profile = updated
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
            }
        }
    }

    func load() async {
        if profile == nil { isLoading = true }
        errorMessage = nil
        do {
            let res: APIResponse<ProfileData> = try await APIClient.shared.get("/account/profile")
            if let apiErr = res.error, res.success == false {
                errorMessage = apiErr
            } else {
                profile = res.data?.profile
                errorMessage = nil
            }
        } catch {
            if profile == nil {
                errorMessage = "Gagal memuat profil. Periksa koneksi lalu coba lagi."
            }
        }
        isLoading = false
    }
}

struct ProfileData: Decodable { let profile: Profile }

// MARK: - Edit Profil

struct EditProfileView: View {
    let profile: Profile
    var onSaved: (Profile) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var displayName: String
    @State private var bio: String
    @State private var avatarUrl: String
    @State private var pickedImage: UIImage?
    @State private var showPhotoPicker = false
    @State private var isSaving = false
    @State private var isUploadingPhoto = false
    @State private var errorMessage: String?

    init(profile: Profile, onSaved: @escaping (Profile) -> Void) {
        self.profile = profile
        self.onSaved = onSaved
        _displayName = State(initialValue: profile.displayName)
        _bio = State(initialValue: profile.bio)
        _avatarUrl = State(initialValue: profile.avatarUrl)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nama tampil") {
                    TextField("Nama", text: $displayName)
                }
                Section("Bio") {
                    TextField("Ceritakan dirimu", text: $bio, axis: .vertical)
                }
                Section("Foto") {
                    HStack(spacing: 12) {
                        Group {
                            if let pickedImage {
                                Image(uiImage: pickedImage).resizable().scaledToFill()
                            } else if !avatarUrl.isEmpty, avatarUrl.hasPrefix("http") {
                                AsyncImage(url: URL(string: avatarUrl)) { phase in
                                    switch phase {
                                    case .success(let img): img.resizable().scaledToFill()
                                    default: Color(uiColor: .systemGray5)
                                    }
                                }
                            } else {
                                Color(uiColor: .systemGray5).overlay {
                                    Image(systemName: "person.fill").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                        Button(isUploadingPhoto ? "Mengunggah…" : "Pilih foto") {
                            showPhotoPicker = true
                        }
                        .disabled(isUploadingPhoto || isSaving)
                    }
                    TextField("atau tempel URL avatar (https://…)", text: $avatarUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if let err = errorMessage {
                    Section { Text(err).font(.caption).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Edit Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") { Task { await save() } }
                        .bold()
                        .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving || isUploadingPhoto)
                }
            }
            .sheet(isPresented: $showPhotoPicker) {
                MediaPicker(
                    onPhoto: { img in Task { await uploadPhoto(img) } },
                    onVideo: { _ in }
                )
            }
        }
    }

    /// Upload foto profil via R2 (parity §5), hasilnya jadi avatarUrl.
    func uploadPhoto(_ image: UIImage) async {
        isUploadingPhoto = true
        errorMessage = nil
        defer { isUploadingPhoto = false }
        do {
            let uid = AuthManager.shared.uid ?? "anon"
            let url = try await R2UploadService.shared.uploadImage(image, userId: uid)
            pickedImage = image
            avatarUrl = url
        } catch {
            errorMessage = "Gagal mengunggah foto. Coba lagi."
        }
    }

    func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        struct Body: Encodable { let displayName: String; let avatarUrl: String; let bio: String }
        struct D: Decodable { let profile: Profile? }
        do {
            let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let avatar = avatarUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            let biografi = bio.trimmingCharacters(in: .whitespacesAndNewlines)
            let res: APIResponse<D> = try await APIClient.shared.post("/account/profile/update", body: Body(
                displayName: name, avatarUrl: avatar, bio: biografi
            ))
            if let apiErr = res.error, res.success == false {
                errorMessage = apiErr
                return
            }
            if let updated = res.data?.profile {
                onSaved(updated)
                dismiss()
                return
            }
            // Server tidak mengembalikan profil: muat ulang agar yang
            // disimpan adalah data asli, bukan tebakan lokal.
            let re: APIResponse<ProfileData> = try await APIClient.shared.get("/account/profile")
            if let fresh = re.data?.profile {
                onSaved(fresh)
                dismiss()
            } else {
                errorMessage = re.error ?? "Gagal memuat profil terbaru. Coba lagi."
            }
        } catch {
            errorMessage = "Gagal menyimpan. Coba lagi."
        }
    }
}

// MARK: - Daftar Blokir

struct BlockListView: View {
    @State private var blocks: [BlockedUser] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                List {
                    ForEach(0..<4, id: \.self) { _ in
                        HStack(spacing: 12) {
                            Circle().fill(.quaternary).frame(width: 40, height: 40)
                            SkeletonBar(width: 160)
                        }
                        .redacted(reason: .placeholder)
                    }
                }
                .listStyle(.plain)
            } else if let err = errorMessage, blocks.isEmpty {
                ErrorStateView(pesan: err) { Task { await load() } }
            } else if blocks.isEmpty {
                EmptyStateView(icon: "nosign", judul: "Belum ada yang diblokir",
                               pesan: "User yang kamu blokir akan muncul di sini.")
            } else {
                List(blocks) { b in
                    HStack(spacing: 12) {
                        InitialAvatarView(nama: b.displayName.isEmpty ? b.userId : b.displayName, diameter: 40)
                        Text(b.displayName.isEmpty ? String(b.userId.prefix(8)) : b.displayName)
                            .font(.subheadline).bold()
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Daftar blokir")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    func load() async {
        if blocks.isEmpty { isLoading = true }
        errorMessage = nil
        do {
            struct D: Decodable { let blocks: [BlockedUser] }
            let res: APIResponse<D> = try await APIClient.shared.get("/safety/blocks")
            if let apiErr = res.error, res.success == false {
                if blocks.isEmpty { errorMessage = apiErr }
            } else {
                blocks = res.data?.blocks ?? []
                errorMessage = nil
            }
        } catch {
            if blocks.isEmpty { errorMessage = "Gagal memuat daftar blokir." }
        }
        isLoading = false
    }
}

struct BlockedUser: Identifiable, Decodable {
    var id: String { userId }
    let userId: String
    let displayName: String

    enum CodingKeys: String, CodingKey { case userId, displayName, targetId, name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Backend bisa kirim userId/displayName atau targetId/name.
        let uid = (try? c.decode(String.self, forKey: .userId)) ?? (try? c.decode(String.self, forKey: .targetId)) ?? ""
        let name = (try? c.decode(String.self, forKey: .displayName)) ?? (try? c.decode(String.self, forKey: .name)) ?? ""
        self.userId = uid
        self.displayName = name
    }
}
