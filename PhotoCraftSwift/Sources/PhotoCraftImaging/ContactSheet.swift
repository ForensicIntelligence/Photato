import Foundation
import PhotoCraftCore

/// Layout controls derived from the licensed PhotoCraft workflow. Numerical spacing,
/// resampling and typography are not yet qualified against Photoshop 2026 output.
public struct ContactSheetSettings: Codable, Equatable, Sendable {
  public enum Units: String, Codable, CaseIterable, Sendable { case inches, cm, mm, pixels }
  public var units: Units = .inches
  public var width = 8.0
  public var height = 10.0
  public var resolution = 300.0
  public var mode: DocumentColorMode = .rgb
  public var depth: PixelDepth = .u8
  public var profile: Data?
  public var columns = 5
  public var rows = 6
  public var placeAcrossFirst = true
  public var autoSpacing = true
  public var horizontal = 0.014
  public var vertical = 0.014
  public var rotateForBestFit = false
  public var caption = true
  public var font = "ArialMT"
  public var fontSize = 12.0
  public var flatten = true
  public init() {}
  public func pixels(_ value: Double) -> Double {
    switch units { case .inches: value * resolution; case .cm: value * resolution / 2.54; case .mm: value * resolution / 25.4; case .pixels: value }
  }
  public struct Layout: Sendable {
    public let width: Int, height: Int, perPage: Int
    public let horizontal: Double, vertical: Double, cellWidth: Double, cellHeight: Double, imageHeight: Double, captionHeight: Double
  }
  public func layout() throws -> Layout {
    guard [width,height,resolution,horizontal,vertical,fontSize].allSatisfy(\.isFinite),
      width > 0, height > 0, (1...10000).contains(resolution), horizontal >= 0, vertical >= 0,
      (1...100).contains(columns), (1...100).contains(rows), (0.1...4096).contains(fontSize),
      !font.isEmpty, font.utf8.count <= 256, DocumentColorMode.componentModes.contains(mode), mode.depths.contains(depth) else {
      throw CraftError.invalid("Choose valid page dimensions, resolution, grid, font and color mode.")
    }
    let w = pixels(width).rounded(), h = pixels(height).rounded()
    guard w >= 1, h >= 1, w <= 30000, h <= 30000, w*h <= Double(NativeModeRaster.maximumPixels) else {
      throw CraftError.unsupported("Contact sheet pages currently support up to 8,388,608 pixels and 30,000 pixels per side.")
    }
    if let profile { try NativeModeProfile.validate(profile,mode:mode,depth:depth) }
    let gap = max(2,min(w,h)*0.014), hs = autoSpacing ? gap:pixels(horizontal), vs = autoSpacing ? gap:pixels(vertical)
    let cw = (w-Double(columns+1)*hs)/Double(columns), ch = (h-Double(rows+1)*vs)/Double(rows)
    let captionHeight = caption ? fontSize*resolution/72*1.5:0
    guard cw >= 1, ch-captionHeight >= 1 else { throw CraftError.invalid("The grid, spacing and captions leave no room for thumbnails. Increase the page size or reduce these settings.") }
    return Layout(width:Int(w),height:Int(h),perPage:columns*rows,horizontal:hs,vertical:vs,cellWidth:cw,cellHeight:ch,imageHeight:ch-captionHeight,captionHeight:captionHeight)
  }
}
public enum ContactSheet {
  public static let maximumSources = 256
  public static let maximumPages = 32
  public static let maximumBytes = 512 * 1024 * 1024
  public struct Source: Sendable {
    public let document: CraftDocument
    public let name: String
    public init(document: CraftDocument, name: String? = nil) { self.document = document; self.name = name ?? document.name }
  }
  public struct Placement: Codable, Equatable, Sendable {
    public let source: Int, page: Int, column: Int, row: Int, x: Int, y: Int, width: Int, height: Int
    public let rotated: Bool
  }
  public struct Result: Sendable {
    public let documents: [CraftDocument]
    public let placements: [Placement]
  }
  public static func prepare(_ sources: [Source], settings: ContactSheetSettings, name: String = "ContactSheet") throws -> Result {
    let layout = try settings.layout();try Task.checkCancellation()
    // Validate even for layered output: the API must not publish captions that
    // only fail when a window later attempts to render them.
    if settings.caption {
      var style = TypeStyle();style.font = settings.font;style.size = settings.fontSize
      _ = try NativeFonts.font(style,dpi:settings.resolution)
    }
    guard (1...maximumSources).contains(sources.count), !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, name.utf8.count <= 240 else {
      throw CraftError.invalid("Choose one to 256 images and a page name of at most 240 bytes.")
    }
    let pages = (sources.count+layout.perPage-1)/layout.perPage
    guard pages <= maximumPages, layout.width*layout.height*pages <= 67_108_864 else {
      throw CraftError.unsupported("Contact sheets support up to32 pages and64 megapixels of combined page area.")
    }
    var sourceBytes = 0
    for source in sources {
      try Task.checkCancellation();try source.document.validate()
      guard source.document.animation == nil, source.document.videoTimeline == nil else { throw CraftError.unsupported("Choose still images for Contact Sheet II.") }
      guard !source.name.isEmpty,source.name.utf8.count <= 1024 else { throw CraftError.invalid("A source filename is empty or too long.") }
      sourceBytes += source.document.estimatedBytes
      guard sourceBytes <= maximumBytes else { throw CraftError.unsupported("Source documents exceed the512MiB contact-sheet budget.") }
    }
    var output: [CraftDocument] = [], placements: [Placement] = [], outputBytes = 0
    for page in 0..<pages {
      try Task.checkCancellation()
      var document = try DocumentCreation.blank(width:layout.width,height:layout.height,depth:settings.depth,name:String(format:"%@-%03d",name,page+1),resolution:settings.resolution)
      document.workingICC = settings.mode == .rgb ? settings.profile:nil
      var captions: [Layer] = []
      for index in page*layout.perPage..<min(sources.count,(page+1)*layout.perPage) {
        try Task.checkCancellation()
        let source = sources[index], k = index % layout.perPage
        let col = settings.placeAcrossFirst ? k % settings.columns:k / settings.rows
        let row = settings.placeAcrossFirst ? k / settings.columns:k % settings.rows
        let x0 = layout.horizontal+Double(col)*(layout.cellWidth+layout.horizontal)
        let y0 = layout.vertical+Double(row)*(layout.cellHeight+layout.vertical)
        let sw = Double(source.document.width), sh = Double(source.document.height)
        func fit(_ w: Double,_ h: Double) -> Double { min(layout.cellWidth/w,layout.imageHeight/h) }
        let rotated = settings.rotateForBestFit && fit(sh,sw) > fit(sw,sh)*1.001
        let w = rotated ? sh:sw, h = rotated ? sw:sh, scale = fit(w,h)
        let tw = max(1,Int((w*scale).rounded())), th = max(1,Int((h*scale).rounded()))
        let x = Int((x0+(layout.cellWidth-Double(tw))/2).rounded()), y = Int((y0+(layout.imageHeight-Double(th))/2).rounded())
        let pixels = try ColorManagement.converted(Renderer.composite(source.document),from:source.document,to:document)
        let turn = rotated ? CanvasTurn.clockwise.transform(width:pixels.width,height:pixels.height):.identity
        let transform = Transform2D.scale(Double(tw)/w,Double(th)/h)*turn
        let thumb = try RasterGeometry.render(pixels,transform:transform,bounds:.init(x:0,y:0,width:tw,height:th),method:.bicubic,clampEdges:true)
        var layer = Layer(name:source.name,content:.raster(thumb));layer.x = x;layer.y = y;document.layers.append(layer)
        placements.append(.init(source:index,page:page,column:col,row:row,x:x,y:y,width:tw,height:th,rotated:rotated))
        if settings.caption {
          var text = TextContent(text:source.name,fontName:settings.font,size:settings.fontSize,color:.black)
          var type = TextTypography();type.kind = .paragraph;type.defaultStyle.font = settings.font;type.defaultStyle.size = settings.fontSize;type.defaultStyle.color = .black;type.defaultParagraph.alignment = .center
          text.typography = type;text.layoutWidth = max(1,Int(layout.cellWidth.rounded(.down)));text.layoutHeight = max(1,Int(layout.captionHeight.rounded(.up)))
          var caption = Layer(name:source.name+" caption",content:.text(text));caption.x = Int(x0.rounded());caption.y = Int((y0+layout.imageHeight).rounded());captions.append(caption)
        }
      }
      if settings.flatten {
        document.layers += captions;document.activeLayerID = document.layers.last?.id
        let pixels = try Renderer.composite(document)
        document.layers = [Layer(name:"Background",content:.raster(pixels))];document.activeLayerID = document.layers[0].id
      }
      if settings.mode != .rgb { document = try document.convertingMode(.init(mode:settings.mode,depth:settings.depth,profile:settings.profile)) }
      if !settings.flatten { document.layers += captions }
      document.activeLayerID = document.layers.last?.id
      try document.validate();outputBytes += document.estimatedBytes
      guard outputBytes <= maximumBytes else { throw CraftError.unsupported("The prepared contact sheets exceed512MiB. Use fewer sources or flatten the pages.") }
      output.append(document)
    }
    try Task.checkCancellation();return .init(documents:output,placements:placements)
  }
}
