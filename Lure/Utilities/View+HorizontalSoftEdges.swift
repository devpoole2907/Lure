import SwiftUI

private struct HorizontalSoftEdgesModifier: ViewModifier {
    var edgeWidth: CGFloat

    func body(content: Content) -> some View {
        content.mask {
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [.clear, .black],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: edgeWidth)

                Rectangle()
                    .fill(.black)

                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: edgeWidth)
            }
        }
    }
}

extension View {
    func horizontalSoftEdges(edgeWidth: CGFloat = 18) -> some View {
        modifier(HorizontalSoftEdgesModifier(edgeWidth: edgeWidth))
    }
}

#if DEBUG && os(iOS)
#Preview("Horizontal Soft Edges — iPadOS", traits: .fixedLayout(width: 1024, height: 1366)) {
    VStack(alignment: .leading, spacing: 14) {
        Text("Trending")
            .font(.title2.bold())

        HStack(spacing: 14) {
            ForEach(0..<8) { index in
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.indigo.gradient)
                    .frame(width: 140, height: 200)
                    .overlay {
                        Text("\(index + 1)")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: 620, alignment: .leading)
        .horizontalSoftEdges(edgeWidth: 36)
    }
    .padding()
}
#endif
