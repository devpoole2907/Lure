import SwiftUI

struct CastShelfCell: View {
    let item: CastShelfItem

    var body: some View {
        Group {
        #if os(tvOS)
        VStack(spacing: 6) {
            portrait

            // The labels size naturally so a one-line name doesn't leave a
            // reserved-height gap above the role; the outer fixed frame keeps
            // cells uniform when a name wraps to two lines.
            VStack(spacing: 2) {
                Text(item.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)

                Text(item.role ?? "")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .multilineTextAlignment(.center)
            .frame(width: 180, alignment: .top)
        }
        .frame(width: 180, height: 280, alignment: .top)
        #else
        VStack(spacing: 4) {
            portrait

            VStack(spacing: 1) {
                Text(item.name)
                    .font(.caption)
                    .lineLimit(2)

                if let role = item.role {
                    Text(role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .multilineTextAlignment(.center)
            .frame(width: 76, alignment: .top)
        }
        .frame(width: 76, alignment: .top)
        #endif
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var portrait: some View {
        AsyncImage(url: item.profileURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Circle()
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                }
        }
        #if os(tvOS)
        .frame(width: 150, height: 150)
        #else
        .frame(width: 56, height: 56)
        #endif
        .clipShape(Circle())
        .posterFocusHighlight(shape: Circle())
    }

    private var accessibilityLabel: String {
        guard let role = item.role else { return item.name }
        return "\(item.name), as \(role)"
    }
}
