import Foundation
import Combine

// MARK: - Auth Manager (Firebase)

final class AuthManager: ObservableObject {
    static let shared = AuthManager()
    private init() {}

    @Published var isLoggedIn = false
    @Published var idToken: String?

    // TODO: Integrasikan Firebase Auth iOS SDK.
    // 1. Tambah Firebase via SPM.
    // 2. Google Sign-In / Apple Sign-In.
    // 3. Panggil user.getIDToken() → simpan ke idToken.

    func signIn(idToken: String) {
        self.idToken = idToken
        self.isLoggedIn = true
    }

    func signOut() {
        self.idToken = nil
        self.isLoggedIn = false
    }
}
