import SwiftUI

struct MusicModuleView: View {
    @ObservedObject var runtime: MusicModuleRuntime

    var body: some View {
        MusicModuleContentView(viewModel: MusicModuleViewModel(runtime: runtime))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
