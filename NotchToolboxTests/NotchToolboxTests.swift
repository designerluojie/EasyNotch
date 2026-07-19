//
//  NotchToolboxTests.swift
//  NotchToolboxTests
//
//  Created by 洛杰 on 2026/5/6.
//

import Testing
@testable import NotchToolbox

struct NotchToolboxTests {

    @Test func moduleIDsMatchProductOrder() {
        #expect(NotchModuleID.allCases == [
            .music,
            .fileStash,
            .aiChat,
            .clipboard,
            .pomodoro,
            .settings
        ])
    }

    @Test func defaultModuleDescriptorsDefineHostContainers() throws {
        let descriptors = NotchModuleDescriptor.defaultDescriptors

        #expect(descriptors.map(\.id) == NotchModuleID.allCases)
        #expect(try #require(descriptors.first { $0.id == .music }).containerKind == .standardNotchPage)
        #expect(try #require(descriptors.first { $0.id == .music }).defaultRestVariant == .wideNotchStrip)
        #expect(try #require(descriptors.first { $0.id == .clipboard }).defaultRestVariant == nil)
        #expect(try #require(descriptors.first { $0.id == .clipboard }).supportsCollapsedSummary == false)
        #expect(try #require(descriptors.first { $0.id == .pomodoro }).containerKind == .lightweightPomodoro)
        #expect(try #require(descriptors.first { $0.id == .settings }).containerKind == .settingsWindow)
        #expect(try #require(descriptors.first { $0.id == .settings }).canShowInStandardTab == false)
    }

    @Test func energyPoliciesKeepClosedModeLowCost() {
        #expect(ModuleEnergyPolicy.aiChat.closedMode == .suspended)
        #expect(ModuleEnergyPolicy.aiChat.allowsBackgroundCore == false)
        #expect(ModuleEnergyPolicy.clipboard.closedMode == .backgroundCore)
        #expect(ModuleEnergyPolicy.clipboard.allowsBackgroundCore == true)
        #expect(ModuleEnergyPolicy.pomodoro.closedMode == .backgroundCore)
        #expect(ModuleEnergyPolicy.pomodoro.visibleMode == .visible)
    }

    @Test func externalCapabilitiesUseExplicitStatuses() {
        #expect(CapabilityStatus.allCases == [
            .verified,
            .target,
            .unsupported
        ])
    }

}
