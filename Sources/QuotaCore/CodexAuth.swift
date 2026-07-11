import Foundation

public enum CodexAuth {
    public static func load(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Credentials {
        let base = environment["CODEX_HOME"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex")
        let data = try Data(contentsOf: base.appending(path: "auth.json"), options: .mappedIfSafe)
        guard data.count <= 262_144,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        let tokens = root["tokens"] as? [String: Any] ?? root
        guard let token = (tokens["access_token"] ?? tokens["accessToken"]) as? String, !token.isEmpty else { throw CocoaError(.fileReadNoPermission) }
        let account = (tokens["account_id"] ?? tokens["accountId"]) as? String ?? accountID(from: token)
        return Credentials(accessToken: token, accountID: account)
    }

    private static func accountID(from token: String) -> String? {
        guard let part = token.split(separator: ".").dropFirst().first,
              let data = Data(base64Encoded: String(part).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + String(repeating: "=", count: (4 - part.count % 4) % 4)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["https://api.openai.com/auth.chatgpt_account_id"] as? String ?? json["chatgpt_account_id"] as? String
    }
}
