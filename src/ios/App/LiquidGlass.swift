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
    /// A Liquid Glass surface in `shape`. Without glass: `fill` with the lighting pass, the
    /// theme rim and `elevation`, which is what MuffinCard and the secondary button wore.
    ///
    /// - tint: a theme colour for the glass to pick up (accent or muffin-top). Nil is clear glass.
    /// - interactive: the glass reacts to touch (use on buttons and tappable rows only).
    @ViewBuilder func muffinGlassSurface<S: InsettableShape>(
        _ shape: S,
        tint: Color? = nil,
        interactive: Bool = false,
        fill: Color = MuffinTheme.cream,
        elevation: MuffinTheme.Elevation = .resting
    ) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), UIStyle.allowsLiquidGlass {
            self.muffinGlassEffect(in: shape, tint: tint, interactive: interactive)
        } else {
            self.muffinPaintedSurface(shape, fill: fill, elevation: elevation)
        }
        #else
        self.muffinPaintedSurface(shape, fill: fill, elevation: elevation)
        #endif
    }

    /// Glass behind the view, or nothing special: for a view that already has its own
    /// fallback background and only wants the glass swapped in on iOS 26.
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

    /// Glass behind the view when active; otherwise the view is returned untouched.
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

    /// The pre-glass card look. Shared by the fallbacks above.
    fileprivate func muffinPaintedSurface<S: InsettableShape>(
        _ shape: S, fill: Color, elevation: MuffinTheme.Elevation
    ) -> some View {
        self
            .background(fill.overlay(MuffinTheme.surfaceSheen))
            .clipShape(shape)
            .overlay(shape.strokeBorder(MuffinTheme.edgeStroke, lineWidth: 1))
            .muffinElevation(elevation)
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
            self.listRowBackground(Rectangle().fill(.thinMaterial))
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
                    // The system grouped ground with a wash of the theme on it: headers and
                    // footers sit straight on this, so it stays near neutral for their ink,
                    // while the translucent rows above still pick the theme up.
                    MuffinTheme.formGround
                        .overlay(MuffinTheme.backgroundGradient.opacity(0.28))
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
/// glass surface without the MuffinCard wrapper.
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

/// A small capsule of glass for a status pill or badge floating over a game or a cover.
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
