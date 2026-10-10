# PRD — ChatAja iOS UI

> Dokumen ini untuk Antigravity (AI coding agent). Ikuti spesifikasi di bawah
> persis. Backend API: lihat `docs/API.md`. Bahasa aplikasi: **Indonesia saja**.

## 1. Gambaran Umum

ChatAja adalah aplikasi anonymous chat + microblogging (Utas). Versi iOS ini
dibangun dengan SwiftUI, target iOS 18+, mengikuti bahasa desain **Liquid Glass**
(iOS 26). Kesan yang dituju: **elegan, tenang, premium** — bukan ramai.

Struktur kode existing (jangan ubah arsitektur):
- `ChatAja/App/ChatAjaApp.swift` — entry point
- `ChatAja/Core/API/APIClient.swift` — REST client (sudah jadi)
- `ChatAja/Core/API/AuthManager.swift` — auth state (TODO: Firebase)
- `ChatAja/Core/Models/Models.swift` — model (sudah jadi)
- `ChatAja/Features/MainTabView.swift` — tab bar
- `ChatAja/Features/Feed/FeedView.swift` — feed + post card
- `ChatAja/Features/Thread/ThreadView.swift` — thread + composer

## 2. Bahasa Desain

### Prinsip
- **Liquid Glass**: pakai `.glassEffect()` / material blur untuk tab bar, sheet,
  dan elemen mengambang. Jangan pakai warna solid untuk chrome.
- **Ruang napas**: spacing longgar, jangan padat. Padding horizontal 16–20.
- **Tipografi iOS native**: SF Pro via `.font()` system. Judul pakai
  `.headline`/`.title3` bold, body `.body`, meta `.caption` secondary.
- **Warna semantik saja**: `.primary`, `.secondary`, `.tertiary` — JANGAN hardcode
  hitam/putih kecuali aksen brand. Dark/light mode harus otomatis jalan.
- **Aksen**: indigo `#5B5BD6` untuk aksi primer (tombol kirim, link). Merah untuk
  destructive/like aktif. Alias anonim pakai warna dari API (`aliasColor`).

### Jangan
- Jangan pakai gradient mencolok di background utama.
- Jangan pakai border tebal / shadow berat.
- Jangan ubah struktur navigasi tab yang sudah ada.

## 3. Layar per Layar

### 3.1 Login (`LoginView`)
- Tampilkan logo (AppIcon), nama "ChatAja", tagline "Ngobrol anonim, tanpa nama."
- Tombol "Masuk dengan Google" dan "Masuk dengan Apple" (style iOS native).
- Setelah login: simpan Firebase ID token ke `AuthManager.shared.idToken`,
  set `isLoggedIn = true`.
- Loading state saat proses auth, error state dengan pesan Indonesia.

### 3.2 Feed Utas (`FeedView`)
Layout ala Threads, dua tab di atas: **Public** | **Mengikuti** (segmented control).

Setiap kartu post (`PostCardView`):
- Kiri: avatar 40pt (foto profil, atau lingkaran warna alias + inisial untuk anonim).
- Kanan:
  - Baris 1: nama (bold, subheadline) + badge verified + waktu relatif kanan ("5m", "2j", "3h").
  - Isi teks (body).
  - Media: carousel horizontal, rounded 12, tinggi 200. Satu foto = tampil penuh proporsional.
  - Baris aksi: 💬 jumlah balasan | ♡ jumlah like | … (menu: Hapus jika milik sendiri, Laporkan jika bukan).
- Tap kartu → buka Thread.
- Pull-to-refresh. Infinite scroll via `nextCursor`.
- Empty state: ilustrasi sederhana + "Belum ada utas. Jadilah yang pertama."
- Tombol compose (✎) di toolbar kanan → sheet `CreatePostView`.

Interaksi like: optimistic update (langsung berubah, rollback kalau gagal).

### 3.3 Thread (`ThreadView`)
- Post utama di atas (full card), divider, lalu daftar komentar.
- Komentar balasan (field `replyTo` terisi dan ≠ postId) **indent 24pt ke kanan**
  dengan garis vertikal tipis sebagai thread line.
- Tap "Balas" di komentar → composer bawah berubah placeholder jadi
  "Balas @Nama…" dan kirim dengan `parentId` = ID komentar itu.
- Composer komentar: sticky di bawah keyboard, text field + tombol Kirim.

### 3.4 Composer (`CreatePostView`)
- Sheet modal dengan navigation bar: "Batal" kiri, "Kirim" kanan.
- Toggle "Posting anonim" di atas (jelaskan: nama disamarkan jadi alias permanen).
- TextEditor dengan placeholder "Apa yang kamu pikirkan?" + counter 0/1000.
- Tombol Kirim disabled kalau teks kosong atau > 1000 char.
- Setelah sukses: tutup sheet, refresh feed.

### 3.5 Chat — Daftar Kontak (`ContactsView`)
- List kontak: avatar, nama, preview pesan terakhir, waktu, badge unread.
- Tap → buka room chat (lihat 3.6).
- Pull-to-refresh.

### 3.6 Chat — Room (BARU, belum ada)
- **Realtime via Firestore langsung** (bukan REST API):
  - Collection: `rooms/{roomId}/messages`, order by `createdAt`.
  - Field pesan: `senderId`, `text`, `createdAt`, `type`.
  - Typing indicator: field `typingUsers` di dokumen room (array UID).
- Bubble chat: kanan (sendiri, aksen indigo) / kiri (lawan, glass/quaternary).
- Header: nama lawan + status typing ("mengetik…").
- Input bar sticky: text field + tombol kirim (✈︎).
- Room ID didapat dari `POST /api/chat/from-utas` (saat tap kartu Utas → "Chat").
- Aturan Firestore: klien hanya boleh update `typingUsers`. Jangan tulis field lain.

### 3.7 Notifikasi (`NotificationsView`)
- List: ikon tipe, judul (bold), body (secondary), waktu relatif.
- Unread: dot indigo di kiri + background subtle.
- Tap notifikasi → navigasi ke target (room atau thread).
- Tandai dibaca saat dibuka (panggil `POST /api/chat/notifications/read`).
- Badge unread di tab bar.

### 3.8 Profil (`ProfileView`)
- Header: avatar besar 80pt, nama (title2 bold), bio (secondary), badge verified.
- Statistik: jumlah utas, pengikut, mengikuti (jika API mendukung; kalau belum, skip).
- Tombol "Edit Profil" → sheet edit (nama, bio, avatar URL) → `POST /api/account/profile/update`.
- Menu: Daftar blokir, Hapus akun (konfirmasi ganda), Keluar.

## 4. Tab Bar

`MainTabView` — 4 tab:
1. Utas (text.bubble) 2. Chat (message) 3. Notifikasi (bell + badge) 4. Profil (person)

- Background: `.ultraThinMaterial` (Liquid Glass).
- Ikon SF Symbols, label kecil di bawah.

## 5. State & Error Handling

Setiap layar async WAJIB punya 3 state: **loading** (skeleton/shimmer, bukan
spinner polos), **kosong** (ilustrasi + teks), **error** (pesan + tombol "Coba lagi").
Tidak boleh ada layar putih atau spinner abadi.

Error dari API (`{success:false, error}`): tampilkan `error` apa adanya ke user
(sudah Bahasa Indonesia dari backend).

## 6. Kriteria Selesai (Definition of Done)

- [ ] Semua layar di atas jalan di simulator iPhone (iOS 18+).
- [ ] Dark mode & light mode otomatis benar (tidak ada teks hilang/kontras rusak).
- [ ] Build tanpa warning/error di Xcode.
- [ ] Tidak ada custom color hardcoded yang merusak dark mode.
- [ ] Semua string user-facing Bahasa Indonesia.
- [ ] Like bersifat optimistic, kirim post/komentar tunggu konfirmasi server.
- [ ] Tidak mengubah file di `Core/API/` kecuali diminta (milik Niko).
