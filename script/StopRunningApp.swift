import AppKit
import Foundation

// Request normal application termination. Never escalate to forceTerminate or SIGKILL.
let bundleIdentifier = "com.tomorrowpet.desktop"
let applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
for application in applications {
    guard application.terminate() else {
        fputs("Could not request a normal quit. Close Tomorrow Pet and retry.\n", stderr)
        exit(1)
    }
}
let deadline = Date().addingTimeInterval(10)
while applications.contains(where: { !$0.isTerminated }) && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
}
guard applications.allSatisfy(\.isTerminated) else {
    fputs("Tomorrow Pet has not quit. Finish any pending dialog and retry; no process was forced to stop.\n", stderr)
    exit(1)
}
