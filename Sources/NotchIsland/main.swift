import Darwin
import Foundation
import MachO
import NotchIslandKit

// Read by the system libraries only at launch, so they come from the environment: Info.plist's
// LSEnvironment when LaunchServices starts the app; otherwise the app sets them and starts itself
// over once (same process, before anything else has run).
//
// - MallocSpaceEfficient: the allocator's space-efficient mode. Freed memory goes back to the
//   system instead of staying with the app for reuse. Measured (release build): 19 MB at rest
//   instead of 25–28, 46 MB after a tour of Settings instead of ~90, the Settings pages 20–30 MB
//   smaller while open.
// - RB_DISABLE_GPU: SwiftUI's own renderer (RenderBox) draws on the CPU. It draws only what Core
//   Animation cannot — symbol effects, the Liquid Glass knobs of native controls — and each time
//   one appeared it set up a Metal context of ~40 MB for a second or two (every volume key press,
//   every banner with a bouncing symbol, ~80 MB more while Settings opened). On the CPU: the same
//   pixels (screenshots compared), the same or less CPU for those moments, no GPU time.
// Started as the screen recorder (`RecordingHelper`): it records, and quits once the movie is
// written; the app itself does not start.
RecordingHelper.runIfAsked()
// Started by launchd as the fan helper (`FanHelper`, root): it sets the fans for Fan Control and
// quits when idle; the app itself does not start.
FanHelper.runIfAsked()

let environment = ["MallocSpaceEfficient": "1", "RB_DISABLE_GPU": "1"]
if environment.keys.contains(where: { getenv($0) == nil }) {
    for (name, value) in environment { setenv(name, value, 1) }
    // The executable's own path (argv[0] may be relative or a bare name).
    var size = UInt32(PATH_MAX)
    var path = [CChar](repeating: 0, count: Int(size))
    if _NSGetExecutablePath(&path, &size) == 0 { execv(path, CommandLine.unsafeArgv) }
    // exec failed: carry on without them.
}

// macOS 27's AppKit offers every window of an app to Spotlight (window and tab search) whenever
// its windows change: for the island that is every opening and closing, three items each time,
// which Spotlight's knowledge daemon then works through at the app's expense (~90 mJ billed per
// hover opening, 70 % of what an opening cost; measured with `Scripts/perf/serviced.py`). The
// island's panels are not windows anyone looks for; AppKit's own switch leaves them out.
UserDefaults.standard.register(defaults: ["NSEnableWindowTabIndexing": false])

NotchIslandApp.main()
