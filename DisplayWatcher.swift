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
            { (refcon, iterator) in DisplayObserver.deviceChanged() },
            nil,
            &addedIter
        )

        IOServiceAddMatchingNotification(
            notifyPort!,
            kIOTerminatedNotification,
            matchingDict,
            { (refcon, iterator) in DisplayObserver.deviceChanged() },
            nil,
            &removedIter
        )

        DisplayObserver.deviceChanged()
    }

    private func stopMonitoring() {
        if let port = notifyPort {
            IONotificationPortDestroy(port)
        }
    }

    static func deviceChanged() {
        print("Display change detected")
        applyDisplayplacer()
    }

    static func applyDisplayplacer() {
        guard let displayplacerCommand = loadCommand() else {
            print("No displayplacer command found")
            return
        }
        let task = Process()
        task.launchPath = "/bin/zsh"
        task.arguments = ["-c", displayplacerCommand]
        task.launch()
    }

    static func loadCommand() -> String? {
        let fileManager = FileManager.default
        let appSupportDir = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DisplayWatcher")
        let configPath = appSupportDir.appendingPathComponent("displaywatcher.conf").path
        if fileManager.fileExists(atPath: configPath) {
            do {
                let contents = try String(contentsOfFile: configPath, encoding: .utf8)
                return contents.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                print("Failed to read configuration file: \(error)")
            }
        } else {
            print("Configuration file not found: \(configPath)")
        }
        return nil
    }
}

let observer = DisplayObserver()
CFRunLoopRun()
