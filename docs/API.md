# ChatAja API Reference

Base URL: `https://chat-anon-roan.vercel.app/api`

## Auth

Semua endpoint butuh Firebase ID Token:
```
Authorization: Bearer <firebase-id-token>
```

## Utas

### POST /api/utas/create
Bikin post / komentar / balasan.

```json
{
  "text": "isi utas (max 1000 char)",
  "mode": "profile" | "anon",
  "mediaUrls": ["https://..."],
  "parentId": "optional — ID post (jadi komentar) atau ID komentar (jadi balasan)"
}
```
Response: `{ "success": true, "data": { "postId": "...", "alias": "..." } }`

### GET /api/utas/feed?tab=public|following&limit=20&cursor=
Feed dua tab. `tab=public` = semua post, `tab=following` = yang di-follow aja.

Response item:
```json
{
  "id": "...",
  "text": "...",
  "createdAt": 1234567890000,
  "expiresAt": 1234567890000,
  "author": {
    "mode": "profile" | "anon",
    "displayName": "...",
    "avatarUrl": "...",
    "isVerified": false,
    "alias": "Kucing Terbang",
    "aliasColor": "#5B8DEF"
  },
  "mediaUrls": [],
  "stats": { "likes": 5, "replies": 3 },
  "viewer": { "isMine": false, "isLiked": false },
  "replyTo": null
}
```
Response: `{ "success": true, "data": { "items": [...], "nextCursor": "..." } }`

### GET /api/utas/thread?postId=
Detail post + semua komentar (nested via field `replyTo`).

Response: `{ "success": true, "data": { "post": {...}, "comments": [...], "nextCursor": "..." } }`

### POST /api/utas/like
```json
{ "postId": "...", "like": true }
```
Response: `{ "success": true, "data": { "liked": true, "likeCount": 6 } }`

### POST /api/utas/delete
```json
{ "postId": "..." }
```
Response: `{ "success": true, "data": { "deleted": true } }`

### POST /api/utas/follow
```json
{ "targetUserId": "...", "follow": true }
```
Response: `{ "success": true, "data": { "following": true } }`

### POST /api/utas/report
```json
{ "postId": "...", "reason": "spam" }
```
Response: `{ "success": true, "data": { "reported": true } }`

## Chat

### POST /api/chat/from-utas
Buka/mulai chat dengan author utas.
```json
{ "utasId": "..." }
```
Response: `{ "success": true, "data": { "roomId": "..." } }`

### GET /api/chat/contacts
Response: `{ "success": true, "data": { "contacts": [...] } }`

Contact: `{ "userId": "...", "roomId": "...", "lastMessage": "...", "lastMessageTime": 123, "unreadCount": 0, "partnerName": "...", "partnerAvatar": "..." }`

### GET /api/chat/notifications
Response: `{ "success": true, "data": { "notifications": [...], "unreadCount": 0 } }`

### POST /api/chat/notifications/read
```json
{ "notificationIds": ["..."] }
```

## Account

### GET /api/account/profile
Response: `{ "success": true, "data": { "profile": { "userId": "...", "displayName": "...", "avatarUrl": "...", "bio": "...", "isVerified": false, "isOwn": true } } }`

### POST /api/account/profile/update
```json
{ "displayName": "...", "avatarUrl": "...", "bio": "..." }
```

## Safety

### GET /api/safety/blocks
Response: `{ "success": true, "data": { "blocks": [...] } }`

### POST /api/safety/block
Blokir user (juga end room kalau ada).
```json
{ "userId": "<uid sendiri>", "targetId": "<uid target>", "roomId": "optional" }
```
Response: `{ "success": true, "message": "User blocked successfully" }`

### POST /api/safety/report
Lapor user.
```json
{ "reporterId": "<uid sendiri>", "reportedId": "<uid target>", "reason": "spam", "details": "optional", "roomId": "optional" }
```
Response: `{ "success": true, "message": "Report submitted successfully" }`

## Account (lanjutan)

### POST /api/account/delete
Hapus akun permanen. Body kosong.
Response: `{ "success": true }`

## Catatan

- Chat realtime (room, pesan, typing) tetap via **Firestore langsung**, bukan API.
- Semua teks Bahasa Indonesia.
- Error format: `{ "success": false, "error": "pesan" }`
