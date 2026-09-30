//
//  JSONValue.swift
//  A small generic JSON value. The core's state snapshot is a JSON object whose fields grow as the
//  core grows; carrying it as a value (instead of a struct that has to be edited for every new
//  counter) means a new counter shows up in reports and in the diff without touching the app.
//
import Foundation

enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    static func parse(_ text: String) -> JSONValue? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    var double: Double? { if case .number(let d) = self { return d }; return nil }
    var int: Int? { if case .number(let d) = self, d.isFinite { return Int(d) }; return nil }
    var string: String? { if case .string(let s) = self { return s }; return nil }
    var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    var object: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }

    /// Looks a value up by a dotted path ("gpuThread.cbErrorStreak").
    func path(_ dotted: String) -> JSONValue? {
        var current: JSONValue? = self
        for part in dotted.split(separator: ".") {
            current = current?[String(part)]
            if current == nil { return nil }
        }
        return current
    }

    /// `self - earlier` for every numeric leaf both objects share. Booleans, strings and leaves that only
    /// one side has come through as they are in `self`, so the result has the same shape as the snapshot.
    func delta(from earlier: JSONValue) -> JSONValue {
        switch (self, earlier) {
        case (.number(let a), .number(let b)):
            return .number(a - b)
        case (.object(let a), .object(let b)):
            var out: [String: JSONValue] = [:]
            for (k, v) in a {
                if let e = b[k] { out[k] = v.delta(from: e) } else { out[k] = v }
            }
            return .object(out)
        default:
            return self
        }
    }
}
