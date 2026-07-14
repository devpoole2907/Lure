#if os(macOS)
import SwiftUI

struct MacSidebarProfileButton: View {
    let currentUser: SeerrUser
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                AsyncImage(url: currentUser.avatarURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .foregroundStyle(.secondary)
                }
                .frame(width: 28, height: 28)
                .clipShape(Circle())
                .accessibilityHidden(true)

                Text(profileTitle)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Open profile for \(profileTitle)")
    }

    private var profileTitle: String {
        let candidates = [
            currentUser.username,
            currentUser.jellyfinUsername,
            currentUser.plexUsername,
            currentUser.discordUsername,
            currentUser.displayNameValue
        ]

        for candidate in candidates {
            if let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return "Profile"
    }
}
#endif
