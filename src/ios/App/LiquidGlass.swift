// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

// The one place that touches the iOS 26 Liquid Glass APIs. Every call site in the app goes
// through the helpers below, so each `#available` check and the fallback live here.
//
// Glass is drawn only when all three hold: the app was built with a Swift 6.2 or later
// toolchain, the device runs iOS 26 or later, and `UIStyle.allowsLiquidGlass` is true (the
// player has not turned Liquid Glass off, and Classic UI is not on). In every other case each
// helper draws the pre-glass MuffinEMU look: the theme's cream fill, lighting pass, rim and
// elevation, so iOS 15 to 25 render exactly as before.
//
// Two layers, kept apart (Apple's rule for Liquid Glass):
//   • CONTENT — settings rows, library cards, sheets — is calm and legible. On iOS 26 it is a
//     warm frosted *material* (`muffinGlassSurface`, i.e. every MuffinCard), never the glass
//     effect, so nothing competes with the chrome floating above it.
//   • CHROME — the sidebar, bars, the in-game top bar, the HOME menu, buttons, the FPS pill,
//     icon chips — is real Liquid Glass (`muffinGlassBackground` / `muffinGlassOnly`), floating
//     over the content.
// Depth comes from the material refracting what is behind it and from concentric corners, NOT
// from drawn rims or drop shadows. (The pre-glass painted look keeps its own rim and elevation,
// which are legitimate there.)

enum MuffinGlass {
    /// True when glass should be drawn right now.
    static var isActive: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { return UIStyle.allowsLiquidGlass }
        #endif
        return false
    }

    /// Ink for text and glyphs that sit directly on glass: the system label colour, which
    /// glass adapts to light and dark, instead of a theme brown tuned for a cream card.
    static func ink(_ fallback: Color) -> Color {
        isActive ? Color.primary : fallback
    }

    /// Secondary ink on glass.
    static func secondaryInk(_ fallback: Color) -> Color {
        isActive ? Color.secondary : fallback
    }
}

extension View {
    /// A CONTENT surface in `shape`: a card, a settings section, a sheet panel. On Liquid Glass
    /// it is a warm frosted material (the theme fill washed over `.regularMaterial`) with a
    /// hairline rim and concentric corners — calm and legible, so the glass chrome above it can
    /// do the refracting. Below iOS 26 it is the painted cream card (`fill` + lighting pass +
    /// theme rim + `elevation`), exactly as before.
    ///
    /// `tint` / `interactive` are accepted for call-site compatibility and ignored for content
    /// (content is never interactive glass).
    @ViewBuilder func muffinGlassSurface<S: InsettableShape>(
        _ shape: S,
        tint: Color? = nil,
        interactive: Bool = false,
        fill: Color = MuffinTheme.cream,
        elevation: MuffinTheme.Elevation = .resting
    ) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), UIStyle.allowsLiquidGlass {
            self.muffinContentMaterial(shape, fill: fill)
        } else {
            self.muffinPaintedSurface(shape, fill: fill, elevation: elevation)
        }
        #else
        self.muffinPaintedSurface(shape, fill: fill, elevation: elevation)
        #endif
    }

    /// CHROME glass behind the view (bars, the in-game top bar, overlays), or the supplied
    /// fallback below iOS 26. Clean glass: the material alone, no drawn rim.
    @ViewBuilder func muffinGlassBackground<S: Shape, F: View>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false,
        @ViewBuilder fallback: () -> F
    ) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), UIStyle.allowsLiquidGlass {
            self.muffinGlassEffect(in: shape, tint: tint, interactive: interactive)
        } else {
            self.background(fallback())
        }
        #else
        self.background(fallback())
        #endif
    }

    /// A CONTENT background in `shape` (the library panel, a game card): the warm frosted
    /// material on Liquid Glass, the supplied painted fallback below iOS 26. Unlike
    /// `muffinGlassBackground` this never uses the glass effect — content stays calm so the
    /// chrome above it reads. No stroke of its own; the caller adds a hairline if it wants one.
    /// `wash` is how much of the warm fill sits over the material: a low value (an airy ground
    /// panel) lets the gradient through; a high value (a card tile) reads as near-solid cream, so
    /// a tile lifts clearly off the panel behind it instead of frosting-on-frosting into mud.
    @ViewBuilder func muffinContentBackground<S: Shape, F: View>(
        in shape: S,
        fill: Color = MuffinTheme.cream,
        wash: Double = 0.40,
        @ViewBuilder fallback: () -> F
    ) -> some View {
        if MuffinGlass.isActive {
            self.background {
                shape.fill(.regularMaterial)
                shape.fill(fill.opacity(wash))
            }
        } else {
            self.background(fallback())
        }
    }

    /// A dark panel for text drawn white over the game (logs, progress, dialogs). On Liquid
    /// Glass it is dark-scheme glass, so white text stays readable whatever is behind; below
    /// iOS 26 it is the black backing it always had.
    @ViewBuilder func muffinDarkGlassPanel<S: Shape>(in shape: S, fallbackOpacity: Double) -> some View {
        if MuffinGlass.isActive {
            self.muffinGlassOnly(in: shape).environment(\.colorScheme, .dark)
        } else {
            self.background(shape.fill(Color.black.opacity(fallbackOpacity)))
        }
    }

    /// CHROME glass behind the view when active; otherwise the view is returned untouched.
    /// Clean glass, no drawn rim.
    @ViewBuilder func muffinGlassOnly<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), UIStyle.allowsLiquidGlass {
            self.muffinGlassEffect(in: shape, tint: tint, interactive: interactive)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// The pre-glass card look. Shared by the content fallback above.
    fileprivate func muffinPaintedSurface<S: InsettableShape>(
        _ shape: S, fill: Color, elevation: MuffinTheme.Elevation
    ) -> some View {
        self
            .background(fill.overlay(MuffinTheme.surfaceSheen))
            .clipShape(shape)
            .overlay(shape.strokeBorder(MuffinTheme.edgeStroke, lineWidth: 1))
            .muffinElevation(elevation)
    }

    /// A warm frosted content surface for iOS 26: the theme fill washed over `.regularMaterial`,
    /// clipped to `shape` with a hairline rim. The material gives the separation, so there is no
    /// drop shadow — content sits calmly under the floating chrome.
    fileprivate func muffinContentMaterial<S: InsettableShape>(_ shape: S, fill: Color) -> some View {
        self
            .background {
                shape.fill(.regularMaterial)
                // Enough of the theme's own cream sits over the blur that the surface reads as
                // warm cream rather than a dusty tint of whatever saturated ground is behind it.
                shape.fill(fill.opacity(0.62))
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(MuffinTheme.edgeStroke.opacity(0.7), lineWidth: 1))
    }

    /// Native button styles for plain SwiftUI buttons (`.glass`), or the supplied fallback
    /// style below iOS 26. `prominent` is `.glassProminent`.
    @ViewBuilder func muffinGlassButtonStyle(prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), UIStyle.allowsLiquidGlass {
            if prominent {
                self.buttonStyle(.glassProminent).tint(MuffinTheme.pixelBlue)
            } else {
                self.buttonStyle(.glass)
            }
        } else if prominent {
            self.buttonStyle(MuffinPrimaryButtonStyle())
        } else {
            self.buttonStyle(MuffinSecondaryButtonStyle())
        }
        #else
        if prominent {
            self.buttonStyle(MuffinPrimaryButtonStyle())
        } else {
            self.buttonStyle(MuffinSecondaryButtonStyle())
        }
        #endif
    }

    /// Lets the system draw its scroll edge effect (the soft fade under glass bars) when glass
    /// is on, and keeps the app-wide "hidden" setting otherwise.
    @ViewBuilder func muffinScrollEdgeForGlass() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if UIStyle.allowsLiquidGlass {
                self.scrollEdgeEffectStyle(.soft, for: .all)
            } else {
                self.scrollEdgeEffectHidden(true, for: .all)
            }
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Translucent row backgrounds for a Form or List: system material over the theme ground,
    /// so the gradient shows through. Applied to the content of the Form (a Group forwards the
    /// row trait to every Section inside it). Without glass: the list's own rows.
    @ViewBuilder func muffinGlassRows() -> some View {
        if MuffinGlass.isActive {
            // The material plus a wash of the theme cream, so Settings rows read as warm cream
            // and lift off the page ground instead of being a near-white frost over it.
            self.listRowBackground(
                ZStack {
                    Rectangle().fill(.regularMaterial)
                    Rectangle().fill(MuffinTheme.cream.opacity(0.34))
                }
            )
        } else {
            self
        }
    }

    /// The ground behind a Form or List on Liquid Glass: the list's opaque scroll background is
    /// hidden and the theme gradient shows behind translucent rows. Unchanged without glass.
    @ViewBuilder func muffinGlassFormGround() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), UIStyle.allowsLiquidGlass {
            self.scrollContentBackground(.hidden)
                .background(
                    // A warm page ground: the system grouped ground, a wash of the theme cream so
                    // it reads warm rather than grey, and only a faint tint of the (already calmed)
                    // gradient — enough to belong to the theme without the dusty mauve the full
                    // gradient left behind the rows.
                    MuffinTheme.formGround
                        .overlay(MuffinTheme.cream.opacity(0.24))
                        .overlay(MuffinTheme.backgroundGradient.opacity(0.14))
                        .ignoresSafeArea())
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Lets nearby glass shapes blend and morph as one. Without glass: the content as is.
    @ViewBuilder func muffinGlassContainer(spacing: CGFloat = 12) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), UIStyle.allowsLiquidGlass {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Tags a glass element so it can morph into another with the same id in the same namespace.
    @ViewBuilder func muffinGlassID<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), UIStyle.allowsLiquidGlass {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#if compiler(>=6.2)
@available(iOS 26.0, *)
extension View {
    fileprivate func muffinGlassEffect<S: Shape>(in shape: S, tint: Color?, interactive: Bool) -> some View {
        let base: Glass = tint.map { Glass.regular.tint($0) } ?? Glass.regular
        return self.glassEffect(interactive ? base.interactive() : base, in: shape)
    }
}
#endif

// MARK: - Glass card

/// A card on Liquid Glass (MuffinCard's pre-glass look below iOS 26), for views that want the
/// content surface without the MuffinCard wrapper.
struct MuffinGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 18
    var tint: Color?
    var fill: Color = MuffinTheme.cream
    @ViewBuilder var content: Content

    var body: some View {
        content.muffinGlassSurface(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            tint: tint, fill: fill)
    }
}

// MARK: - Glass pill

/// A small capsule of glass for a status pill or badge floating over a game or a cover. This is
/// chrome, so it is real glass on iOS 26.
struct MuffinGlassPill<Content: View>: View {
    var tint: Color?
    var fallbackFill: Color = Color.black.opacity(0.55)
    @ViewBuilder var content: Content

    var body: some View {
        content
            .muffinGlassBackground(in: Capsule(), tint: tint) {
                Capsule().fill(fallbackFill)
            }
    }
}

// MARK: - Glass icon chip

/// A small tinted chip for a section or row icon. This is a control-sized accent, so on Liquid
/// Glass it is a tinted glass tile (tint used sparingly, as Apple advises) and the glyph reads as
/// a little physical chip of coloured glass; below iOS 26 it is the painted tinted tile with the
/// lighting pass and a faint rim. Gives Settings a consistent, dimensional icon treatment instead
/// of a flat colour swatch.
struct MuffinGlassIconChip: View {
    let systemName: String
    var accent: Color
    var size: CGFloat = 34
    var cornerRadius: CGFloat = 10

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous) }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundColor(accent)
            .frame(width: size, height: size)
            .muffinGlassBackground(in: shape, tint: accent.opacity(0.55)) {
                shape.fill(accent.opacity(0.16))
                    .overlay(MuffinTheme.surfaceSheen.clipShape(shape))
                    .overlay(shape.strokeBorder(accent.opacity(0.22), lineWidth: 1))
            }
    }
}
