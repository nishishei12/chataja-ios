import SwiftUI
#if canImport(FirebaseCore)
import FirebaseCore
#endif

@main
struct ChatAjaApp: App {
    @StateObject private var auth = AuthManager.shared

    init() {
        #if canImport(FirebaseCore)
        FirebaseApp.configure()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            if auth.isLoggedIn {
                MainTabView()
                    .environmentObject(auth)
            } else {
                LoginView()
                    .environmentObject(auth)
            }
        }
    }
}
