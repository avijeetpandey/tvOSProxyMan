import Foundation

// Glob matcher: * matches any run of characters; matching is case-insensitive.
// Bare strings without wildcards do a substring search, so "api.example.com" just works.
func patternMatches(_ pattern: String, url: String) -> Bool {
    guard !pattern.isEmpty else { return true }
    let lower = url.lowercased()
    let pat   = pattern.lowercased()

    if !pat.contains("*") { return lower.contains(pat) }

    let escaped = NSRegularExpression.escapedPattern(for: pat)
    let regexStr = "^" + escaped.replacingOccurrences(of: "\\*", with: ".*") + "$"
    guard let regex = try? NSRegularExpression(pattern: regexStr) else { return false }
    return regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil
}
