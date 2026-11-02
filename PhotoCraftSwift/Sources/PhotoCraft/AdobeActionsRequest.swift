import Foundation
import PhotoCraftCore
import PhotoCraftImaging

/// Published Adobe error shape, separate from the existing Photato API envelope.
struct AdobeAPIError: Error, Equatable, Sendable {
  let status: Int
  let code: String
  let message: String
  static func invalid(_ message: String) -> Self {
    .init(status: 400, code: "validation_error", message: message)
  }
  static func unsupported(_ message: String) -> Self {
    .init(status: 422, code: "validation_error", message: message)
  }
  var response: AutomationResponse {
    .json(["error_code": code, "message": message], status: status)
  }
}

/// Contract adapter foundation, not an advertised HTTP endpoint. Resource I/O,
/// jobs/status and UI/Photato integration must be completed before it is exposed.
struct AdobeActionsRequest: Sendable {
  enum MediaType: String, Sendable {
    case png = "image/png"
    case jpeg = "image/jpeg"
    case psd = "image/vnd.adobe.photoshop"
    case tiff = "image/tiff"
    case json = "application/json"
    var format: DocumentIO.Format? {
      switch self { case .png: .png; case .jpeg: .jpeg; case .psd: .psd; case .tiff: .tiff; case .json: nil }
    }
  }
  enum Destination: Equatable, Sendable {
    case hosted(validityPeriod: Int)
    case external(URL, storageType: String?)
  }
  struct Output: Sendable {
    let mediaType: MediaType
    let destination: Destination
    let shouldOverwrite: Bool?
    var encodingOptions = RasterEncodingOptions()
    var colorProfile: AdobeOutputProfile?
    var layerExport: AdobeLayerOutput?
  }
  let input: URL?
  let creation: AdobeDocumentCreation?
  let actions: [PhotoshopActionProgram]
  let outputs: [Output]
  let allowsPhotatoInput: Bool
  var layerEdits: [AdobeCompositeEdit]?
  var textFontOptions = try! AdobeTypeFontOptions()
  static let maximumBodyBytes = 4 * 1_024 * 1_024

  init(data: Data, allowPhotatoOptions: Bool = false, createComposite: Bool = false, artboardOutputs: Bool = false) throws {
    allowsPhotatoInput = allowPhotatoOptions
    guard data.count <= Self.maximumBodyBytes else {
      throw AdobeAPIError(
        status: 413, code: "validation_error", message: "Request exceeds the local 4 MiB limit.")
    }
    let parsed: Any
    do { parsed = try JSONSerialization.jsonObject(with: data) } catch {
      throw AdobeAPIError(
        status: 400, code: "invalid_json", message: "Expected a JSON request object.")
    }
    let root = try Object(parsed, at: "request", allowed: createComposite
      ? ["image", "edits", "outputs", "fontOptions"] : ["image", "options", "outputs"])
    guard let rawImage = root.fields["image"] else { throw AdobeAPIError.invalid("Missing image.") }
    if let fields = rawImage as? [String: Any], fields["source"] == nil,
      createComposite || allowPhotatoOptions {
      creation = try AdobeDocumentCreation(rawImage)
      input = nil
    } else {
      let image = try root.object("image", allowed: ["source"])
      let source = try image.object("source", allowed: ["url"])
      input = try Self.url(source.string("url"), path: "image.source.url", httpsOnly: false)
      creation = nil
    }

    if createComposite {
      textFontOptions = try AdobeTypeFontOptions(root.fields["fontOptions"])
      actions = []
      if let raw = root.fields["edits"] {
        let edits = try Object(raw, at: "edits", allowed: ["layers"])
        layerEdits = try (edits.fields["layers"] == nil ? [] : edits.array("layers", count: 0...64)).enumerated().map {
          try AdobeCompositeEdit($0.element, path: "edits.layers[\($0.offset)]")
        }
      } else { layerEdits = [] }
    } else {
    let options = try root.object("options", allowed: ["actions"])
    let resources = try options.array("actions", count: 1...10)
    actions = try resources.enumerated().map { index, raw in
      let path = "options.actions[\(index)]"
      let resource = try Object(raw, at: path, allowed: ["source"])
      let source = try resource.object("source", allowed: ["content", "contentType"])
      guard try source.string("contentType") == "application/json" else {
        throw AdobeAPIError.invalid("\(path).source.contentType must be application/json.")
      }
      do { return try PhotoshopActionProgram(actionJSON: source.string("content")) } catch let error
        as CraftError
      {
        if case .unsupported = error { throw AdobeAPIError.unsupported(error.localizedDescription) }
        throw AdobeAPIError.invalid(error.localizedDescription)
      }
    }

    }

    outputs = try root.array("outputs", count: 1...25).enumerated().map { index, raw in
      let path = "outputs[\(index)]"
      if let fields = raw as? [String: Any], fields["scan"] != nil {
        throw AdobeAPIError(status: 400, code: "validation_error",
          message: "The execute-actions contract does not accept scan options.")
      }
      let output = try Object(
        raw, at: path,
        allowed: Set([
          "mediaType", "destination", "shouldOverwrite", "cropMode", "scriptOutputPattern",
          "compression", "quality", "iccProfile",
        ] + (createComposite && !artboardOutputs ? ["layers"] : []) + (allowPhotatoOptions ? ["encodingOptions"] : [])))
      guard let mediaType = MediaType(rawValue: try output.string("mediaType")), mediaType != .json || artboardOutputs else {
        throw AdobeAPIError.unsupported("Only PNG, JPEG, TIFF and PSD output are implemented by this adapter.")
      }
      if mediaType == .json, Set(output.fields.keys).subtracting(["mediaType", "destination", "shouldOverwrite"]).isEmpty == false { throw AdobeAPIError.invalid("JSON manifests do not accept raster encoding parameters.") }
      var encoding = RasterEncodingOptions()
      if let raw = output.fields["encodingOptions"] {
        do {
          let value = try JSONDecoder().decode(AutomationValue.self,
            from: JSONSerialization.data(withJSONObject: raw, options: [.fragmentsAllowed]))
          encoding = try DocumentEncodingOptions.parse(value, format: mediaType.format!) ?? .init()
        } catch { throw AdobeAPIError.invalid("Invalid Photato output encodingOptions.") }
      }
      if output.fields["compression"] != nil {
        guard mediaType == .png else {
          throw AdobeAPIError.unsupported("The compression field is only implemented for PNG output.")
        }
        guard encoding.pngCompression == nil,
          let level = DocumentEncodingOptions.pngLevels.firstIndex(of: try output.string("compression")) else {
          throw AdobeAPIError.invalid("Invalid or duplicate PNG compression choice.")
        }
        encoding.pngCompression = level
      }
      if output.fields["quality"] != nil {
        guard mediaType == .jpeg else {
          throw AdobeAPIError.invalid("The quality field requires JPEG output.")
        }
        guard encoding.jpegQuality == nil,
          let level = DocumentEncodingOptions.jpegQualities.firstIndex(of: try output.string("quality")) else {
          throw AdobeAPIError.invalid("Invalid or duplicate JPEG quality choice.")
        }
        // Local scale mapping; Adobe's proprietary quantization is not reproduced.
        encoding.jpegQuality = level * 2
      }
      if output.fields["cropMode"] != nil { _ = try output.string("cropMode") }
      let layerOutput = try AdobeLayerOutput(output.fields, createComposite: createComposite && !artboardOutputs, mediaType: mediaType)
      if let pattern = output.fields["scriptOutputPattern"], !(pattern is NSNull) {
        throw AdobeAPIError.unsupported(
          "Script output patterns require an unimplemented UXP runtime.")
      }
      let destination = try output.object(
        "destination", allowed: ["url", "storageType", "validityPeriod"])
      let target: Destination
      if destination.fields["url"] != nil {
        guard destination.fields["validityPeriod"] == nil else {
          throw AdobeAPIError.invalid("Output destination must choose one storage variant.")
        }
        let url = try Self.url(
          destination.string("url"), path: path + ".destination.url", httpsOnly: true)
        var storageType: String?
        if destination.fields["storageType"] != nil {
          let value = try destination.string("storageType")
          guard ["azure", "dropbox"].contains(value) else {
            throw AdobeAPIError.invalid("storageType must be azure or dropbox when supplied.")
          }
          storageType = value
        }
        target = .external(url, storageType: storageType)
      } else {
        guard destination.fields["storageType"] == nil else {
          throw AdobeAPIError.invalid("storageType requires a URL destination.")
        }
        target = .hosted(
          validityPeriod: try destination.integer("validityPeriod", range: 60...86_400))
      }
      return Output(
        mediaType: mediaType, destination: target,
        shouldOverwrite: try output.optionalBool("shouldOverwrite"), encodingOptions: encoding,
        colorProfile: try output.fields["iccProfile"].map { try AdobeOutputProfile($0) },
        layerExport: output.fields["layers"] != nil || layerOutput.crop != .documentBounds ? layerOutput : nil)
    }
  }

  /// The transport supplies one authorized input snapshot. All action resources
  /// execute in order on a value copy, using the same native command/history path.
  func applying(to document: CraftDocument, resources: [URL: Data] = [:]) throws -> PhotoshopActionProgram.Result {
    if let layerEdits {
      var session = EditorSession(document: document)
      for edit in layerEdits { try edit.apply(to: &session, resources: resources, fontOptions: textFontOptions) }
      return PhotoshopActionProgram.Result(session: session, components: nil,
        selectedLayerIDs: Set(session.document.activeLayerID.map { [$0] } ?? []))
    }
    let renderer: PhotoshopActionProgram.StackRenderer = { try ImageStack.command(in:$0,layerID:$1,mode:$2) }
    let converter: PhotoshopActionProgram.ModeConverter = {
      try DocumentModeInput.command(.init($1, mergeVisible: $2), in: $0)
    }
    var result = try actions[0].applying(to: document, stackRenderer: renderer, modeConverter: converter, flattenRenderer: FlattenPreparation.command)
    for action in actions.dropFirst() {
      result = try action.applying(
        to: result.session, components: result.components, selectedLayerIDs: result.selectedLayerIDs, modeComponents: result.modeComponents,
        stackRenderer: renderer, modeConverter: converter, flattenRenderer: FlattenPreparation.command
      )
    }
    return result
  }

  static func url(_ raw: String, path: String, httpsOnly: Bool) throws -> URL {
    guard raw.utf8.count <= 8_192, let url = URL(string: raw),
      let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let scheme = parts.scheme?.lowercased(),
      (httpsOnly ? ["https"] : ["https", "http"]).contains(scheme),
      !(parts.host ?? "").isEmpty, parts.user == nil, parts.password == nil,
      parts.fragment == nil
    else {
      throw AdobeAPIError.invalid(
        "\(path) must be an absolute \(httpsOnly ? "HTTPS" : "HTTP(S)") resource URL.")
    }
    return url
  }

  struct Object {
    let fields: [String: Any]
    let path: String
    init(_ raw: Any, at path: String, allowed: Set<String>) throws {
      guard let fields = raw as? [String: Any] else {
        throw AdobeAPIError.invalid("\(path) must be an object.")
      }
      guard Set(fields.keys).isSubset(of: allowed) else {
        throw AdobeAPIError.unsupported(
          "\(path) contains options or resource variants that are not implemented.")
      }
      self.fields = fields
      self.path = path
    }
    func object(_ key: String, allowed: Set<String>) throws -> Self {
      guard let raw = fields[key] else { throw AdobeAPIError.invalid("Missing \(path).\(key).") }
      return try Self(raw, at: "\(path).\(key)", allowed: allowed)
    }
    func string(_ key: String) throws -> String {
      guard let value = fields[key] as? String else {
        throw AdobeAPIError.invalid("\(path).\(key) must be a string.")
      }
      return value
    }
    func array(_ key: String, count: ClosedRange<Int>) throws -> [Any] {
      guard let values = fields[key] as? [Any], count.contains(values.count) else {
        throw AdobeAPIError.invalid(
          "\(path).\(key) requires \(count.lowerBound)–\(count.upperBound) items.")
      }
      return values
    }
    func integer(_ key: String, range: ClosedRange<Int>) throws -> Int {
      guard let value = fields[key] as? NSNumber,
        CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite,
        value.doubleValue.rounded() == value.doubleValue,
        (Double(range.lowerBound)...Double(range.upperBound)).contains(value.doubleValue)
      else { throw AdobeAPIError.invalid("\(path).\(key) is outside its integer range.") }
      return value.intValue
    }
    func optionalBool(_ key: String) throws -> Bool? {
      guard let raw = fields[key] else { return nil }
      guard let value = raw as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else {
        throw AdobeAPIError.invalid("\(path).\(key) must be boolean.")
      }
      return value.boolValue
    }
  }
}
