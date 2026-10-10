import SwiftUI

@main
struct ChatAjaApp: App {
    @StateObject private var auth = AuthManager.shared

    var body: some Scene {
        WindowGroup {
            if auth.isLoggedIn {
                MainTabView()
            } else {
                LoginView()
                    .environmentObject(auth)
            }
        }
    }
}
