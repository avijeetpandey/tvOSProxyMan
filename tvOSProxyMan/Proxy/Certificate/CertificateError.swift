import Foundation

enum CertificateError: Error, LocalizedError {
    case keyGenerationFailed(Error)
    case exportFailed(Error)
    case signingFailed(Error)
    case invalidDER
    case keychainError(OSStatus)
    case identityNotFound

    var errorDescription: String? {
        switch self {
        case .keyGenerationFailed(let e): return "Key gen failed: \(e)"
        case .exportFailed(let e):        return "Export failed: \(e)"
        case .signingFailed(let e):       return "Signing failed: \(e)"
        case .invalidDER:                 return "Certificate DER invalid"
        case .keychainError(let s):       return "Keychain OSStatus \(s)"
        case .identityNotFound:           return "SecIdentity not found"
        }
    }
}
