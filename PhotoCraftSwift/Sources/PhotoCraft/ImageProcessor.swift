import Foundation
import PhotoCraftCore
import PhotoCraftImaging

struct ImageProcessorSettings: Codable,Equatable,Sendable {
  struct Format: Codable,Equatable,Sendable {
    var enabled = false
    var resize = false
    var width = 1024
    var height = 1024
    func validate() throws {
      guard (1...30_000).contains(width),(1...30_000).contains(height) else {throw CraftError.invalid("Resize dimensions must be1–30,000 pixels.")}
    }
  }
  var jpeg = Format(enabled:true)
  var psd = Format()
  var tiff = Format()
  var jpegQuality = 8
  var convertJPEGToSRGB = true
  var includeICC = true
  var tiffLZW = true
  var maximizeCompatibility = true
  var dontEnlarge = true
  var copyright = ""
  var actionID: UUID?
  var useFirstImageProfile = false
  var formats: [(DocumentIO.Format,Format)] {[(.jpeg,jpeg),(.psd,psd),(.tiff,tiff)].filter{$0.1.enabled}}
  func validate() throws {
    try jpeg.validate();try psd.validate();try tiff.validate()
    guard !formats.isEmpty,(0...12).contains(jpegQuality),copyright.utf8.count <= 4096,!copyright.contains("\0") else {throw CraftError.invalid("Select at least one output format, JPEG quality0–12 and copyright text up to4096 bytes.")}
    guard maximizeCompatibility else {throw CraftError.unsupported("PSD output currently includes its compatibility composite. Disabling that composite is not implemented yet.")}
  }
  func encoded() throws -> Data {try validate();let encoder = JSONEncoder();encoder.outputFormatting = [.prettyPrinted,.sortedKeys];return try encoder.encode(self)}
  static func decode(_ data: Data) throws -> Self {
    guard data.count <= 65_536 else {throw CraftError.invalid("Image Processor settings exceed64KiB.")}
    let result = try JSONDecoder().decode(Self.self,from:data);try result.validate();return result
  }
}
enum ImageProcessor {
  static let maximumSources = 256
  static let maximumPixels = 8_388_608
  static let maximumBytes = 128*1024*1024
  struct Output: Sendable {
    let files: [StoredZIP.File]
    let records: [Record]
    func zip() throws -> Data {try StoredZIP.encode(files,maximumBytes:ImageProcessor.maximumBytes,allowSubdirectories:true)}
  }
  struct Record: Codable,Sendable {let source: String,file: String,width: Int,height: Int,format: String}
  static func folder(_ format: DocumentIO.Format) -> String {
    switch format {case .jpeg:"JPEG";case .psd:"PSD";case .tiff:"TIFF";default:""}
  }
  static func safeBase(_ name: String) -> String {
    var base = URL(fileURLWithPath:name).deletingPathExtension().lastPathComponent
    base = String(base.map{ "/:\\".contains($0) || $0.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains) ? "_":$0})
    while base.utf8.count > 160 {base.removeLast()}
    return base.isEmpty || base == "." || base == ".." ? "Untitled":base
  }
  static func converted(_ source: CraftDocument,profile: Data) throws -> CraftDocument {
    var document = source,request = ColorProfileRequest(.convert,profile:profile)
    request.mergeVisible = ColorProfileInput.needsMerge(source,destination:try ProofSettings.mode(of:profile))
    try ColorProfileInput.command(request,in:source).apply(to:&document);return document
  }
  static func render(_ sources: [ActionBatchSource],settings: ImageProcessorSettings,action: RecordedAction? = nil,
                     maximumBytes: Int = maximumBytes,progress: @Sendable (Int,Int) -> Void = {_,_ in}) throws -> Output {
    try settings.validate();try Task.checkCancellation()
    guard (1...maximumSources).contains(sources.count),maximumBytes > 0,maximumBytes <= Self.maximumBytes else {throw CraftError.invalid("Choose1–256 images within the128MiB output budget.")}
    guard settings.actionID == action?.id else {throw CraftError.invalid("Load the selected action before processing images.")}
    try action?.validate()
    if action?.usesMasterPalette == true {throw CraftError.unsupported("Master-palette actions require the Batch workflow.")}
    if action?.requiresInitialClipboard == true {throw CraftError.unsupported("Image Processor actions cannot read the system clipboard. Use self-contained actions.")}
    var files: [StoredZIP.File] = [],records: [Record] = [],total = 0,claims = Set<String>(),firstProfile: Data?
    for (index,input) in sources.enumerated() {
      try Task.checkCancellation()
      var document: CraftDocument
      if let snapshot = input.document {document = snapshot} else if let url = input.url {document = try DocumentIO.read(url)} else {throw CraftError.invalid("A source image is unavailable.")}
      try document.validate()
      guard document.width <= maximumPixels/document.height,document.estimatedBytes <= 512*1024*1024,document.animation == nil,document.videoTimeline == nil else {throw CraftError.unsupported("Choose still images up to8,388,608 pixels and512MiB of source data each.")}
      if settings.useFirstImageProfile {
        if firstProfile == nil {firstProfile = try ColorProfileInput.effectiveProfile(document)}
        let profile = try NativeModeProfile.atDepth(firstProfile!,mode:ProofSettings.mode(of:firstProfile!),depth:document.depth)
        document = try converted(document,profile:profile)
      }
      if let action {
        let playback = try RecordedActionRenderer.prepare(action,in:document)
        try playback.command.apply(to:&document)
      }
      guard document.width <= maximumPixels/document.height,document.estimatedBytes <= 512*1024*1024 else {throw CraftError.unsupported("The action result exceeds Image Processor source limits.")}
      if !settings.copyright.isEmpty {document = try CopyrightMetadata.applying(settings.copyright,to:document)}
      for (format,options) in settings.formats {
        try Task.checkCancellation();var output = document
        if options.resize {
          let fit = FitImageOptions(width:options.width,height:options.height,dontEnlarge:settings.dontEnlarge)
          let size = try fit.dimensions(sourceWidth:output.width,sourceHeight:output.height)
          guard size.width <= maximumPixels/size.height else {throw CraftError.unsupported("A resized image exceeds8,388,608 pixels.")}
          try Command.fitImage(fit).apply(to:&output)
        }
        if format == .jpeg,settings.convertJPEGToSRGB {
          output = try converted(output,profile:NativeModeProfile.standard(.rgb,depth:output.depth))
        }
        output.profileIsUntagged = settings.includeICC ? nil:true
        // Applied variations are output, while editable definitions stay in sources.
        output.variables = nil
        let encoding = RasterEncodingOptions(tiffCompression:format == .tiff ? (settings.tiffLZW ? .lzw:RasterEncodingOptions.TIFFCompression.none):nil,jpegQuality:format == .jpeg ? settings.jpegQuality:nil,jpegEmbedProfile:format == .jpeg ? settings.includeICC:nil)
        let bytes = try DocumentIO.encode(output,format:format,options:encoding)
        guard bytes.count <= maximumBytes-total else {throw CraftError.invalid("Processed images exceed128MiB. Process fewer images at once.")}
        total += bytes.count
        let base = safeBase(input.name),directory = folder(format),ext = format == .jpeg ? "jpg":format.rawValue
        var number = 0,name = directory+"/"+base+"."+ext
        while !claims.insert(name.precomposedStringWithCanonicalMapping.lowercased()).inserted {number += 1;name = directory+"/"+base+"_\(number)."+ext}
        files.append(.init(name:name,data:bytes));records.append(.init(source:input.name,file:name,width:output.width,height:output.height,format:format.rawValue))
      }
      progress(index+1,sources.count)
    }
    let encoder = JSONEncoder();encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
    let manifest = try encoder.encode(records)
    guard manifest.count <= maximumBytes-total else {throw CraftError.invalid("Image Processor manifest exceeds the output budget.")}
    files.append(.init(name:"image-processor.json",data:manifest));return Output(files:files,records:records)
  }
}
