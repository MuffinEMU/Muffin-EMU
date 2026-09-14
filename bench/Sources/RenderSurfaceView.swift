//
//  RenderSurfaceView.swift
//  The one on-screen CAMetalLayer-backed view every engine's mbench_attach_surface
//  targets. A single instance lives for the whole run and is handed to all three
//  engines in turn - MuffinBenchEngine.h attaches by raw UIView pointer, so recreating
//  the view between engines would mean re-registering something none of them have ever
//  seen, for no benefit, since no engine owns the view itself, only draws into its layer.
//
import SwiftUI
import UIKit

/// Overriding `+layerClass` is what makes `.layer` a `CAMetalLayer` instead of a plain
/// `CALayer` - this is the only way UIKit lets a view's backing layer be swapped for a
/// different CALayer subclass; setting `.layer` directly is not possible.
final class MetalSurfaceView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
}

struct RenderSurfaceView: UIViewRepresentable {
    let runner: BenchRunner

    func makeUIView(context: Context) -> MetalSurfaceView {
        let view = MetalSurfaceView()
        view.backgroundColor = .black
        runner.renderView = view
        return view
    }

    func updateUIView(_ uiView: MetalSurfaceView, context: Context) {
        // Idempotent: re-assigning the same view on every SwiftUI update is harmless,
        // and cheap insurance against BenchView being recreated before a run starts.
        runner.renderView = uiView
    }
}
