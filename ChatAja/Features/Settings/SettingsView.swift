import SwiftUI

// MARK: - Pengaturan (PRD parity §6 + §7)

struct SettingsView: View {
    @AppStorage("chataja.notifEnabled") private var notifEnabled = true
    @State private var cacheInfo: String?
    @State private var showDelete1 = false
    @State private var showDelete2 = false
    @State private var isDeleting = false
    @State private var actionError: String?

    var body: some View {
        List {
            Section("Umum") {
                Toggle("Notifikasi", isOn: $notifEnabled)
                Button {
                    clearCache()
                } label: {
                    Label("Hapus cache", systemImage: "trash")
                }
                if let info = cacheInfo {
                    Text(info)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Keamanan") {
                NavigationLink {
                    BlockListView()
                } label: {
                    Label("Daftar blokir", systemImage: "nosign")
                }
            }

            Section("Tentang") {
                HStack {
                    Text("ChatAja")
                    Spacer()
                    Text("Versi \(appVersion)")
                        .foregroundStyle(.secondary)
                }
                Text("Ngobrol anonim, tanpa nama.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Akun") {
                Button("Keluar", role: .destructive) {
                    AuthManager.shared.signOut()
                }
                Button("Hapus akun", role: .destructive) {
                    showDelete1 = true
                }
            }

            if let err = actionError {
                Section { Text(err).font(.caption).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Pengaturan")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Hapus akun?", isPresented: $showDelete1) {
            Button("Batal", role: .cancel) {}
            Button("Ya, lanjutkan", role: .destructive) { showDelete2 = true }
        } message: {
            Text("Akun yang dihapus tidak bisa dikembalikan.")
        }
        .alert("Yakin hapus permanen?", isPresented: $showDelete2) {
            Button("Batal", role: .cancel) {}
            Button("Hapus permanen", role: .destructive) { Task { await deleteAccount() } }
        } message: {
            Text("Konfirmasi kedua: semua utas dan chat ikut terhapus.")
        }
    }

    var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        let tmp = FileManager.default.temporaryDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
            for f in files { try? FileManager.default.removeItem(at: f) }
        }
        cacheInfo = "Cache dibersihkan."
    }

    func deleteAccount() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        struct Empty: Encodable {}
        struct D: Decodable { let ok: Bool? }
        do {
            let res: APIResponse<D> = try await APIClient.shared.post("/account/delete", body: Empty())
            if let apiErr = res.error, res.success == false {
                actionError = apiErr
                return
            }
            guard res.success else {
                actionError = "Gagal menghapus akun. Coba lagi."
                return
            }
            AuthManager.shared.signOut()
        } catch {
            actionError = "Gagal menghapus akun. Coba lagi."
        }
    }
}
