import SwiftUI

// MARK: - Shared UI (PRD Bahasa Desain)

/// Aksen brand sesuai PRD. Dipakai hemat: tombol kirim, link, dot unread.
/// Jangan dipakai untuk background besar.
enum Brand {
    static let indigo = Color(red: 0x5B / 255, green: 0x5B / 255, blue: 0xD6 / 255)
}

/// Waktu relatif Bahasa Indonesia: "baru saja", "5m", "2j", "3h".
/// PRD: contoh "5m", "2j", "3h".
func waktuRelatif(_ ms: Int64) -> String {
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    var detik = Int((now - ms) / 1000)
    if detik < 0 { detik = 0 }
    if detik < 10 { return "baru saja" }
    if detik < 60 { return "\(detik)d" }
    let menit = detik / 60
    if menit < 60 { return "\(menit)m" }
    let jam = menit / 60
    if jam < 24 { return "\(jam)j" }
    let hari = jam / 24
    if hari < 7 { return "\(hari)h" }
    let minggu = hari / 7
    if minggu < 5 { return "\(minggu)mg" }
    let bulan = hari / 30
    return "\(max(bulan, 1))bln"
}

// MARK: - Skeleton (loading, bukan spinner polos)

struct SkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.quaternary)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

struct PostSkeletonView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(.quaternary).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBar(width: 140)
                SkeletonBar()
                SkeletonBar(width: 200)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary)
                    .frame(height: 120)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .redacted(reason: .placeholder)
        .accessibilityLabel("Memuat…")
    }
}

// MARK: - Empty & Error (PRD bagian 5)

struct EmptyStateView: View {
    let icon: String
    let judul: String
    let pesan: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
                .padding(.top, 40)
            Text(judul)
                .font(.headline)
            Text(pesan)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

struct ErrorStateView: View {
    let pesan: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .padding(.top, 40)
            Text(pesan)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Coba lagi", action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(Brand.indigo)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Avatar kecil untuk list (kontak/notifikasi)

struct InitialAvatarView: View {
    let nama: String
    let warnaHex: String? = nil
    var diameter: CGFloat = 44

    var body: some View {
        Circle()
            .fill(Color(hexAv: warnaHex ?? "#5B8DEF"))
            .overlay {
                Text(String(nama.prefix(1).uppercased()))
                    .font(.system(size: diameter * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: diameter, height: diameter)
    }
}

// Helper hex khusus shared file (nama unik biar tak bentrok dengan FeedView).
extension Color {
    init(hexAv hex: String) {
        let h = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
