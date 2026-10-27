import Foundation
import AppKit
import CoreGraphics
import IOKit.pwr_mgt
import Carbon
import Combine

enum JiggleMode: String, CaseIterable, Identifiable {
    case stealth = "Stealth"
    case natural = "Natural"
    var id: String { rawValue }
    
    var subtitle: String {
        switch self {
        case .stealth: return "Invisible zero-displacement activity"
        case .natural: return "Visible smooth cursor movement"
        }
    }
}

enum ActivityResponseMode: String, CaseIterable, Identifiable {
    case autoDeactivate = "Stop"
    case smartResume = "Smart Pause"
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .autoDeactivate: return "Fully turn off when you move mouse or type"
        case .smartResume: return "Pause on input, auto-resume after idle delay"
        }
    }
}

enum DeactivateType: String, CaseIterable, Identifiable {
    case afterDuration = "In"
    case atTime = "At"
    var id: String { rawValue }
}

enum MovementRange: String, CaseIterable, Identifiable {
    case subtle = "Subtle (5 px)"
    case medium = "Medium (40 px)"
    case full = "Full (150 px)"
    var id: String { rawValue }
    
    var pixels: CGFloat {
        switch self {
        case .subtle: return 5
        case .medium: return 40
        case .full: return 150
        }
    }
}

@MainActor
final class JigglerEngine: ObservableObject {
    static let shared = JigglerEngine()
    
    // MARK: - Published State
    @Published var isEnabled: Bool = false {
        didSet {
            if isEnabled != oldValue {
                handleEnabledChange()
            }
        }
    }
    
    /// True when enabled, but currently waiting for user idle threshold (either right after activation or during Smart Pause)
    @Published var isPausedForUserActivity: Bool = false
    @Published var isWaitingForSchedule: Bool = false
    @Published var currentIdleSeconds: Int = 0
    @Published var jiggleCount: Int = 0
    @Published var remainingSeconds: Int? = nil
    @Published var hasAccessibilityPermission: Bool = AXIsProcessTrusted()
    
    // MARK: - Settings (Persisted in UserDefaults)
    @Published var jiggleMode: JiggleMode = .stealth {
        didSet { UserDefaults.standard.set(jiggleMode.rawValue, forKey: "jiggleMode") }
    }
    
    @Published var activityResponse: ActivityResponseMode = .smartResume {
        didSet { UserDefaults.standard.set(activityResponse.rawValue, forKey: "activityResponse") }
    }
    
    /// Seconds of inactivity before starting/resuming (3, 10, 30, 60, 180, 300)
    @Published var startMovingAfterSeconds: Int = 3 {
        didSet { UserDefaults.standard.set(startMovingAfterSeconds, forKey: "startMovingAfterSeconds") }
    }
    
    /// Seconds between jiggles (1, 5, 10, 30, 60)
    @Published var moveEverySeconds: Int = 5 {
        didSet {
            UserDefaults.standard.set(moveEverySeconds, forKey: "moveEverySeconds")
            restartJiggleTimerIfNeeded()
        }
    }
    
    @Published var movementRange: MovementRange = .medium {
        didSet { UserDefaults.standard.set(movementRange.rawValue, forKey: "movementRange") }
    }
    
    // Schedule Settings
    @Published var scheduleEnabled: Bool = false {
        didSet { UserDefaults.standard.set(scheduleEnabled, forKey: "scheduleEnabled") }
    }
    @Published var scheduleStartHour: Int = 9 {
        didSet { UserDefaults.standard.set(scheduleStartHour, forKey: "scheduleStartHour") }
    }
    @Published var scheduleStartMinute: Int = 0 {
        didSet { UserDefaults.standard.set(scheduleStartMinute, forKey: "scheduleStartMinute") }
    }
    @Published var scheduleEndHour: Int = 18 {
        didSet { UserDefaults.standard.set(scheduleEndHour, forKey: "scheduleEndHour") }
    }
    @Published var scheduleEndMinute: Int = 0 {
        didSet { UserDefaults.standard.set(scheduleEndMinute, forKey: "scheduleEndMinute") }
    }
    /// 1 = Sunday ... 7 = Saturday (Calendar weekday) -> Default Mon..Fri (2,3,4,5,6)
    @Published var activeWeekdays: Set<Int> = [2, 3, 4, 5, 6] {
        didSet { UserDefaults.standard.set(Array(activeWeekdays), forKey: "activeWeekdays") }
    }
    
    // Auto-Deactivate Timer Settings
    @Published var autoDeactivateEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(autoDeactivateEnabled, forKey: "autoDeactivateEnabled")
            setupDeactivateCountdown()
        }
    }
    @Published var deactivateType: DeactivateType = .afterDuration {
        didSet {
            UserDefaults.standard.set(deactivateType.rawValue, forKey: "deactivateType")
            setupDeactivateCountdown()
        }
    }
    @Published var deactivateHour: Int = 2 {
        didSet {
            UserDefaults.standard.set(deactivateHour, forKey: "deactivateHour")
            setupDeactivateCountdown()
        }
    }
    @Published var deactivateMinute: Int = 0 {
        didSet {
            UserDefaults.standard.set(deactivateMinute, forKey: "deactivateMinute")
            setupDeactivateCountdown()
        }
    }
    
    // Internal state
    private let syntheticTag: Int64 = 0x4A494747 // "JIGG"
    private var lastSyntheticEventTime: TimeInterval = 0
    private var isPerformingSyntheticMove: Bool = false
    private var lastKnownMouseLocation: CGPoint = NSEvent.mouseLocation
    private var activationTime: Date = .distantPast
    private var lastRealUserActivityTime: Date = Date()
    /// Tracks whether GhostMouse has finished its initial idle wait after being enabled
    private var hasCompletedInitialIdleWait: Bool = false
    private var sleepAssertionID: IOPMAssertionID = 0
    private var hasSleepAssertion: Bool = false
    
    private var mainTickTimer: Timer?
    private var jiggleTimer: Timer?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var hotKeyRef: EventHotKeyRef?
    
    /// All non-mouse-move hardware HID event types (keyboard keys, modifiers, clicks, drags, scroll wheel)
    private static let nonMoveHIDEventTypes: [CGEventType] = [
        .keyDown,
        .keyUp,
        .flagsChanged,
        .leftMouseDown,
        .leftMouseUp,
        .rightMouseDown,
        .rightMouseUp,
        .otherMouseDown,
        .otherMouseUp,
        .leftMouseDragged,
        .rightMouseDragged,
        .otherMouseDragged,
        .scrollWheel
    ]
    
    var onStatusChange: (() -> Void)?
    
    private init() {
        loadSettings()
        setupGlobalHotkey()
        startMainTickLoop()
    }
    
    private func loadSettings() {
        let d = UserDefaults.standard
        if let m = d.string(forKey: "jiggleMode"), let mode = JiggleMode(rawValue: m) { jiggleMode = mode }
        if let a = d.string(forKey: "activityResponse"), let resp = ActivityResponseMode(rawValue: a) { activityResponse = resp }
        if d.object(forKey: "startMovingAfterSeconds") != nil {
            let val = d.integer(forKey: "startMovingAfterSeconds")
            if val > 0 { startMovingAfterSeconds = val }
        }
        if d.object(forKey: "moveEverySeconds") != nil {
            let val = d.integer(forKey: "moveEverySeconds")
            if val > 0 { moveEverySeconds = val }
        }
        if let r = d.string(forKey: "movementRange"), let range = MovementRange(rawValue: r) { movementRange = range }
        
        scheduleEnabled = d.bool(forKey: "scheduleEnabled")
        if d.object(forKey: "scheduleStartHour") != nil { scheduleStartHour = d.integer(forKey: "scheduleStartHour") }
        if d.object(forKey: "scheduleStartMinute") != nil { scheduleStartMinute = d.integer(forKey: "scheduleStartMinute") }
        if d.object(forKey: "scheduleEndHour") != nil { scheduleEndHour = d.integer(forKey: "scheduleEndHour") }
        if d.object(forKey: "scheduleEndMinute") != nil { scheduleEndMinute = d.integer(forKey: "scheduleEndMinute") }
        if let days = d.array(forKey: "activeWeekdays") as? [Int] { activeWeekdays = Set(days) }
        
        autoDeactivateEnabled = d.bool(forKey: "autoDeactivateEnabled")
        if let dt = d.string(forKey: "deactivateType"), let dtype = DeactivateType(rawValue: dt) { deactivateType = dtype }
        if d.object(forKey: "deactivateHour") != nil { deactivateHour = d.integer(forKey: "deactivateHour") }
        if d.object(forKey: "deactivateMinute") != nil { deactivateMinute = d.integer(forKey: "deactivateMinute") }
    }
    
    // MARK: - Activation & Lifecycle
    func toggle() {
        isEnabled.toggle()
    }
    
    private func handleEnabledChange() {
        hasAccessibilityPermission = AXIsProcessTrusted()
        if isEnabled {
            activationTime = Date()
            lastRealUserActivityTime = Date()
            currentIdleSeconds = 0
            lastKnownMouseLocation = NSEvent.mouseLocation
            // Start in "waiting for idle" state so activating GhostMouse never jerks the mouse while the user is still holding it!
            hasCompletedInitialIdleWait = false
            isPausedForUserActivity = true
            acquireSleepAssertion()
            startActivityMonitoring()
            setupDeactivateCountdown()
            restartJiggleTimerIfNeeded()
        } else {
            isPausedForUserActivity = false
            hasCompletedInitialIdleWait = false
            isWaitingForSchedule = false
            remainingSeconds = nil
            jiggleTimer?.invalidate()
            jiggleTimer = nil
            stopActivityMonitoring()
            releaseSleepAssertion()
        }
        onStatusChange?()
    }
    
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options)
        if !hasAccessibilityPermission {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    // MARK: - Hardware-Level Keyboard & Mouse Idle Check
    /// Queries macOS WindowServer for any recent keyboard key press, modifier key, mouse click, drag, or scroll wheel event.
    /// Works across all apps without requiring Input Monitoring / keylogger permissions.
    private static func secondsSinceLastNonMoveHIDInput() -> CFTimeInterval {
        var minSecs: CFTimeInterval = 999999.0
        for eventType in nonMoveHIDEventTypes {
            let secs = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: eventType)
            if secs < minSecs {
                minSecs = secs
            }
        }
        return minSecs
    }
    
    // MARK: - Timers & Schedule
    private func startMainTickLoop() {
        mainTickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            Task { @MainActor in
                JigglerEngine.shared.onMainTick()
            }
        }
    }
    
    private func restartJiggleTimerIfNeeded() {
        jiggleTimer?.invalidate()
        jiggleTimer = nil
        guard isEnabled else { return }
        let interval = TimeInterval(max(1, moveEverySeconds))
        jiggleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                JigglerEngine.shared.onJiggleTick()
            }
        }
    }
    
    private func setupDeactivateCountdown() {
        guard isEnabled && autoDeactivateEnabled else {
            remainingSeconds = nil
            return
        }
        switch deactivateType {
        case .afterDuration:
            let total = (deactivateHour * 3600) + (deactivateMinute * 60)
            remainingSeconds = max(60, total)
        case .atTime:
            let now = Date()
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: now)
            comps.hour = deactivateHour
            comps.minute = deactivateMinute
            comps.second = 0
            if var target = Calendar.current.date(from: comps) {
                if target <= now {
                    target = Calendar.current.date(byAdding: .day, value: 1, to: target) ?? target
                }
                remainingSeconds = Int(target.timeIntervalSince(now))
            }
        }
    }
    
    private static var tickCounter: Int = 0
    
    private func onMainTick() {
        hasAccessibilityPermission = AXIsProcessTrusted()
        
        // 1. Check hardware HID keyboard / click / scroll / drag activity across the entire Mac
        let nonMoveIdle = Self.secondsSinceLastNonMoveHIDInput()
        if nonMoveIdle < 0.35 {
            handleDetectedUserActivity()
        }
        
        // 2. Check physical cursor movement delta
        let currentPos = NSEvent.mouseLocation
        let dx = abs(currentPos.x - lastKnownMouseLocation.x)
        let dy = abs(currentPos.y - lastKnownMouseLocation.y)
        let timeSinceSynthetic = ProcessInfo.processInfo.systemUptime - lastSyntheticEventTime
        
        if !isPerformingSyntheticMove && (dx > 2.0 || dy > 2.0) && timeSinceSynthetic > 0.20 {
            lastKnownMouseLocation = currentPos
            handleDetectedUserActivity()
        } else {
            lastKnownMouseLocation = currentPos
        }
        
        let idle = Int(Date().timeIntervalSince(lastRealUserActivityTime))
        currentIdleSeconds = idle
        
        guard isEnabled else { return }
        
        // 3. Update schedule state
        let waitingSched = checkIsWaitingForSchedule()
        if waitingSched != isWaitingForSchedule {
            isWaitingForSchedule = waitingSched
            onStatusChange?()
        }
        
        // 4. Transition out of initial wait or Smart Pause once the user has been idle for `startMovingAfterSeconds`
        if isPausedForUserActivity {
            let threshold = max(1, startMovingAfterSeconds)
            if idle >= threshold {
                isPausedForUserActivity = false
                hasCompletedInitialIdleWait = true
                onStatusChange?()
            }
        }
        
        // 5. Update countdown every 1.0s (every 4 ticks of 0.25s)
        Self.tickCounter = (Self.tickCounter + 1) % 4
        if Self.tickCounter == 0, let rem = remainingSeconds {
            if rem <= 1 {
                isEnabled = false
            } else {
                remainingSeconds = rem - 1
            }
        }
    }
    
    private func onJiggleTick() {
        guard isEnabled, !isPausedForUserActivity, !isWaitingForSchedule else { return }
        performJiggle()
    }
    
    private func checkIsWaitingForSchedule() -> Bool {
        guard scheduleEnabled else { return false }
        let now = Date()
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)
        guard activeWeekdays.contains(weekday) else { return true }
        
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let nowMins = hour * 60 + minute
        let startMins = scheduleStartHour * 60 + scheduleStartMinute
        let endMins = scheduleEndHour * 60 + scheduleEndMinute
        
        if startMins <= endMins {
            return !(nowMins >= startMins && nowMins < endMins)
        } else {
            // Overnight schedule (e.g. 22:00 to 06:00)
            return !(nowMins >= startMins || nowMins < endMins)
        }
    }
    
    // MARK: - User Activity Detection (Mouse & Keyboard)
    private func startActivityMonitoring() {
        stopActivityMonitoring()
        
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseDragged, .rightMouseDragged, .scrollWheel, .keyDown, .flagsChanged
        ]
        
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
            if let cgEvent = event.cgEvent, cgEvent.getIntegerValueField(.eventSourceUserData) == JigglerEngine.shared.syntheticTag {
                return
            }
            Task { @MainActor in
                JigglerEngine.shared.handleDetectedUserActivity()
            }
        }
        
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .scrollWheel]) { event in
            Task { @MainActor in
                JigglerEngine.shared.handleDetectedUserActivity()
            }
            return event
        }
    }
    
    private func stopActivityMonitoring() {
        if let gm = globalEventMonitor {
            NSEvent.removeMonitor(gm)
            globalEventMonitor = nil
        }
        if let lm = localEventMonitor {
            NSEvent.removeMonitor(lm)
            localEventMonitor = nil
        }
    }
    
    private func handleDetectedUserActivity() {
        lastRealUserActivityTime = Date()
        currentIdleSeconds = 0
        
        guard isEnabled else { return }
        
        // Ignore the first 1.2 seconds right after clicking the toggle button in the menu bar
        guard Date().timeIntervalSince(activationTime) > 1.2 else { return }
        
        // If we haven't even finished the initial idle wait after enabling yet, just keep resetting the idle timer!
        guard hasCompletedInitialIdleWait else { return }
        
        switch activityResponse {
        case .autoDeactivate:
            isEnabled = false
        case .smartResume:
            if !isPausedForUserActivity {
                isPausedForUserActivity = true
                onStatusChange?()
            }
        }
    }
    
    // MARK: - Stealth & Natural Jiggling
    func performJiggle() {
        // If user just pressed a key or clicked right as the tick fired, abort immediately
        if Self.secondsSinceLastNonMoveHIDInput() < 0.25 {
            handleDetectedUserActivity()
            return
        }
        
        isPerformingSyntheticMove = true
        defer {
            isPerformingSyntheticMove = false
            lastSyntheticEventTime = ProcessInfo.processInfo.systemUptime
            lastKnownMouseLocation = NSEvent.mouseLocation
        }
        
        lastSyntheticEventTime = ProcessInfo.processInfo.systemUptime
        
        // 1. Reset system HID idle timer at the IOKit power management level
        var assertionID: IOPMAssertionID = 0
        IOPMAssertionDeclareUserActivity(
            "MouseJigglerPro Activity" as CFString,
            kIOPMUserActiveLocal,
            &assertionID
        )
        
        // 2. Post HID mouse event
        let currentAppKitLoc = NSEvent.mouseLocation
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 1080
        let cgCenter = CGPoint(x: currentAppKitLoc.x, y: primaryScreenHeight - currentAppKitLoc.y)
        
        switch jiggleMode {
        case .stealth:
            postSyntheticMouseMove(at: cgCenter, deltaX: 1, deltaY: 0)
            postSyntheticMouseMove(at: cgCenter, deltaX: -1, deltaY: 0)
            
        case .natural:
            let radius = movementRange.pixels
            let angle = Double.random(in: 0...(2 * .pi))
            let targetX = cgCenter.x + CGFloat(cos(angle)) * radius
            let targetY = cgCenter.y + CGFloat(sin(angle)) * radius
            let steps = 12
            for step in 1...steps {
                if Self.secondsSinceLastNonMoveHIDInput() < 0.2 {
                    handleDetectedUserActivity()
                    return
                }
                let t = CGFloat(step) / CGFloat(steps)
                let ix = cgCenter.x + (targetX - cgCenter.x) * t
                let iy = cgCenter.y + (targetY - cgCenter.y) * t
                postSyntheticMouseMove(at: CGPoint(x: ix, y: iy), deltaX: Int64(targetX - cgCenter.x) / Int64(steps), deltaY: Int64(targetY - cgCenter.y) / Int64(steps))
                usleep(8000)
            }
            for step in 1...steps {
                if Self.secondsSinceLastNonMoveHIDInput() < 0.2 {
                    handleDetectedUserActivity()
                    return
                }
                let t = CGFloat(step) / CGFloat(steps)
                let ix = targetX + (cgCenter.x - targetX) * t
                let iy = targetY + (cgCenter.y - targetY) * t
                postSyntheticMouseMove(at: CGPoint(x: ix, y: iy), deltaX: Int64(cgCenter.x - targetX) / Int64(steps), deltaY: Int64(cgCenter.y - targetY) / Int64(steps))
                usleep(8000)
            }
        }
        
        jiggleCount += 1
    }
    
    private func postSyntheticMouseMove(at point: CGPoint, deltaX: Int64, deltaY: Int64) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else {
            return
        }
        event.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
        event.setIntegerValueField(.mouseEventDeltaX, value: deltaX)
        event.setIntegerValueField(.mouseEventDeltaY, value: deltaY)
        event.post(tap: .cghidEventTap)
    }
    
    // MARK: - Power Management Assertion
    private func acquireSleepAssertion() {
        guard !hasSleepAssertion else { return }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "MouseJigglerPro Preventing Idle Sleep" as CFString,
            &sleepAssertionID
        )
        if result == kIOReturnSuccess {
            hasSleepAssertion = true
        }
    }
    
    private func releaseSleepAssertion() {
        guard hasSleepAssertion else { return }
        IOPMAssertionRelease(sleepAssertionID)
        sleepAssertionID = 0
        hasSleepAssertion = false
    }
    
    // MARK: - Global Hotkey (⌃⌘J)
    private func setupGlobalHotkey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let handler: EventHandlerUPP = { _, _, _ in
            Task { @MainActor in
                JigglerEngine.shared.toggle()
            }
            return noErr
        }
        
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)
        
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D4A5052), id: 1) // 'MJPR'
        let modifiers = UInt32(cmdKey | controlKey)
        let keyCode = UInt32(kVK_ANSI_J) // 'J'
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}
