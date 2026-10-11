import SwiftUI

// MARK: - Feed (PRD 3.2)

struct FeedView: View {
    @State private var tab: FeedTab = .public
    @State private var items: [Post] = []
    @State private var cursor: String?
    @State private var isLoading = false
    @State private var isFirstLoad = true
    @State private var errorMessage: String?
    @State private var showComposer = false
    @State private var useFirestore = true
    /// True selama siklus refresh (tarik untuk muat ulang / ganti tab):
    /// sukses pertama mengganti items, bukan menambah.
    @State private var refreshing = false

    enum FeedTab: String, CaseIterable {
        case `public` = "public"
        case following = "following"
        var title: String { self == .public ? "Public" : "Mengikuti" }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Button { showComposer = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                        Text("Apa yang baru?")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tulis utas baru")
                Divider()

                Picker("", selection: $tab) {
                    ForEach(FeedTab.allCases, id: \.self) { t in
                        Text(t.title).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .onChange(of: tab) { _, _ in Task { await refresh() } }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if isFirstLoad && isLoading {
                            ForEach(0..<4, id: \.self) { _ in PostSkeletonView() }
                        } else if let err = errorMessage, items.isEmpty {
                            ErrorStateView(pesan: err) { Task { await refresh() } }
                        } else if items.isEmpty {
                            EmptyStateView(
                                icon: "text.bubble",
                                judul: "Belum ada utas",
                                pesan: "Belum ada utas. Jadilah yang pertama."
                            )
                        } else {
                            ForEach(items) { post in
                                PostCardView(post: post, onDeleted: {
                                    items.removeAll { $0.id == post.id }
                                }, likeAction: { p, like in
                                    try await self.firestoreLike(post: p, like: like)
                                })
                                .onAppear {
                                    if post.id == items.last?.id { Task { await loadMore() } }
                                }
                                Divider().padding(.leading, 72)
                            }
                            if isLoading { ProgressView().padding() }
                            if let err = errorMessage, !items.isEmpty {
                                Button("Gagal memuat lagi: \(err) — ketuk untuk coba lagi") {
                                    Task { await loadMore() }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding()
                            }
                        }
                    }
                }
                .refreshable { await refresh() }
            }
            .navigationTitle("Utas")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showComposer) {
                CreatePostView { Task { await refresh() } }
            }
            .task { await refresh() }
        }
    }

    func refresh() async {
        cursor = nil
        errorMessage = nil
        isFirstLoad = items.isEmpty
        // items TIDAK dikosongkan dulu: layar lama tetap tampil sampai
        // data baru sukses dimuat.
        refreshing = true
        useFirestore = true
        FirestoreUtasService.shared.reset()
        await loadMore()
        isFirstLoad = false
        refreshing = false
    }

    func loadMore() async {
        guard !isLoading else { return }
        if tab == .public {
            await loadPublic()
        } else {
            await loadViaRest()
        }
    }

    /// Tab Public: Firestore langsung dulu (rules mengizinkan user login),
    /// fallback ke REST kalau gagal (mis. login token manual tanpa sesi Firebase).
    func loadPublic() async {
        if useFirestore {
            guard FirestoreUtasService.shared.hasMore else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                let posts = try await FirestoreUtasService.shared.fetchNext()
                if refreshing { items = posts } else { items += posts }
                errorMessage = nil
                return
            } catch {
                if items.isEmpty {
                    // Belum ada apa-apa: jatuh ke REST.
                    useFirestore = false
                    FirestoreUtasService.shared.reset()
                    cursor = nil
                } else {
                    // Sudah ada isi: pertahankan, tampilkan error inline.
                    errorMessage = "Gagal memuat halaman berikutnya."
                    return
                }
            }
        }
        await loadViaRest()
    }

    func loadViaRest() async {
        guard !isLoading else { return }
        // Jangan minta halaman berikutnya kalau cursor habis dan ini bukan load pertama.
        if cursor == nil && !items.isEmpty && !isFirstLoad { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var q: [String: String] = ["tab": tab.rawValue, "limit": "20"]
            if let c = cursor { q["cursor"] = c }
            let res: APIResponse<FeedData> = try await APIClient.shared.get("/utas/feed", query: q)
            if let apiErr = res.error, res.success == false {
                errorMessage = apiErr
                return
            }
            if let d = res.data {
                if refreshing { items = d.items } else { items += d.items }
                cursor = d.nextCursor
                // nextCursor kosong = halaman terakhir.
                if d.nextCursor == nil || d.nextCursor?.isEmpty == true {
                    cursor = nil
                }
            }
        } catch {
            if items.isEmpty {
                errorMessage = pesanErrorFeed(error)
            } else {
                errorMessage = "Gagal memuat halaman berikutnya."
            }
        }
    }

    /// Like via Firestore kalau feed dari sana, kalau tidak via REST.
    func firestoreLike(post: Post, like: Bool) async throws -> (Bool, Int) {
        if useFirestore {
            return try await FirestoreUtasService.shared.setLike(post: post, like: like)
        }
        struct Body: Encodable { let postId: String; let like: Bool }
        struct D: Decodable { let liked: Bool; let likeCount: Int }
        let res: APIResponse<D> = try await APIClient.shared.post("/utas/like", body: Body(postId: post.id, like: like))
        if let apiErr = res.error, res.success == false {
            throw NSError(domain: "api", code: -1, userInfo: [NSLocalizedDescriptionKey: apiErr])
        }
        guard let d = res.data else {
            throw NSError(domain: "api", code: -1, userInfo: [NSLocalizedDescriptionKey: "Respons kosong."])
        }
        return (d.liked, d.likeCount)
    }

    /// Pesan spesifik agar penyebab gagal (terutama auth) terlihat user.
    func pesanErrorFeed(_ error: Error) -> String {
        if let api = error as? APIError, case .http(let code) = api {
            if code == 401 {
                return "Sesi login kedaluwarsa atau token tidak valid. Keluar lalu masuk lagi."
            }
            return "Gagal memuat utas (HTTP \(code)). Coba lagi."
        }
        return "Gagal memuat utas. Periksa koneksi lalu coba lagi."
    }
}

// MARK: - Post Card (ala Threads, PRD 3.2)

struct PostCardView: View {
    let post: Post
    var isInteractive = true
    var onDeleted: (() -> Void)? = nil
    /// Aksi like custom (mis. via Firestore). Nil = via REST.
    var likeAction: ((Post, Bool) async throws -> (Bool, Int))? = nil
    @State private var liked: Bool
    @State private var likeCount: Int
    @State private var showThread = false
    @State private var showChat = false
    @State private var chatRoomId: String?
    @State private var isOpeningChat = false
    @State private var actionError: String?
    @State private var showProfile = false
    @State private var following: Bool
    @State private var isTogglingFollow = false
    @State private var showShare = false

    init(post: Post, isInteractive: Bool = true, onDeleted: (() -> Void)? = nil,
         likeAction: ((Post, Bool) async throws -> (Bool, Int))? = nil) {
        self.post = post
        self.isInteractive = isInteractive
        self.onDeleted = onDeleted
        self.likeAction = likeAction
        _liked = State(initialValue: post.viewer.isLiked)
        _likeCount = State(initialValue: post.stats.likes)
        let uid: String? = post.viewer.isMine
            ? AuthManager.shared.uid
            : FirestoreUtasService.authorUid(forPostId: post.id)
        _following = State(initialValue: uid.map { FollowStore.isFollowing($0) } ?? false)
    }

    /// Uid penulis. Post model tak membawa author id, jadi khusus post dari
    /// Firestore dibaca dari peta author di service; post REST tak dikenal.
    var authorUid: String? {
        if post.viewer.isMine { return AuthManager.shared.uid }
        return FirestoreUtasService.authorUid(forPostId: post.id)
    }

    /// Aksi sosial (ikuti/kunjungi profil) hanya untuk post non-anonim yang
    /// penulisnya dikenal dan bukan milik sendiri. Anonim: nonaktif total
    /// agar identitas penulis tidak bocor.
    var canSocial: Bool {
        post.author.mode != "anon" && authorUid != nil && !post.viewer.isMine
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Button {
                    if canSocial { showProfile = true }
                } label: {
                    AvatarView(post: post)
                }
                .buttonStyle(.plain)
                .disabled(!canSocial)
                .accessibilityLabel(canSocial ? "Lihat profil \(post.author.displayTitle)" : "Avatar")
                .accessibilityIdentifier("uit-avatar") // hook UI test

                if canSocial {
                    Button { Task { await toggleFollow() } } label: {
                        Image(systemName: following ? "minus" : "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 20, height: 20)
                            .background(Color(uiColor: .systemBackground))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color(uiColor: .separator), lineWidth: 1))
                            .shadow(radius: 1)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 5, y: 5)
                    .disabled(isTogglingFollow)
                    .accessibilityLabel(following ? "Berhenti mengikuti" : "Ikuti")
                    .accessibilityIdentifier("uit-followbadge") // hook UI test
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button {
                        if canSocial { showProfile = true }
                    } label: {
                        HStack(spacing: 4) {
                            Text(post.author.displayTitle)
                                .font(.subheadline).bold()
                                .lineLimit(1)
                            if post.author.isVerified == true {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(Brand.indigo).font(.caption)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSocial)
                    .accessibilityIdentifier("uit-username") // hook UI test
                    Spacer()
                    Text(waktuRelatif(post.createdAt))
                        .font(.caption).foregroundStyle(.secondary)
                }

                Text(post.text)
                    .font(.body)

                if !post.mediaUrls.isEmpty {
                    mediaCarousel
                }

                HStack(spacing: 24) {
                    Button {
                        if isInteractive { showThread = true }
                    } label: {
                        Label("\(post.stats.replies)", systemImage: "bubble.right")
                    }
                    .accessibilityIdentifier("uit-comment") // hook UI test
                    Button { Task { await toggleLike() } } label: {
                        Label("\(likeCount)", systemImage: liked ? "heart.fill" : "heart")
                            .foregroundStyle(liked ? .red : .secondary)
                    }
                    .accessibilityIdentifier("uit-like") // hook UI test
                    Button { showShare = true } label: {
                        Image(systemName: "paperplane")
                    }
                    .accessibilityLabel("Bagikan")
                    .accessibilityIdentifier("uit-share") // hook UI test
                    Spacer()
                    Menu {
                        if post.viewer.isMine {
                            Button("Hapus", role: .destructive) { Task { await deletePost() } }
                        } else {
                            Button("Laporkan") { Task { await reportPost() } }
                            Button("Chat dengan penulis") { Task { await openChat() } }
                                .disabled(isOpeningChat)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .padding(.top, 4)

                if let err = actionError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .accessibilityIdentifier("uit-card") // hook UI test
        .contentShape(Rectangle())
        .onTapGesture {
            if isInteractive { showThread = true }
        }
        .contextMenu {
            if canSocial {
                Button(following ? "Berhenti mengikuti" : "Ikuti") {
                    Task { await toggleFollow() }
                }
                Button("Kunjungi profil") { showProfile = true }
            }
        }
        .navigationDestination(isPresented: $showThread) {
            ThreadView(postId: post.id)
        }
        .sheet(isPresented: $showProfile) {
            if let uid = authorUid {
                NavigationStack {
                    AuthorProfileSheet(authorUid: uid, fallbackName: post.author.displayTitle)
                }
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [post.text])
        }
        .sheet(isPresented: $showChat) {
            if let roomId = chatRoomId {
                NavigationStack {
                    ChatRoomView(
                        roomId: roomId,
                        partnerName: post.author.displayTitle,
                        myUserId: AuthManager.shared.uid ?? ""
                    )
                }
            }
        }
    }

    // Carousel horizontal, rounded 12, tinggi 200 (PRD 3.2).
    @ViewBuilder
    private var mediaCarousel: some View {
        if post.mediaUrls.count == 1, let url = post.mediaUrls.first {
            AsyncImage(url: URL(string: url)) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                case .failure: Color(uiColor: .systemGray5).overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
                default: Color(uiColor: .systemGray5).overlay { ProgressView() }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(post.mediaUrls, id: \.self) { url in
                        AsyncImage(url: URL(string: url)) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            case .failure: Color(uiColor: .systemGray5).overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
                            default: Color(uiColor: .systemGray5).overlay { ProgressView() }
                            }
                        }
                        .frame(width: 260, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    // Optimistic update: langsung berubah, rollback kalau gagal (PRD 3.2).
    func toggleLike() async {
        let next = !liked
        let prevLiked = liked
        let prevCount = likeCount
        liked = next
        likeCount = max(0, prevCount + (next ? 1 : -1))
        actionError = nil
        do {
            if let action = likeAction {
                let (l, c) = try await action(post, next)
                liked = l; likeCount = c
                return
            }
            struct Body: Encodable { let postId: String; let like: Bool }
            struct D: Decodable { let liked: Bool; let likeCount: Int }
            let res: APIResponse<D> = try await APIClient.shared.post("/utas/like", body: Body(postId: post.id, like: next))
            if let apiErr = res.error, res.success == false {
                liked = prevLiked; likeCount = prevCount
                actionError = apiErr
                return
            }
            if let d = res.data { liked = d.liked; likeCount = d.likeCount }
        } catch {
            liked = prevLiked; likeCount = prevCount
            actionError = "Gagal menyukai. Coba lagi."
        }
    }

    /// Ikuti/berhenti mengikuti penulis via POST /utas/follow (API.md).
    /// Status di-cache lokal agar badge langsung konsisten.
    func toggleFollow() async {
        guard let uid = authorUid, !isTogglingFollow else { return }
        isTogglingFollow = true
        defer { isTogglingFollow = false }
        let next = !following
        do {
            struct Body: Encodable { let targetUserId: String; let follow: Bool }
            struct D: Decodable { let following: Bool? }
            let res: APIResponse<D> = try await APIClient.shared.post(
                "/utas/follow", body: Body(targetUserId: uid, follow: next)
            )
            if let apiErr = res.error, res.success == false {
                actionError = apiErr
                return
            }
            let ok = res.data?.following ?? next
            following = ok
            FollowStore.setFollowing(uid, ok)
            actionError = nil
        } catch {
            actionError = "Gagal mengikuti. Coba lagi."
        }
    }

    func deletePost() async {
        do {
            struct Body: Encodable { let postId: String }
            struct D: Decodable { let deleted: Bool? }
            let res: APIResponse<D> = try await APIClient.shared.post("/utas/delete", body: Body(postId: post.id))
            if let apiErr = res.error, res.success == false {
                actionError = apiErr
                return
            }
            guard res.data?.deleted != false else {
                actionError = "Gagal menghapus. Coba lagi."
                return
            }
            onDeleted?()
        } catch {
            actionError = "Gagal menghapus. Coba lagi."
        }
    }

    func reportPost() async {
        do {
            struct Body: Encodable { let postId: String; let reason: String }
            struct D: Decodable { let reported: Bool? }
            let res: APIResponse<D> = try await APIClient.shared.post("/utas/report", body: Body(postId: post.id, reason: "spam"))
            if let apiErr = res.error, res.success == false {
                actionError = apiErr
            } else {
                actionError = "Terima kasih, laporanmu terkirim."
            }
        } catch {
            actionError = "Gagal melaporkan. Coba lagi."
        }
    }

    func openChat() async {
        guard !isOpeningChat else { return }
        isOpeningChat = true
        defer { isOpeningChat = false }
        do {
            struct Body: Encodable { let utasId: String }
            struct D: Decodable { let roomId: String }
            let res: APIResponse<D> = try await APIClient.shared.post("/chat/from-utas", body: Body(utasId: post.id))
            if let apiErr = res.error, res.success == false {
                actionError = apiErr
                return
            }
            if let roomId = res.data?.roomId {
                chatRoomId = roomId
                showChat = true
            }
        } catch {
            actionError = "Gagal membuka chat. Coba lagi."
        }
    }
}

// MARK: - Follow (cache lokal status ikuti per penulis)

enum FollowStore {
    private static let key = "utas-following-uids"

    static func isFollowing(_ uid: String) -> Bool {
        UserDefaults.standard.stringArray(forKey: key)?.contains(uid) ?? false
    }

    static func setFollowing(_ uid: String, _ value: Bool) {
        var set = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        if value { set.insert(uid) } else { set.remove(uid) }
        UserDefaults.standard.set(Array(set), forKey: key)
    }
}

// MARK: - Bagikan (share sheet sistem)

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Profil penulis (ala Threads: header + tombol + post)

struct AuthorProfileSheet: View {
    let authorUid: String
    let fallbackName: String
    @Environment(\.dismiss) private var dismiss
    @State private var profile: UtasUserProfile?
    @State private var posts: [Post] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var following: Bool
    @State private var isTogglingFollow = false
    @State private var chatRoomId: String?
    @State private var showChat = false
    @State private var isOpeningChat = false
    @State private var actionError: String?

    init(authorUid: String, fallbackName: String) {
        self.authorUid = authorUid
        self.fallbackName = fallbackName
        _following = State(initialValue: FollowStore.isFollowing(authorUid))
    }

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    Circle().fill(.quaternary).frame(width: 72, height: 72)
                    SkeletonBar(width: 160)
                    SkeletonBar(width: 220)
                }
                .redacted(reason: .placeholder)
                .padding(.top, 32)
                Spacer()
            } else if let err = errorMessage, profile == nil {
                ErrorStateView(pesan: err) { Task { await load() } }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        header
                        Divider().padding(.vertical, 4)
                        if posts.isEmpty {
                            EmptyStateView(
                                icon: "text.bubble",
                                judul: "Belum ada post",
                                pesan: "Penulis ini belum membagikan utas."
                            )
                        } else {
                            ForEach(posts) { post in
                                PostCardView(
                                    post: post,
                                    onDeleted: {
                                        posts.removeAll { $0.id == post.id }
                                    },
                                    likeAction: { p, like in
                                        try await FirestoreUtasService.shared.setLike(post: p, like: like)
                                    }
                                )
                                Divider().padding(.leading, 72)
                            }
                        }
                    }
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle(fallbackName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Tutup") { dismiss() }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showChat) {
            if let roomId = chatRoomId {
                NavigationStack {
                    ChatRoomView(
                        roomId: roomId,
                        partnerName: profile?.displayName ?? fallbackName,
                        myUserId: AuthManager.shared.uid ?? ""
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Group {
                    if let url = profile?.avatarUrl, !url.isEmpty {
                        AsyncImage(url: URL(string: url)) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            default: InitialAvatarView(nama: profile?.displayName ?? fallbackName, diameter: 64)
                            }
                        }
                    } else {
                        InitialAvatarView(nama: profile?.displayName ?? fallbackName, diameter: 64)
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile?.displayName ?? fallbackName)
                        .font(.title3).bold()
                        .lineLimit(1)
                    if let bio = profile?.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }
            HStack(spacing: 10) {
                Button(following ? "Mengikuti" : "Ikuti") {
                    Task { await toggleFollow() }
                }
                .buttonStyle(.borderedProminent)
                .tint(following ? Color(uiColor: .systemGray5) : Brand.indigo)
                .foregroundStyle(following ? Color.primary : Color.white)
                .disabled(isTogglingFollow)
                .accessibilityIdentifier("uit-profile-follow") // hook UI test
                if let firstId = posts.first?.id {
                    Button("Pesan") { Task { await openChat(utasId: firstId) } }
                        .buttonStyle(.bordered)
                        .tint(Brand.indigo)
                        .disabled(isOpeningChat)
                        .accessibilityIdentifier("uit-profile-message") // hook UI test
                }
            }
            if let err = actionError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    func load() async {
        if profile == nil { isLoading = true }
        errorMessage = nil
        do {
            async let fetchedProfile = FirestoreUtasService.shared.fetchUserProfile(uid: authorUid)
            async let fetchedPosts = FirestoreUtasService.shared.fetchPostsByAuthor(uid: authorUid)
            profile = try await fetchedProfile
            posts = try await fetchedPosts
        } catch {
            if profile == nil {
                errorMessage = "Gagal memuat profil. Periksa koneksi lalu coba lagi."
            }
        }
        isLoading = false
    }

    func toggleFollow() async {
        guard !isTogglingFollow else { return }
        isTogglingFollow = true
        defer { isTogglingFollow = false }
        let next = !following
        do {
            struct Body: Encodable { let targetUserId: String; let follow: Bool }
            struct D: Decodable { let following: Bool? }
            let res: APIResponse<D> = try await APIClient.shared.post(
                "/utas/follow", body: Body(targetUserId: authorUid, follow: next)
            )
            if let apiErr = res.error, res.success == false {
                actionError = apiErr
                return
            }
            let ok = res.data?.following ?? next
            following = ok
            FollowStore.setFollowing(authorUid, ok)
            actionError = nil
        } catch {
            actionError = "Gagal mengikuti. Coba lagi."
        }
    }

    func openChat(utasId: String) async {
        guard !isOpeningChat else { return }
        isOpeningChat = true
        defer { isOpeningChat = false }
        do {
            struct Body: Encodable { let utasId: String }
            struct D: Decodable { let roomId: String }
            let res: APIResponse<D> = try await APIClient.shared.post(
                "/chat/from-utas", body: Body(utasId: utasId)
            )
            if let apiErr = res.error, res.success == false {
                actionError = apiErr
                return
            }
            if let roomId = res.data?.roomId {
                chatRoomId = roomId
                showChat = true
            }
        } catch {
            actionError = "Gagal membuka chat. Coba lagi."
        }
    }
}

// MARK: - Avatar

struct AvatarView: View {
    let post: Post
    var body: some View {
        Group {
            if post.author.mode == "profile", let url = post.author.avatarUrl, !url.isEmpty {
                AsyncImage(url: URL(string: url)) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color(uiColor: .systemGray5).overlay { ProgressView() }
                    }
                }
            } else {
                Circle()
                    .fill(Color(hex: post.author.aliasColor ?? "#5B8DEF"))
                    .overlay {
                        Text(String(post.author.displayTitle.prefix(1).uppercased()))
                            .foregroundStyle(.white).bold()
                    }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }
}

// MARK: - Helpers

func timeAgo(_ ms: Int64) -> String { waktuRelatif(ms) }

extension Color {
    /// Hex invalid → abu-abu (jangan hitam pekat yang merusak dark mode).
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var v: UInt64 = 0
        guard h.count == 6, Scanner(string: h).scanHexInt64(&v) else {
            self.init(uiColor: .systemGray)
            return
        }
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}
