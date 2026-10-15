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
///
/// "Skip this time" ends the loading for this boot (cemu_bridge_skip_cache_loading()): what
/// wasn't loaded compiles when the game first needs it. The cache files keep everything, so
/// the next boot loads it all again.

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

/// The card: title, bar, "1,249 of 11,766", the percent and the skip button. Same dark card as
/// the in-game notices (black at 78%, continuous corners, rounded white type, the accent for the bar).
private struct CacheLoadingCard: View {
    let state: CacheLoadingState
    let width: CGFloat
    let reduceMotion: Bool
    let skipping: Bool
    var showsSkip: Bool = true
    let onSkip: () -> Void

    private var percent: Int { Int(state.fraction * 100) }

    private var countText: String {
        let formatter = cacheLoadingCountFormatter
        let loaded = formatter.string(from: NSNumber(value: state.loaded)) ?? "\(state.loaded)"
        let total = formatter.string(from: NSNumber(value: state.total)) ?? "\(state.total)"
        return "\(loaded) of \(total)"
    }

    var body: some View {
        VStack(spacing: 10) {
            progress
            if showsSkip {
                Button(action: onSkip) {
                    Text(skipping ? "Skipping..." : "Skip this time")
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(Color.white.opacity(skipping ? 0.08 : 0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(skipping)
                .accessibilityHint("Starts the game now. Shaders that weren't loaded are compiled when the game needs them, which can stutter at first.")
            }
        }
        .padding(14)
        .frame(width: width)
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var progress: some View {
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
        .allowsHitTesting(false)
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

/// Drop-in layer for the emulator screen, above the video and below the controls, no layout:
/// one card centered on each Wii U screen in `frames` (global coordinates; empty, or not laid
/// out yet, centers one card on the whole layer). Only the cards take touches; the rest passes
/// through. `interactive` is false on the external display, which can't be touched, so its card
/// has no skip button. `active` is true while a title is booting, running or paused.
struct NativeCacheLoadingView: View {
    let active: Bool
    var frames: [CGRect] = []
    var interactive: Bool = true

    @State private var state = CacheLoadingState()
    /// Cleared once the loading has been seen and has ended, or when none was seen for
    /// `giveUpAfter` (a display connected mid-game would otherwise poll for the whole session).
    /// Until then it polls: a read is one atomic load.
    @State private var polling = true
    @State private var seenLoading = false
    @State private var pollingSince = Date()
    /// Set by the skip button for this launch, so it can't be pressed twice.
    @State private var skipping = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let margin: CGFloat = 16
    private static let giveUpAfter: TimeInterval = 300

    var body: some View {
        ZStack {
            if active {
                if polling {
                    CacheLoadingPoller(onTick: tick)
                }
                if state.phase != .none {
                    GeometryReader { proxy in
                        cards(in: proxy)
                    }
                    .transition(.opacity)
                }
            }
        }
        .onAppear { pollingSince = Date() }
        .onChange(of: active) { isActive in
            // A new launch starts the watch again.
            guard isActive else { return }
            polling = true
            seenLoading = false
            pollingSince = Date()
            skipping = false
            state = CacheLoadingState()
        }
    }

    private func tick() {
        let latest = CacheLoadingState.read()
        if latest != state { state = latest }
        if latest.phase != .none {
            seenLoading = true
        } else if seenLoading || Date().timeIntervalSince(pollingSince) > Self.giveUpAfter {
            polling = false
        }
    }

    /// The areas to center a card in, in this layer's own coordinates. Two screens that
    /// report the same frame get one card.
    private func areas(in proxy: GeometryProxy) -> [CGRect] {
        let layer = proxy.frame(in: .global)
        var result: [CGRect] = []
        for frame in frames {
            let local = frame.offsetBy(dx: -layer.minX, dy: -layer.minY)
            if !result.contains(where: { $0.integral == local.integral }) { result.append(local) }
        }
        return result.isEmpty ? [CGRect(origin: .zero, size: proxy.size)] : result
    }

    private func cards(in proxy: GeometryProxy) -> some View {
        ZStack {
            ForEach(Array(areas(in: proxy).enumerated()), id: \.offset) { _, area in
                let width = max(180, min(340, area.width - 2 * Self.margin))
                CacheLoadingCard(state: state, width: width, reduceMotion: reduceMotion,
                                 skipping: skipping, showsSkip: interactive) {
                    skipping = true
                    cemu_bridge_skip_cache_loading()
                }
                .position(x: area.midX, y: area.midY)
            }
        }
    }
}

/// The external display's copy of the loading card, for DisplayRouter's window there. Clear
/// background and no touches: the display shows the game's boot image underneath.
final class ExternalCacheLoadingHost: UIHostingController<NativeCacheLoadingView> {
    init() {
        super.init(rootView: NativeCacheLoadingView(active: true, interactive: false))
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
