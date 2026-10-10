import SwiftUI
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct ChatAjaApp: App {
    @StateObject private var auth = AuthManager.shared

    init() {
        #if canImport(FirebaseCore)
        FirebaseApp.configure()
        #endif
        #if canImport(GoogleSignIn)
        // ClientID diambil dari GoogleService-Info.plist via FirebaseOptions,
        // jadi tidak ada client ID yang di-hardcode di sini.
        if let clientID = FirebaseOptions.defaultOptions()?.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isLoggedIn {
                    MainTabView()
                        .environmentObject(auth)
                } else {
                    LoginView()
                        .environmentObject(auth)
                }
            }
            // Wajib untuk kembalian login Google dari browser/SFSafariView.
            // URL Firebase Auth (mis. verifikasi email) juga diteruskan.
            .onOpenURL { url in
                #if canImport(GoogleSignIn)
                _ = GIDSignIn.sharedInstance.handle(url)
                #endif
                #if canImport(FirebaseAuth)
                _ = Auth.auth().canHandle(url)
                #endif
            }
        }
    }
}
