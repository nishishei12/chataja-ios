import Foundation
import Combine

// MARK: - Auth Manager (Firebase Auth)
//
// SETUP YANG HARUS DILAKUKAN DI XCODE:
// 1. File → Add Package Dependencies → https://github.com/firebase/firebase-ios-sdk
//    Pilih: FirebaseAuth, FirebaseFirestore
// 2. Download GoogleService-Info.plist dari Firebase Console (chataja-apps)
//    → drag ke project (centang target ChatAja)
// 3. Untuk Google Sign-In: tambah juga GoogleSignIn via SPM
//    https://github.com/google/GoogleSignIn-iOS

#if canImport(FirebaseAuth)
import FirebaseAuth
import AuthenticationServices
import CryptoKit
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

final class AuthManager: ObservableObject {
    static let shared = AuthManager()
    private init() {
        // Cek sesi existing
        if let user = Auth.auth().currentUser {
            self.uid = user.uid
            self.isLoggedIn = true
            Task { await self.refreshToken() }
        }
        // Listener perubahan auth state
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            if let user = user {
                self?.uid = user.uid
                self?.isLoggedIn = true
                Task { await self?.refreshToken() }
            } else {
                self?.uid = nil
                self?.idToken = nil
                self?.isLoggedIn = false
            }
        }
    }

    @Published var isLoggedIn = false
    @Published var idToken: String?
    @Published var uid: String?
    @Published var authError: String?

    /// Ambil token fresh (auto-refresh kalau mau expired).
    func refreshToken() async {
        do {
            let token = try await Auth.auth().currentUser?.getIDToken()
            await MainActor.run { self.idToken = token }
        } catch {
            await MainActor.run { self.authError = "Gagal ambil token: \(error.localizedDescription)" }
        }
    }

    /// Login dengan Apple via Firebase OAuth
    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async {
        await MainActor.run { self.authError = nil }
        let credential = OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: rawNonce, fullName: fullName)
        do {
            let result = try await Auth.auth().signIn(with: credential)
            await MainActor.run {
                self.uid = result.user.uid
                self.isLoggedIn = true
            }
            await refreshToken()
        } catch {
            await MainActor.run { self.authError = terjemahkan(error) }
        }
    }

    /// Login dengan Google via Firebase OAuth Provider
    func signInWithGoogleOAuth() async {
        await MainActor.run { self.authError = nil }
        let provider = OAuthProvider(providerID: "google.com")
        do {
            let credential = try await provider.credential(with: nil)
            let result = try await Auth.auth().signIn(with: credential)
            await MainActor.run {
                self.uid = result.user.uid
                self.isLoggedIn = true
            }
            await refreshToken()
        } catch {
            await MainActor.run { self.authError = terjemahkan(error) }
        }
    }

    #if canImport(GoogleSignIn)
    func signInWithGoogle(presenting: UIViewController) async {
        await MainActor.run { self.authError = nil }
        do {
            let GIDSignIn = try await googleSignIn(presenting: presenting)
            guard let idToken = GIDSignIn.user.idToken?.tokenString else {
                throw NSError(domain: "auth", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Token Google kosong"])
            }
            let cred = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: GIDSignIn.user.accessToken.tokenString)
            let result = try await Auth.auth().signIn(with: cred)
            await MainActor.run {
                self.uid = result.user.uid
                self.isLoggedIn = true
            }
            await refreshToken()
        } catch {
            await MainActor.run { self.authError = terjemahkan(error) }
        }
    }
    #endif

    func signOut() {
        try? Auth.auth().signOut()
        self.idToken = nil
        self.uid = nil
        self.isLoggedIn = false
    }

    /// Mode dev: tempel Firebase ID token manual.
    func signInDev(token: String, uid: String) {
        self.idToken = token
        self.uid = uid
        self.isLoggedIn = true
    }

    // MARK: - Private

    #if canImport(GoogleSignIn)
    private func googleSignIn(presenting: UIViewController) async throws -> GIDSignInResult {
        try await withCheckedThrowingContinuation { cont in
            GIDSignIn.sharedInstance.signIn(withPresenting: presenting) { result, error in
                if let error = error { cont.resume(throwing: error); return }
                guard let result = result else {
                    cont.resume(throwing: NSError(domain: "auth", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Batal"]))
                    return
                }
                cont.resume(returning: result)
            }
        }
    }
    #endif

    private func terjemahkan(_ error: Error) -> String {
        let ns = error as NSError
        switch ns.code {
        case AuthErrorCode.wrongPassword.rawValue: return "Password salah."
        case AuthErrorCode.userNotFound.rawValue: return "Email tidak terdaftar."
        case AuthErrorCode.emailAlreadyInUse.rawValue: return "Email sudah dipakai."
        case AuthErrorCode.weakPassword.rawValue: return "Password terlalu lemah (min 6 karakter)."
        case AuthErrorCode.invalidEmail.rawValue: return "Format email tidak valid."
        case AuthErrorCode.networkError.rawValue: return "Tidak ada koneksi internet."
        default: return error.localizedDescription
        }
    }
}
#else
// Fallback: Firebase belum dipasang — mode dev dengan token manual
final class AuthManager: ObservableObject {
    static let shared = AuthManager()
    private init() {}
    @Published var isLoggedIn = false
    @Published var idToken: String?
    @Published var uid: String?
    @Published var authError: String?

    /// Mode dev: tempel Firebase ID token manual (dari Android / Firebase Console).
    func signInDev(token: String, uid: String) {
        self.idToken = token
        self.uid = uid
        self.isLoggedIn = true
    }
    func signOut() {
        self.idToken = nil; self.uid = nil; self.isLoggedIn = false
    }
}
#endif
