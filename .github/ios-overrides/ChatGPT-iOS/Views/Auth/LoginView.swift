import SwiftUI
import SafariServices

struct LoginView: View {
    @ObservedObject var authentication: AuthenticationManager
    @State private var showingChatGPTBrowser = false
    @State private var chatGPTAuthURL: URL?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 54))
                .foregroundStyle(.primary)
            Text("Welcome")
                .font(.largeTitle.bold())
            Text("Sign in to continue to GPT Plus.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                guard let presenter = UIApplication.shared.activeKeyWindowRootViewController else {
                    authentication.errorMessage = "Unable to open the secure Google sign-in window. Please try again."
                    return
                }
                authentication.signInWithGoogle(presenting: presenter)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "g.circle.fill").font(.title2)
                    Text("Continue with Google").fontWeight(.semibold)
                    Spacer()
                    if authentication.isLoading { ProgressView() }
                }
                .foregroundStyle(.primary)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(authentication.isLoading)

            Button {
                Task {
                    do {
                        chatGPTAuthURL = try await authentication.startChatGPTSignIn()
                        showingChatGPTBrowser = true
                    } catch {
                        authentication.errorMessage = error.localizedDescription
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkle")
                    Text("Continue with ChatGPT").fontWeight(.semibold)
                    Spacer()
                    if authentication.chatGPT.isSigningIn { ProgressView() }
                }
                .foregroundStyle(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(authentication.chatGPT.isSigningIn)

            Text("Connect your ChatGPT account through OpenAI's official sign-in and consent screen. ChatGPT plan usage is enabled only if OpenAI grants that permission.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            if let message = authentication.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(24)
        .sheet(isPresented: $showingChatGPTBrowser, onDismiss: {
            chatGPTAuthURL = nil
        }) {
            if let url = chatGPTAuthURL {
                OfficialChatGPTBrowser(url: url)
                    .ignoresSafeArea()
            }
        }
        .onChange(of: authentication.chatGPTBrowserCompleted) { _, completed in
            if completed {
                showingChatGPTBrowser = false
                authentication.chatGPTBrowserCompleted = false
            }
        }
    }
}

private struct OfficialChatGPTBrowser: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
