import SwiftUI

// MARK: - Feed (Threads-like)

struct FeedView: View {
    @State private var tab: FeedTab = .public
    @State private var items: [Post] = []
    @State private var cursor: String?
    @State private var isLoading = false
    @State private var showComposer = false

    enum FeedTab: String, CaseIterable {
        case `public` = "public"
        case following = "following"
        var title: String { self == .public ? "Public" : "Mengikuti" }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab selector (segmented, ala Threads)
                Picker("", selection: $tab) {
                    ForEach(FeedTab.allCases, id: \.self) { t in
                        Text(t.title).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: tab) { _ in Task { await refresh() } }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { post in
                            PostCardView(post: post)
                                .onAppear {
                                    if post.id == items.last?.id { Task { await loadMore() } }
                                }
                            Divider()
                        }
                        if isLoading { ProgressView().padding() }
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
        items = []
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var q: [String: String] = ["tab": tab.rawValue, "limit": "20"]
            if let c = cursor { q["cursor"] = c }
            let res: APIResponse<FeedData> = try await APIClient.shared.get("/utas/feed", query: q)
            if let d = res.data {
                items += d.items
                cursor = d.nextCursor
            }
        } catch { print("feed error:", error) }
    }
}

// MARK: - Post Card (mirip Threads)

struct PostCardView: View {
    let post: Post
    @State private var liked: Bool
    @State private var likeCount: Int
    @State private var showThread = false

    init(post: Post) {
        self.post = post
        _liked = State(initialValue: post.viewer.isLiked)
        _likeCount = State(initialValue: post.stats.likes)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar / alias color
            AvatarView(post: post)

            VStack(alignment: .leading, spacing: 6) {
                // Header: nama + waktu
                HStack {
                    Text(post.author.displayTitle)
                        .font(.subheadline).bold()
                    if post.author.isVerified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.blue).font(.caption)
                    }
                    Spacer()
                    Text(timeAgo(post.createdAt))
                        .font(.caption).foregroundStyle(.secondary)
                }

                // Isi
                Text(post.text)
                    .font(.body)

                // Media
                if !post.mediaUrls.isEmpty {
                    TabView {
                        ForEach(post.mediaUrls, id: \.self) { url in
                            AsyncImage(url: URL(string: url)) { $0.resizable().scaledToFill() }
                                placeholder: { Color.gray.opacity(0.2) }
                        }
                    }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                }

                // Aksi: reply, like
                HStack(spacing: 24) {
                    Button { showThread = true } label: {
                        Label("\(post.stats.replies)", systemImage: "bubble.right")
                    }
                    Button { Task { await toggleLike() } } label: {
                        Label("\(likeCount)", systemImage: liked ? "heart.fill" : "heart")
                            .foregroundStyle(liked ? .red : .primary)
                    }
                    Spacer()
                    if post.viewer.isMine {
                        Menu {
                            Button("Hapus", role: .destructive) { Task { await deletePost() } }
                        } label: { Image(systemName: "ellipsis") }
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { showThread = true }
        .navigationDestination(isPresented: $showThread) {
            ThreadView(postId: post.id)
        }
    }

    func toggleLike() async {
        do {
            struct Body: Encodable { let postId: String; let like: Bool }
            struct D: Decodable { let liked: Bool; let likeCount: Int }
            let res: APIResponse<D> = try await APIClient.shared.post("/utas/like", body: Body(postId: post.id, like: !liked))
            if let d = res.data { liked = d.liked; likeCount = d.likeCount }
        } catch { print("like error:", error) }
    }

    func deletePost() async {
        do {
            struct Body: Encodable { let postId: String }
            struct D: Decodable { let deleted: Bool }
            let _: APIResponse<D> = try await APIClient.shared.post("/utas/delete", body: Body(postId: post.id))
        } catch { print("delete error:", error) }
    }
}

// MARK: - Avatar

struct AvatarView: View {
    let post: Post
    var body: some View {
        Group {
            if post.author.mode == "profile", let url = post.author.avatarUrl, !url.isEmpty {
                AsyncImage(url: URL(string: url)) { $0.resizable() } placeholder: { Color.gray.opacity(0.3) }
            } else {
                Circle()
                    .fill(Color(hex: post.author.aliasColor ?? "#5B8DEF"))
                    .overlay {
                        Text(String(post.author.displayTitle.prefix(1)))
                            .foregroundStyle(.white).bold()
                    }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }
}

// MARK: - Helpers

func timeAgo(_ ms: Int64) -> String {
    let s = Int(Date().timeIntervalSince1970) - Int(ms / 1000)
    if s < 60 { return "\(s)d" }
    if s < 3600 { return "\(s/60)m" }
    if s < 86400 { return "\(s/3600)j" }
    return "\(s/86400)h"
}

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}
