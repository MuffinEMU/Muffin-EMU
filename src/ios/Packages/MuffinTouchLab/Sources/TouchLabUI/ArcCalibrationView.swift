#if canImport(UIKit)
import UIKit
import TouchLabCore

/// The guided calibration for Arc: "Sweep your left thumb in a comfortable arc", then the
/// right, then a review with Done and Redo. The live trace and the fitted arcs are drawn by
/// the pad itself (ArcPad.render); this view is only the prompt card and its buttons.
///
/// It is transparent to touches everywhere except its buttons, so the sweep reaches the pad
/// underneath. Add it over the pad with `TouchPadView.presentArcCalibration`, or build one
/// yourself and add it above a `TouchPadView` that shows the same `ArcPad`.
public final class ArcCalibrationView: UIView {
    public let scheme: ArcPad
    /// true = the player pressed Done, false = cancelled.
    public var onFinished: ((Bool) -> Void)?

    private let card = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let titleLabel = UILabel()
    private let noteLabel = UILabel()
    private let doneButton = UIButton(type: .system)
    private let redoButton = UIButton(type: .system)
    private let skipButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let buttons = UIStackView()
    private var previousHandler: (() -> Void)?

    public init(scheme: ArcPad) {
        self.scheme = scheme
        super.init(frame: .zero)
        backgroundColor = .clear
        autoresizingMask = [.flexibleWidth, .flexibleHeight]

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        noteLabel.font = .systemFont(ofSize: 13)
        noteLabel.textColor = UIColor(white: 1, alpha: 0.7)
        noteLabel.textAlignment = .center
        noteLabel.numberOfLines = 0

        func style(_ b: UIButton, _ title: String, _ action: Selector, bold: Bool = false) {
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 16, weight: bold ? .semibold : .regular)
            b.addTarget(self, action: action, for: .touchUpInside)
        }
        style(doneButton, "Done", #selector(done), bold: true)
        style(redoButton, "Redo", #selector(redo))
        style(skipButton, "Skip this hand", #selector(skipHand))
        style(cancelButton, "Cancel", #selector(cancel))
        [redoButton, skipButton, cancelButton, doneButton].forEach(buttons.addArrangedSubview)
        buttons.axis = .horizontal
        buttons.spacing = 20
        buttons.distribution = .equalSpacing

        let stack = UIStackView(arrangedSubviews: [titleLabel, noteLabel, buttons])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 16
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(stack)
        addSubview(card)
        let margin = card.contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: margin.topAnchor),
            stack.bottomAnchor.constraint(equalTo: margin.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: margin.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: margin.trailingAnchor),
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 460),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
        ])
        card.contentView.layoutMargins = UIEdgeInsets(top: 14, left: 18, bottom: 14, right: 18)

        // Chain in front of whatever the host already bound, and put it back when done.
        previousHandler = scheme.onSettingsChange
        scheme.onSettingsChange = { [weak self] in
            self?.previousHandler?()
            DispatchQueue.main.async { self?.refresh() }
        }
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Only the card's buttons take touches; the sweep goes to the pad underneath.
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self || hit === card || hit === card.contentView ? nil : hit
    }

    private func refresh() {
        guard let phase = scheme.calibrationPhase else {
            scheme.onSettingsChange = previousHandler
            removeFromSuperview()
            return
        }
        titleLabel.text = scheme.calibrationPrompt
        noteLabel.text = scheme.calibrationNote ?? (phase == .review ? nil : "One smooth sweep, then lift.")
        noteLabel.isHidden = noteLabel.text == nil
        let reviewing = phase == .review
        doneButton.isHidden = !reviewing
        redoButton.isHidden = !reviewing
        skipButton.isHidden = reviewing
    }

    @objc private func done() {
        scheme.acceptCalibration()
        finish(true)
    }

    @objc private func redo() { scheme.redoCalibration() }

    @objc private func skipHand() { scheme.skipCalibrationHand() }

    @objc private func cancel() {
        scheme.cancelCalibration()
        finish(false)
    }

    private func finish(_ accepted: Bool) {
        scheme.onSettingsChange = previousHandler
        removeFromSuperview()
        onFinished?(accepted)
    }
}

public extension TouchPadView {
    /// The pad's scheme when it is Arc.
    var arcScheme: ArcPad? { engine.scheme as? ArcPad }

    /// Starts Arc's guided calibration and shows the prompt card over this pad (as a
    /// sibling above it, since the pad takes touches itself). Returns false when the scheme
    /// is not Arc, positions are locked, or the pad is not in a view yet.
    @discardableResult
    func presentArcCalibration(completion: ((Bool) -> Void)? = nil) -> Bool {
        guard let arc = arcScheme, let host = superview, arc.startCalibration() else { return false }
        let overlay = ArcCalibrationView(scheme: arc)
        overlay.frame = frame
        overlay.onFinished = completion
        host.insertSubview(overlay, aboveSubview: self)
        return true
    }
}
#endif
