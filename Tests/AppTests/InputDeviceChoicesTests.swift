import XCTest

@testable import LightTTS

final class InputDeviceChoicesTests: XCTestCase {
    func testSystemDefaultAppearsOnceAsFollowDefaultChoice() {
        let builtIn = InputDevice(id: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone")
        let usb = InputDevice(id: "usb-1", name: "USB Mic")
        let choices = InputDevice.choices(available: [builtIn, usb], systemDefault: builtIn)
        XCTAssertEqual(choices.map(\.id), ["", "usb-1"])
        XCTAssertEqual(choices.map(\.name), ["MacBook Pro Microphone", "USB Mic"])
    }

    func testCoreAudioPrivateAggregatesAreHidden() {
        XCTAssertTrue(
            InputDevice.isHiddenSystemDevice(
                uid: "CADefaultDeviceAggregate-1234-5", name: "CADefaultDeviceAggregate-1234-5"))
        XCTAssertTrue(
            InputDevice.isHiddenSystemDevice(uid: "VPAUAggregateAudioDevice-0x1", name: "x"))
        XCTAssertFalse(
            InputDevice.isHiddenSystemDevice(
                uid: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone"))
    }
}
