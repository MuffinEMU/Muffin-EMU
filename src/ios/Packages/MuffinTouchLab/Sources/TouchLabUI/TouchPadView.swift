// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

#if canImport(UIKit)
import CoreMotion
import SwiftUI
import TouchLabCore
import UIKit

/// One UIView that owns every finger on the pad.
///
/// Why UIKit and one view, rather than a SwiftUI view per button: the shipping pad's worst
/// bugs lived in SwiftUI hit testing (`.position()` plus negative padding shrinking every
/// catchment to nothing, shipped, and visible only under a real finger). Here there is
/// no per-control hit testing to get wrong. `touchesBegan/Moved/Ended/Cancelled` hand
/// raw points to `PadEngine`, and the engine decides. The same code path runs in the
/// check suite on a Mac.
///
/// Touches nothing wants (per `PadEngine.claims`) are not taken: `hitTest` returns nil for
/// them, so menus and buttons under the pad keep working.
public final class TouchPadView: UIView {
    public let engine: PadEngine
    public var hapticsEnabled = true
    /// Whole-pad opacity; controls, not the view, so hit testing is unaffected.
    public var controlOpacity: CGFloat = 0.85 { didSet { invalidatePad(full: true) } }
    /// Colours for the classic schemes (see `PadStyle`); nil = Classic.
    public var colourPreset: ShowcaseColourPreset? { didSet { invalidatePad(full: true) } }
    /// The polished look (see `PadSettings.showcaseStyle`); off draws the earlier flat look.
    public var showcaseStyle = true { didSet { if showcaseStyle != oldValue { relayout(); invalidatePad(full: true) } } }
    /// Called after every input change, for HUDs and diagnostics.
    public var onChange: (() -> Void)?
    /// Where the GamePad image is, in this view's coordinates; see LayoutContext.
    public var touchscreenRect: CGRect? { didSet { relayout() } }
    public var videoRects: [CGRect] = [] { didSet { relayout() } }
    public var scale: CGFloat = 1 { didSet { relayout() } }
    /// See LayoutContext.stickSpacing.
    public var stickSpacing: CGFloat = 0 { didSet { relayout() } }
    /// See LayoutContext.shoulderOffset.
    public var shoulderOffset: CGFloat = 0 { didSet { relayout() } }
    public var stickTuning = StickTuning() { didSet { relayout() } }
    /// See LayoutContext.calibration.
    public var calibration = StickCalibrations() { didSet { relayout() } }
    /// See LayoutContext.tolerance.
    public var tolerance: PadTolerance? { didSet { relayout() } }
    /// See LayoutContext.edits.
    public var edits = PadEdits() { didSet { if edits != oldValue { relayout() } } }

    /// Moving and resizing controls, when the scheme offers it (Zone). Set while the host's edit
    /// panel is open: touches then move the control they land on instead of pressing it.
    public var editSession: PadEditSession? {
        didSet {
            guard let zone = engine.scheme as? ZonePad else { return }
            let was = zone.isEditing
            zone.isEditing = editSession != nil
            zone.editGranularity = editSession?.granularity ?? zone.editGranularity
            zone.editSelection = editSession?.selection
            if zone.isEditing != was {
                // Whatever the pad is holding goes: the next touch moves a control, it does not press one.
                engine.cancelAll()
                editDrag = nil
                pinchOrigin = nil
                pinch.isEnabled = zone.isEditing
            }
            invalidatePad(full: true)
        }
    }
    private var editDrag: (key: String, start: CGPoint, origin: PadEdit, finger: TouchID)?
    private var pinchOrigin: PadEdit?
    private lazy var pinch: UIPinchGestureRecognizer = {
        let g = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        g.isEnabled = false
        return g
    }()

    /// Every shared setting at once; the same values for every scheme.
    public var settings: PadSettings {
        get {
            PadSettings(stick: stickTuning, calibration: calibration, tolerance: tolerance, scale: scale,
                        opacity: controlOpacity, haptics: hapticsEnabled, stickSpacing: stickSpacing,
                        shoulderOffset: shoulderOffset, colourPreset: colourPreset,
                        showcaseStyle: showcaseStyle, edits: edits)
        }
        set {
            if stickTuning != newValue.stick { stickTuning = newValue.stick }
            if calibration != newValue.calibration { calibration = newValue.calibration }
            if tolerance != newValue.tolerance { tolerance = newValue.tolerance }
            if scale != newValue.scale { scale = newValue.scale }
            if stickSpacing != newValue.stickSpacing { stickSpacing = newValue.stickSpacing }
            if shoulderOffset != newValue.shoulderOffset { shoulderOffset = newValue.shoulderOffset }
            if controlOpacity != newValue.opacity { controlOpacity = newValue.opacity }
            if colourPreset != newValue.colourPreset { colourPreset = newValue.colourPreset }
            if showcaseStyle != newValue.showcaseStyle { showcaseStyle = newValue.showcaseStyle }
            if edits != newValue.edits { edits = newValue.edits }
            hapticsEnabled = newValue.haptics
        }
    }
    /// Which coordinate space `touchscreenRect` / `videoRects` are given in. `.window`
    /// takes SwiftUI `.global` frames (window coordinates) and converts them into this
    /// view's space, so a host can report screen frames from anywhere in its hierarchy.
    public var rectSpace: RectSpace = .local { didSet { relayout() } }
    /// Off = the pad is drawn but takes no touches, and anything held is released. For a
    /// paused title and for layout-editing mode.
    public var isInputEnabled = true {
        didSet {
            guard isInputEnabled != oldValue else { return }
            if !isInputEnabled { dropAll() } else { relayout(force: true) }
            updateAmbient()
            invalidatePad(full: true)
        }
    }

    public enum RectSpace: Equatable { case local, window }

    /// Added to the safe area before layout: room the host keeps for its own chrome (a
    /// top bar), so no control is placed underneath it.
    public var extraInsets = Insets() { didSet { relayout() } }

    private var displayLink: CADisplayLink?
    private var glowTimer: Timer?
    private let wheel = WheelAngleSource()
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let snapFeedback = UISelectionFeedbackGenerator()
    private var lastPressed: Set<PadButton> = []
    /// The still part of the Showcase scene, kept as a bitmap so a stick drag redraws only the knob.
    private let cache = ShowcaseCache()
    /// The scene as last built, and its split; `parts` is nil when it must be drawn whole.
    private struct ShownScene {
        var scene: ShowcaseScene
        var parts: ShowcaseSceneParts?
        var size: CGSize = .zero
    }
    private var shown: ShownScene?
    /// A Showcase press is still easing, so the display link keeps the frames coming.
    private var pressEasing = false
    /// Arc's calibration card, when showing. A subview of the pad (not a sibling in the host's
    /// hierarchy, which a SwiftUI wrapper may not route touches into); `hitTest` hands it the
    /// touches that land on its buttons.
    weak var arcOverlay: UIView?

    public init(scheme: TouchScheme, output: PadOutput) {
        engine = PadEngine(scheme: scheme, output: output, context: LayoutContext(size: .zero))
        super.init(frame: .zero)
        bindArcRedraw()
        isMultipleTouchEnabled = true
        addGestureRecognizer(pinch)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        NotificationCenter.default.addObserver(self, selector: #selector(dropAll),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        // Any other way the app or this window can stop being the one in the player's hand:
        // backgrounding, the scene going away or inactive (iPad windows, Stage Manager), another
        // window (a system alert) taking key.
        for name in [UIApplication.didEnterBackgroundNotification, UIScene.willDeactivateNotification,
                     UIScene.didDisconnectNotification, UIScene.didEnterBackgroundNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(sceneLeft(_:)), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(sceneBack(_:)),
                                               name: UIScene.didActivateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowLostKey(_:)),
                                               name: UIWindow.didResignKeyNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        displayLink?.invalidate()
        glowTimer?.invalidate()
        wheel.stop()
    }

    public func setScheme(_ scheme: TouchScheme) {
        engine.setScheme(scheme)
        bindArcRedraw()
        relayout(force: true)
        updateAmbient()
        // A new Zone starts as the panel left things: still editing, same selection.
        let session = editSession
        editSession = nil
        editSession = session
    }

    /// Arc changes state from outside the touch path too (a settings row starts calibration, a
    /// card button says Done); the pad must redraw then, or it shows the old state until a finger lands.
    private func bindArcRedraw() {
        (engine.scheme as? ArcPad)?.onStateChange = { [weak self] in
            DispatchQueue.main.async { self?.changed() }
        }
    }

    // MARK: Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        relayout()
    }

    public override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        relayout()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        impact.prepare()
        relayout()
        updateAmbient()
    }

    private func toLocal(_ r: CGRect) -> CGRect {
        guard rectSpace == .window, window != nil else { return r }
        return convert(r, from: nil)
    }

    private func relayout(force: Bool = false) {
        let i = safeAreaInsets
        let e = extraInsets
        let ctx = LayoutContext(size: bounds.size,
                                safeInsets: Insets(top: i.top + e.top, left: i.left + e.left,
                                                   bottom: i.bottom + e.bottom, right: i.right + e.right),
                                videoRects: videoRects.map(toLocal), touchscreenRect: touchscreenRect.map(toLocal),
                                scale: scale, stick: stickTuning, stickSpacing: stickSpacing,
                                shoulderOffset: shoulderOffset, calibration: calibration, tolerance: tolerance,
                                showcaseStyle: showcaseStyle, edits: edits)
        if force || ctx != engine.context {
            engine.setContext(ctx)
            if force { engine.scheme.layout(ctx) }
            changed()
        }
    }

    // MARK: Touches

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isInputEnabled, isUserInteractionEnabled, !isHidden, alpha > 0.01,
              self.point(inside: point, with: event) else { return nil }
        if let overlay = arcOverlay, overlay.superview === self,
           let hit = overlay.hitTest(convert(point, to: overlay), with: event) { return hit }
        // Only touches a control (or the GamePad touchscreen) wants. A pad that took every
        // touch while a thumb was down would block the host's own buttons - pause, back -
        // for as long as a stick was held, and gain nothing: an unclaimed touch is
        // dropped anyway.
        // Editing: only a control takes a touch (the GamePad screen under the pad is not being played).
        if editingZone != nil { return engine.scheme.claims(point) ? self : nil }
        return engine.claims(point) ? self : nil
    }

    private func id(_ t: UITouch) -> TouchID { ObjectIdentifier(t).hashValue }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let zone = editingZone { editBegan(touches, zone); return }
        // No other finger is down, so anything the engine still holds is a leaked touch whose end never arrived.
        if let all = event?.allTouches {
            if all.count == touches.count { engine.cancelAll() }
            reconcile(with: all)
        }
        for t in touches {
            (engine.scheme as? ArcPad)?.contactRadius = t.majorRadius
            engine.began(id(t), at: t.location(in: self), time: t.timestamp)
        }
        changed()
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let zone = editingZone { editMoved(touches, zone); return }
        for t in touches {
            // Coalesced touches: every intermediate sample, so a fast flick across two
            // buttons or a quick stick snap is not reduced to its endpoints.
            (engine.scheme as? ArcPad)?.contactRadius = t.majorRadius
            for c in event?.coalescedTouches(for: t) ?? [t] {
                engine.moved(id(t), to: c.location(in: self), time: c.timestamp)
            }
        }
        changed()
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if editingZone != nil { editEnded(touches); return }
        for t in touches { engine.ended(id(t), at: t.location(in: self), time: t.timestamp) }
        if let all = event?.allTouches { reconcile(with: all) }
        changed()
    }

    /// Anything the engine holds for a finger the system no longer lists as down is released.
    private func reconcile(with all: Set<UITouch>) {
        let live = Set(all.filter { $0.phase != .ended && $0.phase != .cancelled }.map(id))
        engine.reconcile(live: live)
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if editingZone != nil { editEnded(touches); return }
        for t in touches { engine.cancelled(id(t), time: t.timestamp) }
        changed()
    }

    public override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            engine.ambientEnabled = false
            dropAll()
            wheel.stop()
        }
    }

    /// Every finger forgotten and every input released - the view is leaving, or the app
    /// is. The stuck-button guard lives here, once, for the whole pad.
    @objc public func dropAll() {
        // Anything the pad holds for the player (auto-accelerate) goes too, until the pad is
        // live again: a backgrounded or paused game must not keep A down.
        engine.ambientEnabled = false
        engine.cancelAll()
        changed()
    }

    @objc private func becameActive() {
        impact.prepare()
        updateAmbient()
    }

    /// A scene or window notification: drop everything, but only when it is ours.
    @objc private func sceneLeft(_ note: Notification) {
        if let scene = note.object as? UIScene, scene !== window?.windowScene { return }
        dropAll()
    }

    @objc private func sceneBack(_ note: Notification) {
        guard let scene = note.object as? UIScene, scene === window?.windowScene else { return }
        becameActive()
    }

    /// Another window took key (a system alert): fingers go, the game keeps what it was holding for the player.
    @objc private func windowLostKey(_ note: Notification) {
        guard let other = note.object as? UIWindow, other === window else { return }
        engine.cancelAll()
        changed()
    }

    // A pad that is hidden or switched off mid-press must not keep what the finger held.
    public override var isHidden: Bool { didSet { if isHidden { dropAll() } } }
    public override var isUserInteractionEnabled: Bool {
        didSet { if !isUserInteractionEnabled { dropAll() } }
    }

    /// Turns what the pad holds for the player on or off with whether the pad is live, and
    /// runs the motion sensor only while the scheme steers from it.
    private func updateAmbient() {
        let live = isInputEnabled && window != nil && UIApplication.shared.applicationState == .active
        engine.ambientEnabled = live
        if live, engine.scheme.wantsMotion {
            wheel.start { [weak self] angle in
                guard let self else { return }
                self.engine.motion(angle: angle)
                self.changed(redraw: self.engine.scheme.wantsMotion)
            } orientation: { [weak self] in
                self?.window?.windowScene?.interfaceOrientation ?? .landscapeRight
            }
        } else {
            wheel.stop()
        }
        changed()
    }

    private func changed(redraw: Bool = true) {
        let pressed = engine.mixer.pressed
        if hapticsEnabled, !pressed.subtracting(lastPressed).isEmpty {
            impact.impactOccurred(intensity: 0.7)
            // Warm the engine for the next press, so its haptic isn't late.
            impact.prepare()
        }
        lastPressed = pressed
        // Arc's fine-tune snap: one light tick each time a dragged control settles on a guide.
        if (engine.scheme as? ArcPad)?.takeSnapTick() == true, hapticsEnabled { snapFeedback.selectionChanged() }
        if redraw { invalidatePad() }
        updateDisplayLink()
        scheduleGlowRedraw()
        onChange?()
    }

    /// A button drawn pressed only for its minimum time needs one more draw when that runs out.
    private func scheduleGlowRedraw() {
        glowTimer?.invalidate()
        glowTimer = nil
        guard let expiry = engine.nextLitExpiry() else { return }
        let delay = max(0.005, expiry - engine.clock())
        glowTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.glowTimer = nil
            self?.invalidatePad()
        }
    }

    private func updateDisplayLink() {
        // A press still easing needs a frame each refresh too, though the scheme itself needs no ticks.
        let ticking = engine.needsTicks || pressEasing
        if ticking, displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else if !ticking, let link = displayLink {
            link.invalidate()
            displayLink = nil
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        if engine.needsTicks { engine.tick(time: link.timestamp) }
        changed()
    }

    // MARK: Editing

    /// The Zone pad while it is being edited.
    private var editingZone: ZonePad? {
        guard editSession != nil, let zone = engine.scheme as? ZonePad, zone.isEditing else { return nil }
        return zone
    }

    /// Takes `edit` for `key` as the layout now: the pad moves at once, and the host is told.
    private func setEdit(_ edit: PadEdit, for key: String, final: Bool) {
        var next = engine.context.edits
        next[key] = edit
        edits = next
        editSession?.onEdits(next, final)
        invalidatePad(full: true)
    }

    private func select(_ key: String?, in zone: ZonePad) {
        guard zone.editSelection != key else { return }
        zone.editSelection = key
        editSession?.selection = key
        editSession?.onSelect(key)
        snapFeedback.selectionChanged()
        invalidatePad(full: true)
    }

    private func editBegan(_ touches: Set<UITouch>, _ zone: ZonePad) {
        guard editDrag == nil, let t = touches.first else { return }
        let p = t.location(in: self)
        guard let key = zone.editTarget(at: p) else { return }
        select(key, in: zone)
        editDrag = (key, p, zone.currentEdit(for: key), id(t))
    }

    private func editMoved(_ touches: Set<UITouch>, _ zone: ZonePad) {
        guard let drag = editDrag, let t = touches.first(where: { id($0) == drag.finger }) else { return }
        let u = max(zone.editUnit, 1)
        let here = t.location(in: self)
        let now = zone.currentEdit(for: drag.key)
        let want = PadEdit(dx: drag.origin.dx + (here.x - drag.start.x) / u,
                           dy: drag.origin.dy + (here.y - drag.start.y) / u, scale: now.scale)
        let got = zone.resolveEdit(want, for: drag.key, start: now)
        if got != now { setEdit(got, for: drag.key, final: false) }
    }

    private func editEnded(_ touches: Set<UITouch>) {
        guard let drag = editDrag, touches.contains(where: { id($0) == drag.finger }) else { return }
        editDrag = nil
        editSession?.onEdits(engine.context.edits, true)
    }

    @objc private func pinched(_ g: UIPinchGestureRecognizer) {
        guard let zone = editingZone else { return }
        switch g.state {
        case .began:
            if zone.editSelection == nil { select(zone.editTarget(at: g.location(in: self)), in: zone) }
            if let key = zone.editSelection { pinchOrigin = zone.currentEdit(for: key) }
        case .changed:
            guard let key = zone.editSelection, let origin = pinchOrigin else { return }
            let now = zone.currentEdit(for: key)
            let want = PadEdit(dx: now.dx, dy: now.dy, scale: origin.scale * g.scale)
            let got = zone.resolveEdit(want, for: key, start: now)
            if got != now { setEdit(got, for: key, final: false) }
        case .ended, .cancelled, .failed:
            pinchOrigin = nil
            editSession?.onEdits(engine.context.edits, true)
        default:
            break
        }
    }

    /// Dashed outlines round everything that can be picked, a solid one round what is picked.
    private func drawEditOutlines(_ g: CGContext) {
        guard let zone = editingZone else { return }
        let accent = UIColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 1)
        for o in zone.editOutlines() {
            let rect = o.rect.insetBy(dx: -5, dy: -5)
            let radius = min(14, min(rect.width, rect.height) / 2)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
            if o.selected {
                accent.withAlphaComponent(0.16).setFill()
                path.fill()
                accent.setStroke()
                path.lineWidth = 2.5
            } else {
                UIColor.white.withAlphaComponent(0.6).setStroke()
                path.lineWidth = 1.5
                path.setLineDash([4, 4], count: 2, phase: 0)
            }
            path.stroke()
        }
    }

    // MARK: Showcase scene cache

    /// The Showcase look as a scene, for the schemes that wear it; nil for the flat look and Arc.
    /// Building it steps the press easing, so it is built once per change, not once per draw.
    private func makeScene() -> ShowcaseScene? {
        if let showcase = engine.scheme as? ShowcasePad {
            let scene = showcase.scene(pressed: engine.litButtons(), sticks: engine.mixer.sticks,
                                       opacity: controlOpacity, time: CACurrentMediaTime(),
                                       reduceMotion: UIAccessibility.isReduceMotionEnabled)
            pressEasing = showcase.isAnimatingPress
            return scene
        }
        pressEasing = false
        if showcaseStyle && PadStyle.appliesTo(engine.scheme.info.id) {
            return PadStyle.scene(elements: engine.render(), size: bounds.size,
                                  look: PadStyle.look(colourPreset), opacity: controlOpacity)
        }
        return nil
    }

    /// Rebuilds the scene and brings the cache to it. Returns the area of the view that now looks
    /// different (nil: none, `.infinite`: all of it).
    private func refreshScene() -> CGRect? {
        guard let scene = makeScene() else {
            shown = nil
            cache.reset()
            return .infinite
        }
        let parts = scene.split()
        // A knob that something later in the scene overlaps is not the topmost thing: draw the scene whole.
        guard parts.knobsOnTop else {
            shown = ShownScene(scene: scene, parts: nil, size: bounds.size)
            cache.reset()
            return .infinite
        }
        var dirty: CGRect? = cache.update(parts.base, size: bounds.size, scale: contentScaleFactor)
        if let old = shown, let oldParts = old.parts, old.size == bounds.size {
            if oldParts.opacity != parts.opacity { dirty = .infinite }
            if oldParts.knobs != parts.knobs {
                // The knobs moved: their old and new areas, shadows included.
                var area = CGRect.null
                for p in oldParts.knobs + parts.knobs { area = area.union(p.bounds) }
                if !area.isNull { dirty = Self.merged(dirty, area) }
            }
        } else {
            dirty = .infinite
        }
        shown = ShownScene(scene: scene, parts: parts, size: bounds.size)
        return dirty
    }

    private static func merged(_ a: CGRect?, _ b: CGRect) -> CGRect {
        guard let a else { return b }
        return a.isInfinite ? a : a.union(b)
    }

    /// The pad's content changed: redraw what is different. `full` also redraws what the scene does not
    /// hold (edit outlines) and anything a setting changed everywhere.
    private func invalidatePad(full: Bool = false) {
        let dirty = refreshScene()
        if full { setNeedsDisplay(); return }
        guard let dirty else { return }
        if dirty.isInfinite { setNeedsDisplay() } else { setNeedsDisplay(dirty.insetBy(dx: -1, dy: -1)) }
    }

    // MARK: Drawing

    public override func draw(_ rect: CGRect) {
        guard let g = UIGraphicsGetCurrentContext() else { return }
        drawPad(g)
        drawEditOutlines(g)
    }

    private func drawPad(_ g: CGContext) {
        // Showcase has its own look (shadow, rim, dish, octagonal gate), as a scene to draw. The scene
        // was built when the pad last changed; a size the pad has just been given needs a fresh one.
        if shown == nil || shown?.size != bounds.size || (shown?.parts != nil && !cache.matches(size: bounds.size, scale: contentScaleFactor)) {
            _ = refreshScene()
        }
        if let shown {
            if let parts = shown.parts {
                cache.composite(knobs: parts.knobs, opacity: parts.opacity, in: g)
            } else {
                ShowcaseDrawing.draw(shown.scene, in: g)
            }
            return
        }
        for e in engine.render() {
            if e.role == .guide { PadDrawing.drawGuide(e, in: g, opacity: controlOpacity) }
            else if e.style == .refined { PadDrawing.drawRefined(e, in: g, opacity: controlOpacity) }
            else { PadDrawing.draw(e, in: g, opacity: controlOpacity) }
        }
    }
}

/// What the host tells the pad while the player is editing it, and how the pad reports back.
public struct PadEditSession {
    /// What a tap picks: one control, or its whole cluster.
    public var granularity: PadEditGranularity
    /// The picked target's key, if any.
    public var selection: String?
    /// A control or cluster was picked.
    public var onSelect: (String?) -> Void
    /// The edits changed; `final` once the finger lifts, so the host can save then and not on every frame.
    public var onEdits: (PadEdits, Bool) -> Void

    public init(granularity: PadEditGranularity, selection: String?,
                onSelect: @escaping (String?) -> Void, onEdits: @escaping (PadEdits, Bool) -> Void) {
        self.granularity = granularity
        self.selection = selection
        self.onSelect = onSelect
        self.onEdits = onEdits
    }
}

enum PadDrawing {
    static func draw(_ e: RenderElement, in g: CGContext, opacity: CGFloat) {
        let path: UIBezierPath
        switch e.shape {
        case .circle(let c, let r):
            path = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        case .roundedRect(let rect, let cr):
            path = UIBezierPath(roundedRect: rect, cornerRadius: cr)
        }
        let alpha: CGFloat
        switch e.role {
        case .zone: alpha = e.lit ? 0.10 : 0.0
        case .touchscreen: alpha = 0
        // Racing's steering area: always there, faint enough to leave the game visible.
        case .area: alpha = (e.lit ? 0.34 : 0.2) * opacity
        // Racing's pedals: large, so drawn lighter than a button.
        case .pedal: alpha = 0.62 * opacity
        default: alpha = (e.ghost ? 0.3 : 1) * opacity
        }
        guard alpha > 0 else { return }

        let (fill, stroke, text) = colours(e)
        fill.withAlphaComponent(alpha * (e.lit ? 0.95 : 0.55)).setFill()
        path.fill()
        stroke.withAlphaComponent(alpha * 0.9).setStroke()
        path.lineWidth = 1.5
        path.stroke()

        guard !e.label.isEmpty, e.role != .zone, e.role != .stickBase else { return }
        let box = e.shape.boundingBox
        let size = max(min(box.height * 0.42, 26), 10)
        let label = LabelCache.image(e.label, size: size, text: text, alpha: alpha)
        label.draw(at: CGPoint(x: box.midX - label.size.width / 2, y: box.midY - label.size.height / 2))
    }

    static func colours(_ e: RenderElement) -> (UIColor, UIColor, UIColor) {
        if e.lit, e.role != .stickBase, e.role != .area {
            return (UIColor(red: 1, green: 0.79, blue: 0.24, alpha: 1), .white, UIColor(white: 0.1, alpha: 1))
        }
        switch e.role {
        case .face: return (UIColor(white: 0.93, alpha: 1), .white, UIColor(white: 0.12, alpha: 1))
        case .dpad: return (UIColor(white: 0.80, alpha: 1), .white, UIColor(white: 0.12, alpha: 1))
        case .shoulder: return (UIColor(white: 0.58, alpha: 1), UIColor(white: 0.8, alpha: 1), UIColor(white: 0.05, alpha: 1))
        case .system, .dot: return (UIColor(white: 0.40, alpha: 1), UIColor(white: 0.65, alpha: 1), .white)
        case .stickBase: return (UIColor(white: 0.22, alpha: 1), UIColor(white: 0.5, alpha: 1), .white)
        case .stickKnob: return (UIColor(white: 0.75, alpha: 1), .white, UIColor(white: 0.12, alpha: 1))
        case .zone, .touchscreen: return (UIColor(red: 0.5, green: 0.66, blue: 1, alpha: 1), .clear, .clear)
        case .area: return (UIColor(red: 0.5, green: 0.66, blue: 1, alpha: 1), UIColor(red: 0.6, green: 0.74, blue: 1, alpha: 1),
                            UIColor(red: 0.77, green: 0.84, blue: 1, alpha: 1))
        case .pedal: return (UIColor(white: 0.85, alpha: 1), .white, UIColor(white: 0.1, alpha: 1))
        case .guide, .handle: return (UIColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 1), UIColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 1), .white)
        }
    }

    private static func ui(_ c: LookRGBA, _ alpha: CGFloat = 1) -> UIColor {
        UIColor(red: c.r, green: c.g, blue: c.b, alpha: CGFloat(c.a) * alpha)
    }

    /// A line along `e.path`: Arc's arc band, sweep trace, fitted-arc preview and snap ticks.
    static func drawGuide(_ e: RenderElement, in g: CGContext, opacity: CGFloat) {
        guard e.path.count > 1 else { return }
        let scale = opacity / PadSettings.defaultOpacity
        let base: CGFloat = e.ghost ? 0.28 : (e.lit ? 0.9 : 0.6)
        let alpha = min(1, base * e.fade * scale)
        guard alpha > 0.005 else { return }
        let path = UIBezierPath()
        path.move(to: e.path[0])
        for p in e.path.dropFirst() { path.addLine(to: p) }
        path.lineWidth = max(e.width, 1)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        if e.dash > 0 { path.setLineDash([e.dash, e.dash * 1.4], count: 2, phase: 0) }
        ui(RefinedLook.tone(e.tone), alpha).setStroke()
        path.stroke()
    }

    /// Arc's look (see `RefinedLook`): a body with a hairline outline and a soft shadow, a rim
    /// lit from above, a held state that sinks, and a label that stays legible at any size.
    static func drawRefined(_ e: RenderElement, in g: CGContext, opacity: CGFloat) {
        let look = RefinedLook.of(e)
        let alpha = min(1, (e.ghost ? 0.3 : 1) * e.fade * opacity / PadSettings.defaultOpacity)
        guard alpha > 0.005 else { return }
        let box = e.shape.boundingBox
        func outline(inset: CGFloat) -> UIBezierPath {
            let k = look.scale
            switch e.shape {
            case .circle(let c, let r):
                let rr = max(r * k - inset, 0.5)
                return UIBezierPath(ovalIn: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr))
            case .roundedRect(let rect, let cr):
                let w = rect.width * k - 2 * inset, h = rect.height * k - 2 * inset
                let r = CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
                return UIBezierPath(roundedRect: r, cornerRadius: max(min(cr * k, min(w, h) / 2), 0))
            }
        }
        let body = outline(inset: 0)
        g.saveGState()
        g.setShadow(offset: CGSize(width: 0, height: look.shadowDY), blur: look.shadowBlur,
                    color: UIColor.black.withAlphaComponent(CGFloat(look.shadowOpacity) * alpha).cgColor)
        ui(look.body, alpha).setFill()
        body.fill()
        g.restoreGState()
        ui(look.outline, alpha).setStroke()
        body.lineWidth = look.outlineWidth
        body.stroke()
        if look.rim.a > 0.01 {
            // Lit from above: the rim fades out over the top half.
            g.saveGState()
            g.clip(to: CGRect(x: box.minX - 2, y: box.minY - 2, width: box.width + 4, height: box.height * 0.5 + 2))
            let rim = outline(inset: 1.4)
            rim.lineWidth = 1
            ui(look.rim, alpha).setStroke()
            rim.stroke()
            g.restoreGState()
        }
        guard !e.label.isEmpty, e.role != .stickBase else { return }
        let size = RefinedLook.labelSize(for: box)
        let label = LabelCache.image(e.label, size: size, text: ui(look.text), alpha: alpha)
        label.draw(at: CGPoint(x: box.midX - label.size.width / 2, y: box.midY - label.size.height / 2))
    }
}

/// SwiftUI wrapper. The host keeps the `TouchPadView` alive across updates; scheme and
/// geometry changes are pushed in, never rebuilt, so a finger that is down stays down.
///
/// `makeScheme` builds the scheme for an id - override it to configure one (Float's camera
/// mode, Adaptive's saved positions). Bump `revision` to rebuild with the same id after
/// such a setting changes.
public struct TouchPad: UIViewRepresentable {
    public var schemeID: String
    public var revision: Int
    public var makeScheme: (String) -> TouchScheme
    public var output: PadOutput
    public var touchscreenRect: CGRect?
    public var videoRects: [CGRect]
    public var scale: CGFloat
    public var stickSpacing: CGFloat
    public var shoulderOffset: CGFloat
    public var opacity: CGFloat
    public var haptics: Bool
    public var enabled: Bool
    public var stickTuning: StickTuning
    public var calibration = StickCalibrations()
    public var tolerance: PadTolerance?
    public var colourPreset: ShowcaseColourPreset?
    public var showcaseStyle = true
    /// See `LayoutContext.edits`.
    public var edits = PadEdits()
    /// Set while the player is editing the pad (Zone); nil otherwise.
    public var editSession: PadEditSession?
    public var rectSpace: TouchPadView.RectSpace
    public var extraInsets: Insets
    public var onChange: ((PadEngine) -> Void)?
    /// Called once with the live view, for a host that needs to reach it (Arc's calibration overlay).
    public var onView: ((TouchPadView) -> Void)?

    public init(schemeID: String, output: PadOutput, touchscreenRect: CGRect? = nil, videoRects: [CGRect] = [],
                scale: CGFloat = 1, stickSpacing: CGFloat = 0, shoulderOffset: CGFloat = 0, opacity: CGFloat = 0.85, haptics: Bool = true, revision: Int = 0,
                enabled: Bool = true, stickTuning: StickTuning = StickTuning(),
                rectSpace: TouchPadView.RectSpace = .local, extraInsets: Insets = Insets(),
                makeScheme: @escaping (String) -> TouchScheme = SchemeCatalog.make,
                onChange: ((PadEngine) -> Void)? = nil) {
        self.enabled = enabled
        self.stickTuning = stickTuning
        self.rectSpace = rectSpace
        self.extraInsets = extraInsets
        self.schemeID = schemeID
        self.revision = revision
        self.makeScheme = makeScheme
        self.output = output
        self.touchscreenRect = touchscreenRect
        self.videoRects = videoRects
        self.scale = scale
        self.stickSpacing = stickSpacing
        self.shoulderOffset = shoulderOffset
        self.opacity = opacity
        self.haptics = haptics
        self.onChange = onChange
    }

    /// The usual way in: one `PadSettings` for every scheme.
    public init(schemeID: String, output: PadOutput, settings: PadSettings, touchscreenRect: CGRect? = nil,
                videoRects: [CGRect] = [], revision: Int = 0, enabled: Bool = true,
                rectSpace: TouchPadView.RectSpace = .local, extraInsets: Insets = Insets(),
                makeScheme: @escaping (String) -> TouchScheme = SchemeCatalog.make,
                onChange: ((PadEngine) -> Void)? = nil) {
        self.init(schemeID: schemeID, output: output, touchscreenRect: touchscreenRect, videoRects: videoRects,
                  scale: settings.scale, stickSpacing: settings.stickSpacing, shoulderOffset: settings.shoulderOffset,
                  opacity: settings.opacity, haptics: settings.haptics, revision: revision, enabled: enabled,
                  stickTuning: settings.stick, rectSpace: rectSpace, extraInsets: extraInsets,
                  makeScheme: makeScheme, onChange: onChange)
        self.calibration = settings.calibration
        self.tolerance = settings.tolerance
        self.colourPreset = settings.colourPreset
        self.showcaseStyle = settings.showcaseStyle
        self.edits = settings.edits
    }

    public final class Coordinator {
        var revision = 0
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeUIView(context: Context) -> TouchPadView {
        let view = TouchPadView(scheme: makeScheme(schemeID), output: output)
        context.coordinator.revision = revision
        apply(to: view)
        onView?(view)
        return view
    }

    public func updateUIView(_ view: TouchPadView, context: Context) {
        if view.engine.scheme.info.id != schemeID || context.coordinator.revision != revision {
            context.coordinator.revision = revision
            view.setScheme(makeScheme(schemeID))
        }
        apply(to: view)
    }

    private func apply(to view: TouchPadView) {
        if view.rectSpace != rectSpace { view.rectSpace = rectSpace }
        if view.extraInsets != extraInsets { view.extraInsets = extraInsets }
        if view.stickTuning != stickTuning { view.stickTuning = stickTuning }
        if view.calibration != calibration { view.calibration = calibration }
        if view.tolerance != tolerance { view.tolerance = tolerance }
        if view.colourPreset != colourPreset { view.colourPreset = colourPreset }
        if view.showcaseStyle != showcaseStyle { view.showcaseStyle = showcaseStyle }
        if view.edits != edits { view.edits = edits }
        view.editSession = editSession
        if view.isInputEnabled != enabled { view.isInputEnabled = enabled }
        if view.touchscreenRect != touchscreenRect { view.touchscreenRect = touchscreenRect }
        if view.videoRects != videoRects { view.videoRects = videoRects }
        if view.scale != scale { view.scale = scale }
        if view.stickSpacing != stickSpacing { view.stickSpacing = stickSpacing }
        if view.shoulderOffset != shoulderOffset { view.shoulderOffset = shoulderOffset }
        if view.controlOpacity != opacity { view.controlOpacity = opacity }
        view.hapticsEnabled = haptics
        let engine = view.engine
        view.onChange = onChange.map { f in { f(engine) } }
    }

    public static func dismantleUIView(_ view: TouchPadView, coordinator: Coordinator) {
        view.dropAll()
    }
}
/// The device turned like a steering wheel, as an angle in the screen's own frame: radians,
/// positive when the top of the screen turns toward the player's right, whichever way up the
/// interface is. Read from gravity, so it needs no calibration and is the same on every device;
/// the scheme decides what "straight ahead" is.
///
/// Gravity lying nearly flat on the screen's plane (a device held face up) has no wheel
/// angle, so those samples are skipped rather than turned into noise.
final class WheelAngleSource {
    private let manager = CMMotionManager()
    private var running = false

    func start(handler: @escaping (Double) -> Void, orientation: @escaping () -> UIInterfaceOrientation) {
        guard !running, manager.isDeviceMotionAvailable else { return }
        running = true
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let g = motion?.gravity else { return }
            // The screen's right and down directions in the device's x/y axes, per interface
            // orientation.
            let right: (Double, Double), down: (Double, Double)
            switch orientation() {
            case .portraitUpsideDown: right = (-1, 0); down = (0, 1)
            case .landscapeRight: right = (0, -1); down = (-1, 0)
            case .landscapeLeft: right = (0, 1); down = (1, 0)
            default: right = (1, 0); down = (0, -1)
            }
            let toRight = g.x * right.0 + g.y * right.1
            let toDown = g.x * down.0 + g.y * down.1
            guard (toRight * toRight + toDown * toDown).squareRoot() > 0.35 else { return }
            handler(atan2(toRight, toDown))
        }
    }

    func stop() {
        guard running else { return }
        running = false
        manager.stopDeviceMotionUpdates()
    }
}

/// Pad labels, rendered once with their halo. The pad redraws on every input change,
/// so during a stick drag every label would otherwise be laid out and blurred again on
/// every frame, on the main thread, while the emulator wants the CPU. What shapes a
/// label (text, size, colour, opacity) changes only with the layout or a setting.
enum LabelCache {
    private struct Key: Hashable {
        let label: String
        let size: CGFloat
        let rgba: [CGFloat]
        let alpha: CGFloat
    }

    // Drawing happens on the main thread only (UIView.draw).
    private static var images: [Key: UIImage] = [:]
    private static let limit = 256

    static func image(_ label: String, size: CGFloat, text: UIColor, alpha: CGFloat) -> UIImage {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if !text.getRed(&r, green: &g, blue: &b, alpha: &a) {
            text.getWhite(&r, alpha: &a)
            g = r; b = r
        }
        let key = Key(label: label, size: size, rgba: [r, g, b, a], alpha: alpha)
        if let cached = images[key] { return cached }

        // A halo in the opposite tone. The button behind a label is drawn at about half
        // opacity, so what the label actually sits on is mostly the game: the dark
        // shoulder labels disappeared over dark scenes and the white system labels over
        // bright ones.
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let halo = NSShadow()
        halo.shadowColor = (luminance < 0.5 ? UIColor.white : UIColor.black).withAlphaComponent(alpha * 0.7)
        halo.shadowBlurRadius = max(1.5, size * 0.12)
        halo.shadowOffset = .zero
        let str = NSAttributedString(string: label, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: text.withAlphaComponent(alpha),
            .shadow: halo,
        ])
        // Room for the blur on every side, so the halo isn't clipped at the image edge.
        let pad = ceil(halo.shadowBlurRadius * 2)
        let textSize = str.size()
        let canvas = CGSize(width: ceil(textSize.width) + 2 * pad, height: ceil(textSize.height) + 2 * pad)
        let image = UIGraphicsImageRenderer(size: canvas).image { _ in
            str.draw(at: CGPoint(x: pad, y: pad))
        }
        if images.count >= limit { images.removeAll(keepingCapacity: true) }
        images[key] = image
        return image
    }
}
#endif
