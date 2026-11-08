import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum MagicWandAPI {
  static let name = "selection.wand"
  static let settingKeys: Set<String> = ["sampleSize", "tolerance", "contiguous", "antiAlias", "sampleAllLayers", "mode"]
  static var definition: AutomationCommand.Definition {
    .init(name: name, parameters: ["operation":"configure or select", "sampleSize":"Point1 or average3,5,11,31,51,101",
      "tolerance":"0–255", "contiguous":"Connected region only", "antiAlias":"Smooth selection edges",
      "sampleAllLayers":"Visible composite instead of current layer", "mode":"replace, add, subtract, intersect",
      "x":"Document x", "y":"Document y", "layerID":"Optional source layer UUID", "target":"content or layerMask"],
      description:"Configure window-local Magic Wand options, or select using captured options and the native prepared transaction. Selection overrides do not change defaults. One Undo; source pixels remain intact.",
      optionalParameters: settingKeys.union(["x", "y", "layerID", "target"]))
  }
  static func schema(_ key: String) -> [String:Any] {
    switch key {
    case "operation": return BrushAPI.enumeration(["configure", "select"])
    case "sampleSize": return ["type":"integer", "enum":ColorSampleSettings.sizes]
    case "tolerance": return BrushAPI.number(0,255,integer:true)
    case "contiguous", "antiAlias", "sampleAllLayers": return BrushAPI.flag
    case "mode": return SelectionToolAPI.schema("mode")
    case "x", "y": return ["type":"number", "minimum":0, "exclusiveMaximum":300000]
    case "layerID": return ["type":"string", "format":"uuid"]
    case "target": return BrushAPI.enumeration(["content", "layerMask"])
    default: return [:]
    }
  }
  static var parameterSchema: [String:Any] {
    var properties: [String:Any] = [:]
    for key in definition.parameters.keys { properties[key] = schema(key) }
    var result = BrushAPI.object(properties, required:["operation"])
    var config = BrushAPI.object(properties.filter { settingKeys.contains($0.key) || $0.key == "operation" }, required:["operation"])
    var select = properties; select["operation"] = ["const":"select"]
    config["properties"] = (config["properties"] as! [String:Any]).merging(["operation":["const":"configure"]]) { _, new in new }
    config["minProperties"] = 2
    result["oneOf"] = [config, BrushAPI.object(select,required:["operation","x","y"])]
    return result
  }
  static var settingsSchema: [String:Any] {
    BrushAPI.object(Dictionary(uniqueKeysWithValues:settingKeys.map { ($0,schema($0)) }), required:settingKeys.sorted())
  }
  static var stateSchema: [String:Any] {
    BrushAPI.object(["available":BrushAPI.flag,"settings":settingsSchema,"target":schema("target")], required:["available","settings","target"])
  }
  static var resultSchema: [String:Any] {
    BrushAPI.object(["revision":["type":"string"],"magicWand":stateSchema],required:["revision","magicWand"])
  }
  @MainActor static func state(_ store:EditorStore) -> [String:Any] {
    ["available":store.canUseMagicWand,"target":store.editingMask ? "layerMask":"content",
      "settings":["sampleSize":store.wandOptions.sampleSize,"tolerance":store.wandOptions.tolerance,
        "contiguous":store.wandOptions.contiguous,"antiAlias":store.wandOptions.antiAlias,
        "sampleAllLayers":store.wandSampleAllLayers,"mode":SelectionToolAPI.modeName(store.selectionMode)]]
  }
  @MainActor static func options(_ command:AutomationCommand, store:EditorStore) throws -> ColorMatchOptions {
    var value = store.wandOptions
    if command.parameters["sampleSize"] != nil { value.sampleSize = try command.integer("sampleSize",range:1...101) }
    if command.parameters["tolerance"] != nil { value.tolerance = try command.integer("tolerance",range:0...255) }
    value.contiguous = try command.adjustmentBrushFlag("contiguous",value.contiguous)
    value.antiAlias = try command.adjustmentBrushFlag("antiAlias",value.antiAlias)
    do { try value.validate() } catch { throw AutomationFailure(status:400,message:error.localizedDescription) }
    return value
  }
  static var capabilities: [String:Any] {
    ["command":name,"parameterSchema":parameterSchema,"resultSchema":resultSchema,"stateSchema":stateSchema,
      "subjectSelection":SelectionToolAPI.subjectSelectionCapability,
      "settingsSchema":settingsSchema,"sizes":ColorSampleSettings.sizes,
      "native":"Sample Size picker in Magic Wand Options; W/Shift-W tool group and all existing selection modifiers remain. Options are captured at click. Configure changes window-local settings without editing history; new windows copy them from the prior workspace. Restart persistence remains open.",
      "algorithm":"Same existing RGBA8 matching and span flood. Average the clipped square's quantized RGBA channels with integer nearest rounding, then apply existing tolerance/connectivity/antialiasing. Hidden RGB and alpha participate as before. A contiguous seed must match the average. Exact Photoshop sampling/alpha/profile/rounding/connectivity/output remains unqualified.",
      "input":"Current layer in document coordinates, visible composite with sampleAllLayers, or ordinary layer mask. Locked sources may be sampled. RGB composite editing context; component/alpha/QuickMask/path/Smart Filter mask targets are unsupported.",
      "history":"One prepared native selection Undo; source content is retained. Existing semantic Magic Wand Actions recording remains unsupported. No native/archive/Actions version change.",
      "limits":"Sampling support is at most101x101. Existing dense color-region preparation and renderer limits remain; full maximum/dense capacity, physical platform, 60fps and exact Photoshop defaults/output remain open. API sharing/request limits still apply.",
      "adobe":"No dedicated endpoint in the pinned Photoshop v2 contract. No unverified actionJSON descriptor, UXP runtime or plugin support is claimed."]
  }
}

@MainActor extension AutomationService {
  func executeMagicWand(_ command:AutomationCommand, document:CraftNSDocument, shareID:UUID) async throws -> AutomationResponse {
    let store = document.store, operation = try command.string("operation")
    let options = try MagicWandAPI.options(command,store:store)
    let mode = try command.selectionMode(store.selectionMode)
    let all = try command.adjustmentBrushFlag("sampleAllLayers",store.wandSampleAllLayers)
    if operation == "configure" {
      guard Set(command.parameters.keys).isSubset(of:MagicWandAPI.settingKeys.union(["operation"])), command.parameters.count > 1 else {
        throw AutomationFailure(status:400,message:"Configure requires a nonempty Magic Wand settings patch.")
      }
      try Task.checkCancellation()
      store.wandOptions = options; store.wandSampleAllLayers = all; store.selectionMode = mode
      return .json(["revision":revision(store),"magicWand":MagicWandAPI.state(store)])
    }
    guard operation == "select" else { throw AutomationFailure(status:400,message:"Choose configure or select.") }
    guard store.canUseMagicWand else { throw AutomationFailure(status:422,message:"Magic Wand requires an idle RGB composite or ordinary layer-mask context.") }
    let point = PathPoint(try command.number("x",range:0...300000),try command.number("y",range:0...300000))
    guard let id = try command.parameters["layerID"].map({ _ in try command.actionUUID("layerID") }) ?? store.document.activeLayerID else {
      throw AutomationFailure(status:400,message:"Choose a source layer.")
    }
    let mask:Bool
    if command.parameters["target"] != nil { mask = try command.string("target") == "layerMask" } else { mask = store.editingMask }
    let request = MagicWandRequest(layerID:id,point:point,options:options,mode:mode,sampleAllLayers:all,mask:mask)
    try await executePreparedOperation(document:document,shareID:shareID,revision:command.revision,allowAuxiliary:true) {
      try request.command(in:$0)
    }
    return .json(["revision":revision(store),"magicWand":MagicWandAPI.state(store)])
  }
}
