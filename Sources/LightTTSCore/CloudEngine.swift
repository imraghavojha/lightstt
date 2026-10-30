import Foundation
import AVFoundation
import AudioToolbox
import Security

public enum CloudProvider: String, Codable, CaseIterable, Sendable {
    case groq, gemini, elevenlabs, compatible
    public var title: String { switch self { case .groq: return "Groq"; case .gemini: return "Google Gemini"; case .elevenlabs: return "ElevenLabs"; case .compatible: return "OpenAI-compatible" } }
    public var models: [String] { switch self { case .groq: return ["whisper-large-v3", "whisper-large-v3-turbo"]; case .gemini: return ["gemini-3.8-flash", "gemini-2.5-flash"]; case .elevenlabs: return ["scribe_v2"]; case .compatible: return [] } }
    public var environmentKey: String { switch self { case .groq: return "GROQ_API_KEY"; case .gemini: return "GEMINI_API_KEY"; case .elevenlabs: return "ELEVENLABS_API_KEY"; case .compatible: return "OPENAI_COMPATIBLE_API_KEY" } }
}

public enum CloudKeychain {
    private static let service = "com.lighttts.cloud-stt"
    private static func query(_ id: String) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id, kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail] }
    public static func save(_ key: String, id: String) throws {
        guard !key.isEmpty, !key.contains("\n"), !key.contains("\r") else { throw SpeechError.model("Enter a valid API key.") }
        let data = Data(key.utf8); let q = query(id)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = q; item[kSecValueData as String] = data; item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw SpeechError.model("Could not save the API key in Keychain.") }
        } else if status != errSecSuccess { throw SpeechError.model("Could not update the API key in Keychain.") }
    }
    public static func read(id: String) throws -> String {
        var q = query(id); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { throw SpeechError.model("API key unavailable in Keychain. Add it in Models.") }
        return key
    }
    public static func remove(id: String) throws { let s = SecItemDelete(query(id) as CFDictionary); guard s == errSecSuccess || s == errSecItemNotFound else { throw SpeechError.model("Could not remove the API key from Keychain.") } }
}

