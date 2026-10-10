import SwiftUI

// MARK: - Thread Detail

struct ThreadView: View {
    let postId: String
    @State private var post: Post?
    @State private var comments: [Post] = []
    @State private var replyText = ""
    @State private var replyTo: Post?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let p = post {
                        PostCardView(post: p)
                        Divider().padding(.vertical, 4)
                    }
                    ForEach(comments) { c in
                        HStack(alignment: .top, spacing: 8) {
                            if c.replyTo != nil && c.replyTo != postId {
                                Spacer().frame(width: 24) // indent nested
                            }
                            PostCardView(post: c)
                        }
                        Divider()
                    }
                }
            }

            // Composer komentar
            HStack {
                TextField(replyTo == nil ? "Tulis komentar..." : "Balas \(replyTo?.author.displayTitle ?? "")...",
                          text: $replyText)
                    .textFieldStyle(.roundedBorder)
                Button("Kirim") { Task { await sendComment() } }
                    .disabled(replyText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Thread")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    func load() async {
        do {
            let res: APIResponse<ThreadData> = try await APIClient.shared.get("/utas/thread", query: ["postId": postId])
            if let d = res.data { post = d.post; comments = d.comments }
        } catch { print("thread error:", error) }
    }

    func sendComment() async {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            struct Body: Encodable {
                let text: String; let mode: String
                let parentId: String; let mediaUrls: [String] = []
            }
            struct D: Decodable { let postId: String }
            let _: APIResponse<D> = try await APIClient.shared.post("/utas/create", body: Body(
                text: text, mode: "profile", parentId: replyTo?.id ?? postId
            ))
            replyText = ""; replyTo = nil
            await load()
        } catch { print("comment error:", error) }
    }
}

// MARK: - Create Post Composer

struct CreatePostView: View {
    var onDone: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    @State private var isAnon = false
    @State private var isPosting = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Posting anonim", isOn: $isAnon)
                TextEditor(text: $text)
                    .frame(minHeight: 150)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                Text("\(text.count)/1000")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Utas baru")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kirim") { Task { await submit() } }
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isPosting)
                }
            }
        }
    }

    func submit() async {
        isPosting = true
        defer { isPosting = false }
        do {
            struct Body: Encodable {
                let text: String; let mode: String; let mediaUrls: [String] = []
            }
            struct D: Decodable { let postId: String; let alias: String? }
            let _: APIResponse<D> = try await APIClient.shared.post("/utas/create", body: Body(
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                mode: isAnon ? "anon" : "profile"
            ))
            onDone(); dismiss()
        } catch { print("create error:", error) }
    }
}
