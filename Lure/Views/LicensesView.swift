import SwiftUI

struct LicensesView: View {
    var body: some View {
        List {
            licenseSection(
                title: "AetherEngine",
                license: "GNU Lesser General Public License v2.1",
                url: "https://github.com/superuser404notfound/AetherEngine"
            )
            licenseSection(
                title: "FFmpegBuild",
                license: "GNU Lesser General Public License v2.1",
                url: "https://github.com/superuser404notfound/FFmpegBuild"
            )
            licenseSection(
                title: "dav1d",
                license: "BSD 2-Clause License",
                url: "https://code.videolan.org/videolan/dav1d"
            )
        }
        .lureNavigationTitle("Open Source Licenses")
#if os(iOS) || os(visionOS)
        .listStyle(.insetGrouped)
#endif
    }

    private func licenseSection(title: String, license: String, url: String) -> some View {
        Section(title) {
            LabeledContent("License", value: license)
            if let dest = URL(string: url) {
                Link(destination: dest) {
                    HStack {
                        Text("Source Code")
                        Spacer()
                        Image(systemName: "arrow.up.forward.square")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            }
        }
    }
}
