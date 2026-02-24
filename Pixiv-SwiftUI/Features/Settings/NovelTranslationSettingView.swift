import SwiftUI

struct NovelTranslationSettingView: View {
    @Environment(UserSettingStore.self) var userSettingStore

    @State private var batchEnabled: Bool = true
    @State private var maxParagraphs: Int = 8
    @State private var maxCharacters: Int = 4000
    @State private var contextParagraphs: Int = 2
    @State private var maxConcurrentBatches: Int = 2

    var body: some View {
        Form {
            strategySection
            batchSection
            contextSection
            concurrencySection
        }
        .formStyle(.grouped)
        .navigationTitle("小说翻译")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            loadSettings()
        }
        .onDisappear {
            saveSettings()
        }
    }

    private var strategySection: some View {
        Section {
            LabeledContent("启用 OpenAI 批量翻译") {
                Toggle("", isOn: $batchEnabled)
                    #if os(macOS)
                    .toggleStyle(.switch)
                    #endif
            }
        } header: {
            Text("策略")
        } footer: {
            Text("仅在主翻译服务为 OpenAI 兼容 API 时生效。")
        }
    }

    private var batchSection: some View {
        Section {
            Stepper(value: $maxParagraphs, in: 1...20) {
                HStack {
                    Text("单批最大段落")
                    Spacer()
                    Text("\(maxParagraphs)")
                        .foregroundColor(.secondary)
                }
            }

            Stepper(value: $maxCharacters, in: 500...16000, step: 250) {
                HStack {
                    Text("单批最大字符")
                    Spacer()
                    Text("\(maxCharacters)")
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("批处理")
        } footer: {
            Text("达到段落数或字符数上限时会切分为新的请求批次。")
        }
        .disabled(!batchEnabled)
    }

    private var contextSection: some View {
        Section {
            Stepper(value: $contextParagraphs, in: 0...10) {
                HStack {
                    Text("前文上下文段落")
                    Spacer()
                    Text("\(contextParagraphs)")
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("上下文")
        } footer: {
            Text("每个批次附带前 N 段原文，帮助模型保持人名和语气一致。")
        }
        .disabled(!batchEnabled)
    }

    private var concurrencySection: some View {
        Section {
            Stepper(value: $maxConcurrentBatches, in: 1...4) {
                HStack {
                    Text("并发批次")
                    Spacer()
                    Text("\(maxConcurrentBatches)")
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("并发")
        } footer: {
            Text("并发越高速度越快，但更容易触发服务限流。")
        }
        .disabled(!batchEnabled)
    }

    private func loadSettings() {
        let setting = userSettingStore.userSetting
        batchEnabled = setting.translateNovelBatchEnabled
        maxParagraphs = setting.translateNovelBatchMaxParagraphs
        maxCharacters = setting.translateNovelBatchMaxCharacters
        contextParagraphs = setting.translateNovelContextParagraphs
        maxConcurrentBatches = setting.translateNovelMaxConcurrentBatches
    }

    private func saveSettings() {
        try? userSettingStore.setTranslateNovelBatchEnabled(batchEnabled)
        try? userSettingStore.setTranslateNovelBatchMaxParagraphs(maxParagraphs)
        try? userSettingStore.setTranslateNovelBatchMaxCharacters(maxCharacters)
        try? userSettingStore.setTranslateNovelContextParagraphs(contextParagraphs)
        try? userSettingStore.setTranslateNovelMaxConcurrentBatches(maxConcurrentBatches)
    }
}

#Preview {
    NavigationStack {
        NovelTranslationSettingView()
    }
}
