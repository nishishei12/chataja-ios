import SwiftUI
import AVKit
import UniformTypeIdentifiers

// MARK: - Chat Room (PRD 3.6 + parity: suara, video, kutipan, blokir/lapor)
//
// Realtime tetap via Firestore langsung. Pesan kaya (suara/video/kutipan)
// dikodekan sebagai teks berpenanda (lihat ChatMedia.swift) agar tidak
// mengubah FirestoreChatService (milik Niko): klien hanya boleh update
// field typingUsers.

struct ChatRoomView: View {
    let roomId: String
    let partnerName: String
    let myUserId: String
    var partnerUserId: String? = nil

    @ObservedObject private var chat = FirestoreChatService.shared
    @StateObject private var recorder = VoiceRecorder()
    @State private var inputText = ""
    @State private var replyingTo: QuotedMessage?
    @State private var pickerKind: PickerKind?
    @State private var isUploading = false
    @State private var sendError: String?
    @State private var safetyMessage: String?
    @State private var showBlockConfirm = false
    @State private var showReport = false
    @State private var reportReason = "spam"
    /// Draft pesan suara yang gagal terkirim (file lokal + durasi) + retry.
    @State private var voiceDraftURL: URL?
    @State private var voiceDraftDur = 0

    enum PickerKind: Identifiable {
        case photo, video
        var id: Int { self == .photo ? 0 : 1 }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !chat.typingUsers.isEmpty {
                Text("mengetik…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if chat.messages.isEmpty {
                            EmptyStateView(
                                icon: "message",
                                judul: "Belum ada pesan",
                                pesan: "Belum ada pesan. Sapa duluan dengan ramah."
                            )
                        } else {
                            ForEach(chat.messages) { msg in
                                MessageBubble(
                                    msg: msg,
                                    isMine: msg.senderId == myUserId,
                                    senderName: msg.senderId == myUserId ? "Saya" : partnerName
                                ) {
                                    let parsed = parseQuote(msg.text)
                                    replyingTo = QuotedMessage(
                                        sender: msg.senderId == myUserId ? "Saya" : partnerName,
                                        snippet: snippetLabel(for: parsed.body)
                                    )
                                }
                                .id(msg.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: chat.messages.count) { _, _ in
                    if let last = chat.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if let err = sendError {
                HStack(spacing: 8) {
                    Text(err).font(.caption).foregroundStyle(.red)
                    Spacer()
                    Button("Coba lagi") { Task { await sendText() } }
                        .font(.caption).bold()
                }
                .padding(.horizontal, 16)
            }
            if voiceDraftURL != nil {
                HStack(spacing: 8) {
                    Text("Pesan suara gagal terkirim.")
                        .font(.caption).foregroundStyle(.red)
                    Spacer()
                    Button("Hapus") { discardVoiceDraft() }
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Coba lagi") { Task { await retryVoiceDraft() } }
                        .font(.caption).bold()
                }
                .padding(.horizontal, 16)
            }
            if let info = safetyMessage {
                Text(info).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
            }
            if let recErr = recorder.errorMessage {
                Text(recErr).font(.caption).foregroundStyle(.red).padding(.horizontal, 16)
            }

            // Bar kutipan (parity: balas pesan).
            if let q = replyingTo {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Membalas @\(q.sender)")
                            .font(.caption).bold()
                        Text(q.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { replyingTo = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            // Merekam suara.
            if recorder.isRecording {
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 10, height: 10)
                    Text("Merekam \(formatDurasi(recorder.elapsed)) / 1:00")
                        .font(.subheadline).monospacedDigit()
                    Spacer()
                    Button("Batal") { recorder.stop(cancelled: true) }
                        .foregroundStyle(.secondary)
                    Button("Kirim") { recorder.stop(cancelled: false) }
                        .buttonStyle(.borderedProminent).tint(Brand.indigo)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            // Input bar sticky.
            HStack(spacing: 8) {
                Menu {
                    Button { pickerKind = .photo } label: {
                        Label("Foto", systemImage: "photo")
                    }
                    Button { pickerKind = .video } label: {
                        Label("Video (maks 60 dtk)", systemImage: "video")
                    }
                } label: {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
                .disabled(isUploading || recorder.isRecording)
                .accessibilityLabel("Kirim foto atau video")

                Button { recorder.requestAndStart() } label: {
                    Image(systemName: "mic.fill").foregroundStyle(.secondary)
                }
                .disabled(isUploading || recorder.isRecording)
                .accessibilityLabel("Rekam pesan suara")

                TextField("Tulis pesan…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .disabled(recorder.isRecording || isUploading)
                    .onChange(of: inputText) { _, _ in
                        Task {
                            try? await chat.setTyping(roomId: roomId, userId: myUserId,
                                                      isTyping: !inputText.isEmpty)
                        }
                    }

                Button { Task { await sendText() } } label: {
                    if isUploading {
                        ProgressView()
                    } else {
                        Image(systemName: "paperplane.fill")
                            .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : Brand.indigo)
                    }
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isUploading || recorder.isRecording)
                .accessibilityLabel("Kirim pesan")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .navigationTitle(partnerName.isEmpty ? "Chat" : partnerName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if partnerUserId != nil {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Laporkan", role: .destructive) { showReport = true }
                        Button("Blokir", role: .destructive) { showBlockConfirm = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Keamanan")
                }
            }
        }
        .sheet(item: $pickerKind) { kind in
            MediaPicker(
                allowVideo: kind == .video,
                onPhoto: { img in Task { await sendImage(img) } },
                onVideo: { url in Task { await sendVideo(url: url) } }
            )
        }
        .sheet(isPresented: $showReport) {
            NavigationStack {
                Form {
                    Section("Alasan") {
                        ForEach(["spam", "penipuan", "ujaran kebencian", "konten seksual", "lainnya"], id: \.self) { r in
                            HStack {
                                Text(reasonLabel(r))
                                Spacer()
                                if r == reportReason { Image(systemName: "checkmark").foregroundStyle(Brand.indigo) }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { reportReason = r }
                        }
                    }
                    Section {
                        Button("Kirim laporan", role: .destructive) {
                            showReport = false
                            Task { await reportUser() }
                        }
                    }
                }
                .navigationTitle("Laporkan user")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Batal") { showReport = false }
                    }
                }
            }
        }
        .alert("Blokir user ini?", isPresented: $showBlockConfirm) {
            Button("Batal", role: .cancel) {}
            Button("Blokir", role: .destructive) { Task { await blockUser() } }
        } message: {
            Text("Chat dengan user ini akan berakhir.")
        }
        .onAppear {
            chat.listenMessages(roomId: roomId)
            recorder.onFinish = { url, detik in
                Task { await sendVoice(url: url, detik: detik) }
            }
        }
        .onDisappear {
            chat.stopListening()
            Task { try? await chat.setTyping(roomId: roomId, userId: myUserId, isTyping: false) }
        }
    }

    // MARK: - Kirim

    /// Label ramah untuk kutipan (jangan tampilkan URL mentah).
    func snippetLabel(for body: String) -> String {
        if body.hasPrefix("[foto] ") { return "[Foto]" }
        if body.hasPrefix("[audio] ") { return "[Pesan suara]" }
        if body.hasPrefix("[video] ") { return "[Video]" }
        let s = String(body.prefix(80)).replacingOccurrences(of: "\n", with: " ")
        return s.isEmpty ? "[Lampiran]" : s
    }

    /// Teks dikirim apa adanya; kirim pesan tunggu konfirmasi server (PRD).
    /// Saat gagal, draf + kutipan dipulihkan agar bisa Coba lagi.
    func sendRaw(_ text: String) async {
        let savedQuote = replyingTo
        let body = parseQuote(text).body
        replyingTo = nil
        sendError = nil
        try? await chat.setTyping(roomId: roomId, userId: myUserId, isTyping: false)
        do {
            try await chat.sendMessage(roomId: roomId, senderId: myUserId, text: text)
        } catch {
            sendError = "Gagal mengirim. Coba lagi."
            inputText = body
            replyingTo = savedQuote
        }
    }

    func withQuote(_ body: String) -> String {
        guard let q = replyingTo else { return body }
        replyingTo = nil
        return encodeQuote(q, body: body)
    }

    func sendText() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        await sendRaw(withQuote(text))
    }

    func sendImage(_ image: UIImage) async {
        isUploading = true
        sendError = nil
        defer { isUploading = false }
        do {
            let url = try await R2UploadService.shared.uploadImage(image, userId: myUserId)
            await sendRaw(withQuote("[foto] \(url)"))
        } catch {
            sendError = "Gagal mengunggah foto. Coba lagi."
        }
    }

    func sendVoice(url: URL, detik: Int) async {
        isUploading = true
        sendError = nil
        defer { isUploading = false }
        do {
            let data = try voiceData(url: url)
            let remote = try await R2UploadService.shared.uploadVoice(data, userId: myUserId)
            try? FileManager.default.removeItem(at: url)
            voiceDraftURL = nil
            await sendRaw(withQuote("[audio] \(remote) \(detik)"))
        } catch {
            // Simpan draft agar bisa Coba lagi tanpa merekam ulang.
            voiceDraftURL = url
            voiceDraftDur = detik
            sendError = "Gagal mengirim pesan suara."
        }
    }

    /// Baca file suara dengan batas 25 MB (hindari OOM).
    func voiceData(url: URL) throws -> Data {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs[.size] as? Int ?? 0
        guard size <= 25_000_000 else {
            throw NSError(domain: "voice", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "File suara terlalu besar."])
        }
        return try Data(contentsOf: url)
    }

    func retryVoiceDraft() async {
        guard let url = voiceDraftURL else { return }
        await sendVoice(url: url, detik: voiceDraftDur)
    }

    func discardVoiceDraft() {
        if let url = voiceDraftURL { try? FileManager.default.removeItem(at: url) }
        voiceDraftURL = nil
    }

    func sendVideo(url: URL) async {
        isUploading = true
        sendError = nil
        defer { isUploading = false }
        do {
            let compressed = await ChatVideo.compress(url)
            // Hapus file kompres setelah selesai; jangan hapus file picker asli.
            defer { if compressed != url { try? FileManager.default.removeItem(at: compressed) } }
            let attrs = try FileManager.default.attributesOfItem(atPath: compressed.path)
            let size = attrs[.size] as? Int ?? 0
            guard size <= 100_000_000 else {
                sendError = "Video terlalu besar (maks 100 MB)."
                return
            }
            let data = try Data(contentsOf: compressed)
            let remote = try await R2UploadService.shared.uploadVideo(data, userId: myUserId)
            await sendRaw(withQuote("[video] \(remote)"))
        } catch {
            sendError = "Gagal mengirim video. Coba lagi."
        }
    }

    // MARK: - Keamanan (parity §7)

    func blockUser() async {
        guard let target = partnerUserId, !myUserId.isEmpty else { return }
        struct Body: Encodable { let userId: String; let targetId: String; let roomId: String }
        struct D: Decodable {}
        do {
            let res: APIResponse<D> = try await APIClient.shared.post(
                "/safety/block",
                body: Body(userId: myUserId, targetId: target, roomId: roomId)
            )
            safetyMessage = res.error ?? "User diblokir."
        } catch {
            safetyMessage = "Gagal memblokir. Coba lagi."
        }
    }

    func reportUser() async {
        guard let target = partnerUserId, !myUserId.isEmpty else { return }
        struct Body: Encodable {
            let reporterId: String; let reportedId: String
            let reason: String; let roomId: String
        }
        struct D: Decodable {}
        do {
            let res: APIResponse<D> = try await APIClient.shared.post(
                "/safety/report",
                body: Body(reporterId: myUserId, reportedId: target, reason: reportReason, roomId: roomId)
            )
            safetyMessage = res.error ?? "Terima kasih, laporanmu terkirim."
        } catch {
            safetyMessage = "Gagal melaporkan. Coba lagi."
        }
    }

    func reasonLabel(_ r: String) -> String {
        switch r {
        case "spam": return "Spam"
        case "penipuan": return "Penipuan"
        case "ujaran kebencian": return "Ujaran kebencian"
        case "konten seksual": return "Konten seksual"
        default: return "Lainnya"
        }
    }
}

// MARK: - Bubble (kutipan + penanda media)

struct MessageBubble: View {
    let msg: ChatMessage
    let isMine: Bool
    var senderName: String = ""
    var onQuote: (() -> Void)? = nil
    @State private var showVideo = false

    var body: some View {
        let parsed = parseQuote(msg.text)
        HStack {
            if isMine { Spacer(minLength: 48) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                if let q = parsed.quote {
                    QuoteBox(quote: q, isMine: isMine)
                }
                content(for: parsed.body)
                Text(msg.createdAt, style: .time)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if !isMine { Spacer(minLength: 48) }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                if value.translation.width > 60, abs(value.translation.height) < 40 {
                    onQuote?()
                }
            }
        )
        .contextMenu {
            Button("Balas") { onQuote?() }
        }
        .sheet(isPresented: $showVideo) {
            if case .video(let url) = kind(of: parsed.body) {
                VideoPlayer(player: AVPlayer(url: url))
                    .ignoresSafeArea()
            }
        }
    }

    enum Kind {
        case text(String), photo(URL), audio(URL, Int), video(URL)
    }

    func kind(of body: String) -> Kind {
        if body.hasPrefix("[foto] ") {
            let raw = String(body.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: raw) { return .photo(url) }
        } else if body.hasPrefix("[audio] ") {
            let parts = body.dropFirst(8).split(separator: " ")
            if parts.count >= 2, let url = URL(string: String(parts[0])), let d = Int(parts[1]) {
                // Klem agar durasi rusak tidak merusak UI.
                return .audio(url, min(max(d, 0), 3600))
            }
        } else if body.hasPrefix("[video] ") {
            let raw = String(body.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: raw) { return .video(url) }
        }
        return .text(body)
    }

    @ViewBuilder
    func content(for body: String) -> some View {
        switch kind(of: body) {
        case .photo(let url):
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                case .failure: Color(uiColor: .systemGray5).overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
                default: Color(uiColor: .systemGray5).overlay { ProgressView() }
                }
            }
            .frame(maxWidth: 220, maxHeight: 220)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .audio(let url, let d):
            AudioBubble(url: url, detik: d, isMine: isMine)
        case .video(let url):
            VideoBubble(url: url) { showVideo = true }
        case .text(let t):
            if t.isEmpty {
                Text("Pesan kosong.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(t)
                    .font(.body)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(isMine ? Brand.indigo : Color(uiColor: .systemGray5))
                    .foregroundStyle(isMine ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}

// MARK: - Pemilih foto / video

struct MediaPicker: UIViewControllerRepresentable {
    var allowVideo: Bool = false
    var onPhoto: (UIImage) -> Void
    var onVideo: (URL) -> Void
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.delegate = context.coordinator
        p.mediaTypes = allowVideo
            ? [UTType.movie.identifier]
            : [UTType.image.identifier]
        p.videoMaximumDuration = 60
        return p
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: MediaPicker
        init(_ parent: MediaPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.onPhoto(img)
            } else if let url = info[.mediaURL] as? URL {
                parent.onVideo(url)
            }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
