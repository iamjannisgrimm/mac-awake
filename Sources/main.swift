import AppKit
import Foundation

enum AwakeState: Equatable {
    case enabled, disabled, unknown

    static func parse(_ output: String, exitCode: Int32) -> AwakeState {
        guard exitCode == 0, output.contains("System-wide power settings:") else { return .unknown }
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            if fields.first == "SleepDisabled" {
                guard fields.count == 2 else { return .unknown }
                switch fields[1] {
                case "1": return .enabled
                case "0": return .disabled
                default: return .unknown
                }
            }
        }
        // pmset omits this system-wide key until an override has been saved.
        return .disabled
    }

    var label: String {
        switch self {
        case .enabled: return "Keep Awake: On"
        case .disabled: return "Keep Awake: Off"
        case .unknown: return "Keep Awake: Unknown"
        }
    }
}

struct CommandResult: Sendable {
    let code: Int32
    let output: String
}

func command(_ executable: String, _ arguments: [String]) async -> CommandResult {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: CommandResult(
                    code: process.terminationStatus,
                    output: String(decoding: data, as: UTF8.self)))
            } catch {
                continuation.resume(returning: CommandResult(code: -1, output: error.localizedDescription))
            }
        }
    }
}

@MainActor
final class AwakeApp: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var timer: Timer?
    private var state = AwakeState.unknown
    private var busy = false
    private var refreshing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: "com.jannisgrimm.mac-awake")
        if peers.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }
        render()
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
    }

    private func readState() async -> AwakeState {
        let result = await command("/usr/bin/pmset", ["-g"])
        return AwakeState.parse(result.output, exitCode: result.code)
    }

    private func refresh() async {
        guard !refreshing, !busy else { return }
        refreshing = true
        let current = await readState()
        refreshing = false
        guard !busy else { return }
        state = current
        render()
    }

    private func render() {
        guard let button = item?.button else { return }
        let symbol: String
        if busy { symbol = "hourglass" }
        else {
            switch state {
            case .enabled: symbol = "sun.max.fill"
            case .disabled: symbol = "moon"
            case .unknown: symbol = "questionmark.circle"
            }
        }
        let label = busy ? "Keep Awake: Changing…" : state.label
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.image?.isTemplate = true
        button.title = busy ? " …" : (state == .enabled ? " On" : state == .disabled ? " Off" : " ?")
        button.toolTip = "\(label)\nClick to toggle. Right-click for options."
        button.setAccessibilityLabel(label)
        button.setAccessibilityHelp("Click to toggle keep-awake mode. Right-click for options.")
    }

    @objc private func woke() { Task { await refresh() } }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let heading = menu.addItem(withTitle: busy ? "Changing keep-awake mode…" : state.label, action: nil, keyEquivalent: "")
        heading.isEnabled = false
        let note = menu.addItem(withTitle: "Tracks the sleep override, not other apps", action: nil, keyEquivalent: "")
        note.isEnabled = false
        menu.addItem(.separator())
        let toggleItem = menu.addItem(withTitle: state == .enabled ? "Turn Keep Awake Off" : "Turn Keep Awake On", action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.isEnabled = !busy && state != .unknown
        let refreshItem = menu.addItem(withTitle: "Refresh Status", action: #selector(woke), keyEquivalent: "")
        refreshItem.target = self
        refreshItem.isEnabled = !busy
        menu.addItem(.separator())
        for (title, action) in [("Edit On Shortcut…", #selector(editOn)), ("Edit Off Shortcut…", #selector(editOff))] {
            let entry = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            entry.target = self
        }
        menu.addItem(.separator())
        let quitItem = menu.addItem(withTitle: "Quit Mac Awake (keeps current setting)", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.isEnabled = !busy
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func toggle() {
        guard !busy else { return }
        busy = true
        render()
        Task {
            let before = await readState()
            guard before != .unknown else {
                state = .unknown
                busy = false
                render()
                showError("Cannot read the Mac’s sleep setting. No shortcut was run.")
                return
            }
            let expected: AwakeState = before == .enabled ? .disabled : .enabled
            let shortcut = expected == .enabled ? "Keep Mac Awake On" : "Keep Mac Awake Off"
            let result = await command("/usr/bin/shortcuts", ["run", shortcut])
            state = await readState()
            busy = false
            render()
            if result.code != 0 {
                showError("\(shortcut) did not finish successfully.\n\n\(state.label)\n\n\(result.output.prefix(1500))")
            } else if state != expected {
                showError("The shortcut finished, but the requested sleep setting could not be confirmed.\n\n\(state.label)")
            }
        }
    }

    private func showError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Mac Awake"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func editOn() { edit("Keep Mac Awake On") }
    @objc private func editOff() { edit("Keep Mac Awake Off") }
    private func edit(_ name: String) {
        Task {
            let result = await command("/usr/bin/shortcuts", ["view", name])
            if result.code != 0 { showError(result.output) }
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

if CommandLine.arguments.contains("--self-test") {
    let header = "System-wide power settings:\n"
    precondition(AwakeState.parse(header + " SleepDisabled\t1\nCurrently in use:\n sleep 1", exitCode: 0) == .enabled)
    precondition(AwakeState.parse(header + " SleepDisabled 0", exitCode: 0) == .disabled)
    precondition(AwakeState.parse(header + "Currently in use:\n sleep 1", exitCode: 0) == .disabled)
    precondition(AwakeState.parse(header + " SleepDisabled 2", exitCode: 0) == .unknown)
    precondition(AwakeState.parse(header + " SleepDisabled 1", exitCode: 1) == .unknown)
    precondition(AwakeState.parse("command failed", exitCode: 0) == .unknown)
    print("Passed 6 state checks: on, off, unset, malformed, command failure, unexpected output.")
} else {
    MainActor.assumeIsolated {
        let application = NSApplication.shared
        let delegate = AwakeApp()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
