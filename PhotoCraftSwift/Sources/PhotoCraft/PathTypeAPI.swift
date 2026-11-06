import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum PathTypeAPI {
  static var stateSchema:[String:Any]{BrushAPI.object([
    "supported":BrushAPI.flag,"editing":BrushAPI.flag,"rendering":BrushAPI.flag,
    "mode":["type":["string","null"]],"utf16Selection":["anyOf":[["type":"null"],BrushAPI.object(["location":["type":"integer","minimum":0],"length":["type":"integer","minimum":0]],required:["location","length"])]],
    "caretCount":["type":"integer","minimum":0],"overset":BrushAPI.flag,"error":["type":["string","null"]]],
    required:["supported","editing","rendering","mode","utf16Selection","caretCount","overset","error"])}
  static var capabilities:[String:Any]{[
    "commands":["text.create","text.set","text.layout"],"state":"pathTypeEditing","stateSchema":stateSchema,
    "native":"Horizontal Type hovering a selected connected path uses a wavy type cursor. Click captures a copied path and insertion fraction; native text storage/IME/local Undo, curve caret/range hit testing and shared renderer preview remain editable. Commit is one document transaction; Cancel retains source. Existing horizontal Path/Circle/Arch/Bow layers use the same native curve editor.",
    "API":"Supply text.geometry mode path and a complete copied path/start fraction to text.create at logical x0/y0 for the same native path-creation result; ordinary x/y remain logical offsets. text.set retains exact shared editing; text.layout pathID retains its existing saved-path-copy contract. No new command, Adobe route or format version.",
    "cursor":"All16Control/Command/Option/Shift combinations currently retain the same path-entry operation and cursor; source/tool/point are captured at pointer down. Space pans; unavailable/busy/individual-channel/vertical contexts do not advertise path typing. Full Photoshop alternate-modifier/default comparison remains unqualified.",
    "limits":"Current path renderer16384UTF16units/2000000outlinepoints/16MP; horizontal vector glyphs only. Vertical/inside/warp inline editing, path delimiters/dragging, marked-text/composer/affine/physical-platform/performance and Photoshop exact output remain open. No60fps or complete T04claim."]}
  @MainActor static func state(_ store:EditorStore)->[String:Any] {
    let text=store.typeEditingDraft?.content ?? store.activeLayer?.typeContent,editor=store.typeEditor as?CanvasPathTypeEditor
    let range=editor?.selectedRange()
    return ["supported":text.map{CanvasPathTypeEditor.supports($0)} ?? false,"editing":editor != nil,
      "rendering":editor?.pathRendering ?? false,"mode":text?.typography?.geometry?.mode.rawValue as Any? ?? NSNull(),
      "utf16Selection":range.map{["location":$0.location,"length":$0.length]} as Any? ?? NSNull(),
      "caretCount":editor?.pathGeometry?.carets.count ?? 0,"overset":editor?.pathGeometry?.overset ?? false,"error":editor?.pathError as Any? ?? NSNull()]
  }
}
