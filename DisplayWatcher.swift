import Foundation
import IOKit
import IOKit.graphics
import CoreGraphics

class DisplayObserver {
    private var notifyPort: IONotificationPortRef?
    private var addedIter: io_iterator_t = 0
    private var removedIter: io_iterator_t = 0
    private var cgNotificationCallback: CGDisplayReconfigurationCallBack?
    private var debounceTimer: Timer?
    private var lastDisplayCount: Int = 0

    init() {
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
            nil,
            &addedIter
        )

        IOServiceAddMatchingNotification(
            notifyPort!,
            kIOTerminatedNotification,
            matchingDict,
            displayDisconnectedCallback,
            nil,
            &removedIter
        )

        // Consume iterators during initialization
        DisplayObserver.consumeIterator(addedIter)
        DisplayObserver.consumeIterator(removedIter)
    }

    private func startCGMonitoring() {
        cgNotificationCallback = { (display, flags, userInfo) in
            if flags.contains(.setModeFlag) || flags.contains(.addFlag) || flags.contains(.removeFlag) {
                let observer = Unmanaged<DisplayObserver>.fromOpaque(userInfo!).takeUnretainedValue()
                observer.handleDisplayChange()
            }
        }

        let observer = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback(cgNotificationCallback!, observer)
        lastDisplayCount = getCurrentDisplayCount()
    }

    private func stopMonitoring() {
        if let port = notifyPort {
            IONotificationPortDestroy(port)
        }
    }

    private func stopCGMonitoring() {
        if let callback = cgNotificationCallback {
            CGDisplayUnregisterReconfigurationCallback(callback, Unmanaged.passUnretained(self).toOpaque())
        }
    }

    private func getCurrentDisplayCount() -> Int {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        return Int(displayCount)
    }

    private func handleDisplayChange() {
        let currentDisplayCount = getCurrentDisplayCount()
        // Cancel previous timer
        debounceTimer?.invalidate()
        // Only apply settings if display count changed
        if currentDisplayCount != lastDisplayCount {
            print("Display count changed from \(lastDisplayCount) to \(currentDisplayCount)")
            lastDisplayCount = currentDisplayCount
            // Use longer delay and retry mechanism
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                self.applyDisplayplacerWithRetry()
            }
        }
    }

    private func applyDisplayplacerWithRetry() {
        let maxRetries = 3
        var attempt = 0
        func attemptApply() {
            attempt += 1
            print("Applying displayplacer (attempt \(attempt)/\(maxRetries))")
            if DisplayObserver.applyDisplayplacer() {
                print("Successfully applied displayplacer")
            } else if attempt < maxRetries {
                // Retry after 1 second
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    attemptApply()
                }
            } else {
                print("Failed to apply displayplacer after \(maxRetries) attempts")
            }
        }
        attemptApply()
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
}

func displayDisconnectedCallback(refcon: UnsafeMutableRawPointer?, iterator: io_iterator_t) {
    DisplayObserver.consumeIterator(iterator)
    DisplayObserver.deviceDisconnected()
}

let observer = DisplayObserver()
print("DisplayWatcher started. Monitoring display changes...")
CFRunLoopRun()