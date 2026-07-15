import SwiftUI

struct CastShelfView: View {
    let items: [CastShelfItem]
    var onSelect: ((CastShelfItem) -> Void)?

    init(items: [CastShelfItem], onSelect: ((CastShelfItem) -> Void)? = nil) {
        self.items = items
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            Label("Cast", systemImage: "person.2")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.top, headerTopPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: itemSpacing) {
                    ForEach(items) { item in
                        #if os(tvOS)
                        // A value-based destination keeps nested cast/media
                        // navigation in the correct stack order on tvOS.
                        NavigationLink(value: item.destination) {
                            CastShelfCell(item: item)
                        }
                        .buttonStyle(TVPosterFocusButtonStyle())
                        #else
                        if onSelect != nil {
                            Button {
                                select(item)
                            } label: {
                                CastShelfCell(item: item)
                            }
                            .buttonStyle(.plain)
                        } else {
                            CastShelfCell(item: item)
                        }
                        #endif
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, shelfVerticalPadding)
            }
            #if os(tvOS)
            .clipShape(Rectangle())
            #else
            .horizontalSoftEdges()
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
        #if os(tvOS)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        #endif
    }

    private func select(_ item: CastShelfItem) {
        onSelect?(item)
    }

    private var sectionSpacing: CGFloat {
        #if os(tvOS)
        10
        #else
        4
        #endif
    }

    private var headerTopPadding: CGFloat {
        #if os(tvOS)
        14
        #else
        10
        #endif
    }

    private var itemSpacing: CGFloat {
        #if os(tvOS)
        36
        #else
        12
        #endif
    }

    private var shelfVerticalPadding: CGFloat {
        #if os(tvOS)
        18
        #else
        8
        #endif
    }
}

#if DEBUG && os(iOS)
#Preview("Cast Shelf — iPad", traits: .fixedLayout(width: 1024, height: 1366)) {
    CastShelfView(items: [
        CastShelfItem(
            id: "preview-1",
            name: "Maya Chen",
            role: "Detective Rowan",
            profileURL: nil,
            destination: CastPersonRoute(personId: 1, fallbackName: "Maya Chen", fallbackProfileURL: nil)
        ),
        CastShelfItem(
            id: "preview-2",
            name: "Theo Williams",
            role: "Elias",
            profileURL: nil,
            destination: CastPersonRoute(personId: 2, fallbackName: "Theo Williams", fallbackProfileURL: nil)
        )
    ])
    .padding()
    .background(Color.black)
}
#endif
