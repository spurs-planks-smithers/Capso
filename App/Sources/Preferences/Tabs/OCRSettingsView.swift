// App/Sources/Preferences/Tabs/OCRSettingsView.swift
import SwiftUI
import Vision
import SharedKit
import TranslationKit

struct TextAndTranslationSettingsView: View {
    @Bindable var viewModel: PreferencesViewModel
    @State private var supportedLanguages: [(code: String, name: String)] = []
    @State private var translationLanguages: [(code: String, name: String)] = LanguagePreference.sortedLanguages()
    @State private var providerAPIKey: String = ""
    @State private var providerStatusMessage: String?
    @State private var isTestingProvider = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(Capabilities.current.translationTools ? "Text & Translation" : "Text Recognition")
                .font(.system(size: 20, weight: .bold))

            SettingGroup(visibility: .ocrTextRecognition, title: "Text Recognition") {
                SettingCard {
                    SettingRow(visibility: .ocrTextRecognitionKeepLineBreaks, label: "Keep Line Breaks", sublabel: "Preserve original line structure") {
                        Toggle("", isOn: $viewModel.ocrKeepLineBreaks)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    SettingRow(visibility: .ocrTextRecognitionDetectLinks, label: "Detect Links", sublabel: "Auto-detect and linkify URLs", showDivider: true) {
                        Toggle("", isOn: $viewModel.ocrDetectLinks)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
            }

            if Capabilities.current.translationTools {
                SettingGroup(visibility: .ocrTranslation, title: "Translation") {
                    SettingCard {
                        SettingRow(visibility: .ocrTranslationTargetLanguage, label: "Target Language", sublabel: "Language to translate text into") {
                            Picker("", selection: $viewModel.translationTargetLanguage) {
                                ForEach(translationLanguages, id: \.code) { lang in
                                    Text(lang.name).tag(lang.code)
                                }
                            }
                            .frame(width: 180)
                        }
                        SettingRow(visibility: .ocrTranslationProvider,
                            label: "Provider",
                            sublabel: LocalizedStringKey(viewModel.translationProvider.connectionSummary),
                            showDivider: true
                        ) {
                            Picker("", selection: $viewModel.translationProvider) {
                                ForEach([TranslationProviderKind.apple], id: \.rawValue) { provider in // Fork: on-device only
                                    Text(provider.displayName).tag(provider)
                                }
                            }
                            .frame(width: 180)
                            .onChange(of: viewModel.translationProvider) { _, _ in
                                if Capabilities.current.translationTools { loadProviderAPIKey() }
                            }
                        }
                        if viewModel.translationProvider.requiresAPIKey {
                            SettingRow(visibility: .ocrTranslationApiKey, label: "API Key", sublabel: "Stored in Keychain", showDivider: true) {
                                HStack(spacing: 8) {
                                    SecureField("API Key", text: $providerAPIKey)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 180)
                                        .onSubmit(saveProviderAPIKey)
                                        .settingsVisibility(.ocrTranslationApiKeyInput)
                                    Button(action: saveProviderAPIKey) {
                                        Image(systemName: "checkmark")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Save API key")
                                    .settingsVisibility(.ocrTranslationApiKeySave)
                                }
                            }
                            if viewModel.translationProvider.supportsEndpoint {
                                SettingRow(visibility: .ocrTranslationEndpoint, label: "Endpoint", sublabel: "Leave empty to use the provider default", showDivider: true) {
                                    TextField("", text: $viewModel.translationProviderEndpoint)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 260)
                                }
                            }
                            if viewModel.translationProvider.supportsModel {
                                SettingRow(visibility: .ocrTranslationModel, label: "Model", sublabel: "Leave empty to use the provider default", showDivider: true) {
                                    TextField("", text: $viewModel.translationProviderModel)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 180)
                                }
                            }
                            SettingRow(visibility: .ocrTranslationConnection, label: "Connection", sublabel: "Verify the current provider settings", showDivider: true) {
                                HStack(spacing: 8) {
                                    if isTestingProvider {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                    Button(action: testProviderConnection) {
                                        Label("Test Connection", systemImage: "network")
                                    }
                                    .controlSize(.small)
                                    .disabled(isTestingProvider)
                                }
                            }
                        }
                        if let providerStatusMessage {
                            SettingRow(visibility: .ocrTranslationProviderStatus, label: LocalizedStringKey(providerStatusMessage), showDivider: true) {
                                EmptyView()
                            }
                        }
                        SettingRow(visibility: .ocrTranslationAutoCopyTranslation, label: "Auto-Copy Translation", sublabel: "Copy result to clipboard automatically") {
                            Toggle("", isOn: $viewModel.translationAutoCopy)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                        SettingRow(visibility: .ocrTranslationShowOriginalText, label: "Show Original Text", sublabel: "Display source text alongside translation") {
                            Toggle("", isOn: $viewModel.translationShowOriginal)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                        SettingRow(visibility: .ocrTranslationAutoDismiss, label: "Auto-Dismiss", sublabel: "When to close the translation panel", showDivider: true) {
                            Picker("", selection: $viewModel.translationAutoDismiss) {
                                Text("Manual").tag(TranslationAutoDismiss.manual)
                                Text("Click outside").tag(TranslationAutoDismiss.clickOutside)
                                Text("After delay").tag(TranslationAutoDismiss.afterDelay)
                            }
                            .frame(width: 140)
                        }
                    }
                }
            }

            // TODO: Re-enable the "Language" group once OCRCoordinator actually
            // threads settings.ocrPrimaryLanguage into TextRecognizer. Today
            // TextRecognizer.swift:86 sets `request.recognitionLanguages` from
            // a local parameter and the setting value is never passed in —
            // selecting a language here would have no effect on recognition.
            // When wiring it back, also uncomment the `.onAppear` below.
            // SettingGroup(title: "Language") {
            //     SettingCard {
            //         SettingRow(label: "Primary Language", sublabel: "Auto-detect if unset") {
            //             Picker("", selection: Binding(
            //                 get: { viewModel.ocrPrimaryLanguage ?? "auto" },
            //                 set: { viewModel.ocrPrimaryLanguage = $0 == "auto" ? nil : $0 }
            //             )) {
            //                 Text("Auto").tag("auto")
            //                 ForEach(supportedLanguages, id: \.code) { lang in
            //                     Text(lang.name).tag(lang.code)
            //                 }
            //             }
            //             .frame(width: 160)
            //         }
            //     }
            // }
        }
        .task {
            let codes = await LanguagePreference.loadSupportedLanguageCodes()
            translationLanguages = LanguagePreference.sortedLanguages(from: codes)
        }
        .onAppear {
            if Capabilities.current.translationTools { loadProviderAPIKey() }
            // loadSupportedLanguages()
        }
    }

    private func loadProviderAPIKey() {
        providerAPIKey = viewModel.translationAPIKey()
        providerStatusMessage = nil
    }

    private func saveProviderAPIKey() {
        do {
            try viewModel.setTranslationAPIKey(providerAPIKey)
            providerStatusMessage = providerAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "API key cleared"
                : "API key saved"
        } catch {
            providerStatusMessage = "API key could not be saved"
        }
    }

    private func testProviderConnection() {
        isTestingProvider = true
        providerStatusMessage = nil
        Task {
            do {
                try viewModel.setTranslationAPIKey(providerAPIKey)
                try await viewModel.testTranslationProviderConnection()
                await MainActor.run {
                    providerStatusMessage = "Connection succeeded"
                    isTestingProvider = false
                }
            } catch {
                await MainActor.run {
                    providerStatusMessage = "Connection failed: \(error.localizedDescription)"
                    isTestingProvider = false
                }
            }
        }
    }

    private func loadSupportedLanguages() {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let codes = (try? request.supportedRecognitionLanguages()) ?? []
        let locale = Locale.current
        supportedLanguages = codes.compactMap { code in
            let name = locale.localizedString(forLanguageCode: code) ?? code
            return (code: code, name: name)
        }
    }
}
