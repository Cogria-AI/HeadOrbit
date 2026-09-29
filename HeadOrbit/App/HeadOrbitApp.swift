import SwiftUI

@main
struct HeadOrbitApp: App {
    // Own the models without subscribing the entire scene to every motion frame.
    @StateObject private var runtime = HeadOrbitRuntime()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(runtime.tracker)
                .environmentObject(runtime.blur)
                .environmentObject(runtime.posture)
        } label: {
            TrackingStatusIcon(tracker: runtime.tracker)
        }
        .menuBarExtraStyle(.window)
    }
}

private final class HeadOrbitRuntime: ObservableObject {
    let tracker = HeadTracker()
    let blur = LookAwayBlurAction()
    let posture = PostureReminderAction()
    let engine: ActionEngine

    init() {
        engine = ActionEngine(tracker: tracker, actions: [blur, posture])
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
