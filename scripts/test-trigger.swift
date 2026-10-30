// For a debug app: swift scripts/test-trigger.swift <pid> <hid|toggle>
import AppKit
import Foundation
let args = CommandLine.arguments
precondition(args.count == 3 && Int32(args[1]) != nil && ["hid", "toggle"].contains(args[2]))
if let target = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first {
    target.activate(options: [.activateIgnoringOtherApps])
    usleep(200_000)
}
DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.lighttts.test.\(args[2]).\(args[1])"), object: nil, userInfo: nil, deliverImmediately: true)
