//
//  MetalViewContainer.swift
//  MeloCafe
//
//  Created by Stossy11 on 10/9/2026.
//

import SwiftUI

// yes i stole MeloNX code for this >:3 -stossy11
struct MetalViewContainer: View {
    let metalView: MetalView
    @ObservedObject private var configManager = ConfigManager.shared

    var body: some View {
        GeometryReader { geometry in
            let size = configManager.fullscreenScaling.wrappedValue == .stretch
                ? geometry.size : targetSize(in: geometry.size)
            ZStack {
                Color.black
                MetalKitView(mtkView: metalView)
                    .frame(width: size.width, height: size.height)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }
}

func targetSize(in containerSize: CGSize) -> CGSize {
    guard containerSize.width > 0, containerSize.height > 0 else {
        return .zero
    }

    let targetAspect: CGFloat

    /*
    switch aspectRatio {
    case .fixed4x3:   targetAspect = 4.0  / 3.0
    case .fixed16x9:  targetAspect = 16.0 / 9.0
    case .fixed16x10: targetAspect = 16.0 / 10.0
    case .fixed21x9:  targetAspect = 21.0 / 9.0
    case .fixed32x9:  targetAspect = 32.0 / 9.0
    default:  return containerSize
    }
     */
    
    targetAspect = 16.0 / 9.0
    
    let containerAspect = containerSize.width / containerSize.height
    
    if containerAspect > targetAspect {
        return CGSize(width: containerSize.height * targetAspect, height: containerSize.height)
    } else {
        return CGSize(width: containerSize.width, height: containerSize.width / targetAspect)
    }
}

func isScreenAspectRatio(
    _ targetWidth: CGFloat,
    _ targetHeight: CGFloat,
    in size: CGSize,
    tolerance: CGFloat = 0.05
) -> Bool {
    let w = max(size.width, size.height)
    let h = min(size.width, size.height)
    return abs((w / h) - (targetWidth / targetHeight)) < tolerance
}
