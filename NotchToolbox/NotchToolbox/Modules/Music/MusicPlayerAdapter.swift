import Foundation

protocol MusicPlayerAdapter: Sendable {
    var capability: MusicPlayerCapability { get }
    func launch() async throws
    func perform(_ action: MusicControlAction) async throws
}
