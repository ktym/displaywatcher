import Foundation
import IOKit
import IOKit.graphics
import CoreGraphics

class DisplayObserver {
    private var notifyPort: IONotificationPortRef?
    private var addedIter: io_iterator_t = 0
    private var removedIter: io_iterator_t = 0
    private var cgNotificationCallback: CGDisplayReconfigurationCallBack?
    private var quickTimer: Timer?
    private var lastDisplayCount: Int = 0
    private var displayStates: [CGDirectDisplayID: DisplayState] = [:]
    private var isProcessingChange = false

    struct DisplayState {
        let displayID: CGDirectDisplayID
        let width: Int
        let height: Int
        let refreshRate: Double
        let pixelWidth: Int
        let pixelHeight: Int
    }

    init() {
        captureInitialDisplayStates()
        startMonitoring()
        startCGMonitoring()
    }

    deinit {
        stopMonitoring()
        stopCGMonitoring()
    }

    private func captureInitialDisplayStates() {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)

        if displayCount > 0 {
            let displays = UnsafeMutablePointer<CGDirectDisplayID>.allocate(capacity: Int(displayCount))
            defer { displays.deallocate() }

            CGGetActiveDisplayList(displayCount, displays, &displayCount)

            for i in 0..<Int(displayCount) {
                let displayID = displays[i]
                if let state = getCurrentDisplayState(displayID) {
                    displayStates[displayID] = state
                    print("Record initial state: Display \(displayID) - \(state.width)x\(state.height)")
                }
            }
        }
        lastDisplayCount = Int(displayCount)
    }

    private func getCurrentDisplayState(_ displayID: CGDirectDisplayID) -> DisplayState? {
        let mode = CGDisplayCopyDisplayMode(displayID)
        guard let currentMode = mode else { return nil }

        return DisplayState(
            displayID: displayID,
            width: currentMode.width,
            height: currentMode.height,
            refreshRate: currentMode.refreshRate,
            pixelWidth: currentMode.pixelWidth,
            pixelHeight: currentMode.pixelHeight
        )
    }

    private func startMonitoring() {
        let matchingDict = IOServiceMatching("IODisplayConnect")
        notifyPort = IONotificationPortCreate(kIOMainPortDefault)
        let runLoopSource = IONotificationPortGetRunLoopSource(notifyPort!)?.takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)

        IOServiceAddMatchingNotification(
            notifyPort!,
            kIOMatchedNotification,
            matchingDict,
            displayConnectedCallback,
            Unmanaged.passUnretained(self).toOpaque(),
            &addedIter
        )

        IOServiceAddMatchingNotification(
            notifyPort!,
            kIOTerminatedNotification,
            matchingDict,
            displayDisconnectedCallback,
            Unmanaged.passUnretained(self).toOpaque(),
            &removedIter
        )

        // Consume iterators during initialization
        DisplayObserver.consumeIterator(addedIter)
        DisplayObserver.consumeIterator(removedIter)
    }

    private func startCGMonitoring() {
        cgNotificationCallback = { (display, flags, userInfo) in
            let observer = Unmanaged<DisplayObserver>.fromOpaque(userInfo!).takeUnretainedValue()
            observer.handleCGDisplayChange(display: display, flags: flags)
        }

        let observer = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback(cgNotificationCallback!, observer)
    }

    private func handleCGDisplayChange(display: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        guard !isProcessingChange else { return }

        if flags.contains(.setModeFlag) {
            print("Resolution change detected: Display \(display)")
            // Immediate response
            quickTimer?.invalidate()
            quickTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
                self.immediateRestore(for: display)
            }
        } else if flags.contains(.addFlag) {
            print("New display added: \(display)")
            handleDisplayAddition()
        } else if flags.contains(.removeFlag) {
            print("Display removed: \(display)")
            displayStates.removeValue(forKey: display)
        }
    }

    private func handleDisplayAddition() {
        isProcessingChange = true

        // Wait briefly, then attempt multiple restoration attempts
        let delays = [0.1, 0.3, 0.5, 1.0, 2.0]

        for (index, delay) in delays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                print("Restoration attempt \(index + 1)/\(delays.count)")
                self.restoreAllDisplayStates()

                if index == delays.count - 1 {
                    self.isProcessingChange = false
                }
            }
        }
    }

    private func immediateRestore(for displayID: CGDirectDisplayID) {
        guard let savedState = displayStates[displayID] else { return }

        print("Attempting immediate restoration: Display \(displayID)")

        // Get current state
        guard let currentState = getCurrentDisplayState(displayID) else { return }

        // Only restore if resolution has changed
        if currentState.width != savedState.width || currentState.height != savedState.height {
            print("Resolution change detected: \(currentState.width)x\(currentState.height) -> \(savedState.width)x\(savedState.height)")
            restoreDisplayState(displayID, to: savedState)
        }
    }

    private func restoreAllDisplayStates() {
        for (displayID, savedState) in displayStates {
            guard let currentState = getCurrentDisplayState(displayID) else { continue }

            if currentState.width != savedState.width || currentState.height != savedState.height {
                print("Restore: Display \(displayID) \(currentState.width)x\(currentState.height) -> \(savedState.width)x\(savedState.height)")
                restoreDisplayState(displayID, to: savedState)
            }
        }
    }

    private func restoreDisplayState(_ displayID: CGDirectDisplayID, to targetState: DisplayState) {
        // Get available modes
        guard let modes = CGDisplayCopyAllDisplayModes(displayID, nil) else { return }

        let modeCount = CFArrayGetCount(modes)
        var bestMode: CGDisplayMode?

        for i in 0..<modeCount {
            let mode = unsafeBitCast(CFArrayGetValueAtIndex(modes, i), to: CGDisplayMode.self)

            if mode.width == targetState.width && 
               mode.height == targetState.height &&
               mode.pixelWidth == targetState.pixelWidth &&
               mode.pixelHeight == targetState.pixelHeight {
                bestMode = mode
                break
            }
        }

        guard let targetMode = bestMode else {
            print("Target resolution mode not found")
            return
        }

        // Set resolution
        let config = CGDisplaySetDisplayMode(displayID, targetMode, nil)
        if config == .success {
            print("Resolution restored: \(targetState.width)x\(targetState.height)")
        } else {
            print("Resolution restoration failed: \(config)")
            // Fallback: use displayplacer
            fallbackToDisplayplacer()
        }
    }

    private func fallbackToDisplayplacer() {
        print("Fallback to displayplacer")
        DisplayObserver.applyDisplayplacer()
    }

    private func stopMonitoring() {
        if let port = notifyPort {
            IONotificationPortDestroy(port)
        }
    }

    private func stopCGMonitoring() {
        // Note: CoreGraphics doesn't provide unregister function
        // The callback will be automatically cleaned up when the process ends
        cgNotificationCallback = nil
    }

    private func getCurrentDisplayCount() -> Int {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        return Int(displayCount)
    }

    static func consumeIterator(_ iterator: io_iterator_t) {
        var service: io_service_t
        repeat {
            service = IOIteratorNext(iterator)
            if service != 0 {
                IOObjectRelease(service)
            }
        } while service != 0
    }

    static func deviceConnected() {
        print("Display connected (IOKit)")
    }

    static func deviceDisconnected() {
        print("Display disconnected (IOKit)")
    }

    @discardableResult
    static func applyDisplayplacer() -> Bool {
        guard let displayplacerCommand = loadCommand() else {
            print("No displayplacer command found")
            return false
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", displayplacerCommand]
        do {
            try task.run()
            task.waitUntilExit()
            let success = task.terminationStatus == 0
            if success {
                print("Displayplacer command executed successfully")
            } else {
                print("Displayplacer command failed with status: \(task.terminationStatus)")
            }
            return success
        } catch {
            print("Failed to execute displayplacer: \(error)")
            return false
        }
    }

    static func loadCommand() -> String? {
        let fileManager = FileManager.default
        let appSupportDir = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DisplayWatcher")
        let configPath = appSupportDir.appendingPathComponent("displaywatcher.conf")
        if fileManager.fileExists(atPath: configPath.path) {
            do {
                let contents = try String(contentsOf: configPath, encoding: .utf8)
                return contents.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                print("Failed to read configuration file: \(error)")
            }
        } else {
            print("Configuration file not found: \(configPath.path)")
        }
        return nil
    }
}

// Callback functions
func displayConnectedCallback(refcon: UnsafeMutableRawPointer?, iterator: io_iterator_t) {
    DisplayObserver.consumeIterator(iterator)
    DisplayObserver.deviceConnected()

    if let refcon = refcon {
        let _ = Unmanaged<DisplayObserver>.fromOpaque(refcon).takeUnretainedValue()
        // Additional connection handling can be added here
    }
}

func displayDisconnectedCallback(refcon: UnsafeMutableRawPointer?, iterator: io_iterator_t) {
    DisplayObserver.consumeIterator(iterator)
    DisplayObserver.deviceDisconnected()
}

let observer = DisplayObserver()
print("DisplayWatcher started. Monitoring display changes...")
CFRunLoopRun()