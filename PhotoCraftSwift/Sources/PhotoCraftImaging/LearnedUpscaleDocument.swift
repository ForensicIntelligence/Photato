import CryptoKit
import Foundation
import PhotoCraftCore

public enum LocalUpscaleProvider {
  public static let identifier = "realesr-general-x4v3-coreml-fp16"
  public static let archiveSHA256 = "41368af9dcbcc300c0fe0442202acbf98d30dc07c28d49bf656883f7fef3656a"
  public static var modelURL: URL? { Bundle.main.url(forResource:"LocalUpscale",withExtension:"mlmodelc") }
  public static var unavailableReason: String? {
    #if arch(arm64)
    guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else {
      return "Local super-resolution requires macOS 26 or later on Apple Silicon."
    }
    return modelURL == nil ? "This build does not include the optional Real-ESRGAN model." : nil
    #else
    return "Local super-resolution requires an Apple Silicon build on macOS 26 or later."
    #endif
  }
  public static func validateModel(_ url:URL) throws {
    guard url.isFileURL, url.lastPathComponent == "LocalUpscale.mlmodelc",
      let provenance = try JSONSerialization.jsonObject(with:Data(contentsOf:url.deletingLastPathComponent().appendingPathComponent("LocalUpscale.provenance.json"))) as? [String:Any],
      provenance["identifier"] as? String == identifier, provenance["archive_sha256"] as? String == archiveSHA256,
      let files=provenance["compiled_sha256"] as? [String:String], files.count == 5 else {
      throw CraftError.invalid("Missing or invalid local super-resolution provenance.")
    }
    let expected:Set<String> = ["metadata.json","model.mil","coremldata.bin","weights/weight.bin","analytics/coremldata.bin"]
    guard Set(files.keys) == expected else {throw CraftError.invalid("Invalid local model manifest.")}
    for (path,digest) in files {
      try Task.checkCancellation()
      let file=url.appendingPathComponent(path)
      let values=try file.resourceValues(forKeys:[.isSymbolicLinkKey,.fileSizeKey])
      guard values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 16*1024*1024,
        SHA256.hash(data:try Data(contentsOf:file)).map({String(format:"%02x",$0)}).joined() == digest else {
        throw CraftError.invalid("The local super-resolution model does not match its manifest.")
      }
    }
  }
}

public enum LearnedUpscaleDocument {
  public static func unavailableReason(_ source:CraftDocument) -> String? {
    guard source.colorMode == .rgb, source.modeDescriptor == nil, source.restrictedMode == nil,
      source.inkMode == nil, !source.isChannelOnly, source.animation == nil, source.videoTimeline == nil else {
      return "Local super-resolution currently requires a still RGB document."
    }
    return nil
  }
  public static func prepare(_ source:CraftDocument,scale:Int,
    progress:@escaping @Sendable(LearnedUpscale.Progress)->Void = {_ in}) async throws -> CraftDocument {
    guard let url=LocalUpscaleProvider.modelURL, LocalUpscaleProvider.unavailableReason == nil else {
      throw CraftError.unsupported(LocalUpscaleProvider.unavailableReason ?? "The local model is unavailable.")
    }
    try LocalUpscaleProvider.validateModel(url)
    let model=try CoreMLUpscaleModel(url:url)
    return try await prepare(source,scale:scale,model:model,progress:progress)
  }
  public static func prepare(_ source:CraftDocument,scale:Int,model:any LearnedUpscalePredicting,
    progress:@escaping @Sendable(LearnedUpscale.Progress)->Void = {_ in}) async throws -> CraftDocument {
    try Task.checkCancellation();try source.validate()
    if let reason=unavailableReason(source) {throw CraftError.unsupported(reason)}
    let size=try LearnedUpscale.outputSize(width:source.width,height:source.height,scale:scale)
    let composite=try Renderer.compositePaged(source)
    let linear=try CraftDocument(width:1,height:1,depth:.f32)
    let input=try ColorManagement.converted(composite,from:source,to:linear)
    let pixels=try await LearnedUpscale.render(input,scale:scale,depth:source.depth,model:model,progress:progress)
    var output=try CraftDocument(width:size.width,height:size.height,depth:source.depth)
    output.name=source.name + " - \(scale)x"
    output.resolution=source.resolution;output.workingICC=source.workingICC
    var generated=try CraftDocument(width:1,height:1,depth:source.depth)
    generated.workingICC=nil
    let converted=try ColorManagement.converted(pixels,from:generated,to:output)
    var layer=Layer(name:"Super resolution",content:.raster(converted))
    layer.sourceTags = ["PtSR":try JSONSerialization.data(withJSONObject:["version":1,"model":LocalUpscaleProvider.identifier,
      "scale":scale,"sourceWidth":source.width,"sourceHeight":source.height,
      "sourceDocumentID":source.id.uuidString,"processing":"onDevice","alpha":"bilinear",
      "rgb":"learned4x;2xAreaReduction","PhotoshopOutputEquivalent":false],options:[.sortedKeys])]
    output.layers=[layer];output.activeLayerID=layer.id
    try output.validate();try Task.checkCancellation();return output
  }
}
