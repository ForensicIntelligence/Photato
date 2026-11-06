import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum SelectionChannelSourceAPI {
  static let kinds=["alpha","quickMask","composite","component","transparency","layerMask","smartFilterMask","vectorMask","plate","duotone"]
  static var schema:[String:Any] {
    ["oneOf":kinds.map {kind->[String:Any] in
      let needsID=["alpha","transparency","layerMask","smartFilterMask","vectorMask","plate"].contains(kind)
      var properties:[String:Any]=["kind":["const":kind]]
      if needsID {properties["id"]=["type":"string","format":"uuid"]}
      if kind=="component" {properties["component"]=["type":"integer","minimum":0,"maximum":3]}
      return ["type":"object","additionalProperties":false,"required":properties.keys.sorted(),"properties":properties]
    }]
  }
  static func state(_ source:SelectionChannelSource)->[String:Any] {
    switch source {
    case .alpha(let id):return ["kind":"alpha","id":id.uuidString]
    case .quickMask:return ["kind":"quickMask"]
    case .composite:return ["kind":"composite"]
    case .component(let n):return ["kind":"component","component":n]
    case .transparency(let id):return ["kind":"transparency","id":id.uuidString]
    case .layerMask(let id):return ["kind":"layerMask","id":id.uuidString]
    case .smartFilterMask(let id):return ["kind":"smartFilterMask","id":id.uuidString]
    case .vectorMask(let id):return ["kind":"vectorMask","id":id.uuidString]
    case .plate(let id):return ["kind":"plate","id":id.uuidString]
    case .duotone:return ["kind":"duotone"]
    }
  }
  static func decode(_ raw:AutomationValue)throws->SelectionChannelSource {
    guard case .object(let fields)=raw,case .string(let kind)=fields["kind"],kinds.contains(kind)else{throw AutomationFailure(status:400,message:"Choose a valid selection source kind.")}
    let required:Set<String>=["alpha","transparency","layerMask","smartFilterMask","vectorMask","plate"].contains(kind) ? ["kind","id"]:kind=="component" ? ["kind","component"]:["kind"]
    guard Set(fields.keys)==required else{throw AutomationFailure(status:400,message:"Selection source fields do not match its kind.")}
    func id()throws->UUID {guard case .string(let s)=fields["id"],let id=UUID(uuidString:s)else{throw AutomationFailure(status:400,message:"Invalid source UUID.")};return id}
    switch kind {
    case "alpha":return try .alpha(id());case "quickMask":return .quickMask;case "composite":return .composite
    case "component":guard case .number(let n)=fields["component"],n.isFinite,n.rounded()==n,(0...3).contains(n)else{throw AutomationFailure(status:400,message:"Invalid component index.")};return .component(Int(n))
    case "transparency":return try .transparency(id());case "layerMask":return try .layerMask(id());case "smartFilterMask":return try .smartFilterMask(id());case "vectorMask":return try .vectorMask(id());case "plate":return try .plate(id());default:return .duotone
    }
  }
}
extension EditorStore {
  var selectionChannelState:[String:Any] {
    let sources=SelectionChannelSource.choices(in:document,includingComponents:true)
    let grayName=(try? workingColorSettings.profile(.grayscale,depth:document.depth)).map(ColorPolicyInput.name) ?? "Unavailable"
    return ["footer":channelFooterState,"sources":sources.map(SelectionChannelSourceAPI.state),"workingGrayProfile":grayName,
      "canSaveSelection":canSaveSelectionChannel,"canSaveNewDocument":canSaveSelectionChannel,
      "canLoadSelection":canEditChannels && !sources.isEmpty,
      "canCreateAlpha":canEditChannels && (document.alphaChannels?.count ?? 0)<CraftDocument.maximumAlphaChannels]
  }
  func loadSelectionSource(_ source:SelectionChannelSource,mode:SelectionMode = .replace,invert:Bool=false) {
    guard canEditChannels else{return}
    let colorSettings=workingColorSettings
    performPreparedGeometry(label:"Load Selection",allowAuxiliary:true,prepare:{document in
      try PreparedEdit(command:.channel(.loadCoverage(source.selection(in:document,invert:invert,colorSettings:colorSettings),mode)),document:document)
    },validateCommit:{
      guard self.workingColorSettings==colorSettings else{throw CraftError.invalid("Color Settings changed during selection loading.")}
    })
  }
}
