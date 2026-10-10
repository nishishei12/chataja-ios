import Foundation

// MARK: - Post

struct Post: Identifiable, Decodable {
    let id: String
    let text: String
    let createdAt: Int64
    let expiresAt: Int64
    let author: Author
    let mediaUrls: [String]
    let stats: PostStats
    let viewer: ViewerInfo
    let replyTo: String?

    struct Author: Decodable {
        let mode: String // "profile" | "anon"
        let displayName: String?
        let avatarUrl: String?
        let isVerified: Bool?
        let alias: String?
        let aliasColor: String?

        var displayTitle: String {
            if mode == "anon" { return alias ?? "Anonim" }
            return displayName ?? "Pengguna"
        }
    }

    struct PostStats: Decodable {
        let likes: Int
        let replies: Int
    }

    struct ViewerInfo: Decodable {
        let isMine: Bool
        let isLiked: Bool
    }
}

// MARK: - Feed

struct FeedData: Decodable {
    let items: [Post]
    let nextCursor: String?
}

// MARK: - Thread

struct ThreadData: Decodable {
    let post: Post
    let comments: [Post]
    let nextCursor: String?
}

// MARK: - Contact

struct Contact: Identifiable, Decodable {
    var id: String { userId }
    let userId: String
    let roomId: String?
    let lastMessage: String
    let lastMessageTime: Int64
    let unreadCount: Int
    let partnerName: String
    let partnerAvatar: String
}

// MARK: - App Notification

struct AppNotification: Identifiable, Decodable {
    let id: String
    let type: String
    let title: String
    let body: String
    let roomId: String?
    let utasId: String?
    let isRead: Bool
    let createdAt: Int64
}

// MARK: - Profile

struct Profile: Decodable {
    let userId: String
    let displayName: String
    let avatarUrl: String
    let bio: String
    let isVerified: Bool
    let isOwn: Bool
}
