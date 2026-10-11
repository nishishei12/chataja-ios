import Foundation

// MARK: - Baca utas langsung dari Firestore (sesuai firestore.rules pengguna)
//
// Rules: /utas boleh dibaca user login; create/update tunduk skema ketat
// (authorRef = ref /users/{uid} sendiri, createdAt ±1 jam, likedBy hanya
// ref sendiri ±1). Service ini hanya memakai operasi yang rules izinkan:
// baca koleksi + toggle likedBy. Tulis post/komentar tetap via REST.

enum FirestoreUtasError: Error {
    case unavailable
    case noAuth
}

#if canImport(FirebaseFirestore)
import FirebaseFirestore

struct UtasUserProfile {
    let uid: String
    let displayName: String
    let avatarUrl: String
    let bio: String
}

final class FirestoreUtasService {
    static let shared = FirestoreUtasService()
    private init() {}

    private let db = Firestore.firestore()
    private let pageSize = 20
    private var lastDoc: DocumentSnapshot?
    private var exhausted = false

    /// postId -> authorUid (authorRef). Model Post tidak membawa author id
    /// (kontrak milik Niko, tak boleh diubah), jadi dipetakan di sini agar
    /// tombol Ikuti dan profil penulis bisa bekerja untuk post dari Firestore.
    private static var authorIds: [String: String] = [:]

    static func authorUid(forPostId postId: String) -> String? {
        authorIds[postId]
    }

    func reset() {
        lastDoc = nil
        exhausted = false
    }

    /// False kalau halaman terakhir sudah dimuat (hindari spinner sia-sia).
    var hasMore: Bool { !exhausted }

    /// Halaman berikutnya (kosong = habis). Throw kalau tidak ada auth Firebase.
    func fetchNext() async throws -> [Post] {
        guard let uid = AuthManager.shared.uid, !uid.isEmpty else {
            throw FirestoreUtasError.noAuth
        }
        guard !exhausted else { return [] }
        var q = db.collection("utas")
            .order(by: "createdAt", descending: true)
            .limit(to: pageSize)
        if let last = lastDoc {
            q = q.start(afterDocument: last)
        }
        let snap = try await q.getDocuments()
        if snap.documents.count < pageSize { exhausted = true }
        lastDoc = snap.documents.last
        return snap.documents.compactMap { Self.post(from: $0, myUid: uid) }
    }

    /// Toggle like sesuai rules (update HANYA likedBy, ref sendiri).
    /// Count dibaca ulang dari server (likesCount milik trigger), bukan karangan ±1.
    func setLike(post: Post, like: Bool) async throws -> (Bool, Int) {
        guard let uid = AuthManager.shared.uid, !uid.isEmpty else {
            throw FirestoreUtasError.noAuth
        }
        let myRef = db.collection("users").document(uid)
        let ref = db.collection("utas").document(post.id)
        if like {
            try await ref.updateData(["likedBy": FieldValue.arrayUnion([myRef])])
        } else {
            try await ref.updateData(["likedBy": FieldValue.arrayRemove([myRef])])
        }
        let fresh = try await ref.getDocument()
        return (like, fresh.get("likesCount") as? Int ?? post.stats.likes)
    }

    // MARK: - Profil penulis (baca /users, diizinkan rules untuk user login)

    /// Profil penulis lain. Rules: /users boleh dibaca user login.
    func fetchUserProfile(uid: String) async throws -> UtasUserProfile {
        let snap = try await db.collection("users").document(uid).getDocument()
        let d = snap.data() ?? [:]
        let name = d["display_name"] as? String
        return UtasUserProfile(
            uid: uid,
            displayName: name?.isEmpty == false ? name! : "Pengguna",
            avatarUrl: d["photo_url"] as? String ?? "",
            bio: d["bio"] as? String ?? ""
        )
    }

    /// Post milik penulis (untuk tab Post di profil). authorRef == ref user.
    func fetchPostsByAuthor(uid: String, limit: Int = 20) async throws -> [Post] {
        guard let myUid = AuthManager.shared.uid, !myUid.isEmpty else {
            throw FirestoreUtasError.noAuth
        }
        let userRef = db.collection("users").document(uid)
        // Tanpa orderBy server (hindari butuh composite index): urutkan lokal.
        let snap = try await db.collection("utas")
            .whereField("authorRef", isEqualTo: userRef)
            .limit(to: limit)
            .getDocuments()
        return snap.documents
            .compactMap { Self.post(from: $0, myUid: myUid) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Mapping (skema rules 2026-09-26)

    static func post(from doc: QueryDocumentSnapshot, myUid: String) -> Post? {
        let d = doc.data()
        guard let text = d["text"] as? String,
              let ts = d["createdAt"] as? Timestamp else { return nil }
        let ms = Int64(ts.dateValue().timeIntervalSince1970 * 1000)
        let isAnon = d["isAnonymous"] as? Bool ?? false
        let name = d["authorName"] as? String
        let photo = d["authorPhotoUrl"] as? String
        let myRefId = myUid
        let authorUid = (d["authorRef"] as? DocumentReference)?.documentID
        let likedBy = (d["likedBy"] as? [DocumentReference])?.map(\.documentID) ?? []
        if let authorUid {
            Self.authorIds[doc.documentID] = authorUid
        }

        let author = Post.Author(
            mode: isAnon ? "anon" : "profile",
            displayName: isAnon ? nil : (name?.isEmpty == false ? name : "Pengguna"),
            avatarUrl: isAnon ? nil : photo,
            isVerified: false,
            alias: isAnon ? "Anonim" : nil,
            aliasColor: "#5B8DEF"
        )
        return Post(
            id: doc.documentID,
            text: text,
            createdAt: ms,
            expiresAt: 0,
            author: author,
            mediaUrls: d["photos"] as? [String] ?? [],
            stats: Post.PostStats(
                likes: d["likesCount"] as? Int ?? 0,
                replies: d["commentCount"] as? Int ?? 0
            ),
            viewer: Post.ViewerInfo(
                isMine: authorUid == myRefId,
                isLiked: likedBy.contains(myRefId)
            ),
            replyTo: nil
        )
    }
}
#else
// Fallback kalau Firebase belum dipasang — pemanggil fallback ke REST.
struct UtasUserProfile {
    let uid: String
    let displayName: String
    let avatarUrl: String
    let bio: String
}

final class FirestoreUtasService {
    static let shared = FirestoreUtasService()
    func reset() {}
    var hasMore: Bool { true }
    static func authorUid(forPostId postId: String) -> String? { nil }
    func fetchUserProfile(uid: String) async throws -> UtasUserProfile {
        throw FirestoreUtasError.unavailable
    }
    func fetchPostsByAuthor(uid: String, limit: Int = 20) async throws -> [Post] {
        throw FirestoreUtasError.unavailable
    }
    func fetchNext() async throws -> [Post] { throw FirestoreUtasError.unavailable }
    func setLike(post: Post, like: Bool) async throws -> (Bool, Int) {
        throw FirestoreUtasError.unavailable
    }
}
#endif
