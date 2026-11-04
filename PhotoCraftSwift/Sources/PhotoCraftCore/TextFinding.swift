import Foundation

public struct TextSearchSettings: Codable, Equatable, Sendable {
  public var find: String
  public var caseSensitive: Bool
  public var wholeWord: Bool
  public init(find: String, caseSensitive: Bool = false, wholeWord: Bool = false) {
    self.find = find; self.caseSensitive = caseSensitive; self.wholeWord = wholeWord
  }
  public func validate() throws {
    guard !find.isEmpty, find.utf16.count <= 100_000 else { throw CraftError.invalid("Enter text to find (maximum 100,000 UTF-16 units).") }
  }
  public func ranges(in text: String, start: Int = 0) throws -> [NSRange] {
    try validate()
    guard (0...text.utf16.count).contains(start), TextTypography.isBoundary(start, in:text) else { throw CraftError.invalid("The search position splits text or is outside its bounds.") }
    let literal = NSRegularExpression.escapedPattern(for:find)
    let pattern = wholeWord ? "\\b(?:\(literal))\\b" : literal
    var options: NSRegularExpression.Options = [.useUnicodeWordBoundaries]
    if !caseSensitive { options.insert(.caseInsensitive) }
    let expression = try NSRegularExpression(pattern:pattern,options:options)
    return expression.matches(in:text,options:[.withTransparentBounds],range:NSRange(location:start,length:text.utf16.count-start)).map(\.range)
  }
}
public struct TextSearchMatch: Codable, Equatable, Sendable {
  public let layerID: UUID
  public let layerName: String
  public let location: Int
  public let length: Int
}
public struct TextSearchResult: Codable, Equatable, Sendable {
  public let matches: [TextSearchMatch]
  public let total: Int
  public let offset: Int
  public let hasMore: Bool
}
public enum NativeTextSearch {
  public static func layers(in document:CraftDocument,layerID:UUID? = nil) throws -> [Layer] {
    if let layerID, !document.layers.contains(where:{$0.id==layerID}) { throw CraftError.invalid("The text search layer no longer exists.") }
    let hierarchy=LayerHierarchyIndex(document)
    return document.layers.reversed().filter { layer in
      guard layerID == nil || layer.id == layerID, case .text = layer.content,
        layer.visible, !hierarchy.effectiveProtection(layer.id).locksImage else { return false }
      // Eye visibility is independent of opacity and clipping/composite appearance.
      return !hierarchy.ancestors(of:layer.id).contains{!$0.visible}
    }
  }
  public static func scan(_ document:CraftDocument,settings:TextSearchSettings,layerID:UUID? = nil,
    start:Int = 0,offset:Int = 0,limit:Int = 100) throws -> TextSearchResult {
    try settings.validate()
    guard (0...100_000).contains(start),start==0 || layerID != nil,
      (0...2_000_000_000).contains(offset),(1...10_000).contains(limit) else { throw CraftError.invalid("Invalid text search position or page.") }
    var result:[TextSearchMatch]=[],count=0
    for layer in try layers(in:document,layerID:layerID) {
      try Task.checkCancellation()
      guard case .text(let text)=layer.content else {continue}
      for range in try settings.ranges(in:text.text,start:start) {
        if count>=offset,result.count<limit {result.append(.init(layerID:layer.id,layerName:layer.name,location:range.location,length:range.length))}
        count+=1
      }
    }
    return .init(matches:result,total:count,offset:offset,hasMore:count>offset+result.count)
  }
  /// Preserve untouched attributes; inserted text inherits the first replaced scalar.
  public static func replacing(_ source:TextContent,ranges:[NSRange],with replacement:String) throws -> TextContent {
    try source.validate();let old=Array(source.text.utf16),insert=Array(replacement.utf16)
    var end=0,removed=0
    for range in ranges {
      guard range.location>=end,range.length>0,range.location<=old.count,range.length<=old.count-range.location,
        TextTypography.isBoundary(range.location,in:source.text),TextTypography.isBoundary(range.location+range.length,in:source.text) else {throw CraftError.invalid("Invalid or overlapping text replacement ranges.")}
      end=range.location+range.length;removed+=range.length
    }
    let addition=insert.count.multipliedReportingOverflow(by:ranges.count)
    guard !addition.overflow,addition.partialValue<=100_000-(old.count-removed) else {throw CraftError.invalid("The replacement exceeds the native text limit.")}
    if ranges.isEmpty{return source}
    struct Span {var start:Int,end:Int;var style:TypeStyle;var paragraph:TypeParagraph}
    let type=source.typography ?? TextTypography();var spans:[Span]=[],position=0
    for run in type.runs {spans.append(.init(start:position,end:position+run.length,style:run.style,paragraph:run.paragraph));position+=run.length}
    if spans.isEmpty{spans=[.init(start:0,end:old.count,style:type.defaultStyle,paragraph:type.defaultParagraph)]}
    func spanIndex(_ at:Int)->Int {
      var low=0,high=spans.count-1
      while low<high {let mid=(low+high)/2;if spans[mid].end<=at{low=mid+1}else{high=mid}}
      return low
    }
    var units:[UInt16]=[],runs:[TypeRun]=[]
    func append(_ part:ArraySlice<UInt16>,style original:TypeStyle,paragraph:TypeParagraph) {
      guard !part.isEmpty else{return};var style=original
      if let glyph=style.glyphOverride,String(decoding:part,as:UTF16.self) != glyph.baseString{style.glyphOverride=nil}
      units.append(contentsOf:part)
      if let last=runs.last,last.style==style,last.paragraph==paragraph {runs[runs.count-1].length+=part.count}
      else {runs.append(.init(length:part.count,style:style,paragraph:paragraph))}
    }
    func appendOriginal(_ start:Int,_ stop:Int) {
      guard start<stop else{return};var at=start,index=spanIndex(start)
      while at<stop {let span=spans[index],to=min(stop,span.end);append(old[at..<to],style:span.style,paragraph:span.paragraph);at=to;index+=1}
    }
    position=0
    for range in ranges {
      try Task.checkCancellation();appendOriginal(position,range.location)
      var style=spans[spanIndex(range.location)].style;style.glyphOverride=nil
      append(insert[...],style:style,paragraph:spans[spanIndex(range.location)].paragraph)
      position=range.location+range.length
    }
    appendOriginal(position,old.count)
    var result=source;result.text=String(decoding:units,as:UTF16.self)
    if result.text==source.text{return source}
    if var type=result.typography {type.defaultStyle.glyphOverride=nil;type.runs = runs.count==1 && runs[0].style==type.defaultStyle && runs[0].paragraph==type.defaultParagraph ? []:runs;result.typography=type}
    result.importedAppearance=nil;try result.validate();return result
  }
}
/// Portable search semantics; target resolution occurs in each playback document.
public struct RecordedTextReplacement: Codable, Equatable, Sendable {
  public var settings:TextSearchSettings
  public var replacement:String
  public var target:ActionLayerTarget?
  public var start:Int
  public var replaceAll:Bool
  public init(settings:TextSearchSettings,replacement:String,target:ActionLayerTarget? = nil,start:Int = 0,replaceAll:Bool = true) {
    self.settings=settings;self.replacement=replacement;self.target=target;self.start=start;self.replaceAll=replaceAll
  }
  public func validate()throws {
    try settings.validate()
    guard replacement.utf16.count<=100_000,(0...100_000).contains(start),start==0 || target != nil else {throw CraftError.invalid("Invalid text replacement settings.")}
    if case .named(let name,let occurrence)=target {guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.utf16.count<=65_535,(0..<LayerLimits.maximumLayers).contains(occurrence) else {throw CraftError.invalid("Invalid recorded text layer target.")}}
  }
}
