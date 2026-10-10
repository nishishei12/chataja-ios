import SwiftUI
import AVFoundation
import AVKit

// MARK: - Codec penanda pesan kaya (tanpa ubah Core/API)
//
// Pesan foto existing memakai konvensi teks "[foto] <url>".
// Penanda baru mengikuti pola yang sama agar FirestoreChatService
// (milik Niko) tidak perlu diubah:
// - Suara : "[audio] <url> <detik>"
// - Video : "[video] <url>"
// - Kutipan: baris pertama "[balas @Nama: cuplikan]", isi di baris berikut.

struct QuotedMessage: Equatable {
    let sender: String
    let snippet: String
}

func parseQuote(_ text: String) -> (quote: QuotedMessage?, body: String) {
    guard text.hasPrefix("[balas @") else { return (nil, text) }
    guard let newline = text.firstIndex(of: "\n") else { return (nil, text) }
    let first = String(text[..<newline])
    guard first.hasSuffix("]") else { return (nil, text) }
    let inner = first.dropFirst("[balas @".count).dropLast()
    guard let colon = inner.firstIndex(of: ":") else { return (nil, text) }
    let sender = String(inner[..<colon]).trimmingCharacters(in: .whitespaces)
    let snippet = String(inner[inner.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
    guard !sender.isEmpty else { return (nil, text) }
    return (QuotedMessage(sender: sender, snippet: snippet), String(text[text.index(after: newline)...]))
}

func encodeQuote(_ quote: QuotedMessage, body: String) -> String {
    let oneLine = quote.snippet.replacingOccurrences(of: "\n", with: " ")
    let short = String(oneLine.prefix(80))
    return "[balas @\(quote.sender): \(short)]\n\(body)"
}

func formatDurasi(_ detik: Int) -> String {
    "\(detik / 60):\(String(format: "%02d", detik % 60))"
}

// MARK: - Perekam pesan suara (maks 60 detik, m4a)

final class VoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var elapsed = 0
    @Published var errorMessage: String?
    var onFinish: ((URL, Int) -> Void)?

    let maxDuration = 60
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?
    /// Cegah onFinish ganda (timer + delegate auto-stop bisa berbarengan).
    private var didFinish = false

    func requestAndStart() {
        errorMessage = nil
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard granted else {
                    self?.errorMessage = "Izin mikrofon ditolak. Nyalakan di Pengaturan iPhone."
                    return
                }
                self?.start()
            }
        }
    }

    private func start() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("voice_\(Int(Date().timeIntervalSince1970 * 1000)).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.delegate = self
            recorder?.record(forDuration: TimeInterval(maxDuration))
            fileURL = url
            didFinish = false
            elapsed = 0
            isRecording = true
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.elapsed += 1
                if self.elapsed >= self.maxDuration { self.stop(cancelled: false) }
            }
        } catch {
            errorMessage = "Gagal merekam suara. Coba lagi."
        }
    }

    func stop(cancelled: Bool) {
        guard !didFinish else { return }
        didFinish = true
        timer?.invalidate()
        timer = nil
        let url = fileURL
        let dur = elapsed
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        if !cancelled {
            if let url, dur > 0 {
                onFinish?(url, min(dur, maxDuration))
            } else {
                errorMessage = "Rekaman terlalu pendek. Tahan dan bicara minimal 1 detik."
                if let url { try? FileManager.default.removeItem(at: url) }
            }
        } else if let url {
            try? FileManager.default.removeItem(at: url)
        }
        fileURL = nil
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // Auto-stop saat mencapai durasi maks: selesaikan lewat jalur yang sama.
        if isRecording { stop(cancelled: !flag) }
    }
}

// MARK: - Pemutar pesan suara

@MainActor
final class VoicePlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    private var player: AVAudioPlayer?

    func toggle(url: URL) {
        if isPlaying {
            player?.stop()
            isPlaying = false
            return
        }
        errorMessage = nil
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                try AVAudioSession.sharedInstance().setCategory(.playback)
                self.player = try AVAudioPlayer(data: data)
                self.player?.play()
                self.isPlaying = true
            } catch {
                self.isPlaying = false
                self.errorMessage = "Gagal memutar pesan suara."
            }
            self.isLoading = false
        }
    }

    func stop() {
        player?.stop()
        isPlaying = false
    }
}

// MARK: - Video: kompres 720p + thumbnail

enum ChatVideo {
    /// Kompres ke max 720p (PRD parity). Kembalikan file asli kalau gagal.
    static func compress(_ sourceURL: URL) async -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            return sourceURL
        }
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("video_\(Int(Date().timeIntervalSince1970 * 1000)).mp4")
        try? FileManager.default.removeItem(at: outURL)
        session.outputURL = outURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        do {
            try await session.export(to: outURL, as: .mp4)
            return outURL
        } catch {
            return sourceURL
        }
    }

    static func thumbnail(_ videoURL: URL) async -> UIImage? {
        let asset = AVURLAsset(url: videoURL)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 480, height: 480)
        do {
            let result = try await gen.image(at: CMTime(seconds: 1, preferredTimescale: 1))
            return UIImage(cgImage: result.image)
        } catch {
            return nil
        }
    }
}

// MARK: - Bubble audio & video + bar kutipan

struct AudioBubble: View {
    let url: URL
    let detik: Int
    let isMine: Bool
    @StateObject private var player = VoicePlayer()

    var body: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
            HStack(spacing: 8) {
                Button {
                    player.toggle(url: url)
                } label: {
                    if player.isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: player.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                            .font(.system(size: 30))
                    }
                }
                .foregroundStyle(isMine ? .white : Brand.indigo)
                Text(formatDurasi(detik))
                    .font(.subheadline)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(isMine ? Brand.indigo : Color(uiColor: .systemGray5))
            .foregroundStyle(isMine ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if let err = player.errorMessage {
                Text(err).font(.caption2).foregroundStyle(.red)
            }
        }
        .onDisappear { player.stop() }
    }
}

struct VideoBubble: View {
    let url: URL
    var onPlay: () -> Void
    @State private var thumb: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Group {
                if let thumb {
                    Image(uiImage: thumb).resizable().scaledToFill()
                } else if failed {
                    Color(uiColor: .systemGray5).overlay {
                        Button("Muat ulang") { Task { await reload() } }
                            .font(.caption)
                    }
                } else {
                    Color(uiColor: .systemGray5).overlay { ProgressView() }
                }
            }
            .frame(width: 220, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if thumb != nil {
                Button(action: onPlay) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                }
            }
        }
        .task { await reload() }
    }

    func reload() async {
        guard thumb == nil else { return }
        failed = false
        thumb = await ChatVideo.thumbnail(url)
        failed = thumb == nil
    }
}

struct QuoteBox: View {
    let quote: QuotedMessage
    var isMine: Bool

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isMine ? .white.opacity(0.7) : Brand.indigo)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(quote.sender)
                    .font(.caption).bold()
                Text(quote.snippet)
                    .font(.caption)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
