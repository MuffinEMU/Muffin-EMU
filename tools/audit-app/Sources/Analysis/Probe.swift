//
//  Probe.swift
//  The log half of the probe protocol (guest -> host). The guest's OSReport lines arrive in the core
//  log as "... MUFFINAUDIT <KIND> <fields>"; this parses them. The mailbox half lives in GuestLink.swift.
//  The wire format is specified in docs/AUDIT.md and tools/audit-app/guest/audit_protocol.h.
//
import Foundation

enum ProbeEvent: Equatable {
    case hello(protocolVersion: Int, build: String, mailbox: UInt32, tv: String)
    case testBegin(id: String, token: UInt32, seed: UInt32, params: String)
    case phase(id: String, token: UInt32, name: String)
    case checkpoint(id: String, token: UInt32, name: String, frame: Int)
    case note(id: String, token: UInt32, text: String)
    case selfCheck(id: String, token: UInt32, verdict: String, text: String)
    case testEnd(id: String, token: UInt32, status: String, checksum: String, frames: Int, errors: Int)
    case bye
}

enum Probe {
    static let prefix = "MUFFINAUDIT"

    /// nil for any line that is not a probe line or is malformed.
    static func parse(line: String) -> ProbeEvent? {
        guard let range = line.range(of: prefix + " ") else { return nil }
        let rest = String(line[range.upperBound...])
        let parts = rest.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true).map(String.init)
        guard let kind = parts.first else { return nil }

        func field(_ fields: [String], _ key: String) -> String? {
            for f in fields where f.hasPrefix(key + "=") { return String(f.dropFirst(key.count + 1)) }
            return nil
        }
        func all(_ s: String) -> [String] { s.split(separator: " ").map(String.init) }

        switch kind {
        case "HELLO":
            // HELLO <protocol> <build> mailbox=0x... tv=WxH
            let f = all(rest)
            guard f.count >= 4, let proto = Int(f[1]), let box = field(f, "mailbox"), let addr = parseHex(box) else { return nil }
            return .hello(protocolVersion: proto, build: f[2], mailbox: addr, tv: field(f, "tv") ?? "")
        case "TEST_BEGIN":
            // TEST_BEGIN <id> <token> seed=<n> <params...>
            let f = all(rest)
            guard f.count >= 4, let token = UInt32(f[2]) else { return nil }
            let seed = UInt32(field(f, "seed") ?? "0") ?? 0
            let params = f.count > 4 ? f[4...].joined(separator: " ") : ""
            return .testBegin(id: f[1], token: token, seed: seed, params: params)
        case "PHASE":
            let f = rest.split(separator: " ", maxSplits: 3).map(String.init)
            guard f.count >= 4, let token = UInt32(f[2]) else { return nil }
            return .phase(id: f[1], token: token, name: f[3])
        case "CHECKPOINT":
            let f = all(rest)
            guard f.count >= 4, let token = UInt32(f[2]) else { return nil }
            let frame = Int(field(f, "frame") ?? "0") ?? 0
            return .checkpoint(id: f[1], token: token, name: f[3], frame: frame)
        case "NOTE":
            let f = rest.split(separator: " ", maxSplits: 3).map(String.init)
            guard f.count >= 3, let token = UInt32(f[2]) else { return nil }
            return .note(id: f[1], token: token, text: f.count > 3 ? f[3] : "")
        case "SELF":
            let f = rest.split(separator: " ", maxSplits: 4).map(String.init)
            guard f.count >= 4, let token = UInt32(f[2]) else { return nil }
            return .selfCheck(id: f[1], token: token, verdict: f[3], text: f.count > 4 ? f[4] : "")
        case "TEST_END":
            let f = all(rest)
            guard f.count >= 4, let token = UInt32(f[2]) else { return nil }
            return .testEnd(id: f[1], token: token, status: f[3], checksum: field(f, "checksum") ?? "",
                            frames: Int(field(f, "frames") ?? "0") ?? 0, errors: Int(field(f, "errors") ?? "0") ?? 0)
        case "BYE":
            return .bye
        default:
            return nil
        }
    }

    static func parseHex(_ s: String) -> UInt32? {
        let t = s.hasPrefix("0x") || s.hasPrefix("0X") ? String(s.dropFirst(2)) : s
        return UInt32(t, radix: 16)
    }

    /// The core's live log prefixes every line with "HH:MM:SS.mmm +  1.234s ". Returns the seconds and the rest.
    static func splitCoreStamp(_ line: String) -> (elapsed: Double?, text: String) {
        // "12:34:56.789 +  1.234s text"
        let scalars = Array(line.unicodeScalars)
        guard scalars.count > 20, scalars[2] == ":", scalars[5] == ":", scalars[8] == "." else { return (nil, line) }
        guard let plus = line.firstIndex(of: "+"), let s = line[plus...].firstIndex(of: "s") else { return (nil, line) }
        let number = line[line.index(after: plus)..<s].trimmingCharacters(in: .whitespaces)
        let rest = line[line.index(after: s)...].drop(while: { $0 == " " })
        return (Double(number), String(rest))
    }
}
