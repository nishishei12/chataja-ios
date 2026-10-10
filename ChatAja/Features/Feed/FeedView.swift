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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showComposer = true } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Tulis utas baru")
                }
            }
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

    init(post: Post, isInteractive: Bool = true, onDeleted: (() -> Void)? = nil,
         likeAction: ((Post, Bool) async throws -> (Bool, Int))? = nil) {
        self.post = post
        self.isInteractive = isInteractive
        self.onDeleted = onDeleted
        self.likeAction = likeAction
        _liked = State(initialValue: post.viewer.isLiked)
        _likeCount = State(initialValue: post.stats.likes)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(post: post)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(post.author.displayTitle)
                        .font(.subheadline).bold()
                        .lineLimit(1)
                    if post.author.isVerified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Brand.indigo).font(.caption)
                    }
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
                    Button { Task { await toggleLike() } } label: {
                        Label("\(likeCount)", systemImage: liked ? "heart.fill" : "heart")
                            .foregroundStyle(liked ? .red : .secondary)
                    }
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
        .contentShape(Rectangle())
        .onTapGesture {
            if isInteractive { showThread = true }
        }
        .navigationDestination(isPresented: $showThread) {
            ThreadView(postId: post.id)
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
