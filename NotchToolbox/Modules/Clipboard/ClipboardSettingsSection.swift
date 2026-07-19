import SwiftUI

struct ClipboardSettingsSection: View {
    @ObservedObject var viewModel: ClipboardSettingsViewModel

    var body: some View {
        GroupBox("剪贴板设置") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("最大保存数")
                        .font(.headline)

                    Picker("最大保存数", selection: Binding(
                        get: { viewModel.maxItems },
                        set: { viewModel.selectMaxItems($0) }
                    )) {
                        ForEach(viewModel.supportedMaxItems, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("自动清理")
                        .font(.headline)

                    Picker("自动清理", selection: Binding(
                        get: { viewModel.cleanupPolicy },
                        set: { viewModel.selectCleanupPolicy($0) }
                    )) {
                        Text("不自动").tag(CleanupPolicy.none)
                        Text("每日").tag(CleanupPolicy.daily)
                        Text("每周").tag(CleanupPolicy.weekly)
                        Text("每月").tag(CleanupPolicy.monthly)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                if let lastSaveError = viewModel.lastSaveError {
                    Text(lastSaveError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
