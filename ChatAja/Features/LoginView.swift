import SwiftUI

// MARK: - Login View

struct LoginView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isSignUp = false
    @State private var isLoading = false
    @State private var showDevLogin = false
    @State private var devToken = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Logo
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.indigo)
                        Text("ChatAja")
                            .font(.largeTitle).bold()
                        Text("Ngobrol anonim, tanpa nama.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 60)

                    // Form
                    VStack(spacing: 16) {
                        if isSignUp {
                            TextField("Nama tampilan", text: $displayName)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.words)
                        }
                        TextField("Email", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)

                        if let err = auth.authError {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }

                        Button {
                            Task {
                                isLoading = true
                                defer { isLoading = false }
                                if isSignUp {
                                    await auth.signUp(email: email, password: password,
                                                      displayName: displayName)
                                } else {
                                    await auth.signIn(email: email, password: password)
                                }
                            }
                        } label: {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text(isSignUp ? "Daftar" : "Masuk")
                                    .bold()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.indigo)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .disabled(email.isEmpty || password.isEmpty || isLoading)

                        Button(isSignUp ? "Sudah punya akun? Masuk" : "Belum punya akun? Daftar") {
                            isSignUp.toggle()
                            auth.authError = nil
                        }
                        .font(.subheadline)
                    }
                    .padding(.horizontal, 32)

                    Spacer()

                    // Mode dev (sementara, hapus sebelum rilis)
                    DisclosureGroup("Mode Pengembang", isExpanded: $showDevLogin) {
                        VStack(spacing: 8) {
                            Text("Tempel Firebase ID token manual (mis. dari aplikasi Android yang sudah login).")
                                .font(.caption).foregroundStyle(.secondary)
                            SecureField("Firebase ID Token", text: $devToken)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                            Button("Masuk dengan Token") {
                                // UID dummy — API cuma butuh token valid
                                auth.signInDev(token: devToken, uid: "dev-user")
                            }
                            .font(.subheadline)
                            .disabled(devToken.isEmpty)
                        }
                        .padding(.top, 8)
                    }
                    .font(.caption)
                    .padding(.horizontal, 32)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Dev Auth Extension (fallback)

#if !canImport(FirebaseAuth)
extension AuthManager {
    func signIn(email: String, password: String) async {}
    func signUp(email: String, password: String, displayName: String) async {}
}
#endif
