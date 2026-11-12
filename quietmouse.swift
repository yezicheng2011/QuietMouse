// Quiet Mouse — tap-to-click for the Magic Mouse (menu bar app).
//
// A light tap on the left half of the mouse surface sends a left click; a tap on the
// right half sends a right click. Physical presses keep working through macOS itself
// (a tap that coincides with a physical press is ignored, so you never get a double click).
//
// Build:  ./build.sh   (produces QuietMouse.app)
// Debug:  QuietMouse.app/Contents/MacOS/QuietMouse --debug [--flip] | --list

import Foundation
import CoreGraphics
import ApplicationServices
import AppKit
import ServiceManagement

// MARK: - Tunables

let maxTapDuration = 0.25        // seconds a finger may stay down and still count as a tap
let maxTouchTravel: Float = 0.05 // normalized surface units the finger may drift
let maxCursorTravel: CGFloat = 5 // points the pointer may move during the tap
let physicalClickGrace = 0.12    // a physical press this long before the touch cancels the tap
let clickDebounce = 0.05         // ignore taps this soon after a synthesized click
let selfMarker: Int64 = 0x514D   // tags events we post so we do not mistake them for physical ones

let args = Set(CommandLine.arguments.dropFirst())
let debug = args.contains("--debug")
let flip = args.contains("--flip")
var tapEnabled = true

func log(_ s: @autoclosure () -> String) {
    if debug { print(s()); fflush(stdout) }
}

// MARK: - MultitouchSupport (private framework)

struct MTPoint { var x: Float; var y: Float }
struct MTReadout { var pos: MTPoint; var vel: MTPoint }
struct MTFinger {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32          // 3 = make touch, 4 = touching, 5 = break touch
    var fingerId: Int32
    var handId: Int32
    var normalized: MTReadout // pos.x / pos.y in 0...1
    var size: Float
    var pressure: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var mm: MTReadout
    var unused: (Int32, Int32)
    var density: Float
}

typealias MTDeviceRef = UnsafeMutableRawPointer
typealias MTContactCallback = @convention(c) (MTDeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

guard let mtHandle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW) else {
    fputs("quietmouse: cannot load MultitouchSupport\n", stderr); exit(1)
}
func mtSym<T>(_ name: String, _ type: T.Type) -> T {
    guard let p = dlsym(mtHandle, name) else { fputs("quietmouse: missing \(name)\n", stderr); exit(1) }
    return unsafeBitCast(p, to: T.self)
}
let MTDeviceCreateList = mtSym("MTDeviceCreateList", (@convention(c) () -> Unmanaged<CFArray>?).self)
let MTRegisterContactFrameCallback = mtSym("MTRegisterContactFrameCallback", (@convention(c) (MTDeviceRef, MTContactCallback) -> Void).self)
let MTDeviceStart = mtSym("MTDeviceStart", (@convention(c) (MTDeviceRef, Int32) -> Void).self)
let MTDeviceGetDeviceID = mtSym("MTDeviceGetDeviceID", (@convention(c) (MTDeviceRef, UnsafeMutablePointer<UInt64>) -> Int32).self)
let MTDeviceIsBuiltIn = mtSym("MTDeviceIsBuiltIn", (@convention(c) (MTDeviceRef) -> Bool).self)
let MTDeviceGetDimensions = mtSym("MTDeviceGetSensorSurfaceDimensions",
                                  (@convention(c) (MTDeviceRef, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32).self)

/// The Magic Mouse sensor is taller than it is wide; trackpads are the opposite.
func isMouse(_ dev: MTDeviceRef) -> Bool {
    var w: Int32 = 0, h: Int32 = 0
    _ = MTDeviceGetDimensions(dev, &w, &h)
    return !MTDeviceIsBuiltIn(dev) && h > w
}

// MARK: - Settings

/// Where the right-click zone starts, as a fraction of the mouse width (System Settings → Mouse).
func rightZoneStart() -> Float {
    let domain = "com.apple.AppleMultitouchMouse" as CFString
    if let mode = CFPreferencesCopyAppValue("MouseButtonMode" as CFString, domain) as? String, mode != "TwoButton" {
        return 2 // one-button mode: every tap is a left click
    }
    if let div = CFPreferencesCopyAppValue("MouseButtonDivision" as CFString, domain) as? Int {
        return Float(div) / 100
    }
    return 0.5
}

// MARK: - Physical click tracking

let stateLock = NSLock()
var lastPhysicalDown = -1000.0
var lastSynthClick = -1000.0
var lastClickTime = -1000.0
var lastClickPoint = CGPoint.zero
var clickCount: Int64 = 0

func now() -> Double { ProcessInfo.processInfo.systemUptime }

let tapCallback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = eventTap { CGEvent.tapEnable(tap: t, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    if event.getIntegerValueField(.eventSourceUserData) != selfMarker {
        stateLock.lock(); lastPhysicalDown = now(); stateLock.unlock()
        log("physical press")
    }
    return Unmanaged.passUnretained(event)
}
var eventTap: CFMachPort?

// MARK: - Click synthesis

func postClick(right: Bool) {
    let loc = CGEvent(source: nil)?.location ?? .zero
    stateLock.lock()
    let t = now()
    if t - lastSynthClick < clickDebounce { stateLock.unlock(); return }
    lastSynthClick = t
    // Count quick repeat taps in the same spot as a double / triple click.
    let interval = 0.4
    if !right, t - lastClickTime < interval, hypot(loc.x - lastClickPoint.x, loc.y - lastClickPoint.y) < 6 {
        clickCount += 1
    } else {
        clickCount = 1
    }
    lastClickTime = t
    lastClickPoint = loc
    let count = right ? 1 : clickCount
    stateLock.unlock()

    let src = CGEventSource(stateID: .hidSystemState)
    let (downType, upType, button): (CGEventType, CGEventType, CGMouseButton) =
        right ? (.rightMouseDown, .rightMouseUp, .right) : (.leftMouseDown, .leftMouseUp, .left)
    func make(_ type: CGEventType) -> CGEvent? {
        let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: loc, mouseButton: button)
        e?.setIntegerValueField(.eventSourceUserData, value: selfMarker)
        e?.setIntegerValueField(.mouseEventClickState, value: count)
        return e
    }
    make(downType)?.post(tap: .cghidEventTap)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) {
        make(upType)?.post(tap: .cghidEventTap)
    }
}

// MARK: - Tap detection

final class TapState {
    var prevCount = 0
    var active = false
    var cancelled = false
    var startTime = 0.0
    var startX: Float = 0
    var startY: Float = 0
    var travel: Float = 0
    var cursorStart = CGPoint.zero
}
var states: [UnsafeMutableRawPointer: TapState] = [:]

func finishTap(_ st: TapState) {
    defer { st.active = false; st.cancelled = false }
    let t = now()
    let duration = t - st.startTime
    let cursor = CGEvent(source: nil)?.location ?? .zero
    let moved = hypot(cursor.x - st.cursorStart.x, cursor.y - st.cursorStart.y)
    stateLock.lock(); let physical = lastPhysicalDown; stateLock.unlock()

    var reason = "ok"
    if st.cancelled { reason = "multi-finger" }
    else if duration > maxTapDuration { reason = "too long (\(Int(duration * 1000)) ms)" }
    else if st.travel > maxTouchTravel { reason = "finger moved" }
    else if moved > maxCursorTravel { reason = "pointer moved" }
    else if physical >= st.startTime - physicalClickGrace { reason = "physical press" }

    var x = st.startX
    if flip { x = 1 - x }
    let right = x >= rightZoneStart()
    log("tap x=\(String(format: "%.2f", st.startX)) \(right ? "RIGHT" : "LEFT") -> \(reason)")
    guard reason == "ok", tapEnabled else { return }
    DispatchQueue.main.async { postClick(right: right) }
}

let contactCallback: MTContactCallback = { device, fingers, count, _, _ in
    guard let device = device else { return 0 }
    stateLock.lock()
    let st: TapState
    if let s = states[device] { st = s } else { st = TapState(); states[device] = st }
    stateLock.unlock()

    var touching: [MTFinger] = []
    if let raw = fingers {
        let fingers = raw.assumingMemoryBound(to: MTFinger.self)
        for i in 0..<Int(count) where fingers[i].state == 3 || fingers[i].state == 4 {
            touching.append(fingers[i])
        }
    }
    let n = touching.count
    if debug && n > 0 && !st.active {
        log("frame: \(n) finger(s), states \(touching.map { $0.state }), x=\(touching.map { String(format: "%.2f", $0.normalized.pos.x) })")
    }

    if n == 0 {
        if st.active { finishTap(st) }
    } else if n == 1 && st.prevCount == 0 && !st.active {
        let f = touching[0]
        st.active = true
        st.cancelled = false
        st.startTime = now()
        st.startX = f.normalized.pos.x
        st.startY = f.normalized.pos.y
        st.travel = 0
        st.cursorStart = CGEvent(source: nil)?.location ?? .zero
    } else if n > 1 {
        if st.active { st.cancelled = true }
    } else if st.active {
        let f = touching[0]
        let d = max(abs(f.normalized.pos.x - st.startX), abs(f.normalized.pos.y - st.startY))
        st.travel = max(st.travel, d)
    }
    st.prevCount = n
    return 0
}

// MARK: - Device management

var registeredIDs = Set<UInt64>()

/// MTDeviceCreateList hands back fresh refs on every call, so devices are tracked by ID.
/// A mouse that drops off the list (sleep, Bluetooth reconnect) is registered again when it returns.
func scanDevices() {
    guard let list = MTDeviceCreateList()?.takeRetainedValue() else { return }
    var present = Set<UInt64>()
    for i in 0..<CFArrayGetCount(list) {
        guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
        let dev = UnsafeMutableRawPointer(mutating: raw)
        if args.contains("--list") {
            var w: Int32 = 0, h: Int32 = 0
            _ = MTDeviceGetDimensions(dev, &w, &h)
            print("device \(i): builtIn=\(MTDeviceIsBuiltIn(dev)) size=\(w)x\(h) mouse=\(isMouse(dev))")
        }
        guard isMouse(dev) else { continue }
        var id: UInt64 = 0
        _ = MTDeviceGetDeviceID(dev, &id)
        present.insert(id)
        guard !registeredIDs.contains(id) else { continue }
        registeredIDs.insert(id)
        _ = Unmanaged<AnyObject>.fromOpaque(dev).retain() // keep the device alive after the list is released
        MTRegisterContactFrameCallback(dev, contactCallback)
        MTDeviceStart(dev, 0)
        log("listening on Magic Mouse \(String(id, radix: 16))")
    }
    registeredIDs.formIntersection(present)
}

// MARK: - Event tap for physical presses

func installEventTap() {
    guard eventTap == nil else { return }
    let mask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue)
        | (1 << CGEventType.otherMouseDown.rawValue)
    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                      eventsOfInterest: mask, callback: tapCallback, userInfo: nil) else { return }
    eventTap = tap
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
}

// MARK: - Menu bar app

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let toggleItem = NSMenuItem(title: "Tap to Click", action: #selector(toggleTap), keyEquivalent: "")
    let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
    let permItem = NSMenuItem(title: "Grant Permissions…", action: #selector(openPermissions), keyEquivalent: "")

    func applicationDidFinishLaunching(_ note: Notification) {
        tapEnabled = UserDefaults.standard.object(forKey: "tapEnabled") as? Bool ?? true

        statusItem.button?.image = menuBarGlyph()
        applyAppIcon()
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in self?.applyAppIcon() }
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(toggleItem)
        menu.addItem(permItem)
        menu.addItem(.separator())
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Quiet Mouse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        statusItem.menu = menu

        if !AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) {
            log("needs Accessibility permission")
        }
        if !CGPreflightListenEventAccess() { CGRequestListenEventAccess() }

        installEventTap()
        scanDevices()
        updateIcon()
        // Pick up the mouse after sleep/reconnect, and the event tap once permission is granted.
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            scanDevices(); installEventTap()
        }
    }

    var permissionsOK: Bool { AXIsProcessTrusted() && CGPreflightListenEventAccess() }

    func menuNeedsUpdate(_ menu: NSMenu) {
        toggleItem.state = tapEnabled ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        permItem.isHidden = permissionsOK
    }

    /// Template image, so macOS tints it for light/dark menu bars automatically.
    func menuBarGlyph() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()
            let body = NSBezierPath(roundedRect: NSRect(x: 4.5, y: 1.5, width: 9, height: 15), xRadius: 4.5, yRadius: 4.5)
            body.lineWidth = 1.4
            body.stroke()
            NSBezierPath(ovalIn: NSRect(x: 6.2, y: 10.2, width: 2.6, height: 2.6)).fill()
            let arc = NSBezierPath()
            arc.appendArc(withCenter: NSPoint(x: 7.5, y: 11.5), radius: 4.2, startAngle: 20, endAngle: 160)
            arc.lineWidth = 1.1
            arc.stroke()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Quiet Mouse"
        return img
    }

    /// Dock / alert icon follows the system appearance (Finder shows the light icon).
    func applyAppIcon() {
        let dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        let name = dark ? "Logo-Dark" : "Logo-Light"
        if let url = Bundle.main.url(forResource: name, withExtension: "png"), let img = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = img
        }
    }

    func updateIcon() {
        statusItem.button?.appearsDisabled = !tapEnabled
    }

    @objc func toggleTap() {
        tapEnabled.toggle()
        UserDefaults.standard.set(tapEnabled, forKey: "tapEnabled")
        updateIcon()
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Open at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nTry moving Quiet Mouse into the Applications folder first."
            alert.runModal()
        }
    }

    @objc func openPermissions() {
        let pane = AXIsProcessTrusted() ? "Privacy_ListenEvent" : "Privacy_Accessibility"
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }
}

// MARK: - Main

if args.contains("--list") { scanDevices(); exit(0) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
