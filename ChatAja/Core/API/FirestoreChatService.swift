import Foundation
import Combine

// MARK: - Firestore Chat Service (Realtime)
//
// INTEGRASI FIREBASE:
// 1. Di Xcode: File → Add Package Dependencies → https://github.com/firebase/firebase-ios-sdk
//    Pilih: FirebaseAuth, FirebaseFirestore
// 2. Download GoogleService-Info.plist dari Firebase Console (project chataja-apps)
//    → drag ke Xcode (centang Copy items if needed)
// 3. Di ChatAjaApp.swift, tambah di init:
//      import FirebaseCore
//      FirebaseApp.configure()

#if canImport(FirebaseFirestore)
import FirebaseFirestore

final class FirestoreChatService: ObservableObject {
    static let shared = FirestoreChatService()
    private init() {}

    private let db = Firestore.firestore()

    @Published var messages: [ChatMessage] = []
    @Published var typingUsers: [String] = []

    private var msgListener: ListenerRegistration?
    private var roomListener: ListenerRegistration?

    // MARK: - Listen pesan realtime

    func listenMessages(roomId: String) {
        stopListening()
        msgListener = db.collection("rooms").document(roomId)
            .collection("messages")
            .order(by: "createdAt")
            .limit(toLast: 100)
            .addSnapshotListener { [weak self] snap, err in
                guard let docs = snap?.documents else { return }
                self?.messages = docs.compactMap { ChatMessage(doc: $0) }
            }

        roomListener = db.collection("rooms").document(roomId)
            .addSnapshotListener { [weak self] snap, _ in
                let users = snap?.data()?["typingUsers"] as? [String] ?? []
                let me = AuthManager.shared.idToken ?? "" // ganti dengan UID asli
                self?.typingUsers = users.filter { $0 != me }
            }
    }

    func stopListening() {
        msgListener?.remove()
        roomListener?.remove()
        msgListener = nil
        roomListener = nil
        messages = []
        typingUsers = []
    }

    // MARK: - Kirim pesan

    func sendMessage(roomId: String, senderId: String, text: String) async throws {
        let data: [String: Any] = [
            "senderId": senderId,
            "text": text,
            "type": "text",
            "createdAt": FieldValue.serverTimestamp(),
        ]
        try await db.collection("rooms").document(roomId)
            .collection("messages").addDocument(data: data)

        // Update lastMessage di contacts kedua belah pihak
        // (disederhanakan — backend sudah handle via API)
    }

    // MARK: - Typing indicator

    func setTyping(roomId: String, userId: String, isTyping: Bool) async throws {
        let ref = db.collection("rooms").document(roomId)
        if isTyping {
            try await ref.updateData(["typingUsers": FieldValue.arrayUnion([userId])])
        } else {
            try await ref.updateData(["typingUsers": FieldValue.arrayRemove([userId])])
        }
    }
}

// MARK: - Model

struct ChatMessage: Identifiable {
    let id: String
    let senderId: String
    let text: String
    let createdAt: Date
    let type: String

    init?(doc: QueryDocumentSnapshot) {
        let d = doc.data()
        guard let senderId = d["senderId"] as? String,
              let text = d["text"] as? String else { return nil }
        self.id = doc.documentID
        self.senderId = senderId
        self.text = text
        self.type = d["type"] as? String ?? "text"
        self.createdAt = (d["createdAt"] as? Timestamp)?.dateValue() ?? Date()
    }
}
#else
// Fallback kalau Firebase belum dipasang — biar tetap compile
final class FirestoreChatService: ObservableObject {
    static let shared = FirestoreChatService()
    @Published var messages: [ChatMessage] = []
    @Published var typingUsers: [String] = []
    func listenMessages(roomId: String) {}
    func stopListening() {}
}
struct ChatMessage: Identifiable {
    let id: String; let senderId: String; let text: String
    let createdAt: Date; let type: String
}
#endif
