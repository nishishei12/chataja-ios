# PRD — Feature Parity Android → iOS

> Tujuan: semua fitur aplikasi Android (FlutterFlow) harus ada di iOS.
> Dokumen ini untuk Antigravity. Backend API: `docs/API.md`.
> Bahasa aplikasi: **Indonesia saja**.

## Ringkasan Status

| Fitur Android | Status iOS | Keterangan |
|---|---|---|
| Login (email/Google/anonim) | 🟡 Sebagian | LoginView ada, Firebase SDK belum dipasang di Xcode |
| Feed Utas (Public/Mengikuti) | ✅ Ada | FeedView |
| Buat utas (teks/foto/anonim) | ✅ Ada | CreatePostView |
| Thread + komentar nested | ✅ Ada | ThreadView |
| Like, follow, hapus, lapor utas | ✅ Ada | — |
| Daftar kontak chat | ✅ Ada | ContactsView |
| Chat 1-on-1 realtime | 🟡 Sebagian | ChatRoomView ada (teks+foto), lihat detail di bawah |
| Notifikasi | ✅ Ada | NotificationsView |
| Profil + edit profil | 🟡 Sebagian | Lihat/profil dasar ada, edit belum |
| Pengaturan | ❌ Belum | — |
| Blokir / laporkan user | ❌ Belum | API sudah ada |
| Premium / QRIS | ❌ Belum | — |

## Detail yang Belum Ada di iOS

### 1. Chat — Pesan Suara (Voice Note)
Android bisa kirim voice note (max 60 detik, format m4a).
- iOS: tambah tombol mic di `ChatRoomView`, rekam via `AVAudioRecorder`.
- Upload via `R2UploadService.uploadVoice()` (sudah ada).
- Tampilkan bubble audio dengan tombol play + durasi (pakai `AVAudioPlayer`).
- Field pesan: `type: "audio"`, `audioUrl`, `audioDuration`.

### 2. Chat — Video
Android bisa kirim video (max 60 detik, dikompres).
- iOS: tambah opsi video di image picker (`mediaTypes: [.movie]`).
- Kompres sebelum upload (pakai `AVAssetExportSession`, max 720p).
- Upload via R2 (tambah `uploadVideo()` di `R2UploadService`, contentType `video/mp4`).
- Tampilkan thumbnail + tombol play di bubble.

### 3. Chat — Balas Pesan (Quote Reply)
Android bisa reply pesan tertentu (tampil kutipan di atas bubble).
- iOS: swipe kanan pada bubble → set `replyTo` state.
- Tampilkan bar kutipan di atas input ("Membalas @Nama: ...").
- Field pesan: `replyToId`, `replyToText`, `replyToSender`, `replyToType`.
- Bubble tampilkan kutipan kecil di atas isi pesan.

### 4. Chat — Media Sekali Lihat (View Once)
Android punya foto sekali lihat.
- iOS: opsi "sekali lihat" saat kirim foto.
- Field: `isViewOnce: true`, `isViewed: false`.
- Setelah dibuka: tampilkan "Foto sudah dilihat", set `isViewed: true` di Firestore.

### 5. Profil — Edit
- Sheet edit: nama tampilan, bio, foto profil (upload via R2).
- Simpan via `POST /api/account/profile/update`.

### 6. Pengaturan (Halaman Baru)
- Notifikasi on/off, hapus cache, tentang aplikasi, versi.
- Menu: Keluar, Hapus Akun (konfirmasi ganda → `POST /api/account/delete`).

### 7. Blokir / Laporkan User
- Di profil user lain atau di chat: tombol "Blokir" dan "Laporkan".
- Blokir → `POST /api/safety/block`.
- Lapor → `POST /api/safety/report` (dengan alasan).
- Daftar blokir di Pengaturan → `GET /api/safety/blocks`.

### 8. Premium (Opsional, Tahap 2)
Android punya status premium + QRIS. iOS: pakai In-App Purchase (StoreKit 2).
- Status: `isPremium`, `premiumUntil` dari profil.
- Jangan implementasi pembayaran manual — wajib via App Store.

## Prioritas Pengerjaan

**P0 (inti, harus jalan):**
1. Login Firebase beneran (butuh aksi user di Xcode: tambah SPM + plist)
2. Voice note (rekam + play)
3. Edit profil

**P1 (penting):**
4. Balas pesan (quote)
5. Video
6. Pengaturan + blokir/lapor

**P2 (nanti):**
7. View once
8. Premium via StoreKit

## Aturan Tetap

- Jangan ubah file di `ChatAja/Core/API/` (milik Niko) kecuali diminta.
- Semua string Bahasa Indonesia.
- Dark/light mode otomatis (warna semantik saja).
- Setiap layar: loading / kosong / error state.
- Optimistic update untuk like; kirim pesan tunggu konfirmasi server.
