import Foundation
import PhotoCraftCore

enum CustomKernelPresetAPI {
  static let name="filter.custom.preset"
  static let maximumBase64=((CustomKernelPreset.maximumBytes+2)/3)*4
  static var definition:AutomationCommand.Definition {
    .init(name:name,parameters:["operation":"encode or decode","format":"acf or json","data":"Base64 preset for decode","settings":"Custom Filter settings for encode"],description:"Convert ACF or Photato JSON Custom Filter presets through the native codec, without changing pixels, history, settings or files. Apply the returned filter with filter.apply.",optionalParameters:["data","settings"])
  }
  static var settingsSchema:[String:Any] {OtherVideoSettings.apiSchema(kind:.customFilter)}
  static var parameterSchema:[String:Any] {
    let format=BrushAPI.enumeration(CustomKernelPreset.Format.allCases.map(\.rawValue))
    let data:[String:Any]=["type":"string","contentEncoding":"base64","minLength":1,"maxLength":maximumBase64]
    var value=BrushAPI.object(["operation":BrushAPI.enumeration(["encode","decode"]),"format":format,"data":data,"settings":settingsSchema],required:["operation","format"])
    value["oneOf"]=[BrushAPI.object(["operation":["const":"encode"],"format":format,"settings":settingsSchema],required:["operation","format","settings"]),BrushAPI.object(["operation":["const":"decode"],"format":format,"data":data],required:["operation","format","data"])]
    return value
  }
  static var commandSchema:[String:Any] {
    BrushAPI.object(["command":["const":name],"revision":["type":"string","minLength":1],"parameters":parameterSchema],required:["command","revision","parameters"])
  }
  static var resultSchema:[String:Any] {
    BrushAPI.object(["revision":["type":"string"],"format":BrushAPI.enumeration(CustomKernelPreset.Format.allCases.map(\.rawValue)),"data":["type":"string","contentEncoding":"base64","maxLength":maximumBase64],"byteLength":BrushAPI.number(1,Double(CustomKernelPreset.maximumBytes),integer:true),"filename":["type":"string"],"contentType":BrushAPI.enumeration(["application/octet-stream","application/json"]),"filter":BrushAPI.object(["kind":["const":"customFilter"],"otherVideo":settingsSchema],required:["kind","otherVideo"])],required:["revision","format","data","byteLength","filename","contentType","filter"])
  }
  static var capabilities:[String:Any] {
    ["command":name,"parameterSchema":parameterSchema,"resultSchema":resultSchema,"readOnly":true,"formats":["acf","json"],"acfBytes":54,"maximumJSONBytes":CustomKernelPreset.maximumBytes,"defaultDesktopSaveFormat":"acf","layout":"27 signed big-endian Int16 values:25 row-major weights, Scale, Offset; no header or trailing bytes.","ranges":"Weights -999...999; whole Scale1...9999 and Offset-9999...9999. Fractional Scale/Offset require Photato JSON; never rounded silently.","application":"filter.apply with returned filter uses native preview/history/Smart Filters/portable Actions. Conversion alone has no history or document/file side effects. Shared current document and revision required; normal busy/stale/revocation guards apply.","Adobe":"No new Adobe endpoint; preset conversion is a Photato utility. Full Custom Filter output/default/descriptor fidelity remains open."]
  }
  static func convert(_ command:AutomationCommand,revision:String)throws->[String:Any] {
    do{return try convertChecked(command,revision:revision)}
    catch let failure as AutomationFailure {throw failure}
    catch is CancellationError {throw CancellationError()}
    catch {throw AutomationFailure(status:400,message:error.localizedDescription)}
  }
  private static func convertChecked(_ command:AutomationCommand,revision:String)throws->[String:Any] {
    let operation=try command.string("operation"),rawFormat=try command.string("format")
    guard let format=CustomKernelPreset.Format(rawValue:rawFormat)else{throw AutomationFailure(status:400,message:"Choose acf or json.")}
    let settings:OtherVideoSettings,data:Data
    switch operation {
    case "decode":
      guard Set(command.parameters.keys)==["operation","format","data"],case .string(let raw)=command.parameters["data"],!raw.isEmpty,raw.utf8.count<=maximumBase64,let bytes=Data(base64Encoded:raw),bytes.count<=CustomKernelPreset.maximumBytes,bytes.base64EncodedString()==raw else {throw AutomationFailure(status:400,message:"Supply only format and a bounded canonical base64 preset for decode.")}
      settings=try CustomKernelPreset.decode(bytes,format:format);data=bytes
    case "encode":
      guard Set(command.parameters.keys)==["operation","format","settings"],let value=command.parameters["settings"]else{throw AutomationFailure(status:400,message:"Supply only format and Custom Filter settings for encode.")}
      let object=try BrushAPI.merge(value,schema:settingsSchema,path:"settings")
      settings=try OtherVideoSettings.decodeJSON(JSONSerialization.data(withJSONObject:object),kind:.customFilter)
      data=try CustomKernelPreset.encode(settings,format:format)
    default:throw AutomationFailure(status:400,message:"Choose encode or decode.")
    }
    return ["revision":revision,"format":format.rawValue,"data":data.base64EncodedString(),"byteLength":data.count,"filename":"Custom Filter."+format.rawValue,"contentType":format == .acf ? "application/octet-stream":"application/json","filter":["kind":"customFilter","otherVideo":settings.apiParameters(kind:.customFilter)]]
  }
}
