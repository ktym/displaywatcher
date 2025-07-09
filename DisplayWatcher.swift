import Foundation
import IOKit
import IOKit.graphics

class DisplayObserver {
    private var notifyPort: IONotificationPortRef?
    private var addedIter: io_iterator_t = 0
    private var removedIter: io_iterator_t = 0

    init() {
        startMonitoring()
    }

    deinit {
        stopMonitoring()
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

    private func stopMonitoring() {
        if let port = notifyPort {
            IONotificationPortDestroy(port)
        }
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
        print("Display connected")
        // Execute displayplacer after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            applyDisplayplacer()
        }
    }

    static func deviceDisconnected() {
        print("Display disconnected")
        // Apply configuration when display is disconnected if needed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            applyDisplayplacer()
        }
    }

    static func applyDisplayplacer() {
        guard let displayplacerCommand = loadCommand() else {
            print("No displayplacer command found")
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", displayplacerCommand]

        do {
            try task.run()
            print("Displayplacer command executed")
        } catch {
            print("Failed to execute displayplacer: \(error)")
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
CFRunLoopRun()