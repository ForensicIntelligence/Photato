import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum GalleryTextureAPI {
  static let name="filter.gallery.texture"
  static let maximumBase64=((GalleryTextureLoader.maximumInputBytes+2)/3)*4
  static var definition:AutomationCommand.Definition {
    .init(name:name,parameters:["data":"Canonical base64 Photoshop PSD/PSB merged image","name":"Texture display name"],description:"Decode a custom Gallery texture into self-contained height samples using the native loader. No document or preference change; use the returned texture in filter.apply artistic.effects[].texture.",optionalParameters:["name"])
  }
  static var parameterSchema:[String:Any] {BrushAPI.object(["data":["type":"string","contentEncoding":"base64","minLength":4,"maxLength":maximumBase64],"name":["type":"string","minLength":1,"maxLength":256,"default":"Texture.psd"]],required:["data"])}
  static var commandSchema:[String:Any] {BrushAPI.object(["command":["const":name],"revision":["type":"string","minLength":1],"parameters":parameterSchema],required:["command","revision","parameters"])}
  static var resultSchema:[String:Any] {BrushAPI.object(["revision":["type":"string"],"texture":GalleryTextureSource.apiSchema],required:["revision","texture"])}
  static var workspaceStateSchema:[String:Any] {["type":"object","properties":["textureLoading":["type":"boolean"],"textureError":["type":["string","null"]]]]}
  static var capabilities:[String:Any] {
    ["command":name,"parameterSchema":parameterSchema,"resultSchema":resultSchema,"textureSchema":GalleryTextureSource.apiSchema,"workspaceStateExtensionSchema":workspaceStateSchema,
      "maximumCommandBodyBytes":maximumBase64+65536,"readOnly":true,"filters":GalleryFilter.allCases.filter{GalleryTextureSource.supports($0)}.map(\.rawValue),
      "nativeArchiveVersion":88,"ActionsVersion":54,
      "application":"filter.apply with kind filterGallery and artistic.effects[].texture; existing Smart Filters, Actions, local and document history retain embedded samples. Texture null or omission uses the built-in texture choice.",
      "conversion":"ImageIO merged PSD/PSB decode into encoded sRGB8, then rounded0.299R+0.587G+0.114B height. Texture has row-major8bit samples, no external URL/bookmark. Desktop file and API use the same loader.",
      "sampling":"Bilinear periodic height samples at integer pixel centers; existing scaling/invert/light/relief controls apply. Glass uses distortion/smoothness. Built-in effects and numeric paths remain unchanged.",
      "workspace":"filterGallery.workspace.textureLoading/textureError; invalid/cancelled/stale loads preserve prior settings, history and usable preview. OK waits for loading; Cancel cancels the owned load.",
      "limits":["texturePixels":GalleryTextureSource.maximumPixels,"fileBytes":GalleryTextureLoader.maximumInputBytes,"body":"Existing native API request limits also apply; existing Gallery8MP layer/64M effect-pixel and Actions16MiB limits remain."],
      "qualification":"Custom textures functional for five effects. Exact Photoshop conversion, merged/alpha/profile interpretation, orientation/tiling/scale/light/Glass sampling and numerical output remain unqualified; physical capacity/60fps/full F06 remain open.",
      "Adobe":"No dedicated Photoshop v2 texture-import operation. Gallery actionJSON remains unsupported; no route or descriptor is invented."]
  }
  struct Input:Sendable {let data:String;let name:String}
  static func input(_ command:AutomationCommand)throws->Input {
    guard Set(command.parameters.keys).isSubset(of:["data","name"]),case .string(let raw)=command.parameters["data"],!raw.isEmpty,raw.utf8.count<=maximumBase64 else {throw AutomationFailure(status:400,message:"Supply a bounded canonical base64 Photoshop texture.")}
    let name=try command.parameters["name"].map{_ in try command.string("name")} ?? "Texture.psd"
    guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.utf8.count<=256,!name.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains) else {throw AutomationFailure(status:400,message:"Supply a texture name of1–256 UTF8 bytes without control characters.")}
    return .init(data:raw,name:name)
  }
  static func result(_ input:Input,revision:String)throws->Data {
    try Task.checkCancellation()
    guard let bytes=Data(base64Encoded:input.data),bytes.count<=GalleryTextureLoader.maximumInputBytes,bytes.base64EncodedString()==input.data else {throw CraftError.invalid("Invalid canonical base64 texture.")}
    let texture=try GalleryTextureLoader.decode(bytes,name:input.name)
    struct Envelope:Encodable {let revision:String;let texture:GalleryTextureSource}
    return try JSONEncoder().encode(Envelope(revision:revision,texture:texture))
  }
}

@MainActor extension AutomationService {
  func decodeGalleryTexture(_ command:AutomationCommand,document:CraftNSDocument,shareID:UUID)async throws->AutomationResponse {
    let input=try GalleryTextureAPI.input(command),epoch=generation
    guard !previewBusy else {throw AutomationFailure(status:429,message:"A preview or texture conversion is already running.")}
    previewBusy=true;defer{previewBusy=false}
    let worker=Task.detached(priority:.userInitiated){try GalleryTextureAPI.result(input,revision:command.revision)}
    let result:Data
    do {result=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()}}
    catch is CancellationError {throw CancellationError()}
    catch {throw AutomationFailure(status:400,message:error.localizedDescription)}
    prune();try Task.checkCancellation()
    guard generation==epoch,shares.contains(where:{$0.id==shareID}),command.revision==revision(document.store) else {throw AutomationFailure(status:409,message:"The document changed or sharing ended during texture conversion. Refresh and retry.")}
    try preflight(document)
    return .init(status:200,contentType:"application/json",body:result)
  }
}
