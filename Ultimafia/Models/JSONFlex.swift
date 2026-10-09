import Foundation

struct FlexInt: Decodable, Hashable {
    var value: Int
    init(_ value: Int = 0) { self.value = value }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = i; return }
        if let s = try? c.decode(String.self), let i = Int(s) { value = i; return }
        if let d = try? c.decode(Double.self) { value = Int(d); return }
        if let b = try? c.decode(Bool.self) { value = b ? 1 : 0; return }
        value = 0
    }
}

struct FlexString: Decodable, Hashable {
    var value: String
    init(_ value: String = "") { self.value = value }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = ""; return }
        if let s = try? c.decode(String.self) { value = s; return }
        if let i = try? c.decode(Int.self) { value = String(i); return }
        if let d = try? c.decode(Double.self) {
            value = d == d.rounded() ? String(Int(d)) : String(d)
            return
        }
        if let b = try? c.decode(Bool.self) { value = b ? "true" : ""; return }
        value = ""
    }
}

enum JSONValue: Decodable, Sendable, Hashable {
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
        if let i = try? c.decode(Int.self) { self = .number(Double(i)); return }
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        self = .null
    }

    var asAny: Any? {
        switch self {
        case .null: return nil
        case .bool(let b): return b
        case .number(let d):
            if d.isFinite, d == d.rounded(), d >= Double(Int.min), d <= Double(Int.max) {
                return Int(d)
            }
            return d
        case .string(let s): return s
        case .array(let a): return a.compactMap(\.asAny)
        case .object(let o):
            var dict: [String: Any] = [:]
            for (k, v) in o {
                if let value = v.asAny { dict[k] = value }
            }
            return dict
        }
    }
}
