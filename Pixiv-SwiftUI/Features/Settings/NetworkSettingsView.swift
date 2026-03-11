import SwiftUI

struct NetworkSettingsView: View {
    @Environment(AccountStore.self) private var accountStore
    @State private var userSettingStore = UserSettingStore.shared
    @State private var networkModeStore = NetworkModeStore.shared
    @State private var showAuthView = false

    var body: some View {
        Form {
            networkSection
            downloadSection
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "网络"))
        .sheet(isPresented: $showAuthView) {
            AuthView(accountStore: accountStore, onGuestMode: nil)
        }
    }

    private var networkSection: some View {
        Section {
            LabeledContent(String(localized: "网络模式")) {
                Picker("", selection: $networkModeStore.currentMode) {
                    ForEach(NetworkMode.allCases) { mode in
                        Text(mode.displayName)
                            .tag(mode)
                    }
                }
                #if os(macOS)
                .pickerStyle(.menu)
                #endif
            }
        } header: {
            Text(String(localized: "网络"))
        } footer: {
            Text(networkModeStore.currentMode.description)
        }
    }

    private var downloadSection: some View {
        Section {
            LabeledContent(String(localized: "下载线程数")) {
                Picker("", selection: $userSettingStore.userSetting.downloadConcurrency) {
                    ForEach([1, 2, 4, 8, 12, 16], id: \.self) { count in
                        Text("\(count)")
                            .tag(count)
                    }
                }
                #if os(macOS)
                .pickerStyle(.menu)
                #endif
            }
        } header: {
            Text(String(localized: "下载"))
        } footer: {
            Text(String(localized: "动图等多线程加载时的并发分片数。"))
        }
    }
}

#Preview {
    NavigationStack {
        NetworkSettingsView()
    }
}
