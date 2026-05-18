import Foundation

enum ConnectionsStore {
    private static let key = "ecswizard.connections"

    static func load() -> [Connection] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Connection].self, from: data)
        else { return [] }
        return list
    }

    static func save(_ connections: [Connection]) {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
