import Foundation

/// Legacy SSH host profile used for one-time migration from old storage keys.
struct SSHHostProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int,
        username: String
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
    }
}
