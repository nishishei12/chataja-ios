import SwiftUI

// MARK: - Chat Room (realtime via Firestore + media via R2)

struct ChatRoomView: View {
    let roomId: String
    let partnerName: String
    let myUserId: String

    @StateObject private var chat = FirestoreChatService.shared
    @State private var inputText = ""
    @State private var showImagePicker = false
    @State private var isUploading = false

    var body: some View {
        VStack(spacing: 0) {
            // Daftar pesan
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(chat.messages) { msg in
                            MessageBubble(msg: msg, isMine: msg.senderId == myUserId)
                                .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: chat.messages.count) { _ in
                    if let last = chat.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            // Typing indicator
            if !chat.typingUsers.isEmpty {
                Text("mengetik…")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            // Input bar
            HStack(spacing: 8) {
                Button { showImagePicker = true } label: {
                    Image(systemName: "photo")
                }
                .disabled(isUploading)

                TextField("Tulis pesan…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: inputText) { _ in
                        Task {
                            try? await chat.setTyping(roomId: roomId, userId: myUserId,
                                                      isTyping: !inputText.isEmpty)
                        }
                    }

                Button { Task { await sendText() } } label: {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isUploading)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationTitle(partnerName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showImagePicker) {
            ImagePicker { image in Task { await sendImage(image) } }
        }
        .onAppear { chat.listenMessages(roomId: roomId) }
        .onDisappear {
            chat.stopListening()
            Task { try? await chat.setTyping(roomId: roomId, userId: myUserId, isTyping: false) }
        }
    }

    func sendText() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        try? await chat.setTyping(roomId: roomId, userId: myUserId, isTyping: false)
        try? await chat.sendMessage(roomId: roomId, senderId: myUserId, text: text)
    }

    func sendImage(_ image: UIImage) async {
        isUploading = true
        defer { isUploading = false }
        do {
            let url = try await R2UploadService.shared.uploadImage(image, userId: myUserId)
            try? await chat.sendMessage(roomId: roomId, senderId: myUserId,
                                        text: "[foto] \(url)")
        } catch {
            print("upload gagal:", error.localizedDescription)
        }
    }
}

// MARK: - Bubble

struct MessageBubble: View {
    let msg: ChatMessage
    let isMine: Bool

    var body: some View {
        HStack {
            if isMine { Spacer() }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                if msg.text.hasPrefix("[foto] ") {
                    let url = String(msg.text.dropFirst(7))
                    AsyncImage(url: URL(string: url)) { $0.resizable().scaledToFill() }
                        placeholder: { Color.gray.opacity(0.2) }
                        .frame(maxWidth: 220, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Text(msg.text)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(isMine ? Color.accentColor : Color(.systemGray5))
                        .foregroundStyle(isMine ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                Text(msg.createdAt, style: .time)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if !isMine { Spacer() }
        }
    }
}

// MARK: - Image Picker

struct ImagePicker: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onPick(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
