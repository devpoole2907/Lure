import AetherEngine

extension TrackInfo {
    /// Human-readable track label, e.g. "English · 5.1 · AC3".
    var displayLabel: String {
        var parts: [String] = []
        if !name.isEmpty {
            parts.append(name)
        } else if let lang = language, !lang.isEmpty {
            parts.append(lang.uppercased())
        } else {
            parts.append("Track \(id)")
        }
        if isAtmos {
            parts.append("Atmos")
        } else if channels == 6 {
            parts.append("5.1")
        } else if channels == 8 {
            parts.append("7.1")
        }
        if !codec.isEmpty {
            parts.append(codec.uppercased())
        }
        return parts.joined(separator: " · ")
    }
}
