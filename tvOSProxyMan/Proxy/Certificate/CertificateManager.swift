import Foundation
import Security
import CryptoKit
import os.log

final class CertificateManager {
    static let shared = CertificateManager()

    private let logger = Logger(subsystem: "com.tvOSProxyMan", category: "CertificateManager")
    private let keychainLabel = "tvOSProxyMan"

    private var rootKey: SecKey?
    private var rootCert: SecCertificate?

    private var leafCache: [String: SecIdentity] = [:]
    private let cacheQueue = DispatchQueue(label: "com.tvOSProxyMan.certCache")

    private init() {}

    // MARK: - Bootstrap

    func initialize() throws {
        if rootKey != nil { return }
        pruneOldLeafCerts()
        let (key, cert) = try loadOrCreateRootCA()
        rootKey  = key
        rootCert = cert
        logger.info("CertificateManager ready — install Root CA to trust MITM certs")
    }

    var rootCACertificateDER: Data? {
        rootCert.map { SecCertificateCopyData($0) as Data }
    }

    // MARK: - Leaf identity (cached per hostname)

    func leafIdentity(for hostname: String) throws -> SecIdentity {
        let cached = cacheQueue.sync { leafCache[hostname] }
        if let id = cached { return id }

        guard let rKey = rootKey, let rCert = rootCert else {
            throw CertificateError.identityNotFound
        }
        let id = try makeLeafIdentity(hostname: hostname, rootKey: rKey, rootCert: rCert)
        cacheQueue.sync { leafCache[hostname] = id }
        return id
    }

    // MARK: - Root CA — load from keychain or generate fresh

    private func loadOrCreateRootCA() throws -> (SecKey, SecCertificate) {
        let keyQuery: [CFString: Any] = [
            kSecClass:            kSecClassKey,
            kSecAttrKeyClass:     kSecAttrKeyClassPrivate,
            kSecAttrLabel:        "\(keychainLabel)-RootCA" as CFString,
            kSecReturnRef:        true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var ref: CFTypeRef?
        if SecItemCopyMatching(keyQuery as CFDictionary, &ref) == errSecSuccess,
           let key = ref as! SecKey? {
            let certQuery: [CFString: Any] = [
                kSecClass:      kSecClassCertificate,
                kSecAttrLabel:  "\(keychainLabel)-RootCA" as CFString,
                kSecReturnRef:  true,
                kSecMatchLimit: kSecMatchLimitOne
            ]
            if SecItemCopyMatching(certQuery as CFDictionary, &ref) == errSecSuccess,
               let cert = ref as! SecCertificate? {
                logger.info("Loaded existing Root CA from keychain")
                return (key, cert)
            }
        }
        logger.info("Generating new Root CA …")
        return try generateAndStoreRootCA()
    }

    private func generateAndStoreRootCA() throws -> (SecKey, SecCertificate) {
        let (privKey, pubKey) = try generateP256KeyPair()
        let pubPoint          = try exportPublicKeyPoint(pubKey)
        let serial            = randomSerial()
        let now               = Date()
        let expiry            = Calendar.current.date(byAdding: .year, value: 10, to: now)!

        let subject = DER.distinguishedName(cn: "tvOSProxyMan Root CA",
                                            org: "tvOSProxyMan", country: "US")
        let ski = sha1(pubPoint)

        let extensions = DER.sequence([
            DER.x509Extension(
                oid: "2.5.29.19", critical: true,
                value: DER.sequence(DER.encode(tag: 0x01, content: Data([0xFF])))
            ),
            DER.x509Extension(
                oid: "2.5.29.15", critical: true,
                value: DER.bitString(Data([0x06]), unusedBits: 1)
            ),
            DER.x509Extension(
                oid: "2.5.29.14",
                value: DER.octetString(ski)
            )
        ])

        let tbs = buildTBSCertificate(
            serial: serial, issuer: subject,
            notBefore: now, notAfter: expiry,
            subject: subject, pubPoint: pubPoint, extensions: extensions
        )
        let certDER = try finalizeCertificate(tbs: tbs, signKey: privKey)
        guard let cert = SecCertificateCreateWithData(nil, certDER as CFData) else {
            throw CertificateError.invalidDER
        }
        try storeInKeychain(key: privKey, cert: cert, label: "\(keychainLabel)-RootCA")
        return (privKey, cert)
    }

    // MARK: - Leaf certificate

    private func makeLeafIdentity(hostname: String,
                                  rootKey: SecKey,
                                  rootCert: SecCertificate) throws -> SecIdentity {
        let (privKey, pubKey) = try generateP256KeyPair()
        let pubPoint          = try exportPublicKeyPoint(pubKey)
        let serial            = randomSerial()
        let now               = Date()
        let expiry            = Calendar.current.date(byAdding: .year, value: 1, to: now)!

        guard let issuerDER = SecCertificateCopyNormalizedSubjectSequence(rootCert) as Data? else {
            throw CertificateError.invalidDER
        }
        let subject     = DER.distinguishedName(cn: hostname)
        let rootPubPoint = try exportPublicKeyPoint(SecKeyCopyPublicKey(rootKey)!)
        let aki         = sha1(rootPubPoint)

        let extensions = DER.sequence([
            DER.x509Extension(
                oid: "2.5.29.17",
                value: DER.sequence(DER.encode(tag: 0x82,
                                               content: hostname.data(using: .ascii)!))
            ),
            DER.x509Extension(oid: "2.5.29.19", critical: true, value: DER.sequence()),
            DER.x509Extension(
                oid: "2.5.29.37",
                value: DER.sequence([
                    DER.oid("1.3.6.1.5.5.7.3.1"),
                    DER.oid("1.3.6.1.5.5.7.3.2")
                ])
            ),
            DER.x509Extension(
                oid: "2.5.29.35",
                value: DER.sequence(DER.implicit(0, aki))
            )
        ])

        let tbs = buildTBSCertificate(
            serial: serial, issuer: issuerDER,
            notBefore: now, notAfter: expiry,
            subject: subject, pubPoint: pubPoint, extensions: extensions
        )
        let certDER = try finalizeCertificate(tbs: tbs, signKey: rootKey)
        guard let cert = SecCertificateCreateWithData(nil, certDER as CFData) else {
            throw CertificateError.invalidDER
        }
        let label = "\(keychainLabel)-Leaf-\(hostname)"
        try storeInKeychain(key: privKey, cert: cert, label: label)
        return try fetchIdentity(label: label)
    }

    // MARK: - TBSCertificate builder

    private func buildTBSCertificate(serial: Data, issuer: Data,
                                     notBefore: Date, notAfter: Date,
                                     subject: Data, pubPoint: Data,
                                     extensions: Data) -> Data {
        DER.sequence([
            DER.explicit(0, DER.integer(2)),
            DER.integer(bytes: serial),
            DER.ecdsaSHA256AlgID(),
            issuer,
            DER.sequence(DER.utcTime(notBefore), DER.utcTime(notAfter)),
            subject,
            DER.ecSubjectPublicKeyInfo(pubPoint),
            DER.explicit(3, extensions)
        ])
    }

    private func finalizeCertificate(tbs: Data, signKey: SecKey) throws -> Data {
        var cfErr: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(
            signKey, .ecdsaSignatureMessageX962SHA256, tbs as CFData, &cfErr
        ) as Data? else {
            throw CertificateError.signingFailed(cfErr!.takeRetainedValue() as Error)
        }
        return DER.sequence([tbs, DER.ecdsaSHA256AlgID(), DER.bitString(sig)])
    }

    // MARK: - Keychain helpers

    private func storeInKeychain(key: SecKey, cert: SecCertificate, label: String) throws {
        let certAdd: [CFString: Any] = [
            kSecClass:      kSecClassCertificate,
            kSecValueRef:   cert,
            kSecAttrLabel:  label as CFString
        ]
        SecItemDelete(certAdd as CFDictionary)
        var st = SecItemAdd(certAdd as CFDictionary, nil)
        guard st == errSecSuccess || st == errSecDuplicateItem else {
            throw CertificateError.keychainError(st)
        }

        guard let pubKey = SecKeyCopyPublicKey(key),
              let pubPoint = try? exportPublicKeyPoint(pubKey) else {
            throw CertificateError.identityNotFound
        }
        let pubKeyHash = sha1(pubPoint)

        let keyAdd: [CFString: Any] = [
            kSecClass:                kSecClassKey,
            kSecAttrKeyClass:         kSecAttrKeyClassPrivate,
            kSecValueRef:             key,
            kSecAttrLabel:            label as CFString,
            kSecAttrApplicationLabel: pubKeyHash as CFData
        ]
        SecItemDelete(keyAdd as CFDictionary)
        st = SecItemAdd(keyAdd as CFDictionary, nil)
        guard st == errSecSuccess || st == errSecDuplicateItem else {
            SecItemDelete(certAdd as CFDictionary)
            throw CertificateError.keychainError(st)
        }
    }

    private func fetchIdentity(label: String) throws -> SecIdentity {
        let query: [CFString: Any] = [
            kSecClass:      kSecClassIdentity,
            kSecAttrLabel:  label as CFString,
            kSecReturnRef:  true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var ref: CFTypeRef?
        let st = SecItemCopyMatching(query as CFDictionary, &ref)
        guard st == errSecSuccess, let id = ref as! SecIdentity? else {
            throw CertificateError.keychainError(st)
        }
        return id
    }

    private func pruneOldLeafCerts() {
        let query: [CFString: Any] = [
            kSecClass:           kSecClassCertificate,
            kSecMatchLimit:      kSecMatchLimitAll,
            kSecReturnAttributes: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[CFString: Any]] else { return }

        for item in items {
            guard let label = item[kSecAttrLabel] as? String,
                  label.hasPrefix("\(keychainLabel)-Leaf-") else { continue }
            let del: [CFString: Any] = [kSecClass: kSecClassCertificate,
                                        kSecAttrLabel: label as CFString]
            SecItemDelete(del as CFDictionary)
        }
    }

    // MARK: - Crypto utilities

    private func generateP256KeyPair() throws -> (SecKey, SecKey) {
        let attrs: [CFString: Any] = [
            kSecAttrKeyType:       kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecAttrIsPermanent:   false
        ]
        var cfErr: Unmanaged<CFError>?
        guard let priv = SecKeyCreateRandomKey(attrs as CFDictionary, &cfErr) else {
            throw CertificateError.keyGenerationFailed(cfErr!.takeRetainedValue() as Error)
        }
        guard let pub = SecKeyCopyPublicKey(priv) else {
            throw CertificateError.identityNotFound
        }
        return (priv, pub)
    }

    private func exportPublicKeyPoint(_ key: SecKey) throws -> Data {
        var cfErr: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(key, &cfErr) as Data? else {
            throw CertificateError.exportFailed(cfErr!.takeRetainedValue() as Error)
        }
        return data
    }

    private func sha1(_ data: Data) -> Data {
        Data(Insecure.SHA1.hash(data: data))
    }

    private func randomSerial() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        bytes[0] &= 0x7F
        return Data(bytes)
    }
}
