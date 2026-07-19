//
//  NotchToolboxApp.swift
//  NotchToolbox
//
//  Created by 洛杰 on 2026/5/6.
//

import SwiftUI

@main
struct NotchToolboxApp: App {
    @NSApplicationDelegateAdaptor(NotchAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
