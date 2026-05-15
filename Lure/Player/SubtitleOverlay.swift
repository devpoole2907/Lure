import SwiftUI
import AetherEngine

/// Renders active subtitle cues over the video layer.
/// Handles both text (SubRip / ASS / WebVTT) and bitmap (PGS / DVB) cues.
/// The position is given in [0, 1] normalised coordinates against the video
/// frame; this view scales them to the actual on-screen video rect.
struct SubtitleOverlay: View {
    let vm: PlayerViewModel

    private var activeCues: [SubtitleCue] {
        let t = vm.currentTime
        return vm.subtitleCues.filter { $0.startTime <= t && t < $0.endTime }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if vm.isSubtitleActive {
                    if vm.isLoadingSubtitles {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, 80)
                    } else {
                        ForEach(activeCues) { cue in
                            cueView(cue, in: geo.size)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func cueView(_ cue: SubtitleCue, in size: CGSize) -> some View {
        switch cue.body {
        case .text(let text):
            textCue(text, size: size)
        case .image(let img):
            imageCue(img, in: size)
        }
    }

    private func textCue(_ text: String, size: CGSize) -> some View {
        Text(text)
            .font(.system(size: clamp(size.width * 0.04, min: 14, max: 26)))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .shadow(color: .black, radius: 2, x: 1, y: 1)
            .shadow(color: .black, radius: 2, x: -1, y: -1)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 4))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 88)
            .padding(.horizontal, 20)
            .accessibilityLabel(text)
    }

    private func imageCue(_ img: SubtitleImage, in size: CGSize) -> some View {
        let rect = CGRect(
            x: img.position.minX * size.width,
            y: img.position.minY * size.height,
            width: img.position.width * size.width,
            height: img.position.height * size.height
        )
        return Image(decorative: img.cgImage, scale: 1)
            .resizable()
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .accessibilityHidden(true)
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(max, value))
    }
}
