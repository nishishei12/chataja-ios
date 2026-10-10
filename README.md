# ChatAja iOS

Aplikasi iOS ChatAja (SwiftUI) — timeline Utas ala Threads + anon chat.

## Arsitektur

- **SwiftUI** + `async/await`
- **Backend:** REST API `https://chat-anon-roan.vercel.app/api`
  - Utas: `/api/utas/*` (create, feed, thread, like, delete, follow, report)
  - Chat: `/api/chat/*` (contacts, notifications, from-utas)
  - Akun: `/api/account/*` (profile)
  - Safety: `/api/safety/*` (blocks)
- **Auth:** Firebase ID Token (header `Authorization: Bearer`)
- **Chat realtime:** tetap via Firestore (belum di versi ini)

## Setup

1. Buka `ChatAja.xcodeproj` di Xcode 16+
2. Tambah Firebase via SPM (Auth)
3. Isi `AuthManager` dengan Firebase Auth yang bener
4. Run di simulator / device iOS 18+

## Fitur

- [x] Feed Utas (Public + Mengikuti)
- [x] Post + komentar + balas komentar (nested)
- [x] Like idempoten
- [x] Mode anonim (alias permanen)
- [x] Follow/unfollow
- [x] Hapus post sendiri
- [x] Report konten
- [x] Kontak, Notifikasi, Profil
- [ ] Chat realtime (Firestore) — menyusul
- [ ] Login Firebase UI — menyusul

## Desain

- Liquid Glass tab bar (iOS 26)
- Threads-like post card
- Bahasa Indonesia
