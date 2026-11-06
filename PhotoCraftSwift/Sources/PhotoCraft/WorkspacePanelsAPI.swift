import Foundation
import PhotoCraftCore

// Workspace state is shared presentation, independently revisioned from image edits.
enum WorkspacePanelsAPI {
  static let name = "workspace.panels"
  static var definition: AutomationCommand.Definition {
    .init(name: name, parameters: ["workspaceRevision":"Current workspace UUID", "operation":"show, hide or layout",
      "panel":"Panel name for show/hide", "layout":"Complete current-catalog layout snapshot"],
      description:"Show/hide native panels or replace their validated shared layout without editing image content.",
      optionalParameters:["panel","layout"])
  }
  static var panelSchema:[String:Any] { BrushAPI.enumeration(WorkspacePanel.allCases.map(\.rawValue)) }
  static var identifier:[String:Any] { ["type":"string","minLength":1,"maxLength":64] }
  static var frameSchema:[String:Any] { BrushAPI.object([
    "x":BrushAPI.number(-100000,100000),"y":BrushAPI.number(-100000,100000),
    "width":BrushAPI.number(275,4000),"height":BrushAPI.number(120,4000)],required:["x","y","width","height"]) }
  static var dockSchema:[String:Any] {
    let group = BrushAPI.object(["id":identifier,"panels":ShapeAPI.array(panelSchema,14),"selected":panelSchema,
      "collapsed":BrushAPI.flag,"preferredHeight":BrushAPI.number(29,4000),"floatingFrame":frameSchema,
      "columnID":identifier,"floatingStack":identifier],required:["id","panels","selected","collapsed"])
    let column = BrushAPI.object(["id":identifier,"side":BrushAPI.enumeration(["left","right"]),
      "width":BrushAPI.number(275,600),"collapsed":BrushAPI.flag,"iconWidth":BrushAPI.number(34,240)],required:["id","side"])
    return BrushAPI.object(["catalogVersion":["type":"integer","enum":[3]],"groups":ShapeAPI.array(group,14),
      "hidden":ShapeAPI.array(panelSchema,14),"columns":ShapeAPI.array(column,15)],required:["catalogVersion","groups","hidden"])
  }
  static var layoutSchema:[String:Any] {
    let visibility = BrushAPI.object(Dictionary(uniqueKeysWithValues:
      ["tools","options","color","properties","layers","rail","collapsedDock"].map{($0,BrushAPI.flag)}),
      required:["tools","options","color","properties","layers","rail","collapsedDock"])
    return BrushAPI.object(["visibility":visibility,"colorTab":BrushAPI.enumeration(ColorPanelTab.allCases.map(\.rawValue)),
      "propertiesTab":BrushAPI.enumeration(PropertiesTab.allCases.map(\.rawValue)),"layersTab":BrushAPI.enumeration(LayersTab.allCases.map(\.rawValue)),
      "dockWidth":BrushAPI.number(275,410),"propertiesHeight":BrushAPI.number(160,10000),"doubleTools":BrushAPI.flag,"panelDock":dockSchema],
      required:["visibility","colorTab","propertiesTab","layersTab","dockWidth","propertiesHeight","doubleTools","panelDock"])
  }
  static func schema(_ key:String)->[String:Any] {
    switch key {
    case "workspaceRevision":return ["type":"string","format":"uuid"]
    case "operation":return BrushAPI.enumeration(["show","hide","layout"])
    case "panel":return panelSchema
    case "layout":return layoutSchema
    default:return [:]
    }
  }
  static var stateSchema:[String:Any] { BrushAPI.object([
    "workspaceRevision":schema("workspaceRevision"),"activeWorkspace":["type":"string"],"locked":BrushAPI.flag,
    "available":BrushAPI.flag,"writePermission":BrushAPI.flag,"layout":layoutSchema],
    required:["workspaceRevision","activeWorkspace","locked","available","writePermission","layout"]) }
  static var capabilities:[String:Any] { ["command":name,"stateSchema":stateSchema,"presentationOnly":true,"panelCatalogVersion":3,
    "native":"Character and Paragraph are real tabs in the existing dock, columns, floating stacks, close/reveal and saved-workspace system. Window and Type > Panels commands reveal the same panels. Their controls share existing selected-range/whole-layer text formatting, native text drafts and Undo; Properties remains available.",
    "operations":"show/hide requires panel only; layout requires a complete returned layout snapshot only. Layout includes panel order/group/selected/collapse/hidden, columns, floating frames/stacks, dimensions and visibility. Every supported panel occurs exactly once. Current-catalog3 only; legacy1/2 files migrate after strict validation. No proprietary Adobe endpoint invented.",
    "permission":"Separate native Allow workspace panel changes switch, off on API start/stop. Layout is shared by all open documents and persists in Workspaces.json. No image document transaction, Undo or recorded Action is added. Text edits retain existing text APIs and supported Adobe job contracts.",
    "revision":"workspaceRevision UUID is required in addition to the document revision. Native layout, saved-workspace switch and settings changes invalidate it; no-op state edits retain it. Busy/modal/gesture/stale/unshared/revoked and failed storage requests change nothing. Workspace Lock allows show/hide but rejects layout replacement.",
    "qualification":"Shared native text engine, not Photoshop pixel/default/composer/shortcut equivalence. Missing text defaults before creating a layer, mixed-value controls, dynamic panel formatting menus/shortcuts, exact layout/composition/PSD/physical-platform fidelity and fullT01remain major stillneeded where functional. No new canvas tool or modifier action."] }
  @MainActor static func state(_ library:WorkspaceLibrary, allowed:Bool)->[String:Any] {
    var value = library.layout
    value.panelDock = library.panelDock
    let encoded = (try? JSONEncoder().encode(value)) ?? Data()
    let layout = (try? JSONSerialization.jsonObject(with:encoded)) ?? [:]
    return ["workspaceRevision":library.panelRevision.uuidString,"activeWorkspace":library.activeName,"locked":library.workspaceLocked,
      "available":allowed && library.error == nil,"writePermission":allowed,"layout":layout]
  }
  static func isTypographyVisibility(_ command:AutomationCommand)->Bool {
    guard case .string(let operation) = command.parameters["operation"], ["show","hide"].contains(operation),
      case .string(let panel) = command.parameters["panel"] else { return false }
    return panel == "Character" || panel == "Paragraph"
  }
  @MainActor static func apply(_ command:AutomationCommand, library:WorkspaceLibrary)throws {
    guard try command.actionUUID("workspaceRevision") == library.panelRevision else { throw AutomationFailure(status:409,message:"Stale workspace. Refresh panel state.") }
    guard library.error == nil else { throw AutomationFailure(status:409,message:"Resolve the saved workspace error first.") }
    switch try command.string("operation") {
    case "show","hide":
      guard command.parameters["layout"] == nil, let panel = WorkspacePanel(rawValue:try command.string("panel")) else { throw AutomationFailure(status:400,message:"Choose one supported panel without layout.") }
      do { try library.setPanelVisible(panel,try command.string("operation") == "show") }
      catch { throw AutomationFailure(status:422,message:error.localizedDescription) }
    case "layout":
      guard command.parameters["panel"] == nil, let raw = command.parameters["layout"] else { throw AutomationFailure(status:400,message:"Provide layout without panel.") }
      guard !library.workspaceLocked else { throw AutomationFailure(status:409,message:"Unlock the workspace before arranging panels.") }
      let merged = try BrushAPI.merge(raw,schema:layoutSchema,path:"layout")
      let value:WorkspaceLayout
      do { value = try JSONDecoder().decode(WorkspaceLayout.self,from:JSONSerialization.data(withJSONObject:merged));try value.validate() }
      catch { throw AutomationFailure(status:400,message:"Invalid workspace topology: " + error.localizedDescription) }
      do { try library.setPanelLayout(value) }
      catch { throw AutomationFailure(status:422,message:error.localizedDescription) }
    default:throw AutomationFailure(status:400,message:"Unknown workspace panel operation.")
    }
  }
}
