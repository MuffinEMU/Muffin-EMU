// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI

/// The shader and pipeline cache loading screen, drawn natively at full screen resolution.
///
/// While a title starts, the core loads its cached shaders and then its cached pipelines, and
/// used to show the title, a bar and a counter with ImGui inside the game's render surface.
/// That surface has a reduced backing scale (RenderScale.swift), so the text was soft, and the
/// box sat over the game's logo. With the native overlay on (NativeCoreOverlayView) the core
/// draws only the game's boot image there and reports progress through
/// cemu_bridge_cache_loading(); this view draws the rest.
///
/// It polls only until the loading has been seen and has finished (or a long time has passed
/// with none), so there is no polling during play.

// MARK: - Model

private struct CacheLoadingState: Equatable {
    enum Phase: Equatable {
        case none, shaders, pipelines
    }

    var phase: Phase = .none
    var loaded: Int = 0
    var total: Int = 0

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(loaded) / Double(total)))
    }

    var title: String {
        phase == .pipelines ? "Loading cached pipelines" : "Loading cached shaders"
    }

    static func read() -> CacheLoadingState {
        var loaded: UInt32 = 0
        var total: UInt32 = 0
        let raw = cemu_bridge_cache_loading(&loaded, &total)
        let phase: Phase
        switch raw {
        case 1: phase = .shaders
        case 2: phase = .pipelines
        default: phase = .none
        }
        return CacheLoadingState(phase: phase, loaded: Int(loaded), total: Int(total))
    }
}

private let cacheLoadingCountFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter
}()

// MARK: - Views

/// The card: title, bar, "1,249 of 11,766" and the percent. Same dark card as the in-game
/// notices (black at 78%, continuous corners, rounded white type, the accent for the bar).
private struct CacheLoadingCard: View {
    let state: CacheLoadingState
    let width: CGFloat
    let reduceMotion: Bool

    private var percent: Int { Int(state.fraction * 100) }

    private var countText: String {
        let formatter = cacheLoadingCountFormatter
        let loaded = formatter.string(from: NSNumber(value: state.loaded)) ?? "\(state.loaded)"
        let total = formatter.string(from: NSNumber(value: state.total)) ?? "\(state.total)"
        return "\(loaded) of \(total)"
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(state.title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            CacheLoadingBar(fraction: state.fraction, reduceMotion: reduceMotion)
                .frame(height: 8)

            HStack {
                Text(countText)
                Spacer(minLength: 8)
                Text("\(percent)%")
            }
            .font(.system(.caption, design: .rounded).weight(.medium).monospacedDigit())
            .foregroundColor(.white.opacity(0.85))
        }
        .padding(14)
        .frame(width: width)
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.title)
        .accessibilityValue("\(percent) percent, \(countText)")
    }
}

private struct CacheLoadingBar: View {
    let fraction: Double
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(MuffinTheme.accentOnDark)
                    .frame(width: max(0, proxy.size.width * CGFloat(fraction)))
                    .animation(reduceMotion ? nil : .linear(duration: 0.25), value: fraction)
            }
        }
    }
}

/// Fires at 4 Hz while it is in the tree. Its own view so the timer stops when it is removed.
private struct CacheLoadingPoller: View {
    let onTick: () -> Void
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(timer) { _ in onTick() }
    }
}

/// Drop-in layer for the emulator screen: centered on the TV picture, above the video and
/// below the controls, no layout and no touches. `active` is the same condition as
/// NativeCoreOverlayView's (the core only skips its own text while the native overlay is on).
/// `tvFrame` is the TV view's frame in global coordinates; nil (not laid out yet) centers on
/// the whole layer.
struct NativeCacheLoadingView: View {
    let active: Bool
    let tvFrame: CGRect?

    @State private var state = CacheLoadingState()
    /// Cleared once the loading has been seen and has ended, or after `maxTicks` with none.
    @State private var polling = true
    @State private var seenLoading = false
    @State private var ticks = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 3 minutes at 4 Hz: boot normally reaches the cache loading well inside this, and a title
    /// with no caches never shows it at all.
    private static let maxTicks = 720
    private static let margin: CGFloat = 16

    var body: some View {
        ZStack {
            if active {
                if polling {
                    CacheLoadingPoller(onTick: tick)
                }
                if state.phase != .none {
                    GeometryReader { proxy in
                        card(in: proxy)
                    }
                    .transition(.opacity)
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: active) { isActive in
            // A new launch starts the watch again.
            guard isActive else { return }
            polling = true
            seenLoading = false
            ticks = 0
            state = CacheLoadingState()
        }
    }

    private func tick() {
        let latest = CacheLoadingState.read()
        if latest != state { state = latest }
        if latest.phase != .none {
            seenLoading = true
        } else if seenLoading {
            polling = false
        }
        ticks += 1
        if ticks >= Self.maxTicks { polling = false }
    }

    private func card(in proxy: GeometryProxy) -> some View {
        let layer = proxy.frame(in: .global)
        // The area to center in, in this layer's own coordinates.
        let area: CGRect = {
            if let tv = tvFrame {
                return tv.offsetBy(dx: -layer.minX, dy: -layer.minY)
            }
            return CGRect(origin: .zero, size: proxy.size)
        }()
        let width = max(180, min(340, area.width - 2 * Self.margin))
        return CacheLoadingCard(state: state, width: width, reduceMotion: reduceMotion)
            .position(x: area.midX, y: area.midY)
    }
}
