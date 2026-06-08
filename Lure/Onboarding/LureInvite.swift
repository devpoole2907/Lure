import Foundation

/// A self-contained invitation that prefills both server connections so a
/// non-technical user can get set up by tapping one link (or pasting one code).
///
/// Encoded as a `lure://` deep link, e.g.
/// `lure://invite?s=https://requests.example.com&j=https://watch.example.com&n=Smith%20Family&u=grandpa`
///
/// - `s` / `seerr`     — Seerr base URL (required)
/// - `j` / `jellyfin`  — Jellyfin base URL (optional; adds in-app playback)
/// - `n` / `name`      — display name for the household/server (optional)
/// - `u` / `user`      — username to prefill on the sign-in screen (optional)
///
/// The legacy `lure://connect?url=<seerr>` link is still understood and maps to
/// a Seerr-only invite.
struct LureInvite: Equatable, Sendable, Identifiable {
    var seerrURL: String
    var jellyfinURL: String?
    var displayName: String?
    var username: String?

    /// Stable enough for `.sheet(item:)` / `.fullScreenCover(item:)` presentation.
    var id: String { "\(seerrURL)|\(jellyfinURL ?? "")" }

    var hasJellyfin: Bool {
        (jellyfinURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
    }

    // MARK: - Parsing

    /// Parse a `lure://invite` or legacy `lure://connect` deep link.
    static func parse(_ url: URL) -> LureInvite? {
        guard url.scheme?.lowercased() == "lure" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let host = (url.host ?? components.host)?.lowercased()

        func value(_ names: String...) -> String? {
            for name in names {
                if let match = components.queryItems?.first(where: { $0.name == name })?.value {
                    let trimmed = match.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
            return nil
        }

        switch host {
        case "invite":
            guard let seerr = value("s", "seerr") else { return nil }
            return LureInvite(
                seerrURL: seerr,
                jellyfinURL: value("j", "jellyfin"),
                displayName: value("n", "name"),
                username: value("u", "user")
            )
        case "connect":
            guard let seerr = value("url", "s", "seerr") else { return nil }
            return LureInvite(seerrURL: seerr, jellyfinURL: nil, displayName: nil, username: nil)
        default:
            return nil
        }
    }

    /// Parse a pasted invite. Accepts a full `lure://invite?...` string.
    static func parse(pasted text: String) -> LureInvite? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        return parse(url)
    }
}
