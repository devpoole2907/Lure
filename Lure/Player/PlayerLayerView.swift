import SwiftUI
import UIKit
import AVFoundation
import QuartzCore
import AetherEngine

/// Wraps AetherEngine's video layer in a UIView so it integrates with
/// SwiftUI. The engine replaces its display layer on every `load()` call;
/// `onVideoLayerReplaced` keeps the host view in sync without rebuilding
/// the UIViewRepresentable.
struct PlayerLayerView: UIViewRepresentable {
    let engine: AetherEngine

    func makeUIView(context: Context) -> ContainerView {
        let view = ContainerView()
        #if DEBUG
        print("[PlayerLayerView] makeUIView bounds=\(view.bounds) layer=\(Self.describe(layer: engine.videoLayer))")
        #endif
        Self.addLayer(engine.videoLayer, to: view)
        engine.onVideoLayerReplaced = { [weak view] newLayer in
            guard let view else { return }
            #if DEBUG
            print("[PlayerLayerView] onVideoLayerReplaced old=\(view.engineLayer.map(Self.describe(layer:)) ?? "nil") new=\(Self.describe(layer: newLayer)) viewBounds=\(view.bounds) window=\(view.window != nil)")
            #endif
            view.engineLayer?.removeFromSuperlayer()
            Self.addLayer(newLayer, to: view)
        }
        return view
    }

    func updateUIView(_ uiView: ContainerView, context: Context) {}

    private static func addLayer(_ layer: CALayer, to view: ContainerView) {
        // SwiftUI can host this view before presentation layout has settled.
        // Force layout before reading bounds so the first decoded frame is not
        // submitted to a zero-sized display layer.
        view.setNeedsLayout()
        view.layoutIfNeeded()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        CATransaction.commit()
        view.engineLayer = layer
        #if DEBUG
        print("[PlayerLayerView] addLayer frame=\(layer.frame) viewBounds=\(view.bounds) sublayers=\(view.layer.sublayers?.count ?? 0) window=\(view.window != nil) layer=\(Self.describe(layer: layer))")
        #endif
    }

    #if DEBUG
    nonisolated private static func describe(layer: CALayer) -> String {
        let id = ObjectIdentifier(layer).hashValue
        if let displayLayer = layer as? AVSampleBufferDisplayLayer {
            let status: String
            switch displayLayer.status {
            case .unknown: status = "unknown"
            case .rendering: status = "rendering"
            case .failed: status = "failed"
            @unknown default: status = "?"
            }
            return "id=\(id) frame=\(displayLayer.frame) status=\(status) ready=\(displayLayer.isReadyForMoreMediaData) error=\(displayLayer.error?.localizedDescription ?? "nil")"
        }
        return "id=\(id) frame=\(layer.frame)"
    }
    #endif

    final class ContainerView: UIView {
        var engineLayer: CALayer?
        #if DEBUG
        private var lastLoggedBounds: CGRect = .null
        #endif

        override func layoutSubviews() {
            super.layoutSubviews()
            engineLayer?.frame = bounds
            #if DEBUG
            if bounds != lastLoggedBounds {
                lastLoggedBounds = bounds
                print("[PlayerLayerView] layoutSubviews bounds=\(bounds) layerFrame=\(engineLayer?.frame ?? .zero) window=\(window != nil)")
            }
            #endif
        }
    }
}
