import AuthenticationServices
import CryptoKit
import SwiftUI

// MARK: - Login (PRD 3.1)

struct LoginView: View {
  @EnvironmentObject var auth: AuthManager

  @State private var isLoading = false
  @State private var loadingMethod: String?
  @State private var showDevLogin = false
  @State private var devToken = ""
  @State private var appleCoordinator: AppleAuthCoordinator?
  /// Generasi login: hasil dari percobaan lama diabaikan (anti race).
  @State private var loginGeneration = 0

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 0) {
          Spacer().frame(height: 64)

          // Logo: lingkaran aksen + ikon bubble, tanpa gradient mencolok.
          ZStack {
            Circle()
              .fill(Brand.indigo)
              .frame(width: 72, height: 72)
            Image(systemName: "text.bubble.fill")
              .font(.system(size: 32))
              .foregroundStyle(.white)
          }
          .padding(.bottom, 16)
          .accessibilityLabel("Logo ChatAja")

          Text("ChatAja")
            .font(.title2).bold()
            .padding(.bottom, 4)

          Text("Ngobrol anonim, tanpa nama.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.bottom, 32)

          VStack(spacing: 12) {
            // Apple (style iOS native)
            if isLoading && loadingMethod == "apple" {
              Button {
              } label: {
                ProgressView()
                  .frame(maxWidth: .infinity)
                  .frame(height: 52)
              }
              .disabled(true)
            } else {
              SignInWithAppleButton(.signIn) { _ in
                handleAppleSignIn()
              } onCompletion: { _ in
              }
              .signInWithAppleButtonStyle(.black)
              .frame(maxWidth: .infinity)
              .frame(height: 52)
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
              .disabled(isLoading)
              .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                  .stroke(Color(uiColor: .separator), lineWidth: 1)
              )
            }
            // Google (gaya iOS native: tombol outline)
            Button(action: handleGoogleSignIn) {
              HStack(spacing: 12) {
                if isLoading && loadingMethod == "google" {
                  ProgressView().tint(.primary)
                } else {
                  GoogleGLogoView().frame(width: 20, height: 20)
                  Text("Masuk dengan Google")
                    .font(.system(size: 16, weight: .semibold))
                }
              }
              .frame(maxWidth: .infinity)
              .frame(height: 52)
              .background(Color(uiColor: .systemBackground))
              .foregroundStyle(Color.primary)
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
              .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                  .stroke(Color(uiColor: .separator), lineWidth: 1)
              )
            }
            .disabled(isLoading)

          }
          .padding(.horizontal, 24)

          if let err = auth.authError {
            Text(err)
              .font(.caption)
              .foregroundStyle(.red)
              .multilineTextAlignment(.center)
              .padding(.horizontal, 24)
              .padding(.top, 16)
          }

          Spacer().frame(height: 32)

          #if DEBUG
            DisclosureGroup("Mode Pengembang", isExpanded: $showDevLogin) {
              VStack(spacing: 8) {
                Text("Tempel Firebase ID token manual untuk pengujian tanpa login:")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .frame(maxWidth: .infinity, alignment: .leading)
                SecureField("Firebase ID Token", text: $devToken)
                  .textFieldStyle(.roundedBorder)
                  .font(.caption)
                Button("Masuk dengan Token") {
                  auth.signInDev(token: devToken, uid: "dev-user")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(devToken.isEmpty)
              }
              .padding(.top, 8)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
          #endif

          Spacer().frame(height: 32)
        }
      }
      .toolbar(.hidden, for: .navigationBar)
    }
  }

  // MARK: - Actions

  private func handleGoogleSignIn() {
    loginGeneration += 1
    let gen = loginGeneration
    isLoading = true
    loadingMethod = "google"
    Task {
      defer {
        if gen == loginGeneration {
          isLoading = false
          loadingMethod = nil
        }
      }
      // Batas 30 detik: alur Google yang sehat selesai dalam hitungan
      // detik; kalau menggantung (SDK belum dipasang / URL scheme belum
      // didaftar), user dapat pesan jelas, bukan spinner abadi.
      let selesai =
        await withThrowingTaskGroup(of: Bool.self) { group in
          group.addTask {
            #if canImport(GoogleSignIn)
              if let rootVC = activeRootViewController() {
                await auth.signInWithGoogle(presenting: rootVC)
                return true
              }
            #endif
            await auth.signInWithGoogleOAuth()
            return true
          }
          group.addTask {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            return false
          }
          let hasil = (try? await group.next()) ?? false
          group.cancelAll()
          return hasil
        } ?? false
      guard gen == loginGeneration else { return }
      if !selesai && !auth.isLoggedIn && auth.authError == nil {
        auth.authError =
          "Login Google tidak merespons. Pastikan paket GoogleSignIn sudah ditambah dan URL scheme sudah didaftarkan, lalu coba lagi."
      }
    }
  }

  /// Root VC dari scene yang sedang aktif (bukan scene pertama sembarang).
  private func activeRootViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    return active?.windows.first { $0.isKeyWindow }?.rootViewController
      ?? active?.windows.first?.rootViewController
  }

  private func handleAppleSignIn() {
    loginGeneration += 1
    let gen = loginGeneration
    let coordinator = AppleAuthCoordinator()
    self.appleCoordinator = coordinator

    isLoading = true
    loadingMethod = "apple"

    // Watchdog: kalau sheet Apple tidak kembali dalam 60 detik, bebaskan UI.
    Task {
      try? await Task.sleep(nanoseconds: 60_000_000_000)
      if gen == loginGeneration, loadingMethod == "apple", !auth.isLoggedIn {
        isLoading = false
        loadingMethod = nil
        auth.authError = "Login Apple tidak merespons. Coba lagi."
      }
    }

    coordinator.onCompletion = { idToken, nonce, fullName in
      Task {
        await auth.signInWithApple(idToken: idToken, rawNonce: nonce, fullName: fullName)
        guard gen == loginGeneration else { return }
        isLoading = false
        loadingMethod = nil
      }
    }

    coordinator.onError = { error in
      guard gen == loginGeneration else { return }
      isLoading = false
      loadingMethod = nil
      // Batal oleh user = sunyi, bukan error.
      if (error as? ASAuthorizationError)?.code == .canceled { return }
      auth.authError = "Login Apple gagal. Coba lagi."
    }

    coordinator.startSignInWithAppleFlow()
  }
}

// MARK: - Google 4-Color "G" Logo

struct GoogleGLogoView: View {
  var body: some View {
    ZStack {
      Circle()
        .trim(from: 0.0, to: 0.3)
        .stroke(Color(red: 66 / 255, green: 133 / 255, blue: 244 / 255), lineWidth: 3.2)

      Circle()
        .trim(from: 0.3, to: 0.55)
        .stroke(Color(red: 52 / 255, green: 168 / 255, blue: 83 / 255), lineWidth: 3.2)

      Circle()
        .trim(from: 0.55, to: 0.75)
        .stroke(Color(red: 251 / 255, green: 188 / 255, blue: 5 / 255), lineWidth: 3.2)

      Circle()
        .trim(from: 0.75, to: 1.0)
        .stroke(Color(red: 234 / 255, green: 67 / 255, blue: 53 / 255), lineWidth: 3.2)

      Rectangle()
        .fill(Color(red: 66 / 255, green: 133 / 255, blue: 244 / 255))
        .frame(width: 7, height: 3.2)
        .offset(x: 3)
    }
    .rotationEffect(.degrees(-45))
  }
}

// MARK: - Apple Sign-In Coordinator

final class AppleAuthCoordinator: NSObject, ASAuthorizationControllerDelegate,
  ASAuthorizationControllerPresentationContextProviding
{
  private var currentNonce: String?
  var onCompletion: ((String, String, PersonNameComponents?) -> Void)?
  var onError: ((Error) -> Void)?

  func startSignInWithAppleFlow() {
    let nonce = randomNonceString()
    currentNonce = nonce
    let appleIDProvider = ASAuthorizationAppleIDProvider()
    let request = appleIDProvider.createRequest()
    request.requestedScopes = [.fullName, .email]
    request.nonce = sha256(nonce)

    let authorizationController = ASAuthorizationController(authorizationRequests: [request])
    authorizationController.delegate = self
    authorizationController.presentationContextProvider = self
    authorizationController.performRequests()
  }

  func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let window = windowScene.windows.first
    {
      return window
    }
    return UIWindow()
  }

  func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithAuthorization authorization: ASAuthorization
  ) {
    if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
      guard let nonce = currentNonce,
        let appleIDToken = appleIDCredential.identityToken,
        let idTokenString = String(data: appleIDToken, encoding: .utf8)
      else {
        onError?(
          NSError(
            domain: "AppleAuth", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Gagal mengambil token Apple."]))
        return
      }
      onCompletion?(idTokenString, nonce, appleIDCredential.fullName)
    }
  }

  func authorizationController(
    controller: ASAuthorizationController, didCompleteWithError error: Error
  ) {
    onError?(error)
  }

  private func randomNonceString(length: Int = 32) -> String {
    precondition(length > 0)
    var randomBytes = [UInt8](repeating: 0, count: length)
    let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
    if errorCode != errSecSuccess {
      fatalError("Unable to generate nonce: \(errorCode)")
    }
    let charset: [Character] = Array(
      "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    let nonce = randomBytes.map { charset[Int($0) % charset.count] }
    return String(nonce)
  }

  private func sha256(_ input: String) -> String {
    let inputData = Data(input.utf8)
    let hashedData = SHA256.hash(data: inputData)
    return hashedData.compactMap { String(format: "%02x", $0) }.joined()
  }
}
