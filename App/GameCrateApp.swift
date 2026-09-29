import SwiftUI

@main
struct GameCrateApp: App {
    @State private var model: GameCrateModel = GameCrateApp.makeModel()

    var body: some Scene {
        WindowGroup {
            BootstrapHomeView(model: model)
        }
    }

    nonisolated private static func makeModel() -> GameCrateModel {
        MainActor.assumeIsolated {
            GameCrateModel.make()
        }
    }
}
