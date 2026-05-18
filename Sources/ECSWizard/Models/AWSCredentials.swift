import Foundation
import SwiftUI

enum ConnectionColor: String, Codable, CaseIterable {
    case red, orange, yellow, green, blue, purple, pink, gray

    var color: Color {
        switch self {
        case .red:    return Color(red: 0.90, green: 0.20, blue: 0.20)
        case .orange: return Color.orange
        case .yellow: return Color(red: 0.85, green: 0.70, blue: 0.00)
        case .green:  return Color(red: 0.15, green: 0.70, blue: 0.30)
        case .blue:   return Color.blue
        case .purple: return Color.purple
        case .pink:   return Color.pink
        case .gray:   return Color.gray
        }
    }
}

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
    var emoji: String = "🔵"
    var color: ConnectionColor = .blue

    enum CodingKeys: String, CodingKey {
        case id, name, credentials, region, emoji, color
    }

    init(id: UUID = UUID(), name: String, credentials: AWSCredentials, region: String,
         emoji: String = "🔵", color: ConnectionColor = .blue) {
        self.id = id; self.name = name; self.credentials = credentials
        self.region = region; self.emoji = emoji; self.color = color
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(UUID.self,           forKey: .id)
        name        = try c.decode(String.self,         forKey: .name)
        credentials = try c.decode(AWSCredentials.self, forKey: .credentials)
        region      = try c.decode(String.self,         forKey: .region)
        emoji       = try c.decodeIfPresent(String.self,          forKey: .emoji) ?? "🔵"
        color       = try c.decodeIfPresent(ConnectionColor.self, forKey: .color) ?? .blue
    }
}
