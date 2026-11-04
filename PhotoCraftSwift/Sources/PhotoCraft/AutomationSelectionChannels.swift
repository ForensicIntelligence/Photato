import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension ChannelAPI {
  static func optionsState(_ options:ChannelDisplayOptions)->[String:Any] {
    ["color":[options.color.r,options.color.g,options.color.b],"opacity":options.opacity,"indicates":options.indicates.rawValue]
  }
}
extension AutomationCommand {
  func channelDisplayOptions(_ initial:ChannelDisplayOptions)throws->ChannelDisplayOptions {
    var options=initial
    if parameters["opacity"] != nil {options.opacity=Float(try number("opacity",range:0...1))}
    if parameters["indicates"] != nil {
      guard let value=ChannelDisplayOptions.Indicates(rawValue:try string("indicates"))else{throw AutomationFailure(status:400,message:"Invalid Color Indicates option.")}
      options.indicates=value
    }
    if let raw=parameters["overlayColor"] {
      guard case .array(let values)=raw,values.count==3 else{throw AutomationFailure(status:400,message:"overlayColor requires three RGB values.")}
      let rgb=try values.map {value->Float in
        guard case .number(let n)=value,n.isFinite,(0...1).contains(n)else{throw AutomationFailure(status:400,message:"Invalid overlay color.")}
        return Float(n)
      }
      options.color=Pixel(rgb[0],rgb[1],rgb[2])
    }
    try options.validate();return options
  }
}
extension AutomationService {
  func executeSelectionChannel(_ command:AutomationCommand,document:CraftNSDocument,share:Share)async throws {
    let store=document.store,action=try command.string("action"),defaults=store.quickMaskOptions
    let maskTarget=action=="quickMask" && store.document.quickMask != nil ? store.selectedMaskPaintTarget:nil
    if ["stroke", "fill", "invert"].contains(action), case .string("quickMask") = command.parameters["target"],
      store.document.quickMask != nil, !store.isQuickMaskVisible {
      try store.validateQuickMaskVisibility(command.channelEdit(document:store.document,defaults:defaults))
    }
    if action == "quickMaskOptions" {
      guard Set(command.parameters.keys).isSubset(of:["action","overlayColor","opacity","indicates"]) else{throw AutomationFailure(status:400,message:"Unknown Quick Mask option.")}
      let options=try command.channelDisplayOptions(defaults)
      if store.document.quickMask != nil {
        try await executePreparedOperation(document:document,shareID:share.id,revision:command.revision,allowSelection:action == "loadSelection",allowAuxiliary:true,validateCommit:{
          guard store.quickMaskOptions==defaults else{throw AutomationFailure(status:409,message:"Quick Mask defaults changed.")}
        }){_ in .channel(.options(.quickMask,options))}
      }
      try store.quickMaskPreferences.set(options);store.render();return
    }
    let hasSource=command.parameters["sourceDocumentID"] != nil || command.parameters["sourceRevision"] != nil
    var sourceDocument:CraftNSDocument?,sourceShareID:UUID?,sourceRevision:String?,sourceModel:CraftDocument?
    if hasSource {
      guard ["saveSelection","loadSelection"].contains(action)else{throw AutomationFailure(status:400,message:"Only save/load selections accepts a source document.")}
      let id=try command.actionUUID("sourceDocumentID"),revision=try command.string("sourceRevision")
      guard let entry=shares.first(where:{$0.id==id}),let source=entry.document else{throw AutomationFailure(status:404,message:"Shared source document not found.")}
      try preflight(source)
      guard self.revision(source.store)==revision else{throw AutomationFailure(status:409,message:"The source revision changed.")}
      guard source.store.document.width==store.document.width,source.store.document.height==store.document.height else{throw AutomationFailure(status:422,message:"Selection source and destination must have equal pixel dimensions.")}
      sourceDocument=source;sourceShareID=id;sourceRevision=revision;sourceModel=source.store.document
    }
    let capturedSource=sourceModel,prepare=selectionChannelPrepare,colorSettings=controller.colorSettings.value
    try await executePreparedOperation(document:document,shareID:share.id,revision:command.revision,allowAuxiliary:true,validateCommit:{
      guard self.controller.colorSettings.value==colorSettings else{throw AutomationFailure(status:409,message:"Color Settings changed during selection processing.")}
      if let sourceDocument,let sourceShareID,let sourceRevision,let sourceModel {
        guard self.shares.contains(where:{$0.id==sourceShareID && $0.document === sourceDocument}),
          self.revision(sourceDocument.store)==sourceRevision,sourceDocument.store.document==sourceModel else{throw AutomationFailure(status:409,message:"The source changed, closed or sharing was revoked.")}
        if sourceDocument !== document {try self.preflight(sourceDocument)}
      }
      if action == "quickMask",store.quickMaskOptions != defaults{throw AutomationFailure(status:409,message:"Quick Mask defaults changed.")}
    }) {original in
      try await prepare(command,original,defaults,capturedSource,colorSettings)
    }
    if action == "quickMask" {store.resetQuickMaskEditingContext(preserving:maskTarget);store.render()}
  }
}

/// Shared source snapshot adapter; the engine remains the desktop channel command path.
enum SelectionChannelPreparation {
  static func prepare(_ command:AutomationCommand,target:CraftDocument,defaults:ChannelDisplayOptions,source:CraftDocument?,colorSettings:ColorSettings = .init())throws->Command {
      if let raw=command.parameters["source"] {
        guard try command.string("action")=="loadSelection",Set(command.parameters.keys).isSubset(of:["action","source","mode","invert","sourceDocumentID","sourceRevision"])else{throw AutomationFailure(status:400,message:"Selection source is valid only for Load Selection, without target.")}
        let selected=try SelectionChannelSourceAPI.decode(raw)
        let mode:SelectionMode
        if command.parameters["mode"] != nil {guard let value=SelectionMode(rawValue:try command.string("mode"))else{throw AutomationFailure(status:400,message:"Invalid selection combination.")};mode=value}else{mode = .replace}
        return try .channel(.loadCoverage(selected.selection(in:source ?? target,invert:command.pathFlag("invert",false),colorSettings:colorSettings),mode))
      }
      let operation=try command.channelEdit(document:target,defaults:defaults,allowExternalSource:source != nil)
      guard let source=source else{return operation}
      guard case .channel(let channel)=operation else{throw AutomationFailure(status:400,message:"Expected a channel operation.")}
      switch channel {
      case .saveSelection(let id,let name,let mode):
        guard source.quickMask == nil,source.selection != nil || source.selectionMask != nil else{throw CraftError.invalid("Make a selection outside Quick Mask before saving it.")}
        return try .channel(.storeSelection(AlphaChannel.coverage(source.coverageSelection(),width:source.width,height:source.height,depth:target.depth),id,name,mode))
      case .load(let target,let mode,let invert):return try .channel(.loadCoverage(source.channel(target).selection(invert:invert),mode))
      default:throw AutomationFailure(status:400,message:"Expected save/load selection.")
      }
  }
}
