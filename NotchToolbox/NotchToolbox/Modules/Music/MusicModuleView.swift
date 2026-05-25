import SwiftUI

struct MusicModuleView: View {
    @ObservedObject var runtime: MusicModuleRuntime

    var body: some View {
        MusicModuleContentView(viewModel: MusicModuleViewModel(runtime: runtime))
            .frame(maxWidth: .infinity, alignment: .leading)
            .task {
                runtime.handleLifecycle(.moduleDidAppear)
                await runtime.refreshSnapshot()

                while Task.isCancelled == false {
                    do {
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                    } catch {
                        break
                    }

                    await runtime.refreshSnapshot()
                }
            }
            .onDisappear {
                runtime.handleLifecycle(.moduleWillDisappear)
            }
    }
}
