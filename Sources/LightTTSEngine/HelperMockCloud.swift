#if DEBUG
import Foundation
import LightTTSCore
final class HelperMockCloudProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, request.httpMethod == "POST" else { fputs("Mock missing request\n", stderr); client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }; var buffer = [UInt8](repeating: 0, count: 8192)
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; body.append(contentsOf: buffer.prefix(count)) }
        }
        if url.host == "offline.invalid" { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        if url.host == "timeout.invalid" { client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return }
        if url.host == "auth.invalid" { let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!; client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: Data("{}".utf8)); client?.urlProtocolDidFinishLoading(self); return }
        let expectedKey = "unit-test-key"
        let payload: String
        if url.host == "generativelanguage.googleapis.com" {
            guard url.path == "/v1beta/models/\(CloudProvider.gemini.models[0]):generateContent", request.value(forHTTPHeaderField: "x-goog-api-key") == expectedKey, let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any], let contents = obj["contents"] as? [[String: Any]], let parts = contents.first?["parts"] as? [[String: Any]], let audio = parts.last?["inline_data"] as? [String: Any], let encoded = audio["data"] as? String, let bytes = Data(base64Encoded: encoded), bytes.range(of: Data("ftyp".utf8)) != nil else { fputs("Mock request validation failed\n", stderr); client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
            payload = "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"ok\"}]}}]}"
        } else {
            let field = url.host == "api.elevenlabs.io" ? "xi-api-key" : "Authorization"
            let expected = field == "xi-api-key" ? expectedKey : "Bearer " + expectedKey
            guard request.value(forHTTPHeaderField: field) == expected, body.range(of: Data("ftyp".utf8)) != nil, body.range(of: Data("multipart/form-data".utf8)) == nil, request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true else { fputs("Mock request validation failed\n", stderr); client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
            payload = "{\"text\":\"ok\"}"
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: Data(payload.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
