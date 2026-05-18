import Foundation

struct AWSCredentials: Codable {
    let accessKeyId: String
    let secretAccessKey: String
    let sessionToken: String?

    static func parse(from text: String) -> AWSCredentials? {
        guard
            let keyId = extractValue(for: "AWS_ACCESS_KEY_ID", in: text),
            let secret = extractValue(for: "AWS_SECRET_ACCESS_KEY", in: text)
        else { return nil }
        let token = extractValue(for: "AWS_SESSION_TOKEN", in: text)
        return AWSCredentials(accessKeyId: keyId, secretAccessKey: secret, sessionToken: token)
    }

    // Matches: export KEY="value", export KEY=value, KEY="value", KEY=value
    private static func extractValue(for key: String, in text: String) -> String? {
        let pattern = key + #"[=\s]["']?([^"'\s\n]+)["']?"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }
}

struct Connection: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var credentials: AWSCredentials
    var region: String
}
