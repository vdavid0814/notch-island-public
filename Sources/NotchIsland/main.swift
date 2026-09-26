import Darwin
import NotchIslandKit

// The allocator's space-efficient mode: freed memory goes back to the system instead of staying
// with the app for reuse. Measured (release build): 19 MB at rest instead of 25–28, 46 MB after a
// tour of Settings instead of ~90, the Settings pages 20–30 MB smaller while open. The allocator
// reads it only at launch, so it comes from the environment: Info.plist's LSEnvironment when
// LaunchServices starts the app, and otherwise the app sets it and starts itself over once (same
// process, before anything else has run).
if getenv("MallocSpaceEfficient") == nil {
    setenv("MallocSpaceEfficient", "1", 1)
    let path = CommandLine.unsafeArgv[0]
    if let path { execv(path, CommandLine.unsafeArgv) }
    // exec failed: carry on without it.
}

NotchIslandApp.main()
