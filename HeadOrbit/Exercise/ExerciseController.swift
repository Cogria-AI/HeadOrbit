import AppKit
import Combine
import SwiftUI
import os

private let log = Logger(subsystem: "com.cogria.HeadOrbit", category: "Exercise")

/// 每帧都变的状态，只有练习画面订阅
final class ExerciseState: ObservableObject {
    enum Phase: Equatable {
        case intro(seconds: Int)  // 说明 + 倒计时，结束时以当前姿态校准
        case active
        case stepDone
        case finished
    }

    @Published var step = 0
    @Published var phase = Phase.intro(seconds: 3)
    @Published var follower = PathFollower(exercise: NeckExercise.routine[0])
    /// 最近几秒的位置（度），画轨迹尾巴
    @Published var trail: [(x: Double, y: Double, t: TimeInterval)] = []
    @Published var isTracking = true

    var exercise: NeckExercise { NeckExercise.routine[step] }
}

/// 颈部活动：全屏模糊，主屏正中画目标轨迹和头部实时轨迹，按流程走完自动关闭，Esc 随时退出。
/// 期间暂停所有场景，免得绕环时触发按键或模糊
final class ExerciseController: ObservableObject {
    @Published private(set) var isRunning = false

    private let tracker: HeadTracker
    private let engine: SceneEngine
    private let state = ExerciseState()
    private let overlay = BlurOverlayController.shared
    private let owner = "exercise"
    private var window: NSWindow?
    private var bag = Set<AnyCancellable>()
    private var timer: Timer?
    private let trailSeconds: TimeInterval = 2.5
    private lazy var escapeKey = GlobalHotKey(keyCode: GlobalHotKey.escape) { [weak self] in self?.stop() }

    init(tracker: HeadTracker, engine: SceneEngine) {
        self.tracker = tracker
        self.engine = engine
    }

    func start() {
        guard !isRunning else { return }
        log.notice("start")
        isRunning = true
        engine.isSuspended = true
        state.step = 0
        overlay.request(owner, dim: 0.45)
        showWindow()
        escapeKey.register()
        tracker.samples.sink { [weak self] in self?.handle($0) }.store(in: &bag)
        tracker.$status.map(\.isTracking).removeDuplicates()
            .sink { [weak self] in self?.state.isTracking = $0 }.store(in: &bag)
        beginStep()
    }

    func stop() {
        guard isRunning else { return }
        log.notice("stop at step \(self.state.step)")
        isRunning = false
        bag.removeAll()
        timer?.invalidate(); timer = nil
        escapeKey.unregister()
        window?.orderOut(nil); window = nil
        overlay.release(owner)
        engine.isSuspended = false
    }

    // MARK: - 流程

    private func beginStep() {
        state.follower = PathFollower(exercise: state.exercise)
        state.trail = []
        countdown(3)
    }

    private func countdown(_ n: Int) {
        state.phase = .intro(seconds: n)
        after(1) { [weak self] in
            guard let self else { return }
            if n > 1 { self.countdown(n - 1); return }
            // 每个动作开始前都以当前姿态为正前方，抵消上一个动作带来的漂移
            self.tracker.recenter()
            self.state.phase = .active
        }
    }

    private func handle(_ pose: HeadPose) {
        guard state.phase == .active else { return }
        let p = state.exercise.position(pose)
        state.trail.append((p.x, p.y, pose.timestamp))
        state.trail.removeAll { pose.timestamp - $0.t > trailSeconds }
        state.follower.update(x: p.x, y: p.y)
        guard state.follower.completedReps >= NeckExercise.reps else { return }
        log.notice("step \(self.state.step) done")
        state.phase = .stepDone
        after(1.2) { [weak self] in
            guard let self else { return }
            if self.state.step + 1 < NeckExercise.routine.count {
                self.state.step += 1
                self.beginStep()
            } else {
                self.state.phase = .finished
                self.after(2) { [weak self] in self?.stop() }
            }
        }
    }

    private func after(_ seconds: TimeInterval, _ block: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in block() }
    }

    // MARK: - 窗口

    private func showWindow() {
        guard let screen = NSScreen.main else { return }
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.isReleasedWhenClosed = false
        w.level = BlurOverlayController.Layer.aboveBlur.windowLevel
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        w.contentView = NSHostingView(rootView: ExerciseView(state: state))
        w.setFrame(screen.frame, display: true)
        w.orderFrontRegardless()
        window = w
    }
}
