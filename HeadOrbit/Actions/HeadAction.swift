import Combine
import Foundation

/// 一个「头部动作 → 本地功能」的插件。后续想加新功能（比如低头暂停视频、转头切歌）就再实现一个。
protocol HeadAction: AnyObject {
    var id: String { get }
    var title: String { get }
    var isEnabled: Bool { get set }

    /// 每一帧姿态都会调到这里（主线程）
    func process(_ pose: HeadPose)
    /// 追踪中断（摘下耳机 / 断连 / 关闭）或用户重新校准时调用：清掉计时器、提醒、暂停，回到初始状态
    func reset()
}

/// 把 HeadTracker 的数据分发给所有动作
final class ActionEngine: ObservableObject {
    let actions: [HeadAction]
    private var bag = Set<AnyCancellable>()

    init(tracker: HeadTracker, actions: [HeadAction]) {
        self.actions = actions
        let blur = actions.compactMap { $0 as? LookAwayBlurAction }.first
        let posture = actions.compactMap { $0 as? PostureReminderAction }.first

        tracker.samples
            .sink { [weak self, weak tracker] pose in
                let postureUnsafe = posture.map { $0.isEnabled && ($0.isReminding || $0.isOver(pose.pitch)) } ?? false
                blur?.updateForward(pose, allowed: tracker?.isCalibrated == true && !postureUnsafe)
                self?.actions.forEach { if $0.isEnabled { $0.process(pose) } }
            }
            .store(in: &bag)

        tracker.$status
            .removeDuplicates()
            .sink { [weak self] status in
                if !status.isTracking { self?.actions.forEach { $0.reset() } }
            }
            .store(in: &bag)

        tracker.didRecenter
            .sink { [weak self] in self?.actions.forEach { $0.reset() } }
            .store(in: &bag)
    }
}
