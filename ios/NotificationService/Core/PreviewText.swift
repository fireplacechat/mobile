import Foundation

/// The same Unicode-scalar limits and whitespace rules as the Dart formatter.
/// Do not use Swift Character counts: a grapheme may contain several scalars.
public enum PreviewText {
  public static let fallback = "New Message"

  private static func whitespace(_ value: Unicode.Scalar, regex: Bool = false) -> Bool {
    switch value.value {
    case 9...13, 32, 160, 5760, 8192...8202, 8232, 8233, 8239, 8287, 12288, 65279:
      return true
    case 133: return !regex
    default: return false
    }
  }

  private static func trim(_ text: String, leading: Bool = true) -> String {
    let scalars = text.unicodeScalars
    var start = scalars.startIndex, end = scalars.endIndex
    if leading {
      while start != end && whitespace(scalars[start]) { start = scalars.index(after: start) }
    }
    while start != end {
      let previous = scalars.index(before: end)
      if !whitespace(scalars[previous]) { break }
      end = previous
    }
    return String(scalars[start..<end])
  }

  private static func clip(_ text: String, _ limit: Int) -> String {
    String(String.UnicodeScalarView(text.unicodeScalars.prefix(limit)))
  }

  public static func isBlank(_ text: String) -> Bool { trim(text).isEmpty }

  public static func body(_ text: String) -> String {
    let value = trim(text)
    if value.isEmpty { return fallback }
    if value.unicodeScalars.count <= 1000 { return value }
    return trim(clip(value, 1000), leading: false) + "…"
  }

  public static func reaction(_ emoji: String, target: String?) -> String {
    guard let target = target else { return "Reacted \(emoji) to a message" }
    var line = String.UnicodeScalarView()
    var space = false
    for scalar in target.unicodeScalars {
      if whitespace(scalar, regex: true) {
        if !space { line.append(" "); space = true }
      } else {
        line.append(scalar)
        space = false
      }
    }
    let value = trim(String(line))
    let quote: String
    if value.unicodeScalars.count <= 40 {
      quote = value
    } else {
      var clipped = clip(value, 40)
      let position = (clipped as NSString).range(of: " ", options: .backwards).location
      if position != NSNotFound && position >= clipped.utf16.count / 2 {
        clipped = (clipped as NSString).substring(to: position)
      }
      quote = trim(clipped, leading: false) + "…"
    }
    return quote.isEmpty ? "Reacted \(emoji)" : "Reacted \(emoji) to “\(quote)”"
  }
}
