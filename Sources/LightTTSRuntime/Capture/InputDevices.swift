public struct InputDeviceDescriptor: Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

@MainActor
public protocol InputDevicesProviding: AnyObject {
    func devices() async -> [InputDeviceDescriptor]
}
