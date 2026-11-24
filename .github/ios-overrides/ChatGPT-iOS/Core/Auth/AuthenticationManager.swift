import Foundation
import Combine
import GoogleSignIn
import UIKit

/// Google identity for this app. A Google identity is NOT an OpenAI/ChatGPT session.
@MainActor
public final class AuthenticationManager: ObservableObject {
    @Published private(set) var isSignedIn = false
    @Published private(set) var userEmail: String?
    @Published private(set) var userName: String?
    @Published var errorMessage: String?
    @Published private(set) var isLoading = false

    private var isConfigured: Bool {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else { return false }
        return !clientID.isEmpty &&
            !clientID.contains("REPLACE_WITH") &&
            clientID.hasSuffix(".apps.googleusercontent.com")
    }

    public init() {
        restoreGoogleSession()
    }

    func signInWithGoogle(presenting viewController: UIViewController) {
        guard isConfigured,
              let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else {
            errorMessage = "Google Sign-In is not configured. Add your iOS OAuth client ID and matching reversed URL scheme to Info.plist."
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        isLoading = true
        errorMessage = nil

        GIDSignIn.sharedInstance.signIn(withPresenting: viewController) { [weak self] result, error in
            guard let self else { return }
            self.isLoading = false

            if let error {
                self.errorMessage = error.localizedDescription
                return
            }
            guard let user = result?.user else {
                self.errorMessage = "Google did not return an authenticated account. Please try again."
                return
            }

            self.userEmail = user.profile?.email
            self.userName = user.profile?.name
            self.isSignedIn = true
        }
    }

    func restoreGoogleSession() {
        guard isConfigured,
              let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else { return }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, _ in
            guard let self, let user else { return }
            self.userEmail = user.profile?.email
            self.userName = user.profile?.name
            self.isSignedIn = true
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        isSignedIn = false
        userEmail = nil
        userName = nil
    }
}

extension UIApplication {
    var activeKeyWindowRootViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .windows
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}
