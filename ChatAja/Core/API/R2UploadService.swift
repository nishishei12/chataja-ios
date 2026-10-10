import Foundation
import UIKit

// MARK: - R2 Upload Service
//
// Alur sama seperti Android (uploadPhotosToR2):
// 1. Minta tiket presigned ke database-media-curhatin.vercel.app/api/upload-ticket
// 2. PUT file langsung ke R2 via uploadUrl
// 3. Dapat publicUrl buat dipakai di chat/utas

final class R2UploadService {
    static let shared = R2UploadService()
    private init() {}

    private let ticketURL = URL(string: "https://database-media-curhatin.vercel.app/api/upload-ticket")!

    struct TicketResponse: Decodable {
        let success: Bool
        let data: TicketData?
        let error: String?
        struct TicketData: Decodable {
            let uploadUrl: String
            let publicUrl: String
        }
    }

    enum UploadError: Error, LocalizedError {
        case ticketFailed(String)
        case uploadFailed(Int)
        case invalidImage

        var errorDescription: String? {
            switch self {
            case .ticketFailed(let msg): return "Gagal dapat tiket upload: \(msg)"
            case .uploadFailed(let code): return "Gagal upload (HTTP \(code))"
            case .invalidImage: return "File bukan gambar yang valid"
            }
        }
    }

    /// Upload satu gambar ke R2. Otomatis resize max 1600px + JPEG q82 (strip EXIF).
    func uploadImage(_ image: UIImage, userId: String) async throws -> String {
        // Resize jika terlalu besar
        let resized = resizeIfNeeded(image, maxDimension: 1600)
        guard let jpegData = resized.jpegData(compressionQuality: 0.82) else {
            throw UploadError.invalidImage
        }

        let fileName = "photo_\(Int(Date().timeIntervalSince1970 * 1000))_\(Int.random(in: 1000...9999)).jpg"
        return try await upload(data: jpegData, fileName: fileName,
                                contentType: "image/jpeg", userId: userId)
    }

    /// Upload voice note (m4a) ke R2.
    func uploadVoice(_ data: Data, userId: String) async throws -> String {
        let fileName = "voice_\(Int(Date().timeIntervalSince1970 * 1000)).m4a"
        return try await upload(data: data, fileName: fileName,
                                contentType: "audio/mp4", userId: userId)
    }

    // MARK: - Private

    private func upload(data: Data, fileName: String, contentType: String, userId: String) async throws -> String {
        // 1. Minta tiket
        var ticketReq = URLRequest(url: ticketURL)
        ticketReq.httpMethod = "POST"
        ticketReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = AuthManager.shared.idToken {
            ticketReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        struct TicketRequest: Encodable {
            let userId: String
            let fileName: String
            let contentType: String
            let contentLength: Int
        }
        ticketReq.httpBody = try JSONEncoder().encode(TicketRequest(
            userId: userId,
            fileName: fileName,
            contentType: contentType,
            contentLength: data.count
        ))

        let (ticketData, ticketResp) = try await URLSession.shared.data(for: ticketReq)
        guard (ticketResp as? HTTPURLResponse)?.statusCode == 200 else {
            throw UploadError.ticketFailed("HTTP \((ticketResp as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        let ticket = try JSONDecoder().decode(TicketResponse.self, from: ticketData)
        guard ticket.success, let t = ticket.data else {
            throw UploadError.ticketFailed(ticket.error ?? "?")
        }

        // 2. PUT ke R2
        var putReq = URLRequest(url: URL(string: t.uploadUrl)!)
        putReq.httpMethod = "PUT"
        putReq.setValue(contentType, forHTTPHeaderField: "Content-Type")
        putReq.httpBody = data

        let (_, putResp) = try await URLSession.shared.data(for: putReq)
        let code = (putResp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            throw UploadError.uploadFailed(code)
        }

        return t.publicUrl
    }

    private func resizeIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard max(size.width, size.height) > maxDimension else { return image }
        let scale = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
