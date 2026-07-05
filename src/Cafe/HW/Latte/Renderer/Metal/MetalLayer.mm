#include "Cafe/HW/Latte/Renderer/Metal/MetalLayer.h"

#include <TargetConditionals.h>

#if TARGET_OS_IOS

// iOS / UIKit path. Cemu's Metal renderer only needs a CAMetalLayer to draw into.
// `handle` is a UIView* supplied by the app shell (see src/ios). We back it with a
// CAMetalLayer sized to the view and return that layer.
#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>

void* CreateMetalLayer(void* handle, float& scaleX, float& scaleY)
{
	UIView* view = (__bridge UIView*)handle;

	CAMetalLayer* metalLayer = [CAMetalLayer layer];
	metalLayer.frame = view.bounds;
	metalLayer.contentsScale = view.contentScaleFactor;
	metalLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
	[view.layer addSublayer:metalLayer];

	// iOS reports the backing-store scale directly; width/height scale are equal.
	const float scale = (float)view.contentScaleFactor;
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
