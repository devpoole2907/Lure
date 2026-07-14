import Foundation

struct CastShelfItem: Identifiable, Hashable {
    let id: String
    let name: String
    let role: String?
    let profileURL: URL?
    let destination: CastPersonRoute

    init(
        id: String,
        name: String,
        role: String?,
        profileURL: URL?,
        destination: CastPersonRoute
    ) {
        self.id = id
        self.name = name
        self.role = role?.nilIfBlank
        self.profileURL = profileURL
        self.destination = destination
    }

    init(_ member: SeerrCastMember) {
        let destination = CastPersonRoute(member: member)
        self.init(
            id: "seerr-\(destination.id)-\(member.character ?? "no-role")",
            name: member.name?.nilIfBlank ?? "Unknown",
            role: member.character,
            profileURL: member.profileURL,
            destination: destination
        )
    }

    init(person: JellyfinPerson, profileURL: URL?) {
        let destination = CastPersonRoute(
            personId: nil,
            fallbackName: person.name,
            fallbackProfileURL: profileURL
        )
        self.init(
            id: "jellyfin-\(person.id)",
            name: person.name?.nilIfBlank ?? "Unknown",
            role: person.role,
            profileURL: profileURL,
            destination: destination
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
