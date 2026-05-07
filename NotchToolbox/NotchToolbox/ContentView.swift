//
//  ContentView.swift
//  NotchToolbox
//
//  Created by 洛杰 on 2026/5/6.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var compositionRoot: AppCompositionRoot

    var body: some View {
        ContentHostView(compositionRoot: compositionRoot)
    }
}

#Preview {
    ContentView(compositionRoot: AppCompositionRoot())
}
