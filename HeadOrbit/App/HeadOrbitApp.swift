import SwiftUI

@main
struct HeadOrbitApp: App {
    // Own the models without subscribing the entire scene to every motion frame.
    @StateObject private var runtime = HeadOrbitRuntime()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(runtime.tracker)
                .environmentObject(runtime.engine)
        } label: {
            TrackingStatusIcon(tracker: runtime.tracker)
        }
        .menuBarExtraStyle(.window)

        Window("HeadOrbit", id: "settings") {
            SettingsView()
                .environmentObject(runtime.tracker)
                .environmentObject(runtime.store)
                .environmentObject(runtime.engine)
        }
        .defaultSize(width: 820, height: 620)
    }
}

private final class HeadOrbitRuntime: ObservableObject {
    let tracker = HeadTracker()
    let store = SceneStore()
    let engine: SceneEngine

    init() {
        engine = SceneEngine(tracker: tracker, store: store)
        tracker.start()
        L10n.shared.applyAppearance()
    }
}

private struct TrackingStatusIcon: View {
    let tracker: HeadTracker
    @State private var isTracking = false

    var body: some View {
        Image(nsImage: isTracking ? MenuBarIcon.connected : MenuBarIcon.disconnected)
            .onReceive(tracker.$status.map(\.isTracking).removeDuplicates()) {
                isTracking = $0
            }
    }
}
