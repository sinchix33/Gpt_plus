import Foundation
import Combine
import GoogleSignIn
import UIKit

/// Google and ChatGPT are separate identity providers. Neither provider's token is
/// placed in the other provider's credential slot.
@MainActor
public final class AuthenticationManager: ObservableObject {
    /// Shared authentication state used by the app root and sidebar.
    public static let shared = AuthenticationManager()
    @Published private(set) var isSignedIn = false

    /// Compatibility with sidebar views that bind to the authenticated state.
    var isAuthenticated: Bool {
        get { isSignedIn }
        set { isSignedIn = newValue }
    }
    @Published private(set) var userEmail: String?
    @Published private(set) var userName: String?
    @Published var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published var chatGPTBrowserCompleted = false

    let chatGPT = ChatGPTSignInManager()

    private var isGoogleConfigured: Bool {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else { return false }
        return !clientID.isEmpty &&
            !clientID.contains("REPLACE_WITH") &&
            clientID.hasSuffix(".apps.googleusercontent.com")
    }

    public init() {
        if chatGPT.hasIdentity {
            isSignedIn = true
            userEmail = chatGPT.email
            userName = chatGPT.displayName
        }
        chatGPT.onAuthenticated = { [weak self] email in
            self?.isSignedIn = true
            self?.userEmail = email
            self?.userName = self?.chatGPT.displayName
            self?.errorMessage = nil
        }
        chatGPT.onBrowserCompleted = { [weak self] in
            self?.chatGPTBrowserCompleted = true
        }
        NotificationCenter.default.addObserver(
            forName: .chatGPTSignInFailed,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.errorMessage = notification.object as? String ?? "ChatGPT sign-in failed."
            }
        }
        restoreGoogleSession()
    }

    func signInWithGoogle(presenting viewController: UIViewController) {
        guard isGoogleConfigured,
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

    func startChatGPTSignIn() async throws -> URL {
        errorMessage = nil
        return try await chatGPT.prepareAuthorization()
    }

    func cancelChatGPTSignIn() {
        chatGPT.cancelSignIn()
    }

    func restoreGoogleSession() {
        guard isGoogleConfigured,
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
        chatGPT.signOut()
        isSignedIn = false
        userEmail = nil
        userName = nil
        errorMessage = nil
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
