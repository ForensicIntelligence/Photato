import Foundation

/// Nonrecursive appearance identity: the cache is never the editable text model.
public struct TextAppearanceReference:Codable,Equatable,Sendable {
  public var text:String,fontName:String,size:Double,color:Pixel
  public var typography:TextTypography?
  public var width:Int?,height:Int?
  public init(_ value:TextContent){text=value.text;fontName=value.fontName;size=value.size;color=value.color;typography=value.typography;width=value.layoutWidth;height=value.layoutHeight}
  public var content:TextContent {
    var result=TextContent(text:text,fontName:fontName,size:size,color:color);result.typography=typography;result.layoutWidth=width;result.layoutHeight=height;return result
  }
  public var estimatedBytes:Int {512+text.utf8.count+fontName.utf8.count+(typography?.runs.count ?? 0)*1024}
}
public struct ImportedTextAppearance:Codable,Equatable,Sendable {
  public var reference:TextAppearanceReference
  public var pixels:Surface?
  public var x:Int,y:Int
  /// Original text-space to document-space transform (source baseline/box origin).
  public var textTransform:Transform2D
  public var typeRecord:Data?
  public init(content:TextContent,pixels:Surface?=nil,x:Int=0,y:Int=0,textTransform:Transform2D = .identity,typeRecord:Data?=nil){reference = .init(content);self.pixels=pixels;self.x=x;self.y=y;self.textTransform=textTransform;self.typeRecord=typeRecord}
  public func isPristine(_ text:TextContent)->Bool{reference==TextAppearanceReference(text)}
  public var estimatedBytes:Int {reference.estimatedBytes+(pixels?.allocatedBytes ?? 0)+(typeRecord?.count ?? 0)}
  public func validate(depth:PixelDepth?=nil)throws {
    try reference.content.validate();try textTransform.validated()
    guard abs(Double(x))<=1_000_000,abs(Double(y))<=1_000_000,(typeRecord?.count ?? 0)<=16*1024*1024 else{throw CraftError.invalid("Invalid imported type appearance.")}
    if let pixels {
      guard depth==nil || pixels.depth==depth,pixels.width<=32768,pixels.height<=32768,pixels.width*pixels.height<=16_777_216 else{throw CraftError.invalid("Imported type cache exceeds the supported depth or bounds.")}
      try pixels.validated()
    }
  }
}
extension TextContent {
  public var pristineSourceAppearance:ImportedTextAppearance? {
    guard let importedAppearance,importedAppearance.isPristine(self) else{return nil};return importedAppearance
  }
  public var requiresRichTypeArchive:Bool {
    importedAppearance != nil || typography?.requiresRichTypeArchive == true
  }
}
extension TextTypography {
  public var requiresRichTypeArchive:Bool {
    sourceFrame != nil || antialiasMode != nil || defaultStyle.characterFormatting != nil || defaultParagraph.formatting != nil || [defaultParagraph].contains(where:{$0.firstIndent<0 || $0.startIndent<0 || $0.endIndent<0}) || runs.contains(where:{$0.style.characterFormatting != nil || $0.paragraph.formatting != nil || $0.paragraph.firstIndent<0 || $0.paragraph.startIndent<0 || $0.paragraph.endIndent<0})
  }
}
extension Layer {
  public var typeContent:TextContent? {if case .text(let value)=content{return value};return nil}
  public var importedTypeAppearanceBytes:Int {typeContent?.importedAppearance?.estimatedBytes ?? 0}
  /// Preserve the logical baseline while a source cache occupies its own raster frame.
  public func sourceTypeTransform()throws->Transform2D? {
    guard let text=typeContent,let appearance=text.pristineSourceAppearance,appearance.pixels != nil else{return nil}
    return coordinateTransform * .translation(-Double(appearance.x),-Double(appearance.y)) * appearance.textTransform
  }
}
extension CraftDocument {
  var requiresRichTypeArchive:Bool {
    func content(_ value:LayerContent)->Bool {if case .text(let text)=value{return text.requiresRichTypeArchive};return false}
    func layer(_ value:Layer)->Bool {content(value.content) || value.videoKeyframes?.contains(where:{$0.content.map{content($0.content)} ?? false}) == true}
    if layers.contains(where:layer) || animation?.frames.contains(where:{$0.layers.contains(where:{$0.payload.map{content($0.content)} ?? false})}) == true{return true}
    var retained=videoTimeline?.retainedFrameSources ?? [];if let source=animation?.retainedVideoSource{retained.append(source)}
    while let source=retained.popLast(){if source.layers.contains(where:layer){return true};retained.append(contentsOf:source.timeline.retainedFrameSources ?? [])}
    return false
  }
}
