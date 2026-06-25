import AppKit

/// Opens a command in Terminal without using AppleScript/Automation (which a
/// self-distributed, unsigned app can't use without the user granting TCC
/// permission). We write a temporary executable `.command` file and open it
/// directly in Terminal.app via NSWorkspace.
func openInTerminal(_ command: String) {
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("pingmaster-\(UUID().uuidString).command")
    let script = "#!/bin/bash\nclear\nexec \(command)\n"
    do {
        try script.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([file], withApplicationAt: terminal,
                                configuration: NSWorkspace.OpenConfiguration())
    } catch {
        NSWorkspace.shared.open(file)  // fall back to default handler
    }
}
