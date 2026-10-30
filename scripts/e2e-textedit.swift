import AppKit
import ApplicationServices
import Foundation
// Preflight in the same process that sends Apple events; never request consent.
let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.TextEdit")
let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
guard status == noErr else { fputs("TextEdit automation permission is required (status \(status)).\n", stderr); exit(1) }
let scripts = [
    "new": "tell application \"TextEdit\" to make new document\ntell application \"TextEdit\" to activate",
    "text": "tell application \"TextEdit\" to get text of front document",
    "close": "tell application \"TextEdit\" to close front document saving no",
    "quit": "tell application \"TextEdit\" to quit saving no"
]
guard CommandLine.arguments.count == 2, let source = scripts[CommandLine.arguments[1]], let script = NSAppleScript(source: source) else { exit(2) }
var error: NSDictionary?
let result = script.executeAndReturnError(&error)
if let error { fputs("TextEdit automation failed: \(error)\n", stderr); exit(1) }
if let value = result.stringValue { print(value) }
