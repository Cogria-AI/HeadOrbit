import Combine
import CoreMotion
import Foundation
import os

private let log = Logger(subsystem: "com.cogria.HeadOrbit", category: "HeadTracker")

/// 封装 CMHeadphoneMotionManager：
/// - 判断系统 / 权限 / 是否有支持头部追踪的 AirPods 在提供数据
/// - 输出相对校准基准的 HeadPose（校准 = 把当前姿态当作「正对屏幕」）
final class HeadTracker: NSObject, ObservableObject {
    enum Status: Equatable {
        case unsupported            // 系统不支持（理论上 macOS 14+ 都支持）
        case denied                 // 「运动与健身」权限被拒
        case restricted
        case waitingForPermission   // 还没询问 / 用户还没答
        case waitingForHeadphones   // 权限 OK，但没有支持头部追踪的耳机在送数据
        case tracking(SensorSide)   // 正常收数

        var isTracking: Bool { if case .tracking = self { return true } else { return false } }
    }

    @Published private(set) var status: Status = .waitingForPermission
    @Published private(set) var authorization: CMAuthorizationStatus = CMHeadphoneMotionManager.authorizationStatus()
    @Published private(set) var pose: HeadPose = .zero
    @Published private(set) var isCalibrated = false
    @Published private(set) var lastError: String?

    /// 每一帧都会推送（比 @Published pose 更适合做逻辑，不受 SwiftUI 合并影响）
    let samples = PassthroughSubject<HeadPose, Never>()
    /// 用户点了校准。所有功能应据此清掉计时器、提醒和暂停，从当前姿态重新开始算
    let didRecenter = PassthroughSubject<Void, Never>()

    private var manager = CMHeadphoneMotionManager()
    private var reference: CMAttitude?
    private var lastAttitude: CMAttitude?
    private var lastSampleAt: Date?
    private var staleTimer: Timer?
    private var permissionTimer: Timer?
    private var connectCheckTimer: Timer?
    /// 每次「耳机断开 → 重新连上」只自动重建一次会话，避免无数据时无限循环
    private var autoReconnectArmed = true
    /// 系统回「已连接」之后等这么久还没数据，就自动重建一次。
    /// 实测首帧延迟 0.25s 到 10s+ 都见过，所以宽限期必须给足，太短会把正要建立的流拆掉。
    private let connectGrace: TimeInterval = 20
    private var connectedByDelegate = false

    /// 超过这个时间没收到数据就当作耳机没在用（摘下 / 切到 iPhone / 断开）
    private let staleInterval: TimeInterval = 2.0

    override init() {
        super.init()
        manager.delegate = self
        refreshStatus()
    }

    var isDeviceMotionAvailable: Bool { manager.isDeviceMotionAvailable }


    func start() {
        log.notice("start: available=\(self.manager.isDeviceMotionAvailable) active=\(self.manager.isDeviceMotionActive) auth=\(CMHeadphoneMotionManager.authorizationStatus().rawValue) connectionStatusActive=\(self.manager.isConnectionStatusActive)")
        guard manager.isDeviceMotionAvailable else { status = .unsupported; return }
        guard !manager.isDeviceMotionActive else { return }
        lastError = nil
        manager.startConnectionStatusUpdates()
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }
            if let error {
                log.error("deviceMotion error: \(error.localizedDescription, privacy: .public) \((error as NSError).domain, privacy: .public)/\((error as NSError).code)")
                self.lastError = error.localizedDescription
                self.refreshStatus()
                return
            }
            guard let motion else { return }
            if self.lastSampleAt == nil {
                log.notice("first sample: sensor=\(motion.sensorLocation.rawValue)")
                self.autoReconnectArmed = true
                self.connectCheckTimer?.invalidate(); self.connectCheckTimer = nil
            }
            self.handle(motion)
        }
        log.notice("startDeviceMotionUpdates called, active=\(self.manager.isDeviceMotionActive)")
        staleTimer?.invalidate()
        staleTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkStale()
        }
        refreshStatus()
        // 首次启动会弹「运动与健身」授权框。系统不会回调告诉我们用户点了什么，
        // 所以在未决期间轮询；一旦授权，重启采集，保证会话是在授权之后建立的。
        if authorization == .notDetermined { startPermissionPolling() }
    }

    /// 打开面板时调一下，把权限 / 状态刷成最新
    func refresh() {
        refreshStatus()
    }

    /// 用户手动点「重新连接」：销毁当前采集会话，换一个全新的 CMHeadphoneMotionManager 重来。
    /// 用于「先开程序后戴耳机」或系统那边的传感器流卡住没数据的情况。
    func reconnect() {
        log.notice("manual reconnect")
        rebuildSession()
    }

    private func rebuildSession() {
        connectCheckTimer?.invalidate(); connectCheckTimer = nil
        manager.stopDeviceMotionUpdates()
        manager.stopConnectionStatusUpdates()
        manager.delegate = nil
        manager = CMHeadphoneMotionManager()
        manager.delegate = self
        lastSampleAt = nil
        status = .waitingForHeadphones
        start()
    }

    func stop() {
        log.notice("stop")
        manager.stopDeviceMotionUpdates()
        manager.stopConnectionStatusUpdates()
        staleTimer?.invalidate(); staleTimer = nil
        permissionTimer?.invalidate(); permissionTimer = nil
        connectCheckTimer?.invalidate(); connectCheckTimer = nil
        lastSampleAt = nil
        refreshStatus()
    }

    /// 把当前姿态当作「正对屏幕」
    func recenter() {
        guard let att = lastAttitude?.copy() as? CMAttitude else { return }
        reference = att
        isCalibrated = true
        pose = .zero
        log.notice("recenter")
        didRecenter.send()
    }

    // MARK: - Private

    private func handle(_ motion: CMDeviceMotion) {
        lastAttitude = motion.attitude
        lastSampleAt = Date()

        let att = motion.attitude.copy() as! CMAttitude
        if let reference { att.multiply(byInverseOf: reference) }
        let p = HeadPose(attitude: att, timestamp: motion.timestamp)
        pose = p
        samples.send(p)

        let side = SensorSide(motion.sensorLocation)
        if status != .tracking(side) { status = .tracking(side) }
    }

    private func checkStale() {
        guard status.isTracking, let last = lastSampleAt else { return }
        if Date().timeIntervalSince(last) > staleInterval {
            status = .waitingForHeadphones
        }
    }

    private func startPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = CMHeadphoneMotionManager.authorizationStatus()
            guard now != .notDetermined else { return }
            self.permissionTimer?.invalidate(); self.permissionTimer = nil
            self.refreshStatus()
            log.notice("permission poll: now=\(now.rawValue)")
            if now == .authorized {
                self.manager.stopDeviceMotionUpdates()
                self.start()
            }
        }
    }

    private func refreshStatus() {
        let auth = CMHeadphoneMotionManager.authorizationStatus()
        if authorization != auth { authorization = auth }
        if !manager.isDeviceMotionAvailable { status = .unsupported; return }
        switch auth {
        case .denied: status = .denied
        case .restricted: status = .restricted
        case .notDetermined: status = .waitingForPermission
        case .authorized:
            if !status.isTracking { status = .waitingForHeadphones }
        @unknown default: status = .waitingForPermission
        }
    }
}

extension HeadTracker: CMHeadphoneMotionManagerDelegate {
    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        log.notice("delegate: didConnect")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.connectedByDelegate = true
            self.refreshStatus()
            // 耳机（重新）连上了但数据没跟着来：给一次自动重建的机会
            guard self.autoReconnectArmed else { return }
            self.connectCheckTimer?.invalidate()
            self.connectCheckTimer = Timer.scheduledTimer(withTimeInterval: self.connectGrace, repeats: false) { [weak self] _ in
                guard let self, !self.status.isTracking else { return }
                log.notice("connected but no data after \(self.connectGrace)s, auto reconnect once")
                self.autoReconnectArmed = false
                self.rebuildSession()
            }
        }
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        log.notice("delegate: didDisconnect")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.connectedByDelegate = false
            self.lastSampleAt = nil
            self.status = .waitingForHeadphones
            self.autoReconnectArmed = true   // 下次连上再给一次机会
            self.connectCheckTimer?.invalidate(); self.connectCheckTimer = nil
        }
    }
}
