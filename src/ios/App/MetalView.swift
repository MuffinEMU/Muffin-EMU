import SwiftUI
import MetalKit
#if os(iOS)
import UIKit
#endif

/// Plain `UIView` has no bounds-changed notification, so `layoutSubviews()` tells `DisplayRouter`
/// when the container settles into a new size (rotation, iPad Split View / Slide Over resize).
final class DeviceContainerView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        DisplayRouter.shared.deviceContainerDidLayout(self)
    }
}

struct MetalViewIOS: UIViewRepresentable {
    var gameManager: GameManager

    // Returns a plain container view; the view the C++ renderer draws into is
    // DisplayRouter.shared.tvRenderView, added as a subview. That lets DisplayRouter move the
    // TV screen between this device and an external display without destroying its CAMetalLayer.
    //
    // Plain UIView, not MTKView: MTKView would make its own layer an active CAMetalLayer, and
    // the C++ renderer's CAMetalLayer sublayer would then compete with it.
    func makeUIView(context: Context) -> UIView {
        // Returns the same container every time (see DisplayRouter.sharedDeviceContainer()).
        let container = DisplayRouter.shared.sharedDeviceContainer()

        // Arm display detection before registering, so a display connected at launch and one
        // plugged in later take the same path. Registering the surface starts the boot
        // (see GameManager.registerRenderSurface).
        DisplayRouter.shared.startObserving()
        DisplayRouter.shared.attach(deviceContainer: container)
        DisplayRouter.shared.registerSurfaces(with: gameManager)

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Fallback if makeUIView's registration didn't take; both calls are idempotent.
        DisplayRouter.shared.attach(deviceContainer: uiView)
        DisplayRouter.shared.registerSurfaces(with: gameManager)
    }
}

/// `MetalViewIOS`'s pad-screen equivalent (see `DisplayRouter.attachLocalPadContainer` /
/// `localPadContainerDidLayout`). Mounted by `EmulatorViewOptimized` when `ScreenLayout` shows
/// the GamePad screen on this device and `DisplayRouter.placement` is not `.dualScreen`. Safe to
/// mount and unmount repeatedly: `makeUIView()` returns the container `DisplayRouter` caches
/// (`sharedLocalPadContainer()`).
final class PadContainerView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        DisplayRouter.shared.localPadContainerDidLayout(self)
    }
}

struct PadMetalViewIOS: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let container = DisplayRouter.shared.sharedLocalPadContainer()
        DisplayRouter.shared.attachLocalPadContainer(container)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DisplayRouter.shared.attachLocalPadContainer(uiView)
    }
}

#if os(macOS)
struct MetalView: NSViewRepresentable {
    var gameManager: GameManager

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        guard let device = MTLCreateSystemDefaultDevice() else {
            return view
        }
        view.device = device
        view.delegate = context.coordinator
        view.preferredFramesPerSecond = 60
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.gameManager = gameManager
    }

    func makeCoordinator() -> MetalRenderer {
        return MetalRenderer(gameManager: gameManager)
    }
}
#endif

class MetalRenderer: NSObject, MTKViewDelegate {
    var gameManager: GameManager
    private var commandQueue: MTLCommandQueue?

    init(gameManager: GameManager) {
        self.gameManager = gameManager
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let device = view.device else { return }

        if commandQueue == nil {
            commandQueue = device.makeCommandQueue()
        }
        guard let commandBuffer = commandQueue?.makeCommandBuffer() else { return }

        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        descriptor.colorAttachments[0].loadAction = .clear

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        if let frameTexture = gameManager.getFrameTexture() {
            let viewSize = view.bounds.size
            renderTextureToScreen(frameTexture, encoder: renderEncoder, viewSize: viewSize, device: device)
        }

        renderEncoder.endEncoding()

        if let drawable = drawable as? CAMetalDrawable {
            commandBuffer.present(drawable)
        }

        commandBuffer.commit()
    }

    private func renderTextureToScreen(_ texture: MTLTexture, encoder: MTLRenderCommandEncoder, viewSize: CGSize, device: MTLDevice) {
        let quad = createScreenQuad(viewSize: viewSize)

        let vertexBuffer = device.makeBuffer(bytes: quad, length: MemoryLayout<Float>.size * quad.count, options: [])

        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(texture, index: 0)

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }

    private func createScreenQuad(viewSize: CGSize) -> [Float] {
        let aspectRatio = Float(viewSize.width / viewSize.height)
        let targetAspect: Float = 1280.0 / 720.0

        var quad = [Float]()

        let scale: Float
        if aspectRatio > targetAspect {
            scale = Float(viewSize.height) / 720.0
        } else {
            scale = Float(viewSize.width) / 1280.0
        }

        let width = 1280.0 * scale / Float(viewSize.width)
        let height = 720.0 * scale / Float(viewSize.height)

        quad.append(-width)
        quad.append(height)
        quad.append(-width)
        quad.append(-height)
        quad.append(width)
        quad.append(-height)

        quad.append(-width)
        quad.append(height)
        quad.append(width)
        quad.append(-height)
        quad.append(width)
        quad.append(height)

        return quad
    }
}
