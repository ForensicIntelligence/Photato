import Foundation

/// A native interpreter for supported Photoshop actionJSON descriptors. It does
/// not evaluate JavaScript, run plug-ins, or silently skip unsupported actions.
/// The HTTP job/resource adapters decide which documents this may access.
public struct PhotoshopActionProgram: Sendable {
  public enum Step: Equatable, Sendable {
    case selectComponents(RGBComponents?)
    case fill(value: Float, opacity: Float)
  }

  public struct Result: Sendable {
    public var session: EditorSession
    public let components: RGBComponents?
  }

  public let steps: [Step]
  public static let maximumCharacters = 51_200
  public static let maximumSteps = 1_024

  public init(actionJSON: String) throws {
    guard actionJSON.unicodeScalars.count <= Self.maximumCharacters else {
      throw CraftError.invalid("Inline actionJSON exceeds 51,200 characters.")
    }
    let data = Data(actionJSON.utf8)
    try Self.checkNesting(data)
    let values: [ActionValue]
    do { values = try JSONDecoder().decode([ActionValue].self, from: data) } catch {
      throw CraftError.invalid("ActionJSON must be a JSON array of action descriptors.")
    }
    guard !values.isEmpty, values.count <= Self.maximumSteps else {
      throw CraftError.invalid("An action program must contain 1–1,024 steps.")
    }
    steps = try values.enumerated().map { index, value in
      do { return try Self.parse(value) } catch let error as CraftError {
        let message = "Action \(index + 1): \(error.localizedDescription)"
        if case .unsupported = error { throw CraftError.unsupported(message) }
        throw CraftError.invalid(message)
      }
    }
  }

  /// Work on an isolated session. Validation, unsupported contexts, cancellation
  /// and later-step errors never partially replace the caller's document.
  public func applying(to document: CraftDocument, components initial: RGBComponents? = nil)
    throws -> Result
  {
    try applying(to: EditorSession(document: document), components: initial)
  }

  /// Continue another action resource without losing its history or target.
  public func applying(to original: EditorSession, components initial: RGBComponents? = nil)
    throws -> Result
  {
    try Task.checkCancellation()
    try original.document.validate()
    if let initial, initial.isEmpty || !initial.isSubset(of: .all) {
      throw CraftError.invalid("Invalid initial component target.")
    }
    if initial != nil && original.document.depth != .u8 {
      throw CraftError.unsupported("Component editing currently requires an RGB8 document.")
    }
    var session = original
    var components = initial
    for step in steps {
      try Task.checkCancellation()
      switch step {
      case .selectComponents(let selected):
        guard selected == nil || session.document.depth == .u8 else {
          throw CraftError.unsupported("Component editing currently requires an RGB8 document.")
        }
        components = selected
      case .fill(let value, let opacity):
        guard let components else {
          throw CraftError.unsupported(
            "This action adapter requires a color-component target for Fill. Composite RGB Fill is not implemented here yet."
          )
        }
        guard let id = session.document.activeLayerID else {
          throw CraftError.invalid("Fill requires an active pixel layer.")
        }
        try session.execute(
          .fillComponents(
            id,
            .init(
              components: components, value: value, opacity: opacity)))
      }
    }
    try Task.checkCancellation()
    return Result(session: session, components: components)
  }

  private static func parse(_ value: ActionValue) throws -> Step {
    guard case .object(let fields) = value, let event = fields["_obj"]?.string else {
      throw CraftError.invalid("Each descriptor requires an _obj command name.")
    }
    if let options = fields["_options"] {
      guard case .object(let options) = options,
        Set(options.keys).isSubset(of: ["dialogOptions", "suppressProgressBar"]),
        options["dialogOptions"] == nil || options["dialogOptions"]?.string == "silent"
          || options["dialogOptions"]?.string == "dontDisplay",
        options["suppressProgressBar"] == nil || options["suppressProgressBar"]?.boolean != nil
      else {
        throw CraftError.unsupported("Interactive or unknown execution options are unsupported.")
      }
    }
    if let command = fields["_isCommand"], command.boolean == nil {
      throw CraftError.invalid("_isCommand must be boolean.")
    }
    let metadata: Set<String> = ["_obj", "_options", "_isCommand"]
    switch event {
    case "select", "$slct":
      try known(fields, keys: metadata.union(["_target", "null"]))
      guard (fields["_target"] == nil) != (fields["null"] == nil),
        case .array(let targets) = fields["_target"] ?? fields["null"],
        (1...2).contains(targets.count), case .object(let target) = targets[0],
        Set(target.keys) == ["_ref", "_enum", "_value"],
        ["channel", "$Chnl"].contains(target["_ref"]?.string ?? ""),
        ["channel", "$Chnl"].contains(target["_enum"]?.string ?? "")
      else {
        throw CraftError.unsupported("Select requires an enumerated color-channel reference.")
      }
      if targets.count == 2 {
        guard case .object(let parent) = targets[1],
          Set(parent.keys) == ["_ref", "_enum", "_value"],
          ["document", "$Dcmn"].contains(parent["_ref"]?.string ?? ""),
          ["ordinal", "$Ordn"].contains(parent["_enum"]?.string ?? ""),
          ["targetEnum", "$Trgt"].contains(parent["_value"]?.string ?? "")
        else { throw CraftError.unsupported("Only the current input document can be selected.") }
      }
      switch target["_value"]?.string {
      case "RGB", "$RGB ": return .selectComponents(nil)
      case "red", "$Rd  ": return .selectComponents(.red)
      case "green", "$Grn ": return .selectComponents(.green)
      case "blue", "$Bl  ": return .selectComponents(.blue)
      default: throw CraftError.unsupported("This channel reference is not implemented.")
      }
    case "fill", "$Fl  ":
      try known(
        fields,
        keys: metadata.union([
          "using", "$Usng", "opacity", "$Opct", "mode", "$Md  ",
          "preserveTransparency", "$PrsT",
        ]))
      let contents = try alias(fields, "using", "$Usng")
      let mode = try alias(fields, "mode", "$Md  ")
      let opacity = try alias(fields, "opacity", "$Opct")
      let preserve = try alias(fields, "preserveTransparency", "$PrsT")
      guard case .object(let opacity) = opacity,
        Set(opacity.keys) == ["_unit", "_value"],
        ["percentUnit", "$#Prc"].contains(opacity["_unit"]?.string ?? ""),
        let amount = opacity["_value"]?.number, amount.isFinite, (0...100).contains(amount)
      else { throw CraftError.invalid("Fill requires an opacity in percent from 0 through 100.") }
      guard
        try enumerated(mode, types: ["blendMode", "$BlnM"]).map({
          ["normal", "$Nrml"].contains($0)
        }) == true
      else { throw CraftError.unsupported("Only Normal component Fill is implemented.") }
      if let preserve {
        guard preserve.boolean != nil else {
          throw CraftError.invalid("preserveTransparency must be boolean.")
        }
        // Component Fill always preserves alpha, but this option has not been
        // independently qualified when explicitly requested in actionJSON.
        guard preserve.boolean == false else {
          throw CraftError.unsupported(
            "Explicit Preserve Transparency actions are not qualified yet.")
        }
      }
      let value: Float
      switch try enumerated(contents, types: ["fillContents", "$FlCn"]) {
      case "white", "$Wht ": value = 1
      case "black", "$Blck": value = 0
      case "gray50", "$Gry ": value = 0.5
      default:
        throw CraftError.unsupported(
          "Only White, Black and 50% Gray component Fill are implemented.")
      }
      return .fill(value: value, opacity: Float(amount / 100))
    default: throw CraftError.unsupported("The \(event) action is not implemented.")
    }
  }

  private static func known(_ object: [String: ActionValue], keys: Set<String>) throws {
    guard Set(object.keys).isSubset(of: keys) else {
      throw CraftError.unsupported("Unknown action parameters cannot be ignored.")
    }
  }

  private static func alias(_ object: [String: ActionValue], _ name: String, _ code: String)
    throws -> ActionValue?
  {
    guard object[name] == nil || object[code] == nil else {
      throw CraftError.invalid("Duplicate parameter aliases for \(name).")
    }
    return object[name] ?? object[code]
  }

  private static func enumerated(_ value: ActionValue?, types: Set<String>) throws -> String? {
    guard case .object(let object) = value, Set(object.keys) == ["_enum", "_value"],
      let type = object["_enum"]?.string, types.contains(type),
      let value = object["_value"]?.string
    else { throw CraftError.invalid("Invalid action enumeration.") }
    return value
  }

  private static func checkNesting(_ data: Data) throws {
    var depth = 0
    var quoted = false
    var escaped = false
    for byte in data {
      if quoted {
        if escaped {
          escaped = false
        } else if byte == 92 {
          escaped = true
        } else if byte == 34 {
          quoted = false
        }
      } else if byte == 34 {
        quoted = true
      } else if byte == 123 || byte == 91 {
        depth += 1
        guard depth <= 64 else { throw CraftError.invalid("ActionJSON nesting exceeds 64 levels.") }
      } else if byte == 125 || byte == 93 {
        depth -= 1
      }
    }
  }
}

private indirect enum ActionValue: Decodable, Sendable {
  case object([String: Self])
  case array([Self])
  case string(String)
  case number(Double)
  case bool(Bool)
  case null
  init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer()
    if value.decodeNil() {
      self = .null
    } else if let b = try? value.decode(Bool.self) {
      self = .bool(b)
    } else if let n = try? value.decode(Double.self) {
      self = .number(n)
    } else if let s = try? value.decode(String.self) {
      self = .string(s)
    } else if let a = try? value.decode([Self].self) {
      self = .array(a)
    } else {
      self = .object(try value.decode([String: Self].self))
    }
  }
  var string: String? { if case .string(let value) = self { value } else { nil } }
  var number: Double? { if case .number(let value) = self { value } else { nil } }
  var boolean: Bool? { if case .bool(let value) = self { value } else { nil } }
}
