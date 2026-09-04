import SwiftUI

// The launch intro: a muffin sketched onto black, which then comes alive, looks
// around, smiles, and hands over to the game.
//
// WHY THIS ONE CAN BE CINEMATIC WHEN THE SHOWCASE ROMS COULD NOT
//
// The three showcase roms render on the emulated Wii U, where GX2 has never produced a
// frame and everything has to go through OSScreen a pixel at a time. This runs on the
// iOS side, in SwiftUI, on a real GPU with no emulator underneath it. None of those
// constraints apply here, so this is the one place the "cinematic 3D" idea can actually
// be honoured rather than approximated.
//
// WHY IT COSTS NO TIME
//
// It plays over the boot, not before it. Booting a title already spends seconds doing
// nothing visible - the guest timer calibration alone is about three - and until now
// that time was a spinner and the word "Booting". The intro is timed to fit inside it,
// and the game is revealed when BOTH the intro has finished and the engine is running,
// so on a slow boot it hides the wait and on a fast one it costs a second or two of
// deliberate theatre. It never blocks input and never delays the engine: boot and
// intro run concurrently and simply meet.
//
// The muffin is the app icon, drawn as vector paths in the same proportions, using
// MuffinTheme's real colours rather than anything invented for this file - the dome
// gradient, the navy blueberries, the one pixel-blue square, the fluted cream wrapper,
// the blush and the smile.

// MARK: - Geometry
//
// Every shape is defined in a unit box and scaled by the caller, so the whole muffin
// composes at any size and the sketch strokes stay proportional.

private struct Dome: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        // A wide dome that overhangs the wrapper, which is the silhouette that reads as
        // "muffin" rather than "cupcake". Two symmetric cubics meeting at the apex.
        p.move(to: CGPoint(x: r.minX + w * 0.03, y: r.minY + h * 0.98))
        p.addCurve(to: CGPoint(x: r.minX + w * 0.50, y: r.minY + h * 0.02),
                   control1: CGPoint(x: r.minX + w * 0.06, y: r.minY + h * 0.46),
                   control2: CGPoint(x: r.minX + w * 0.24, y: r.minY + h * 0.02))
        p.addCurve(to: CGPoint(x: r.minX + w * 0.97, y: r.minY + h * 0.98),
                   control1: CGPoint(x: r.minX + w * 0.76, y: r.minY + h * 0.02),
                   control2: CGPoint(x: r.minX + w * 0.94, y: r.minY + h * 0.46))
        p.closeSubpath()
        return p
    }
}

private struct Wrapper: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        // Flat top, tapering to a narrower base, with slightly bowed sides.
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + w * 0.80, y: r.minY + h),
                       control: CGPoint(x: r.minX + w * 0.93, y: r.minY + h * 0.6))
        p.addLine(to: CGPoint(x: r.minX + w * 0.20, y: r.minY + h))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY),
                       control: CGPoint(x: r.minX + w * 0.07, y: r.minY + h * 0.6))
        p.closeSubpath()
        return p
    }
}

/// The fluting. Separate from Wrapper so it can be drawn as strokes during the sketch
/// and as fills afterwards, which is exactly how someone drawing this would do it.
private struct WrapperFlutes: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        for i in 1..<6 {
            let t = CGFloat(i) / 6.0
            let topX = r.minX + w * t
            let botX = r.minX + w * (0.20 + 0.60 * t)
            p.move(to: CGPoint(x: topX, y: r.minY))
            p.addLine(to: CGPoint(x: botX, y: r.minY + h))
        }
        return p
    }
}

/// The three crease lines on the crown, as in the icon.
private struct Creases: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        for (x, len) in [(0.40, 0.30), (0.52, 0.38), (0.63, 0.34)] {
            p.move(to: CGPoint(x: r.minX + w * x, y: r.minY + h * 0.16))
            p.addQuadCurve(to: CGPoint(x: r.minX + w * (x - 0.03), y: r.minY + h * (0.16 + len)),
                           control: CGPoint(x: r.minX + w * (x + 0.03), y: r.minY + h * (0.16 + len * 0.5)))
        }
        return p
    }
}

private struct Smile: Shape {
    /// 0 = gentle, 1 = full grin. Animatable so the smile can widen on cue.
    var openness: CGFloat
    var animatableData: CGFloat {
        get { openness }
        set { openness = newValue }
    }
    func path(in r: CGRect) -> Path {
        var p = Path()
        let drop = r.height * (0.55 + 0.45 * openness)
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY),
                       control: CGPoint(x: r.midX, y: r.minY + drop))
        return p
    }
}

/// Blueberry placements on the crown, in unit coordinates, matching the icon: four
/// navy berries and one pixel-blue square, which is the app's own small joke and the
/// reason the icon reads as a *pixel* muffin rather than a bakery logo.
private struct Berry: Identifiable {
    let id: Int
    let x: CGFloat, y: CGFloat, r: CGFloat
    let square: Bool
}

private let kBerries: [Berry] = [
    Berry(id: 0, x: 0.24, y: 0.34, r: 0.062, square: false),
    Berry(id: 1, x: 0.40, y: 0.22, r: 0.048, square: false),
    Berry(id: 2, x: 0.66, y: 0.31, r: 0.045, square: false),
    Berry(id: 3, x: 0.77, y: 0.44, r: 0.042, square: false),
    Berry(id: 4, x: 0.60, y: 0.24, r: 0.046, square: true)
]

// MARK: - The intro

struct LaunchIntroView: View {
    /// Called once the intro is finished and faded out. The caller decides when to
    /// actually show the game - see IntroGate.
    var onFinished: () -> Void

    @State private var sketch: CGFloat = 0        // 0..1, how much of the line work is drawn
    @State private var inked: CGFloat = 0         // 0..1, colour fading in behind the lines
    @State private var pop: CGFloat = 0           // 0..1, off-the-page spring
    @State private var pageOpacity: CGFloat = 0
    @State private var eyeShift: CGFloat = 0      // -1 left, +1 right
    @State private var blink: CGFloat = 1         // 1 open, 0 shut
    @State private var grin: CGFloat = 0
    @State private var fade: CGFloat = 0          // final blackout
    @State private var started = false

    private let chalk = Color(red: 0.98, green: 0.95, blue: 0.90)

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.52
            ZStack {
                Color.black.ignoresSafeArea()

                // The page. It is the app icon's own orange card, and the muffin pops
                // OUT of it - so it has to be behind, and has to recede as the muffin
                // comes forward or the pop reads as a zoom instead of a departure.
                RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                    .fill(MuffinTheme.backgroundGradient)
                    .frame(width: side * 1.28, height: side * 1.28)
                    .opacity(pageOpacity * (1 - pop * 0.75))
                    .scaleEffect(1 - pop * 0.10)
                    .blur(radius: pop * 6)

                muffin(side: side)
                    .scaleEffect(0.82 + pop * 0.30)
                    .rotation3DEffect(.degrees(Double((1 - pop) * 34)),
                                      axis: (x: 1, y: 0, z: 0),
                                      perspective: 0.55)
                    .shadow(color: MuffinTheme.shadow.opacity(Double(pop) * 0.55),
                            radius: 26 * pop, x: 0, y: 20 * pop)

                Color.black.opacity(Double(fade)).ignoresSafeArea()
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
        .onAppear { if !started { started = true; run() } }
    }

    @ViewBuilder
    private func muffin(side: CGFloat) -> some View {
        let domeH = side * 0.56
        let wrapH = side * 0.40
        let wrapW = side * 0.62

        ZStack {
            // --- Colour, revealed under the strokes ---
            VStack(spacing: -side * 0.015) {
                Dome().fill(MuffinTheme.muffinTopGradient)
                    .frame(width: side, height: domeH)
                Wrapper().fill(MuffinTheme.cream)
                    .frame(width: wrapW, height: wrapH)
            }
            .opacity(Double(inked))

            // Flute shading, only once inked - stripes drawn as lines during the sketch
            // and as alternating fills afterwards is what a real drawing does.
            VStack(spacing: -side * 0.015) {
                Spacer().frame(width: side, height: domeH)
                WrapperFlutes().stroke(MuffinTheme.wrapper, lineWidth: side * 0.055)
                    .frame(width: wrapW, height: wrapH)
                    .clipShape(Wrapper())
            }
            .opacity(Double(inked))

            berries(side: side, domeH: domeH)
                .opacity(Double(inked))

            face(side: side, domeH: domeH)
                .opacity(Double(inked))

            // --- The line work, drawn on top, chalk on black ---
            VStack(spacing: -side * 0.015) {
                ZStack {
                    Dome().trim(from: 0, to: sketch)
                        .stroke(chalk, style: StrokeStyle(lineWidth: side * 0.012, lineCap: .round))
                    Creases().trim(from: 0, to: max(0, (sketch - 0.45) / 0.35))
                        .stroke(chalk.opacity(0.7), style: StrokeStyle(lineWidth: side * 0.008, lineCap: .round))
                }
                .frame(width: side, height: domeH)

                ZStack {
                    Wrapper().trim(from: 0, to: sketch)
                        .stroke(chalk, style: StrokeStyle(lineWidth: side * 0.012, lineCap: .round))
                    WrapperFlutes().trim(from: 0, to: max(0, (sketch - 0.5) / 0.4))
                        .stroke(chalk.opacity(0.6), style: StrokeStyle(lineWidth: side * 0.007, lineCap: .round))
                }
                .frame(width: wrapW, height: wrapH)
            }
            // The strokes stay visible while the colour arrives, then hand over - a
            // drawing becoming a thing, rather than a cut between two pictures.
            .opacity(Double(1 - inked * 0.85))
        }
        .frame(width: side, height: domeH + wrapH)
    }

    private func berries(side: CGFloat, domeH: CGFloat) -> some View {
        ZStack {
            ForEach(kBerries) { b in
                Group {
                    if b.square {
                        Rectangle().fill(MuffinTheme.pixelBlue)
                    } else {
                        Circle().fill(MuffinTheme.blueberryNavy)
                    }
                }
                .frame(width: side * b.r * 2, height: side * b.r * 2)
                .position(x: side * b.x, y: domeH * b.y)
            }
        }
        .frame(width: side, height: domeH)
        .offset(y: -(side * 0.40) / 2)
    }

    private func face(side: CGFloat, domeH: CGFloat) -> some View {
        let eyeY = domeH * 0.62
        let eyeDX = side * 0.085
        return ZStack {
            // Blush
            ForEach([-1.0, 1.0], id: \.self) { s in
                Ellipse().fill(MuffinTheme.blushPink.opacity(0.85))
                    .frame(width: side * 0.10, height: side * 0.055)
                    .position(x: side * 0.5 + CGFloat(s) * side * 0.155, y: eyeY + domeH * 0.12)
            }
            // Eyes. Height is what blinks; the shift is what looks around.
            ForEach([-1.0, 1.0], id: \.self) { s in
                ZStack {
                    Capsule().fill(Color.black)
                        .frame(width: side * 0.036, height: side * 0.052 * blink)
                    Circle().fill(Color.white)
                        .frame(width: side * 0.013, height: side * 0.013 * blink)
                        .offset(x: -side * 0.008, y: -side * 0.012)
                }
                .position(x: side * 0.5 + CGFloat(s) * eyeDX + eyeShift * side * 0.018, y: eyeY)
            }
            Smile(openness: grin)
                .stroke(MuffinTheme.brownDark,
                        style: StrokeStyle(lineWidth: side * 0.016, lineCap: .round))
                .frame(width: side * 0.13, height: side * 0.07)
                .position(x: side * 0.5, y: eyeY + domeH * 0.19)
        }
        .frame(width: side, height: domeH)
        .offset(y: -(side * 0.40) / 2)
    }

    // MARK: Direction
    //
    // Explicit sleeps rather than a phase animator, because the deployment target is
    // iOS 15 and PhaseAnimator is iOS 17. Nanoseconds rather than .seconds for the same
    // reason - Task.sleep(for:) is iOS 16.
    private func run() {
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.5)) { pageOpacity = 0.55 }
            // 1. Sketched, at a hand's pace rather than a machine's.
            withAnimation(.easeInOut(duration: 2.1)) { sketch = 1 }
            try? await Task.sleep(nanoseconds: 2_150_000_000)

            // 2. Colour arrives under the lines.
            withAnimation(.easeIn(duration: 0.65)) { inked = 1 }
            try? await Task.sleep(nanoseconds: 620_000_000)

            // 3. Off the page. A spring, because nothing alive moves on a curve.
            withAnimation(.interpolatingSpring(stiffness: 120, damping: 11)) { pop = 1 }
            try? await Task.sleep(nanoseconds: 520_000_000)

            // 4. Alive: a look left, a look right, a blink, then the grin.
            withAnimation(.easeInOut(duration: 0.42)) { eyeShift = -1 }
            try? await Task.sleep(nanoseconds: 470_000_000)
            withAnimation(.easeInOut(duration: 0.5)) { eyeShift = 1 }
            try? await Task.sleep(nanoseconds: 540_000_000)
            withAnimation(.easeInOut(duration: 0.28)) { eyeShift = 0 }
            withAnimation(.easeInOut(duration: 0.09)) { blink = 0.08 }
            try? await Task.sleep(nanoseconds: 110_000_000)
            withAnimation(.easeInOut(duration: 0.12)) { blink = 1 }
            try? await Task.sleep(nanoseconds: 160_000_000)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { grin = 1 }
            try? await Task.sleep(nanoseconds: 620_000_000)

            // 5. Out.
            withAnimation(.easeIn(duration: 0.55)) { fade = 1 }
            try? await Task.sleep(nanoseconds: 580_000_000)
            onFinished()
        }
    }
}
