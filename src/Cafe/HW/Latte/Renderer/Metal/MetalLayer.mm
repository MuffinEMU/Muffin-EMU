#include "Cafe/HW/Latte/Renderer/Metal/MetalLayer.h"

#include <TargetConditionals.h>

#if TARGET_OS_IOS

// iOS / UIKit path. Cemu's Metal renderer only needs a CAMetalLayer to draw into.
// `handle` is a UIView* supplied by the app shell (see src/ios). We back it with a
// CAMetalLayer sized to the view and return that layer.
#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>

void* CreateMetalLayer(void* handle, const Vector2i& pixelSize, float& scaleX, float& scaleY)
{
	UIView* view = (__bridge UIView*)handle;

	CAMetalLayer* metalLayer = [CAMetalLayer layer];

	// Frame comes from the caller-supplied pixel size (converted to points), NOT
	// view.bounds: this runs synchronously the instant the render surface is
	// registered (GameManager.registerRenderSurface, called from makeUIView), which
	// is before SwiftUI has necessarily laid the owning view out to a nonzero size -
	// view.bounds was frequently still CGRectZero here, producing a zero-sized,
	// invisible sublayer: correct rendering underneath, black screen on top.
	// Confirmed via live device test after the MetalLayerHandle double-release fix
	// (v1.9) eliminated the earlier crash and exposed this as the next blocker.
	// Nothing later re-syncs this frame either, since a manually-added sublayer
	// doesn't auto-resize with its superlayer - a future dynamic-resize path (e.g.
	// rotation, split view) will need to call back into this layer explicitly.
	const float scale = (float)view.contentScaleFactor;
	metalLayer.frame = CGRectMake(0, 0, pixelSize.x / scale, pixelSize.y / scale);
	metalLayer.contentsScale = scale;
	[view.layer addSublayer:metalLayer];

	// iOS reports the backing-store scale directly; width/height scale are equal.
	scaleX = scale;
	scaleY = scale;

	return (__bridge void*)metalLayer;
}

#else

// macOS / AppKit path (unchanged upstream behavior).
#include "Cafe/HW/Latte/Renderer/MetalView.h"

void* CreateMetalLayer(void* handle, float& scaleX, float& scaleY)
{
	NSView* view = (NSView*)handle;

	MetalView* childView = [[MetalView alloc] initWithFrame:view.bounds];
	childView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	childView.wantsLayer = YES;

	[view addSubview:childView];

	const NSRect points = [childView frame];
    const NSRect pixels = [childView convertRectToBacking:points];

	scaleX = (float)(pixels.size.width / points.size.width);
    scaleY = (float)(pixels.size.height / points.size.height);

	return childView.layer;
}

#endif
