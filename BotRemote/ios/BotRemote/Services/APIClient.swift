import Foundation

/// HTTPS calls: complete pairing and unpair. Everything else uses Socket.IO.
enum APIClient {
    /// https is mandatory; plain http is only accepted for local development hosts.
    static func normalizedOrigin(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var comps = URLComponents(string: trimmed), let scheme = comps.scheme?.lowercased(),
              let host = comps.host?.lowercased(), comps.user == nil, comps.password == nil else {
            throw RemoteError(code: "BAD_URL", message: "Invalid server URL")
        }
        let local = host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local")
        guard scheme == "https" || (scheme == "http" && local) else {
            throw RemoteError(code: "BAD_URL", message: "The server URL must use https://")
        }
        comps.path = ""; comps.query = nil; comps.fragment = nil
        guard let url = comps.url else { throw RemoteError(code: "BAD_URL", message: "Invalid server URL") }
        return url
    }

    private static func request(_ url: URL, path: String, body: [String: String]?, bearer: String? = nil) async throws -> Data {
        var req = URLRequest(url: url.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body ?? [:])
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw RemoteError(code: "NETWORK", message: "No response") }
        guard (200..<300).contains(http.statusCode) else {
            if let e = try? JSONDecoder().decode(APIErrorBody.self, from: data) {
                throw RemoteError(code: e.error.code, message: e.error.message)
            }
            throw RemoteError(code: "HTTP_\(http.statusCode)", message: "Server error (\(http.statusCode))")
        }
        return data
    }

    static func completePairing(origin: URL, code: String, deviceName: String) async throws -> PairResponse {
        let data = try await request(origin, path: "api/pair/complete", body: ["code": code, "deviceName": deviceName])
        return try JSONDecoder().decode(PairResponse.self, from: data)
    }

    static func unpair(origin: URL, token: String) async throws {
        _ = try await request(origin, path: "api/phone/unpair", body: nil, bearer: token)
    }
}
