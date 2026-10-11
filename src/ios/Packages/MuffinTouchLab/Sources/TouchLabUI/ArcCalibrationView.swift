#if canImport(UIKit)
import UIKit
import TouchLabCore

/// The guided calibration for Arc: "Sweep your left thumb in a comfortable arc", then the
/// right, then a review with Done and Redo. The animated example sweep, the live trace, the
/// fitted arc under the thumb and the finished-layout preview are drawn by the pad itself
/// (ArcPad.render); this view is only the prompt card and its buttons. It works the same in
/// portrait and landscape: the card hugs the top of the safe area and wraps its text.
///
/// It is transparent to touches everywhere except its buttons, so the sweep reaches the pad
/// underneath. Add it over the pad with `TouchPadView.presentArcCalibration`, or build one
/// yourself and add it above a `TouchPadView` that shows the same `ArcPad`.
public final class ArcCalibrationView: UIView {
    public let scheme: ArcPad
    /// true = the player pressed Done, false = cancelled.
    public var onFinished: ((Bool) -> Void)?

    private let card = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let stepLabel = UILabel()
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

        stepLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        stepLabel.textColor = UIColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 1)
        stepLabel.textAlignment = .center
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
        // Done is the one filled pill; the rest are plain text buttons.
        doneButton.backgroundColor = UIColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 1)
        doneButton.setTitleColor(UIColor(white: 0.08, alpha: 1), for: .normal)
        doneButton.contentEdgeInsets = UIEdgeInsets(top: 7, left: 22, bottom: 7, right: 22)
        doneButton.layer.cornerRadius = 17
        doneButton.clipsToBounds = true
        style(redoButton, "Redo", #selector(redo))
        style(skipButton, "Skip this hand", #selector(skipHand))
        style(cancelButton, "Cancel", #selector(cancel))
        [redoButton, skipButton, cancelButton, doneButton].forEach(buttons.addArrangedSubview)
        buttons.axis = .horizontal
        buttons.spacing = 20
        buttons.distribution = .equalSpacing

        let stack = UIStackView(arrangedSubviews: [stepLabel, titleLabel, noteLabel, buttons])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        // Same recipe as the pad's controls: a hairline edge and continuous corners.
        card.layer.cornerRadius = 22
        if #available(iOS 13.0, *) { card.layer.cornerCurve = .continuous }
        card.clipsToBounds = true
        card.layer.borderWidth = 0.5
        card.layer.borderColor = UIColor(white: 1, alpha: 0.28).cgColor
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
        // The card shows the prompt and notes, so the pad stops drawing its own.
        scheme.drawsPrompts = false
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
            scheme.drawsPrompts = true
            scheme.onSettingsChange = previousHandler
            removeFromSuperview()
            return
        }
        stepLabel.text = scheme.calibrationStep
        titleLabel.text = scheme.calibrationPrompt
        noteLabel.text = scheme.calibrationNote ?? (phase == .review ? nil : "One smooth sweep, then lift.")
        noteLabel.isHidden = noteLabel.text == nil
        // A note that explains a rejected sweep is amber; the default hint stays quiet.
        let rejected = scheme.calibrationNote != nil
        noteLabel.textColor = rejected ? UIColor(red: 1, green: 0.70, blue: 0.25, alpha: 1) : UIColor(white: 1, alpha: 0.7)
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
        scheme.drawsPrompts = true
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
