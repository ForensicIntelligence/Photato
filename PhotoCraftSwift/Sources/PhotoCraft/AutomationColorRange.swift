import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum ColorRangeAPI {
  static var settingsSchema:[String:Any] {
    let sample=BrushAPI.object(["color":BrushAPI.color,"point":BrushAPI.object(["x":BrushAPI.number(0,1),"y":BrushAPI.number(0,1)],required:["x","y"]),"subtract":BrushAPI.flag],required:["color"])
    return BrushAPI.object(["kind":BrushAPI.enumeration(ColorRangeSettings.Kind.allCases.map(\.rawValue)),"fuzziness":BrushAPI.number(0,200),"localized":BrushAPI.flag,"range":BrushAPI.number(0,100),"minimum":BrushAPI.number(0,255),"maximum":BrushAPI.number(0,255),"invert":BrushAPI.flag,"samples":["type":"array","maxItems":128,"items":sample]])
  }
  static func schema(_ key:String)->[String:Any] {
    key == "settings" ? settingsSchema:["type":"string","minLength":1,"maxLength":174_768]
  }
  static var stateSchema:[String:Any] {
    let fields:[String:Any]=["available":BrushAPI.flag,"workspaceOpen":BrushAPI.flag,"previewBusy":BrushAPI.flag,"settings":settingsSchema,"presetBase64":["type":"string"],"previewError":["anyOf":[["type":"null"],["type":"string"]]]]
    return BrushAPI.object(fields,required:Array(fields.keys).sorted())
  }
  static var resultSchema:[String:Any] {["type":"object","required":["revision","colorRange"],"properties":["revision":["type":"string"],"colorRange":stateSchema]]}
  static var capabilities:[String:Any] {[
    "command":"selection.colorRange","settingsSchema":settingsSchema,"stateSchema":stateSchema,"resultSchema":resultSchema,"defaults":BrushAPI.json(ColorRangeSettings()),
    "input":"Visible RGB composite converted to SDR sRGB; all layers are sampled independently of the active layer. Existing selection constrains the result by coverage intersection. Deselect first to replace an active selection over the whole canvas.",
    "algorithm":"Independent native CIE Lab D65 sample distance, max additive/min subtractive coverage, hue-sector presets and sRGB luminance tone windows with linear fuzziness falloff. Localized clusters multiply radial sample falloff. Source alpha multiplies coverage after inversion. Numerical equivalence to Photoshop is unqualified.",
    "samples":"At most128; normalized image positions x/y0–1 required for localized samples. Colors are SDR sRGB; alpha is ignored as a sampling coordinate. Fuzziness0–200; localized range0–100 percent of image diagonal;0 has a half-pixel minimum radius. Shadows use maximum, highlights minimum, midtones both0–255.",
    "presets":"Either partial settings or a version1 Photato JSON preset encoded as presetBase64; mutually exclusive. Preset maximum128KiB. Result state exposes the accepted preset. No Adobe .axt interoperability.",
    "history":"One Color Range native Undo transaction; Actions stores explicit final selection coverage using existing version4 support rather than rerunning classification. Preview/Cancel never edit source/history.",
    "limits":"No extra document dimension or dense pixel admission cap. Nonlocalized classification uses sparse/tiled stored samples; localized work visits its sample support bounds and is cancellable. API retains shared-document4,194,304 pixels/8,000layers/128MiB and4MiB requests. Physical maximum-capacity and60fps behavior unqualified.",
    "unsupported":["Skin Tones / Detect Faces","Out of Gamut / CMYK proof gamut","Adobe preset format","Photoshop semantic Color Range actionJSON"],
    "adobe":"No dedicated published Color Range endpoint. Existing execute-actions keeps unverified semantic descriptors unsupported; no route is invented.",
    "cursor":"Shift add, Option subtract (Option wins together); Control/Command retain sampling operation. Command temporarily toggles selection/image presentation. Sampler mode is captured until mouse release."
  ]}
}
extension AutomationCommand {
  func colorRangeOptions()throws->ColorRangeSettings {
    guard parameters["settings"]==nil || parameters["presetBase64"]==nil else {throw AutomationFailure(status:400,message:"Use settings or presetBase64, not both.")}
    do {
      if parameters["presetBase64"] != nil {
        guard case .string(let encoded)=parameters["presetBase64"],let bytes=Data(base64Encoded:encoded) else {throw CraftError.invalid("Invalid base64 Color Range preset.")}
        return try ColorRangeSettings.preset(bytes)
      }
      let base=BrushAPI.json(ColorRangeSettings())
      let raw=try parameters["settings"].map {try BrushAPI.merge($0,schema:ColorRangeAPI.settingsSchema,base:base,path:"Color Range settings")} ?? base
      var object=raw as! [String:Any]
      if var samples=object["samples"] as? [[String:Any]] {
        for i in samples.indices {if samples[i]["subtract"]==nil{samples[i]["subtract"]=false}}
        object["samples"]=samples
      }
      let settings=try JSONDecoder().decode(ColorRangeSettings.self,from:JSONSerialization.data(withJSONObject:object));try settings.validate();return settings
    }catch let failure as AutomationFailure {throw failure}
    catch {throw AutomationFailure(status:400,message:error.localizedDescription)}
  }
}
@MainActor extension EditorStore {
  var colorRangeState:[String:Any] {
    let settings=colorRangeDraft?.settings ?? colorRangeSettings
    return ["available":canBeginColorRange,"workspaceOpen":colorRangeDraft != nil,"previewBusy":colorRangeDraft.map{$0.loading || $0.rendering || $0.committing} ?? false,"settings":BrushAPI.json(settings),"presetBase64":(try? settings.presetData().base64EncodedString()) ?? "","previewError":colorRangeDraft?.error as Any? ?? NSNull()]
  }
}
