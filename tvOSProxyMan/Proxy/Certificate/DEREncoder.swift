import Foundation

enum DER {

    // MARK: - Primitives

    static func encode(tag: UInt8, content: Data) -> Data {
        var out = Data([tag])
        out.append(length(content.count))
        out.append(content)
        return out
    }

    private static func length(_ n: Int) -> Data {
        switch n {
        case 0..<0x80:    return Data([UInt8(n)])
        case 0..<0x100:   return Data([0x81, UInt8(n)])
        case 0..<0x10000: return Data([0x82, UInt8(n >> 8), UInt8(n & 0xFF)])
        default:
            return Data([0x83,
                         UInt8((n >> 16) & 0xFF),
                         UInt8((n >>  8) & 0xFF),
                         UInt8( n        & 0xFF)])
        }
    }

    // MARK: - INTEGER

    static func integer(_ value: Int) -> Data {
        if value == 0 { return encode(tag: 0x02, content: Data([0x00])) }
        var v = value
        var bytes: [UInt8] = []
        while v != 0 { bytes.insert(UInt8(v & 0xFF), at: 0); v >>= 8 }
        if bytes[0] & 0x80 != 0 { bytes.insert(0x00, at: 0) }
        return encode(tag: 0x02, content: Data(bytes))
    }

    static func integer(bytes rawBytes: Data) -> Data {
        var b = rawBytes
        while b.count > 1 && b[0] == 0x00 && (b.count < 2 || b[1] & 0x80 == 0) { b = b.dropFirst() }
        if let first = b.first, first & 0x80 != 0 { b = Data([0x00]) + b }
        return encode(tag: 0x02, content: b)
    }

    // MARK: - BIT STRING

    static func bitString(_ bytes: Data, unusedBits: UInt8 = 0) -> Data {
        var content = Data([unusedBits])
        content.append(bytes)
        return encode(tag: 0x03, content: content)
    }

    // MARK: - OCTET STRING

    static func octetString(_ bytes: Data) -> Data {
        encode(tag: 0x04, content: bytes)
    }

    // MARK: - OID

    static func oid(_ dotted: String) -> Data {
        let parts = dotted.split(separator: ".").compactMap { Int($0) }
        precondition(parts.count >= 2, "OID needs at least two arcs")
        var bytes = Data([UInt8(parts[0] * 40 + parts[1])])
        for arc in parts.dropFirst(2) { bytes.append(contentsOf: base128(arc)) }
        return encode(tag: 0x06, content: bytes)
    }

    private static func base128(_ v: Int) -> [UInt8] {
        if v == 0 { return [0] }
        var val = v
        var out: [UInt8] = []
        while val > 0 { out.insert(UInt8(val & 0x7F), at: 0); val >>= 7 }
        for i in 0..<out.count - 1 { out[i] |= 0x80 }
        return out
    }

    // MARK: - String types

    static func utf8String(_ s: String) -> Data {
        encode(tag: 0x0C, content: s.data(using: .utf8)!)
    }

    static func printableString(_ s: String) -> Data {
        encode(tag: 0x13, content: s.data(using: .ascii)!)
    }

    static func ia5String(_ s: String) -> Data {
        encode(tag: 0x16, content: s.data(using: .ascii)!)
    }

    // MARK: - Time

    static func utcTime(_ date: Date) -> Data {
        let f = DateFormatter()
        f.dateFormat = "yyMMddHHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return encode(tag: 0x17, content: f.string(from: date).data(using: .ascii)!)
    }

    // MARK: - SEQUENCE / SET

    static func sequence(_ children: Data...) -> Data {
        encode(tag: 0x30, content: children.reduce(Data(), +))
    }

    static func sequence(_ children: [Data]) -> Data {
        encode(tag: 0x30, content: children.reduce(Data(), +))
    }

    static func set(_ children: Data...) -> Data {
        encode(tag: 0x31, content: children.reduce(Data(), +))
    }

    static func set(_ children: [Data]) -> Data {
        encode(tag: 0x31, content: children.reduce(Data(), +))
    }

    // MARK: - Context-specific tags

    static func explicit(_ tag: UInt8, _ content: Data) -> Data {
        encode(tag: 0xA0 | tag, content: content)
    }

    static func implicit(_ tag: UInt8, _ content: Data) -> Data {
        encode(tag: 0x80 | tag, content: content)
    }

    // MARK: - X.509 composite helpers

    static func rdn(oid oidStr: String, value: Data) -> Data {
        set(sequence(oid(oidStr), value))
    }

    static func distinguishedName(cn: String, org: String? = nil, country: String? = nil) -> Data {
        var rdns: [Data] = []
        if let c = country { rdns.append(rdn(oid: "2.5.4.6",  value: printableString(c))) }
        if let o = org     { rdns.append(rdn(oid: "2.5.4.10", value: utf8String(o)))      }
        rdns.append(           rdn(oid: "2.5.4.3",  value: utf8String(cn)))
        return sequence(rdns)
    }

    static func x509Extension(oid oidStr: String, critical: Bool = false, value: Data) -> Data {
        var parts: [Data] = [oid(oidStr)]
        if critical { parts.append(encode(tag: 0x01, content: Data([0xFF]))) }
        parts.append(octetString(value))
        return sequence(parts)
    }

    static func ecSubjectPublicKeyInfo(_ uncompressedPoint: Data) -> Data {
        let alg = sequence([
            oid("1.2.840.10045.2.1"),
            oid("1.2.840.10045.3.1.7")
        ])
        return sequence([alg, bitString(uncompressedPoint)])
    }

    static func ecdsaSHA256AlgID() -> Data {
        sequence(oid("1.2.840.10045.4.3.2"))
    }
}
