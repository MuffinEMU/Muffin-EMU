#include "Cafe/HW/Latte/Renderer/Metal/MetalLayer.h"

#include <TargetConditionals.h>

#if TARGET_OS_IOS

// iOS / UIKit path. Cemu's Metal renderer only needs a CAMetalLayer to draw into.
// `handle` is a UIView* supplied by the app shell (see src/ios). We back it with a
// CAMetalLayer sized to the view and return that layer.
#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>

void* CreateMetalLayer(void* handle, const Vector2i& sizeInPoints, float& scaleX, float& scaleY)
{
	UIView* view = (__bridge UIView*)handle;

	CAMetalLayer* metalLayer = [CAMetalLayer layer];

	// Frame comes from the caller-supplied size, NOT view.bounds: this runs
	// synchronously the instant the render surface is registered
	// (GameManager.registerRenderSurface, called from makeUIView), which is before
	// SwiftUI has necessarily laid the owning view out to a nonzero size -
	// view.bounds was frequently still CGRectZero here, producing a zero-sized,
	// invisible sublayer: correct rendering underneath, black screen on top.
	// Confirmed via live device test after the MetalLayerHandle double-release fix
	// (v1.9) eliminated the earlier crash and exposed this as the next blocker.
	// A CALayer frame is in POINTS, and sizeInPoints is already points, so it is
	// used as-is; contentsScale carries the points -> pixels conversion, and the
	// caller (MetalLayerHandle) applies it exactly once for setDrawableSize().
	// This used to be `sizeInPoints / scale` back when the iOS caller handed over
	// physical pixels - which left the drawable multiplied by the scale twice.
	// Nothing later re-syncs this frame either, since a manually-added sublayer
	// doesn't auto-resize with its superlayer - a future dynamic-resize path (e.g.
	// rotation, split view) will need to call back into this layer explicitly.
	const float scale = (float)view.contentScaleFactor;
	metalLayer.frame = CGRectMake(0, 0, sizeInPoints.x, sizeInPoints.y);
	metalLayer.contentsScale = scale;

	// A manually created CALayer has opaque = NO, unlike a UIView's own backing layer
	// (UIKit drives that from UIView.isOpaque, which defaults to YES). The macOS branch
	// below never meets this problem because there the CAMetalLayer IS a view's backing
	// layer, via MetalView's +layerClass.
	//
	// This is deliberately NOT being claimed as the black-screen fix: the output shader
	// Cemu blits a title's scanbuffer with (RendererOuputShader.cpp's copy shader)
	// writes vec4(rgb, 1.0), so a real frame is already fully opaque and composites the
	// same either way. What opaque = NO does change is every frame whose alpha is not 1
	// - which today is the ones this fork actually produces most: DrawEmptyFrame()'s
	// backbuffer, ClearColorbuffer()'s explicit a=0.0 clear, and anything drawn before
	// a title starts scanning out. Those blend against whatever is behind the layer
	// instead of covering it, so "presented an empty frame" and "presented nothing at
	// all" look identical on screen. Marking the layer opaque makes the presented
	// contents authoritative, and skips a full-screen per-pixel blend in the compositor
	// on top of that.
	metalLayer.opaque = YES;

	[view.layer addSublayer:metalLayer];

	// iOS reports the backing-store scale directly; width/height scale are equal.
	scaleX = scale;
	scaleY = scale;

	// Hand back a +1 reference, because ~MetalLayerHandle() unconditionally calls
	// m_layer->release() on whatever this returns. Everything above produces a +0
	// object: +[CAMetalLayer layer] is a convenience constructor (autoreleased), and
	// a __bridge cast transfers no ownership - so without this retain the handle's
	// destructor was releasing a reference it never owned. The only strong reference
	// left at that point belongs to view.layer (addSublayer: retains), so the release
	// dropped the layer to zero and deallocated it while it was still sitting in a
	// live view's sublayers array.
	//
	// That destructor is reachable, not theoretical: LatteThread_Exit()
	// (LatteThread.cpp:282) does `delete renderer` on every title shutdown, which
	// destroys MetalRenderer::m_mainLayer. The owning UIView deliberately outlives it
	// - GameManager.registerRenderSurface() passes it with Unmanaged.passRetained and
	// never balances that - so the freed layer stays reachable from Core Animation
	// afterwards, which is a use-after-free on the next compositing pass or the next
	// boot, not a crash confined to teardown. Stopping a title and starting another
	// is the ordinary way to hit it.
	//
	// CFRetain rather than -retain or CFBridgingRetain: this file is compiled without
	// ARC today (nothing adds -fobjc-arc), but it is written in ARC-compatible style,
	// and CFRetain with a __bridge cast is the one spelling that means the same thing
	// either way - CFBridgingRetain only exists under __has_feature(objc_arc), and
	// -retain is rejected under it.
	//
	// Deliberately NOT paired with a removeFromSuperlayer: the handle has no teardown
	// hook to call one from, so the dead layer lingers as a sublayer of a view that is
	// itself already leaked. That is a bounded, invisible leak of one offscreen layer
	// per title launch (the next launch builds a fresh view and layer), which is the
	// correct trade against a use-after-free.
	CFRetain((__bridge CFTypeRef)metalLayer);

	return (__bridge void*)metalLayer;
}

void ResizeMetalLayer(void* layer, const Vector2i& sizeInPoints, float scale)
{
	CAMetalLayer* metalLayer = (__bridge CAMetalLayer*)layer;
	if (!metalLayer)
		return;

	// Same units contract as CreateMetalLayer(): a CALayer frame is in POINTS, and
	// contentsScale carries the points -> pixels conversion. The drawable size is not
	// set here - MetalLayerHandle::ResizeWithScale() does that, exactly once, so the
	// scale is never applied twice (the bug fixed in 6488cc1d).
	metalLayer.frame = CGRectMake(0, 0, sizeInPoints.x, sizeInPoints.y);
	metalLayer.contentsScale = scale;
}

#else

// macOS / AppKit path (unchanged upstream behavior).
#include "Cafe/HW/Latte/Renderer/MetalView.h"

// `sizeInPoints` is unused here (deliberately - see below) but must stay in the
// signature: MetalLayer.h declares ONE CreateMetalLayer() prototype shared by both
// platform bodies below, and MetalLayerHandle.cpp (compiled for both iOS and macOS
// whenever ENABLE_METAL is on - see Cafe/CMakeLists.txt's unconditional
// `if(ENABLE_METAL)` block) calls it with the 4-argument form unconditionally. This
// branch used to take only (handle, scaleX, scaleY) - a leftover from before the
// iOS zero-size fix added the size to the shared declaration - which compiled fine
// in isolation but left the macOS build (ENABLE_METAL default-on for APPLE, see
// CMakeLists.txt, and actually built by build-macos in CI) with no definition
// matching the header's declared signature: a link error, not something caught by
// this file compiling on its own. macOS's actual sizing still comes from
// view.bounds/convertRectToBacking below, same as ever - (void) it to silence the
// unused-parameter warning without pretending it does anything here.
void* CreateMetalLayer(void* handle, const Vector2i& sizeInPoints, float& scaleX, float& scaleY)
{
	(void)sizeInPoints;
	NSView* view = (NSView*)handle;

	MetalView* childView = [[MetalView alloc] initWithFrame:view.bounds];
	childView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	childView.wantsLayer = YES;

	[view addSubview:childView];

	const NSRect points = [childView frame];
    const NSRect pixels = [childView convertRectToBacking:points];

	scaleX = (float)(pixels.size.width / points.size.width);
    scaleY = (float)(pixels.size.height / points.size.height);

	// +1 for the same reason as the iOS branch above: ~MetalLayerHandle() releases
	// whatever comes back, and childView.layer is owned by childView, not by us. This
	// is upstream's behavior, not something the iOS work introduced - it is just far
	// easier to survive here, because on macOS the view hierarchy holding the layer is
	// normally torn down at the same time as the renderer.
	CFRetain((__bridge CFTypeRef)childView.layer);

	return childView.layer;
}

void ResizeMetalLayer(void* layer, const Vector2i& sizeInPoints, float scale)
{
	// Nothing to do on macOS, and deliberately so rather than left undefined: the
	// CAMetalLayer here is MetalView's backing layer (+layerClass), so AppKit resizes
	// it with the view through the autoresizing mask set above, and
	// -layer:shouldInheritContentsScale:fromWindow: keeps contentsScale current across
	// display moves. Touching either from here would fight the framework. The
	// declaration is shared, so the definition has to exist - see MetalLayer.h.
	(void)layer;
	(void)sizeInPoints;
	(void)scale;
}

#endif
