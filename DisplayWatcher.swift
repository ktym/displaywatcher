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
    private var isProcessingChange = false
    private var preferredBuiltinResolution: (width: Int, height: Int)? = nil
    private var restorationCompleted = false

    struct DisplayState {
        let displayID: CGDirectDisplayID
        let width: Int
        let height: Int
        let refreshRate: Double
        let pixelWidth: Int
        let pixelHeight: Int
    }

    init() {
        loadPreferredBuiltinResolution()
        startMonitoring()
        startCGMonitoring()
    }

    deinit {
        stopMonitoring()
        stopCGMonitoring()
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
        isProcessingChange = true
        restorationCompleted = false
        print("Display change detected. Scheduling aggressive restoration of built-in display resolution.")
        let maxAttempts = 90
        let interval: TimeInterval = 2.0
        for attempt in 0..<maxAttempts {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(attempt)) {
                if self.restorationCompleted {
                    if attempt == maxAttempts - 1 {
                        self.isProcessingChange = false
                    }
                    return
                }
                print("[Aggressive] Built-in display restoration attempt \(attempt + 1)/\(maxAttempts)")
                let restored = self.restoreBuiltinDisplayResolution()
                if restored {
                    self.restorationCompleted = true
                    self.isProcessingChange = false
                    print("Restoration successful. No further attempts needed.")
                } else if attempt == maxAttempts - 1 {
                    self.isProcessingChange = false
                    print("Restoration attempts finished. Resolution may not have been restored.")
                }
            }
        }
    }

    private func restoreBuiltinDisplayResolution() -> Bool {
        guard let preferred = preferredBuiltinResolution else {
            print("No preferred built-in display resolution set.")
            return false
        }
        guard let builtinID = getBuiltinDisplayID() else {
            print("No built-in display found.")
            return false
        }
        guard let currentMode = CGDisplayCopyDisplayMode(builtinID) else {
            print("Could not get current mode for built-in display.")
            return false
        }
        if currentMode.width == preferred.width && currentMode.height == preferred.height {
            print("Built-in display already at preferred resolution: \(preferred.width)x\(preferred.height)")
            return true
        }
        print("Restoring built-in display to preferred resolution: \(preferred.width)x\(preferred.height)")
        guard let modes = CGDisplayCopyAllDisplayModes(builtinID, nil) else {
            print("Could not get available modes for built-in display.")
            return false
        }
        let modeCount = CFArrayGetCount(modes)
        var bestMode: CGDisplayMode?
        for i in 0..<modeCount {
            let mode = unsafeBitCast(CFArrayGetValueAtIndex(modes, i), to: CGDisplayMode.self)
            if mode.width == preferred.width && mode.height == preferred.height {
                bestMode = mode
                break
            }
        }
        guard let targetMode = bestMode else {
            print("Preferred resolution mode not found for built-in display.")
            return false
        }
        let config = CGDisplaySetDisplayMode(builtinID, targetMode, nil)
        if config == .success {
            print("Built-in display resolution restored: \(preferred.width)x\(preferred.height)")
            return true
        } else {
            print("Failed to restore built-in display resolution: \(config)")
            return false
        }
    }

    private func handleDisplayAddition() {
        isProcessingChange = true

        // Wait briefly, then attempt multiple restoration attempts
        let delays = [0.1, 0.3, 0.5, 1.0, 2.0]

        for (index, delay) in delays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                print("Restoration attempt \(index + 1)/\(delays.count)")
                // self.restoreAllDisplayStates() // Removed

                if index == delays.count - 1 {
                    self.isProcessingChange = false
                }
            }
        }
    }

    // Removed: restoreAllDisplayStates

    // Remove any code that references displayStates, lastDisplayCount, or the removed methods

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

    private func loadPreferredBuiltinResolution() {
        // Read preferred resolution from config file
        let fileManager = FileManager.default
        let appSupportDir = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DisplayWatcher")
        let configPath = appSupportDir.appendingPathComponent("displaywatcher.conf")
        if fileManager.fileExists(atPath: configPath.path) {
            do {
                let contents = try String(contentsOf: configPath, encoding: .utf8)
                let lines = contents.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                    let parts = trimmed.split(separator: "x")
                    if parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) {
                        preferredBuiltinResolution = (width: w, height: h)
                        print("Preferred built-in display resolution loaded: \(w)x\(h)")
                        return
                    }
                }
                print("No valid resolution found in displaywatcher.conf")
            } catch {
                print("Failed to read displaywatcher.conf: \(error)")
            }
        } else {
            print("displaywatcher.conf not found: \(configPath.path)")
        }
    }

    private func getBuiltinDisplayID() -> CGDirectDisplayID? {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        if displayCount > 0 {
            let displays = UnsafeMutablePointer<CGDirectDisplayID>.allocate(capacity: Int(displayCount))
            defer { displays.deallocate() }
            CGGetActiveDisplayList(displayCount, displays, &displayCount)
            for i in 0..<Int(displayCount) {
                let displayID = displays[i]
                if CGDisplayIsBuiltin(displayID) != 0 {
                    return displayID
                }
            }
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