import SwiftUI
import AppKit

/// Custom shape that draws a rounded panel with a top callout pointer caret aligned to `arrowX`
struct PopoverFrameShape: Shape {
    var arrowX: CGFloat
    var cornerRadius: CGFloat = 16
    var arrowWidth: CGFloat = 24
    var arrowHeight: CGFloat = 11
    
    func path(in rect: CGRect) -> Path {
        let bodyTop = rect.minY + arrowHeight
        let bodyRect = CGRect(x: rect.minX, y: bodyTop, width: rect.width, height: rect.height - arrowHeight)
        let r = cornerRadius
        
        // Clamp arrowX so it stays nicely inside the top corners
        let clampedX = max(bodyRect.minX + r + arrowWidth / 2 + 6, min(arrowX, bodyRect.maxX - r - arrowWidth / 2 - 6))
        let halfW = arrowWidth / 2
        
        var p = Path()
        // Start at top-left after corner
        p.move(to: CGPoint(x: bodyRect.minX + r, y: bodyRect.minY))
        
        // Line to left base of arrow
        p.addLine(to: CGPoint(x: clampedX - halfW, y: bodyRect.minY))
        
        // Smooth curved caret tip pointing up to the menu bar icon
        p.addQuadCurve(
            to: CGPoint(x: clampedX - 2.5, y: rect.minY + 1.5),
            control: CGPoint(x: clampedX - halfW * 0.45, y: bodyRect.minY)
        )
        p.addQuadCurve(
            to: CGPoint(x: clampedX + 2.5, y: rect.minY + 1.5),
            control: CGPoint(x: clampedX, y: rect.minY - 0.5)
        )
        p.addQuadCurve(
            to: CGPoint(x: clampedX + halfW, y: bodyRect.minY),
            control: CGPoint(x: clampedX + halfW * 0.45, y: bodyRect.minY)
        )
        
        // Top-right corner
        p.addLine(to: CGPoint(x: bodyRect.maxX - r, y: bodyRect.minY))
        p.addArc(
            center: CGPoint(x: bodyRect.maxX - r, y: bodyRect.minY + r),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        
        // Bottom-right corner
        p.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY - r))
        p.addArc(
            center: CGPoint(x: bodyRect.maxX - r, y: bodyRect.maxY - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        
        // Bottom-left corner
        p.addLine(to: CGPoint(x: bodyRect.minX + r, y: bodyRect.maxY))
        p.addArc(
            center: CGPoint(x: bodyRect.minX + r, y: bodyRect.maxY - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        
        // Top-left corner
        p.addLine(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY + r))
        p.addArc(
            center: CGPoint(x: bodyRect.minX + r, y: bodyRect.minY + r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        
        p.closeSubpath()
        return p
    }
}

@MainActor
final class PanelGeometryModel: ObservableObject {
    static let shared = PanelGeometryModel()
    @Published var arrowX: CGFloat = 330
}

struct PopoverContentView: View {
    @ObservedObject var engine = JigglerEngine.shared
    @ObservedObject var geometry = PanelGeometryModel.shared
    
    private let weekdays: [(id: Int, label: String)] = [
        (2, "Mo"), (3, "Tu"), (4, "We"), (5, "Th"), (6, "Fr"), (7, "Sa"), (1, "Su")
    ]
    
    var body: some View {
        VStack(spacing: 10) {
            // Top Two-Column Grid
            HStack(alignment: .top, spacing: 12) {
                // LEFT COLUMN
                VStack(spacing: 10) {
                    headerCard
                    scheduleCard
                    deactivateCard
                }
                .frame(width: 305)
                
                // RIGHT COLUMN
                VStack(spacing: 10) {
                    modeCard
                    behaviorCard
                    statusTelemetryCard
                }
                .frame(width: 305)
            }
            
            // Optional Accessibility Banner if not yet granted
            if !engine.hasAccessibilityPermission {
                accessibilityBanner
            }
            
            // Bottom Action Bar
            bottomBar
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .padding(.top, 25) // Extra top space for the 11pt pointer arrow
        .frame(width: 650)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            ZStack {
                PopoverFrameShape(arrowX: geometry.arrowX)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.13, green: 0.14, blue: 0.16),
                                Color(red: 0.10, green: 0.11, blue: 0.13)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                PopoverFrameShape(arrowX: geometry.arrowX)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            }
        )
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Header Card
    private var headerCard: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: engine.isEnabled
                                ? [Color.blue, Color.cyan.opacity(0.85)]
                                : [Color.gray.opacity(0.35), Color.gray.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
                
                Image(systemName: engine.jiggleMode == .stealth ? "computermouse.fill" : "cursorarrow.motionlines")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("GhostMouse")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 7, height: 7)
                    Text(statusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            
            Spacer(minLength: 6)
            
            // Shortcut Badge
            Text("⌃⌘J")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .help("Global keyboard shortcut to toggle GhostMouse anywhere")
            
            Toggle("", isOn: $engine.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(.blue)
        }
        .padding(11)
        .background(cardBackground)
    }
    
    private var statusDotColor: Color {
        if !engine.isEnabled { return Color.gray }
        if engine.isWaitingForSchedule || engine.isPausedForUserActivity { return Color.orange }
        return Color.green
    }
    
    private var statusText: String {
        if !engine.isEnabled { return "Inactive" }
        if engine.isWaitingForSchedule { return "Scheduled Standby" }
        if engine.isPausedForUserActivity {
            let rem = max(0, engine.startMovingAfterSeconds - engine.currentIdleSeconds)
            return "Paused (\(rem)s)"
        }
        return engine.jiggleMode == .stealth ? "Active (Stealth)" : "Active (Natural)"
    }
    
    // MARK: - Schedule Card
    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Schedule", systemImage: "calendar.badge.clock")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Toggle("", isOn: $engine.scheduleEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .tint(.blue)
            }
            
            HStack(spacing: 6) {
                Text("From")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize()
                
                timePicker(hour: $engine.scheduleStartHour, minute: $engine.scheduleStartMinute)
                
                Spacer(minLength: 4)
                
                Text("To")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize()
                
                timePicker(hour: $engine.scheduleEndHour, minute: $engine.scheduleEndMinute)
            }
            .opacity(engine.scheduleEnabled ? 1.0 : 0.45)
            .disabled(!engine.scheduleEnabled)
            
            HStack(spacing: 4) {
                Text("Repeat")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize()
                
                Spacer(minLength: 4)
                
                ForEach(weekdays, id: \.id) { day in
                    let isSelected = engine.activeWeekdays.contains(day.id)
                    Button {
                        if isSelected {
                            engine.activeWeekdays.remove(day.id)
                        } else {
                            engine.activeWeekdays.insert(day.id)
                        }
                    } label: {
                        Text(day.label)
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 28, height: 22)
                            .background(isSelected ? Color.blue : Color.white.opacity(0.08))
                            .foregroundColor(isSelected ? .white : .secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .opacity(engine.scheduleEnabled ? 1.0 : 0.45)
            .disabled(!engine.scheduleEnabled)
        }
        .padding(11)
        .background(cardBackground)
    }
    
    // MARK: - Deactivate Timer Card
    private var deactivateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Auto-Deactivate", systemImage: "timer")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                if let rem = engine.remainingSeconds, engine.isEnabled, engine.autoDeactivateEnabled {
                    Text(formatCountdown(rem))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.cyan)
                }
                
                Toggle("", isOn: $engine.autoDeactivateEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .tint(.blue)
            }
            
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(DeactivateType.allCases) { dtype in
                        let selected = engine.deactivateType == dtype
                        Button {
                            engine.deactivateType = dtype
                        } label: {
                            Text(dtype.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(selected ? Color.blue : Color.white.opacity(0.08))
                                .foregroundColor(selected ? .white : .secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Spacer()
                
                if engine.deactivateType == .afterDuration {
                    HStack(spacing: 4) {
                        Picker("", selection: $engine.deactivateHour) {
                            ForEach(0..<13, id: \.self) { h in
                                Text("\(h) hr").tag(h)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 68)
                        
                        Picker("", selection: $engine.deactivateMinute) {
                            ForEach([0, 15, 30, 45], id: \.self) { m in
                                Text("\(m) min").tag(m)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 76)
                    }
                } else {
                    timePicker(hour: $engine.deactivateHour, minute: $engine.deactivateMinute)
                }
            }
            .opacity(engine.autoDeactivateEnabled ? 1.0 : 0.45)
            .disabled(!engine.autoDeactivateEnabled)
        }
        .padding(11)
        .background(cardBackground)
    }
    
    // MARK: - Mode Card (Stealth vs Natural)
    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Mode", systemImage: "sparkles")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                HStack(spacing: 4) {
                    ForEach(JiggleMode.allCases) { mode in
                        let selected = engine.jiggleMode == mode
                        Button {
                            engine.jiggleMode = mode
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: mode == .stealth ? "eye.slash.fill" : "cursorarrow.motionlines")
                                    .font(.system(size: 10))
                                Text(mode.rawValue)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4.5)
                            .background(selected ? Color.blue : Color.white.opacity(0.08))
                            .foregroundColor(selected ? .white : .secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Text(engine.jiggleMode.subtitle)
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(11)
        .background(cardBackground)
    }
    
    // MARK: - Behavior Card (Activity Deactivation, Idle Threshold, Interval, Range)
    private var behaviorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: When Mouse / Keyboard Used
            HStack {
                VStack(alignment: .leading, spacing: 1.5) {
                    Text("On Activity")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .fixedSize()
                    Text(engine.activityResponse == .autoDeactivate ? "Turn off immediately" : "Pause & auto-resume")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .fixedSize()
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    ForEach(ActivityResponseMode.allCases) { resp in
                        let selected = engine.activityResponse == resp
                        Button {
                            engine.activityResponse = resp
                        } label: {
                            Text(resp.rawValue)
                                .font(.system(size: 10.5, weight: .semibold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(selected ? Color.blue : Color.white.opacity(0.08))
                                .foregroundColor(selected ? .white : .secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            // Row 2: Start / Resume After Idle
            HStack {
                Text("Resume After Idle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                
                Spacer()
                
                Picker("", selection: $engine.startMovingAfterSeconds) {
                    Text("3 sec").tag(3)
                    Text("10 sec").tag(10)
                    Text("30 sec").tag(30)
                    Text("1 min").tag(60)
                    Text("3 min").tag(180)
                    Text("5 min").tag(300)
                }
                .labelsHidden()
                .frame(width: 95)
            }
            .opacity(engine.activityResponse == .smartResume ? 1.0 : 0.45)
            .disabled(engine.activityResponse != .smartResume)
            
            Divider().background(Color.white.opacity(0.1))
            
            // Row 3: Move Every
            HStack {
                Text("Pulse Every")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                
                Spacer()
                
                Picker("", selection: $engine.moveEverySeconds) {
                    Text("1 sec").tag(1)
                    Text("5 sec").tag(5)
                    Text("10 sec").tag(10)
                    Text("30 sec").tag(30)
                    Text("1 min").tag(60)
                }
                .labelsHidden()
                .frame(width: 95)
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            // Row 4: Movement Range (only relevant for Natural mode)
            HStack {
                Text("Movement Range")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                
                Spacer()
                
                Picker("", selection: $engine.movementRange) {
                    ForEach(MovementRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .labelsHidden()
                .frame(width: 125)
            }
            .opacity(engine.jiggleMode == .natural ? 1.0 : 0.45)
            .disabled(engine.jiggleMode != .natural)
        }
        .padding(11)
        .background(cardBackground)
    }
    
    // MARK: - Live Telemetry Card
    private var statusTelemetryCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                .font(.system(size: 18))
                .foregroundColor(.cyan)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("GhostMouse Stealth Engine")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Pulses sent: \(engine.jiggleCount)  •  Any input will \(engine.activityResponse == .autoDeactivate ? "turn off" : "pause")")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.cyan.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.cyan.opacity(0.25), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Accessibility Permission Helper
    private var accessibilityBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility Permission Recommended")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                Text("Allows instant keyboard/mouse auto-deactivation and HID event posting across all apps.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Grant Access") {
                engine.requestAccessibilityPermission()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.small)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Bottom Bar
    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                engine.performJiggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill")
                    Text("Test Pulse Now")
                }
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            
            Button {
                if let url = URL(string: "https://paypal.me/joeystdio") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "cup.and.saucer.fill")
                        .foregroundColor(.yellow)
                    Text("Buy Me a Coffee")
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.yellow.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.yellow.opacity(0.35), lineWidth: 1)
                )
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Buy Joey a coffee via PayPal (paypal.me/joeystdio)")
            
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "power")
                    Text("Quit")
                }
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Helpers
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
    
    private func timePicker(hour: Binding<Int>, minute: Binding<Int>) -> some View {
        HStack(spacing: 2) {
            Picker("", selection: hour) {
                ForEach(0..<24, id: \.self) { h in
                    Text(String(format: "%02d", h)).tag(h)
                }
            }
            .labelsHidden()
            .frame(width: 50)
            
            Text(":")
                .foregroundColor(.secondary)
            
            Picker("", selection: minute) {
                ForEach([0, 15, 30, 45], id: \.self) { m in
                    Text(String(format: "%02d", m)).tag(m)
                }
            }
            .labelsHidden()
            .frame(width: 50)
        }
    }
    
    private func formatCountdown(_ totalSeconds: Int) -> String {
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%dh %02dm", h, m)
        } else {
            return String(format: "%02dm %02ds", m, s)
        }
    }
}
