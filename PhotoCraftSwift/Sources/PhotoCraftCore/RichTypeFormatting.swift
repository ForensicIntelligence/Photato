import Foundation

/// Resolved character attributes omitted by the original native type model.
/// Nil on TypeStyle preserves the existing native document and rendering contract.
public struct TypeCharacterFormatting:Codable,Equatable,Sendable {
  public enum Kerning:String,Codable,CaseIterable,Sendable {case metrics,optical,off}
  public enum Caps:String,Codable,CaseIterable,Sendable {case normal,smallCaps,allCaps}
  public var weight:Int=400
  public var italic=false,fauxBold=false,fauxItalic=false
  public var kerning:Kerning = .metrics
  public var manualKerning:Double=0
  public var caps:Caps = .normal
  public var ligatures=true,discretionaryLigatures=false
  public var sourceFace:String?
  public var sourcePostScriptName:String?
  /// The source face is preferred only while this requested font is unchanged.
  public var sourceFontReference:String?
  public var sourceWeight:Int?
  public var sourceItalic:Bool?
  public var linearColor:Bool?
  public var styleSheet:UInt32?
  public init(){}
  public func validate()throws {
    guard (100...900).contains(weight),manualKerning.isFinite,abs(manualKerning)<=10000 else{throw CraftError.invalid("Invalid character weight or kerning.")}
    for name in [sourceFace,sourcePostScriptName,sourceFontReference].compactMap({$0}) {
      guard name.utf8.count<=256,!name.contains("\0") else{throw CraftError.invalid("Invalid source font identity.")}
    }
    guard sourceWeight.map({(100...900).contains($0)}) != false else{throw CraftError.invalid("Invalid source font weight.")}
    guard styleSheet != 0 else{throw CraftError.invalid("Character style zero is reserved for None.")}
  }
  public var requiresNativeLayoutExtension:Bool {
    weight != 400 || italic || fauxBold || fauxItalic || kerning != .metrics || manualKerning != 0 || caps != .normal || !ligatures || discretionaryLigatures
  }
}

public struct TypeParagraphFormatting:Codable,Equatable,Sendable {
  public enum LastLine:String,Codable,CaseIterable,Sendable {case left,center,right,justified}
  public var lastLine:LastLine = .left
  public var autoLeading:Double=1.2
  public var styleSheet:UInt32?
  public init(){}
  public func validate()throws {
    guard autoLeading.isFinite,(0.1...10).contains(autoLeading) else{throw CraftError.invalid("Invalid paragraph auto leading.")}
  }
}

/// Fractional text-space frame retained independently from integer raster bounds.
public struct TypeSourceFrame:Codable,Equatable,Sendable {
  public enum Kind:String,Codable,Sendable {case point,box}
  public var kind:Kind = .point
  public var x:Double=0,y:Double=0,width:Double=1,height:Double=1
  public init(){}
  public func validate()throws {
    guard [x,y,width,height].allSatisfy({$0.isFinite}),abs(x)<=1_000_000,abs(y)<=1_000_000,width>0,height>0,width<=32768,height<=32768,width*height<=16_777_216 else{throw CraftError.invalid("Invalid source text frame.")}
  }
}

public enum TypeAntialias:String,Codable,CaseIterable,Sendable {case none,sharp,crisp,strong,smooth,windows,windowsLCD}

/// Translate source byte runs before merging the independent character and
/// paragraph ranges. This ports PhotoCraft normalize_runs (MIT OR Apache-2.0),
/// not a grapheme-count conversion; combining scalars keep their own boundaries.
public enum TypeSourceRuns {
  public struct Span<Value:Equatable & Sendable>:Equatable,Sendable {
    public var utf8Length:Int
    public var value:Value
    public init(_ length:Int,_ value:Value){utf8Length=length;self.value=value}
  }
  public struct Range<Value:Equatable & Sendable>:Equatable,Sendable {
    public var utf16Start:Int,utf16Length:Int
    public var value:Value
    public init(start:Int,length:Int,value:Value){utf16Start=start;utf16Length=length;self.value=value}
  }
  public static func normalize<Value:Equatable & Sendable>(_ runs:[Span<Value>],text:String,default value:Value)throws->[Range<Value>] {
    guard text.utf16.count<=100_000,runs.count<=4096,runs.allSatisfy({$0.utf8Length>=0}) else{throw CraftError.invalid("Invalid or oversized source text runs.")}
    let total=text.utf8.count
    if total==0{return [.init(start:0,length:0,value:runs.first?.value ?? value)]}
    var offsets:[Int:Int]=[0:0],bytes=0,units=0
    for scalar in text.unicodeScalars {let string=String(scalar);bytes+=string.utf8.count;units+=string.utf16.count;offsets[bytes]=units}
    var position=0,result:[Range<Value>]=[]
    for run in runs {
      guard position<total else{break}
      let addition=position.addingReportingOverflow(run.utf8Length)
      var end=addition.overflow ? total:min(total,addition.partialValue)
      if offsets[end]==nil {
        // At most three continuation bytes in a Unicode scalar.
        while end<total,offsets[end]==nil{end+=1}
      }
      if end>position {let start=offsets[position]!,stop=offsets[end]!;result.append(.init(start:start,length:stop-start,value:run.value));position=end}
    }
    if position<total {
      let remainder=units-offsets[position]!
      if !result.isEmpty{result[result.count-1].utf16Length+=remainder}
      else{result=[.init(start:0,length:units,value:value)]}
    }
    return result
  }
  public static func merge(characters:[Range<TypeStyle>],paragraphs:[Range<TypeParagraph>],text:String)throws->[TypeRun] {
    let count=text.utf16.count
    if count==0{return []}
    func validate<V>(_ ranges:[Range<V>])throws where V:Equatable & Sendable {
      var at=0
      for range in ranges {
        guard range.utf16Start==at,range.utf16Length>0,range.utf16Length<=count-at,TextTypography.isBoundary(at+range.utf16Length,in:text) else{throw CraftError.invalid("Source text runs do not cover Unicode scalar boundaries.")}
        at+=range.utf16Length
      }
      guard at==count else{throw CraftError.invalid("Incomplete source text runs.")}
    }
    try validate(characters);try validate(paragraphs)
    var c=0,p=0,at=0,result:[TypeRun]=[]
    while at<count {
      let character=characters[c],paragraph=paragraphs[p],end=min(character.utf16Start+character.utf16Length,paragraph.utf16Start+paragraph.utf16Length)
      if let last=result.last,last.style==character.value,last.paragraph==paragraph.value{result[result.count-1].length+=end-at}
      else{result.append(.init(length:end-at,style:character.value,paragraph:paragraph.value))}
      at=end;if at==character.utf16Start+character.utf16Length{c+=1};if at==paragraph.utf16Start+paragraph.utf16Length{p+=1}
      guard result.count<=4096 else{throw CraftError.invalid("Merged source text has too many style boundaries.")}
    }
    return result
  }
}
