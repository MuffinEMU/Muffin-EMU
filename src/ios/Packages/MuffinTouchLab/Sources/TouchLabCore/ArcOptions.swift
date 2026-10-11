import Foundation

/// Arc's own settings, apart from the saved calibration (`ArcProfile`), so a calibration made
/// before these existed loads exactly as it was. Every default keeps today's behaviour.
public struct ArcOptions: Codable, Equatable, Sendable {
    /// Mirror the whole layout for a left-handed player: the d-pad, left stick and
    /// minus/HOME go to the right side of the screen and A/B/X/Y, the right stick and plus to
    /// the left. Each thumb keeps its own calibration and fine-tune; only which controls it
    /// carries swaps. Off by default.
    public var swapHands: Bool
    /// Seconds without a touch before the controls fade almost out; they come straight back
    /// under a thumb. nil (the default) never fades.
    public var idleFadeSeconds: Double?
    /// When the video fills the screen and Arc has to draw over it: a thinner arc, controls
    /// resting dim and brightening under the thumb. On by default; turn off for full-strength
    /// controls there too.
    public var quietOverVideo: Bool
    /// Snap guides while fine-tuning: a control dragged near an equal-spacing position (or
    /// back to its default) settles there, with a tick. On by default.
    public var snapGuides: Bool
    /// A small "Locked" badge on the pad while positions are locked (in quiet mode the badge
    /// only shows for a few seconds after locking).
    public var lockBadge: Bool

    public init(swapHands: Bool = false, idleFadeSeconds: Double? = nil, quietOverVideo: Bool = true,
                snapGuides: Bool = true, lockBadge: Bool = true) {
        self.swapHands = swapHands
        self.idleFadeSeconds = idleFadeSeconds
        self.quietOverVideo = quietOverVideo
        self.snapGuides = snapGuides
        self.lockBadge = lockBadge
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        swapHands = try c.decodeIfPresent(Bool.self, forKey: .swapHands) ?? false
        idleFadeSeconds = try c.decodeIfPresent(Double.self, forKey: .idleFadeSeconds)
        quietOverVideo = try c.decodeIfPresent(Bool.self, forKey: .quietOverVideo) ?? true
        snapGuides = try c.decodeIfPresent(Bool.self, forKey: .snapGuides) ?? true
        lockBadge = try c.decodeIfPresent(Bool.self, forKey: .lockBadge) ?? true
    }

    /// Idle-fade seconds worth honouring: finite and between 1 and 600.
    public var validIdleFade: Double? {
        guard let s = idleFadeSeconds, s.isFinite else { return nil }
        return min(max(s, 1), 600)
    }

    public static func encode(_ options: ArcOptions) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        guard let data = try? enc.encode(options) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Anything unreadable is the defaults.
    public static func decode(_ json: String) -> ArcOptions {
        (try? JSONDecoder().decode(ArcOptions.self, from: Data(json.utf8))) ?? ArcOptions()
    }
}
