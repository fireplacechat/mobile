import CoreFoundation
import Foundation

public enum PreviewEvent: Equatable {
  case text(String)
  case reaction(target: String, emoji: String, clear: Bool)
  case edit(target: String, body: String)
  case delete(target: String)
}

/// Parsing only. Cryptographic protocol operations remain in the Rust core.
public enum PreviewPayload {
  private static let identifier = try! NSRegularExpression(pattern: "^[A-Za-z0-9_-]{1,128}$")
  private static let pictograph = #"[\x{1F300}-\x{1F3FA}\x{1F400}-\x{1FAFF}\x{2600}-\x{27BF}\x{00A9}\x{00AE}\x{203C}\x{2049}\x{2122}\x{2139}\x{2194}-\x{21FF}\x{2300}-\x{23FF}\x{2B00}-\x{2BFF}\x{3030}\x{303D}\x{3297}\x{3299}]"#
  private static let emoji = try! NSRegularExpression(pattern:
    "^(?:" + pictograph + #"\x{FE0F}?[\x{1F3FB}-\x{1F3FF}]?(?:\x{200D}"# + pictograph +
    #"\x{FE0F}?[\x{1F3FB}-\x{1F3FF}]?)*|[\x{1F1E6}-\x{1F1FF}]{2}|[0-9#*]\x{FE0F}?\x{20E3})$"#)

  private static func matches(_ expression: NSRegularExpression, _ value: String) -> Bool {
    let full = NSRange(location: 0, length: value.utf16.count)
    // ICU's dollar anchor also matches before a final newline. Dart's
    // validator rejects that suffix; require the match to cover every unit.
    return expression.firstMatch(in: value, range: full)?.range == full
  }

  private static func integer(_ value: Any?) -> Int64? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
          !["f", "d"].contains(String(cString: number.objCType)) else { return nil }
    return number.int64Value
  }

  private static func validQuote(_ raw: Any) -> Bool {
    guard let q = raw as? [String: Any], let id = q["targetId"] as? String, matches(identifier, id),
          let uid = q["senderUid"] as? String, !uid.isEmpty, uid.utf16.count <= 128,
          let body = q["body"] as? String, body.utf16.count <= 2048, body.unicodeScalars.count <= 1024 else { return false }
    if let unavailable = q["unavailable"] {
      guard let flag = unavailable as? NSNumber, CFGetTypeID(flag) == CFBooleanGetTypeID() else { return false }
    }
    return true
  }

  public static func decode(_ data: Data) -> PreviewEvent? {
    guard data.count <= 128 * 1024,
          let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
    guard let j = value as? [String: Any] else { return .text("[unsupported message]") }
    if j["type"] as? String == "text", let body = j["body"] as? String {
      if integer(j["v"]) == 3, let quote = j["quote"], !(quote is NSNull), !validQuote(quote) { return nil }
      return .text(body)
    }
    let version = integer(j["v"]), type = j["type"] as? String
    guard (version == 2 && (type == "reaction" || type == "delete")) || (version == 3 && type == "edit") else {
      return .text("[unsupported message]")
    }
    guard let target = j["targetId"] as? String, matches(identifier, target) else { return nil }
    if type == "delete" { return .delete(target: target) }
    guard let revision = integer(j["revision"]), revision >= 1 else { return nil }
    if type == "edit" {
      guard revision <= 10, let body = j["body"] as? String,
            body.utf16.count <= 32768, body.unicodeScalars.count <= 16384,
            !PreviewText.isBlank(body) else { return nil }
      return .edit(target: target, body: body)
    }
    guard revision <= 9007199254740991, let glyph = j["emoji"] as? String,
          !glyph.isEmpty, glyph.utf16.count <= 64, matches(emoji, glyph),
          let operation = j["operation"] as? String, operation == "set" || operation == "clear" else { return nil }
    return .reaction(target: target, emoji: glyph, clear: operation == "clear")
  }
}
