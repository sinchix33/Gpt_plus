import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var authentication: AuthenticationManager
    @State private var showPaywall = false
    @Environment(\.dismiss) private var dismiss

    public init(authentication: AuthenticationManager) {
        self.authentication = authentication
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    if let email = authentication.userEmail {
                        LabeledContent("Signed in as", value: email)
                    }
                    Button("Sign Out", role: .destructive) {
                        authentication.signOut()
                        dismiss()
                    }
                } header: {
                    Text("Account")
                }

                Section {
                    Button {
                        showPaywall = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ChatGPT Plus")
                                    .font(.headline)
                                    .foregroundStyle(.purple)
                                Text("Upgrade to access o1 and faster responses")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Subscription")
                }

                Section {
                    Picker("Voice", selection: $settings.selectedVoice) {
                        ForEach(VoicePreset.allCases) { voice in
                            Text(voice.displayName).tag(voice.rawValue)
                        }
                    }
                    Toggle("Haptic Feedback", isOn: $settings.isHapticsEnabled)
                } header: {
                    Text("Speech & Audio")
                }

                Section {
                    Toggle("Chat History & Training", isOn: $settings.isHistoryAndTrainingEnabled)
                    Button("Export Data") {}
                    Button(role: .destructive) {
                    } label: {
                        Text("Delete All Chats")
                    }
                } header: {
                    Text("Data Controls")
                } footer: {
                    Text("Save new chats on this device to your history and allow them to be used to improve our models. Unsaved chats will be deleted within 30 days.")
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.2026.300").foregroundStyle(.secondary)
                    }
                    Link("Terms of Use", destination: URL(string: "https://openai.com/policies/terms-of-use")!)
                    Link("Privacy Policy", destination: URL(string: "https://openai.com/policies/privacy-policy")!)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showPaywall) {
                SubscriptionPaywallView()
            }
        }
    }
}
