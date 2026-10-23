import AppKit
import SwiftUI

@main
struct GhostMouseApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // Native status-bar-only app
        app.run()
    }
}

final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var sharedInstance: AppDelegate?
    private var statusItem: NSStatusItem!
    private var panel: StatusPanel!
    private var hostingController: NSHostingController<PopoverContentView>!
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.sharedInstance = self
        setupStatusItem()
        setupPanel()
        
        JigglerEngine.shared.onStatusChange = { [weak self] in
            self?.updateStatusIcon()
        }
        updateStatusIcon()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(handleStatusItemClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "GhostMouse (Left-click: Panel, Right-click: Quick Toggle, ⌃⌘J)"
        }
    }
    
    private func setupPanel() {
        hostingController = NSHostingController(rootView: PopoverContentView())
        hostingController.sizingOptions = [.preferredContentSize]
        
        panel = StatusPanel(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        
        let hostView = hostingController.view
        hostView.wantsLayer = true
        hostView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostView
    }
    
    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            JigglerEngine.shared.toggle()
        } else {
            togglePanel(sender)
        }
    }
    
    private func togglePanel(_ sender: NSStatusBarButton) {
        if panel.isVisible {
            closePanel()
        } else {
            showPanel(relativeTo: sender)
        }
    }
    
    private func showPanel(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        
        // Refresh accessibility state before measuring so banner hides/shows accurately
        JigglerEngine.shared.hasAccessibilityPermission = AXIsProcessTrusted()
        
        // Let SwiftUI compute exact fitting size (including whether the Accessibility banner is visible)
        hostingController.view.layoutSubtreeIfNeeded()
        let fittingSize = hostingController.view.fittingSize
        let panelWidth: CGFloat = max(650, fittingSize.width)
        let panelHeight: CGFloat = max(320, fittingSize.height)
        
        let buttonFrameInScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main ?? NSScreen.screens.first!
        let visibleFrame = screen.visibleFrame
        
        // Center horizontally under the status bar icon, clamped inside the screen's visible horizontal bounds
        var x = round(buttonFrameInScreen.midX - (panelWidth / 2))
        let minX = visibleFrame.minX + 10
        let maxX = visibleFrame.maxX - panelWidth - 10
        x = max(minX, min(x, maxX))
        
        // Compute exact horizontal offset of the status bar icon relative to the panel's left edge so the top pointer caret points right at the icon!
        PanelGeometryModel.shared.arrowX = buttonFrameInScreen.midX - x
        
        // Position right below the menu bar so the pointer caret touches the bottom of the menu bar
        var y = round(buttonFrameInScreen.minY - panelHeight - 2)
        if y < visibleFrame.minY + 10 {
            y = visibleFrame.minY + 10
        }
        if y + panelHeight > visibleFrame.maxY - 2 {
            y = visibleFrame.maxY - panelHeight - 2
        }
        
        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        panel.invalidateShadow()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            Task { @MainActor in
                AppDelegate.sharedInstance?.closePanel()
            }
        }
        
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 { // Escape key closes panel
                Task { @MainActor in
                    AppDelegate.sharedInstance?.closePanel()
                }
                return nil
            }
            return event
        }
    }
    
    private func closePanel() {
        panel.orderOut(nil)
        if let gm = globalClickMonitor {
            NSEvent.removeMonitor(gm)
            globalClickMonitor = nil
        }
        if let lm = localKeyMonitor {
            NSEvent.removeMonitor(lm)
            localKeyMonitor = nil
        }
    }
    
    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let engine = JigglerEngine.shared
        
        let symbolName = engine.isEnabled ? "computermouse.fill" : "computermouse"
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "GhostMouse")?.withSymbolConfiguration(config) {
            if engine.isEnabled {
                img.isTemplate = false
                let tint: NSColor = (engine.isPausedForUserActivity || engine.isWaitingForSchedule) ? .systemOrange : .systemGreen
                button.image = tintImage(img, with: tint)
            } else {
                img.isTemplate = true
                button.image = img
            }
        }
    }
    
    private func tintImage(_ image: NSImage, with color: NSColor) -> NSImage {
        let tinted = image.copy() as! NSImage
        tinted.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: tinted.size)
        rect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.isTemplate = false
        return tinted
    }
}
