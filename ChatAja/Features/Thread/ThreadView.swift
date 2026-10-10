import SwiftUI

// MARK: - Thread Detail (PRD 3.3)

struct ThreadView: View {
    let postId: String
    @State private var post: Post?
    @State private var comments: [Post] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var replyText = ""
    @State private var replyTo: Post?
    @State private var isSending = false
    @State private var sendError: String?
    @State private var refreshError: String?

    var body: some View {
        VStack(spacing: 0) {
            if let rerr = refreshError, post != nil {
                Button {
                    refreshError = nil
                    Task { await load() }
                } label: {
                    Text("\(rerr) Ketuk untuk coba lagi.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(uiColor: .systemGray6))
                }
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    if isLoading {
                        PostSkeletonView()
                        PostSkeletonView()
                    } else if let err = errorMessage, post == nil {
                        ErrorStateView(pesan: err) { Task { await load() } }
                    } else {
                        if let p = post {
                            PostCardView(post: p, isInteractive: false)
                            Divider().padding(.vertical, 4)
                        }
                        if comments.isEmpty {
                            EmptyStateView(
                                icon: "bubble.right",
                                judul: "Belum ada balasan",
                                pesan: "Jadilah yang pertama membalas utas ini."
                            )
                        } else {
                            ForEach(comments) { c in
                                let isReply = c.replyTo != nil && c.replyTo != postId
                                HStack(alignment: .top, spacing: 0) {
                                    if isReply {
                                        // Thread line vertikal tipis + indent 24pt (PRD 3.3).
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Color(uiColor: .separator))
                                            .frame(width: 2)
                                            .padding(.trailing, 10)
                                            .padding(.leading, 24)
                                    }
                                    CommentRow(
                                        comment: c,
                                        onReply: { replyTo = c },
                                        onDeleted: {
                                            comments.removeAll { $0.id == c.id }
                                        }
                                    )
                                }
                                Divider().padding(.leading, isReply ? 48 : 72)
                            }
                        }
                    }
                }
            }
            .refreshable { await load() }

            // Composer komentar: sticky di bawah keyboard (PRD 3.3).
            VStack(spacing: 6) {
                if let target = replyTo {
                    HStack {
                        Text("Balas @\(target.author.displayTitle)…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button { replyTo = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                HStack(spacing: 8) {
                    TextField(
                        replyTo == nil ? "Tulis komentar..." : "Balas @\(replyTo?.author.displayTitle ?? "")...",
                        text: $replyText, axis: .vertical
                    )
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    Button("Kirim") { Task { await sendComment() } }
                        .buttonStyle(.borderedProminent)
                        .tint(Brand.indigo)
                        .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || replyText.count > 1000 || isSending)
                }
                if let err = sendError {
                    Text(err).font(.caption).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Utas")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    func load() async {
        // Loading penuh hanya saat pertama; refresh berikutnya tetap tampilkan isi lama.
        if post == nil { isLoading = true } else { isLoading = false }
        errorMessage = nil
        refreshError = nil
        do {
            let res: APIResponse<ThreadData> = try await APIClient.shared.get("/utas/thread", query: ["postId": postId])
            if let apiErr = res.error, res.success == false {
                if post == nil { errorMessage = apiErr }
                else { refreshError = apiErr }
            } else if let d = res.data {
                post = d.post
                comments = d.comments
            }
        } catch {
            if post == nil {
                errorMessage = "Gagal memuat thread. Periksa koneksi lalu coba lagi."
            } else {
                refreshError = "Gagal memuat ulang."
            }
        }
        isLoading = false
    }

    func sendComment() async {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        guard text.count <= 1000 else {
            sendError = "Komentar maksimal 1000 karakter."
            return
        }
        isSending = true
        sendError = nil
        defer { isSending = false }
        do {
            struct Body: Encodable {
                let text: String; let mode: String
                let parentId: String; let mediaUrls: [String] = []
            }
            struct D: Decodable { let postId: String }
            let res: APIResponse<D> = try await APIClient.shared.post("/utas/create", body: Body(
                text: text, mode: "profile", parentId: replyTo?.id ?? postId
            ))
            if let apiErr = res.error, res.success == false {
                sendError = apiErr
                return
            }
            replyText = ""; replyTo = nil
            await load()
        } catch {
            sendError = "Gagal mengirim. Coba lagi."
        }
    }
}

// MARK: - Baris komentar (dengan tombol Balas)

struct CommentRow: View {
    let comment: Post
    var onReply: () -> Void
    var onDeleted: (() -> Void)? = nil
    @State private var liked: Bool
    @State private var likeCount: Int
    @State private var actionError: String?

    init(comment: Post, onReply: @escaping () -> Void, onDeleted: (() -> Void)? = nil) {
        self.comment = comment
        self.onReply = onReply
        self.onDeleted = onDeleted
        _liked = State(initialValue: comment.viewer.isLiked)
        _likeCount = State(initialValue: comment.stats.likes)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(post: comment)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(comment.author.displayTitle).font(.subheadline).bold().lineLimit(1)
                    if comment.author.isVerified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Brand.indigo).font(.caption)
                    }
                    Spacer()
                    Text(waktuRelatif(comment.createdAt))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(comment.text).font(.body)
                if !comment.mediaUrls.isEmpty, let url = comment.mediaUrls.first {
                    AsyncImage(url: URL(string: url)) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        case .failure: Color(uiColor: .systemGray5)
                        default: Color(uiColor: .systemGray5).overlay { ProgressView() }
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                HStack(spacing: 20) {
                    Button("Balas", action: onReply)
                    Button { Task { await toggleLike() } } label: {
                        Label("\(likeCount)", systemImage: liked ? "heart.fill" : "heart")
                            .foregroundStyle(liked ? .red : .secondary)
                    }
                    Spacer()
                    if comment.viewer.isMine {
                        Menu {
                            Button("Hapus", role: .destructive) { Task { await deletePost() } }
                        } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary) }
                    } else {
                        Menu {
                            Button("Laporkan") { Task { await reportPost() } }
                        } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary) }
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .padding(.top, 2)
                if let err = actionError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    func toggleLike() async {
        let next = !liked
        let prev = liked
        let prevCount = likeCount
        liked = next
        likeCount = max(0, prevCount + (next ? 1 : -1))
        actionError = nil
        do {
            struct Body: Encodable { let postId: String; let like: Bool }
            struct D: Decodable { let liked: Bool; let likeCount: Int }
            let res: APIResponse<D> = try await APIClient.shared.post("/utas/like", body: Body(postId: comment.id, like: next))
            if let apiErr = res.error, res.success == false {
                liked = prev; likeCount = prevCount
                actionError = apiErr
                return
            }
            if let d = res.data { liked = d.liked; likeCount = d.likeCount }
        } catch {
            liked = prev; likeCount = prevCount
            actionError = "Gagal menyukai. Coba lagi."
        }
    }

    func deletePost() async {
        do {
            struct Body: Encodable { let postId: String }
            struct D: Decodable { let deleted: Bool? }
            let res: APIResponse<D> = try await APIClient.shared.post("/utas/delete", body: Body(postId: comment.id))
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
            let res: APIResponse<D> = try await APIClient.shared.post("/utas/report", body: Body(postId: comment.id, reason: "spam"))
            if let apiErr = res.error, res.success == false {
                actionError = apiErr
            } else {
                actionError = "Terima kasih, laporanmu terkirim."
            }
        } catch {
            actionError = "Gagal melaporkan. Coba lagi."
        }
    }
}

// MARK: - Create Post Composer (PRD 3.4)

struct CreatePostView: View {
    var onDone: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    @State private var isAnon = false
    @State private var isPosting = false
    @State private var errorMessage: String?

    private let limit = 1000

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Posting anonim", isOn: $isAnon)
                    Text("Nama disamarkan jadi alias permanen untuk utas ini.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .frame(minHeight: 150)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    if text.isEmpty {
                        Text("Apa yang kamu pikirkan?")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                }

                HStack {
                    if let err = errorMessage {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                    Spacer()
                    Text("\(text.count)/\(limit)")
                        .font(.caption)
                        .foregroundStyle(text.count > limit ? .red : .secondary)
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("Utas baru")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kirim") { Task { await submit() } }
                        .bold()
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > limit || isPosting)
                }
            }
        }
    }

    func submit() async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= limit else { return }
        isPosting = true
        errorMessage = nil
        defer { isPosting = false }
        do {
            struct Body: Encodable {
                let text: String; let mode: String; let mediaUrls: [String] = []
            }
            struct D: Decodable { let postId: String; let alias: String? }
            let res: APIResponse<D> = try await APIClient.shared.post("/utas/create", body: Body(
                text: body,
                mode: isAnon ? "anon" : "profile"
            ))
            if let apiErr = res.error, res.success == false {
                errorMessage = apiErr
                return
            }
            onDone(); dismiss()
        } catch {
            errorMessage = "Gagal mengirim. Periksa koneksi lalu coba lagi."
        }
    }
}
