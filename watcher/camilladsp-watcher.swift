import CoreAudio
import Foundation

let syncScript = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/camilladsp/sync-audio.sh").path

func runSync() {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
    proc.arguments = [syncScript]
    do {
        try proc.run()
        proc.waitUntilExit()
    } catch {
        fputs("camilladsp-watcher: failed to run sync-audio.sh: \(error)\n", stderr)
    }
}

var pendingWork: DispatchWorkItem?

func scheduleSync(delay: TimeInterval) {
    pendingWork?.cancel()
    let item = DispatchWorkItem { runSync() }
    pendingWork = item
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
}

var address = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDevices,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
)

let status = AudioObjectAddPropertyListenerBlock(
    AudioObjectID(kAudioObjectSystemObject),
    &address,
    DispatchQueue.main
) { _, _ in
    scheduleSync(delay: 1.0)
}

if status != noErr {
    fputs("camilladsp-watcher: AudioObjectAddPropertyListenerBlock failed (\(status))\n", stderr)
    exit(1)
}

fputs("camilladsp-watcher: started CoreAudio device listener.\n", stderr)
scheduleSync(delay: 0.2)
dispatchMain()
