import Foundation
import PhotoCraftCore

/// Adobe's public artb/artd/abdd version16 descriptors. Semantics and geometry
/// are checked against owned Photoshop2026 files; opaque fields are not executed.
enum PSDArtboards {
  static let keys = ["artb","artd","abdd"]
  struct LayerData {
    var descriptor:PSDDescriptor
    var bounds:IntRect
    var background:Pixel
    var preset:String
    var guides:[Int]
  }
  struct GlobalData { var descriptor:PSDDescriptor;var count:Int;var origin:ArtboardOrigin }
  struct Output {
    var layers:[UUID:(String,Data)] = [:]
    var global:(String,Data)?
    var guideDocument:CraftDocument
  }
  struct GuideKey:Hashable { var owner:UUID?;var id:UUID }
  struct GuideEntry { var key:GuideKey;var value:DocumentGuide }
  static func fail(_ message:String)->CraftError { .unsupported("Photoshop artboards: "+message) }
  static func schema(_ d:PSDDescriptor,_ cls:String,_ fields:Set<String>) throws {
    guard d.classID.text==cls,d.items.count==fields.count,Set(d.items.map{$0.key.text})==fields else { throw fail("Unrepresented descriptor fields or class.") }
  }
  static func integer(_ value:PSDValue?,range:ClosedRange<Int> = -1_000_000...1_000_000) throws -> Int {
    guard let number=value?.number,number.isFinite,number.rounded()==number,
      number>=Double(range.lowerBound),number<=Double(range.upperBound) else { throw fail("Whole-pixel coordinates within native bounds are required.") }
    return Int(number)
  }
  static func object(_ value:PSDValue?) throws -> PSDDescriptor {
    guard case .object(let d)=value else { throw fail("Expected a descriptor object.") };return d
  }
  static func text(_ value:PSDValue?) throws -> String {
    guard case .text(var units)=value else { throw fail("Expected a preset name.") }
    if units.last==0 { units.removeLast() }
    guard !units.contains(0) else { throw fail("Embedded nulls in preset names are unsupported.") }
    return String(decoding:units,as:UTF16.self)
  }
  static func color(_ value:PSDValue?) throws -> Pixel {
    let d=try object(value)
    return try PSDSolidColor.read(PSDDescriptor("null",items:[.init("Clr ",.object(d))]).encoded())
  }
  static func layer(_ data:Data,depth:PixelDepth) throws -> LayerData {
    let d=try PSDDescriptor.read(data,padding:true)
    try schema(d,"artboard",["artboardRect","guideIndeces","artboardPresetName","Clr ","artboardBackgroundType"])
    let rect=try object(d["artboardRect"]);try schema(rect,"classFloatRect",["Top ","Left","Btom","Rght"])
    let x=try integer(rect["Left"]),y=try integer(rect["Top "]),right=try integer(rect["Rght"]),bottom=try integer(rect["Btom"])
    guard right>x,bottom>y else { throw fail("Artboard dimensions must be positive.") }
    let bounds=IntRect(x:x,y:y,width:right-x,height:bottom-y)
    let background:Pixel,custom=try color(d["Clr "])
    switch try integer(d["artboardBackgroundType"],range:1...4) {
    case 1:background = .white
    case 2:background = .black
    case 3:background = .clear
    default:background = ArtboardColors.fromDescriptor(custom,depth:depth)
    }
    guard case .list(let raw)=d["guideIndeces"],raw.count<=512 else { throw fail("Invalid artboard guide indices.") }
    let guides=try raw.map{try integer($0,range:0...(DocumentGuide.maximumCount-1))}
    guard Set(guides).count==guides.count else { throw fail("Duplicate artboard guide indices.") }
    let preset=try text(d["artboardPresetName"])
    try Artboard(width:bounds.width,height:bounds.height,background:background,preset:preset).validate()
    return .init(descriptor:d,bounds:bounds,background:background,preset:preset,guides:guides)
  }
  static func point(_ value:PSDValue?) throws -> ArtboardOrigin {
    let d=try object(value);try schema(d,"Pnt ",["Hrzn","Vrtc"])
    return try .init(x:integer(d["Hrzn"]),y:integer(d["Vrtc"]))
  }
  static func global(_ data:Data) throws -> GlobalData {
    let d=try PSDDescriptor.read(data,padding:true)
    try schema(d,"null",["Cnt ","autoExpandOffset","origin","autoExpandEnabled","autoNestEnabled","autoPositionEnabled","shrinkwrapOnSaveEnabled","docDefaultNewArtboardBackgroundColor","docDefaultNewArtboardBackgroundType"])
    for key in ["autoExpandEnabled","autoNestEnabled","autoPositionEnabled","shrinkwrapOnSaveEnabled"] {
      guard case .boolean=d[key] else { throw fail("Invalid artboard document switch.") }
    }
    _ = try point(d["autoExpandOffset"]);_ = try color(d["docDefaultNewArtboardBackgroundColor"])
    _ = try integer(d["docDefaultNewArtboardBackgroundType"],range:1...4)
    return try .init(descriptor:d,count:integer(d["Cnt "],range:0...LayerLimits.maximumLayers),origin:point(d["origin"]))
  }
  static func sourceLayer(_ layer:Layer,depth:PixelDepth) throws -> (String,LayerData)? {
    let found=keys.compactMap{ key in layer.sourceTags?[key].map{(key,$0)} }
    guard found.count<=1 else { throw fail("Conflicting layer artboard blocks.") }
    return try found.first.map{($0.0,try self.layer($0.1,depth:depth))}
  }
  static func sourceGlobal(_ document:CraftDocument) throws -> (String,GlobalData)? {
    let found=keys.compactMap{ key in document.sourceMetadata?["psdGlobal_"+key].map{(key,$0)} }
    guard found.count<=1 else { throw fail("Conflicting document artboard blocks.") }
    return try found.first.map{($0.0,try global($0.1))}
  }
  static func guideID(_ document:CraftDocument,owner:UUID?,index:Int)->UUID {
    PcraftImport.identity(Data(document.id.uuidString.utf8),role:"psd-artboard-guide-"+(owner?.uuidString ?? "canvas"),id:UInt64(index))
  }
  static func read(into document:inout CraftDocument) throws {
    let global=try sourceGlobal(document),source=document.guides ?? []
    var consumed=Set<Int>(),count=0
    for i in document.layers.indices {
      let layer=document.layers[i]
      guard let (_,data)=try sourceLayer(layer,depth:document.depth) else { continue }
      guard document.colorMode == .rgb,layer.parentID==nil,!layer.isClipped,var group=layer.group else { throw fail("Editable RGB artboards must be unclipped top-level groups.") }
      var board=Artboard(width:data.bounds.width,height:data.bounds.height,background:data.background,preset:data.preset)
      for index in data.guides {
        guard source.indices.contains(index),consumed.insert(index).inserted else { throw fail("Missing or shared artboard guide context.") }
        let line=source[index],vertical=line.axis == .vertical
        var guide=ArtboardGuide(axis:vertical ? .vertical:.horizontal,position:line.position-Double(vertical ? data.bounds.x:data.bounds.y))
        guide.id=guideID(document,owner:layer.id,index:index);board.guides.append(guide)
      }
      try board.validate();group.artboard=board;document.layers[i].content = .group(group)
      document.layers[i].x=data.bounds.x;document.layers[i].y=data.bounds.y;count+=1
    }
    if let (_,data)=global { guard data.count==count else { throw fail("Document artboard count disagrees with its groups.") } }
    guard count>0 else { return }
    let origin=global?.1.origin ?? .init()
    document.artboardOrigin = .init(x:-origin.x,y:-origin.y)
    document.guides=source.enumerated().compactMap { index,value in
      guard !consumed.contains(index) else { return nil };var line=value;line.id=guideID(document,owner:nil,index:index);return line
    }
  }
  static func set(_ d:inout PSDDescriptor,_ key:String,_ value:PSDValue) {
    if let i=d.items.firstIndex(where:{$0.key.text==key}) { d.items[i].value=value }
    else { d.items.append(.init(key,value)) }
  }
  static func number(_ d:inout PSDDescriptor,_ key:String,_ value:Double) {
    if d[key]?.number != value { set(&d,key,.number(value)) }
  }
  static func make(_ cls:String,_ items:[PSDDescriptor.Item])->PSDDescriptor {
    var d=PSDDescriptor(cls,items:items);d.name=[0];return d
  }
  static func point(_ x:Int,_ y:Int)->PSDValue {
    .object(make("Pnt ",[.init("Hrzn",.number(Double(x))),.init("Vrtc",.number(Double(y)))]))
  }
  static func rgb(_ p:Pixel)->PSDValue {
    .object(make("RGBC",[.init("Rd  ",.number(Double(p.r)*255)),.init("Grn ",.number(Double(p.g)*255)),.init("Bl  ",.number(Double(p.b)*255))]))
  }
  /// Retain the admitted source bytes, including Photoshop's internal padding,
  /// whenever the editable descriptor has not changed.
  static func encoded(_ descriptor:PSDDescriptor,original:Data?,alignment:Int) throws -> Data {
    if let original,try PSDDescriptor.read(original,padding:true)==descriptor { return original }
    var result=try descriptor.encoded()
    result.append(contentsOf:repeatElement(UInt8(0),count:(alignment-result.count%alignment)%alignment))
    return result
  }
  static func prepare(_ document:CraftDocument) throws -> Output {
    var output=Output(guideDocument:document)
    guard document.hasArtboards else { return output }
    if let issue=PSDArtboardInterchange.photoshopPersistenceIssue(document) { throw CraftError.unsupported(issue) }
    guard document.colorMode == .rgb else { throw fail("Non-RGB editable artboard interchange remains unqualified.") }
    let oldGlobal=try sourceGlobal(document)
    let resources=try PSDImageResources.blocks(document.sourceMetadata?["psdResources"] ?? Data()).filter{$0.id==1032}
    guard resources.count<=1 else { throw fail("Duplicate guide resources.") }
    let oldCount=try resources.first.map{try PSDGuides.decode($0.data).count} ?? 0
    var preferred:[GuideKey:Int]=[:]
    for index in 0..<oldCount { preferred[.init(owner:nil,id:guideID(document,owner:nil,index:index))]=index }
    var entries:[GuideEntry]=[]
    for line in document.guides ?? [] { entries.append(.init(key:.init(owner:nil,id:line.id),value:line)) }
    for layer in document.artboards {
      if let (_,old)=try sourceLayer(layer,depth:document.depth) {
        for index in old.guides { preferred[.init(owner:layer.id,id:guideID(document,owner:layer.id,index:index))]=index }
      }
      for guide in layer.artboard!.guides {
        let vertical=guide.axis == .vertical
        let line=DocumentGuide(axis:vertical ? .vertical:.horizontal,position:guide.position+Double(vertical ? layer.x:layer.y))
        entries.append(.init(key:.init(owner:layer.id,id:guide.id),value:line))
      }
    }
    guard entries.count<=DocumentGuide.maximumCount,Set(entries.map(\.key)).count==entries.count else { throw fail("Too many or duplicate guides.") }
    var slots:[Int:GuideEntry]=[:],tail:[GuideEntry]=[]
    for entry in entries {
      if let index=preferred[entry.key],slots[index]==nil { slots[index]=entry }
      else { tail.append(entry) }
    }
    let ordered=slots.keys.sorted().compactMap{slots[$0]}+tail
    let positions=Dictionary(uniqueKeysWithValues:ordered.enumerated().map{($0.element.key,$0.offset)})
    // Old relative identities are not used as document-guide identities: guide
    // ownership is explicit, including duplicate boards and extracted documents.
    output.guideDocument.guides=ordered.isEmpty && document.guides==nil && resources.isEmpty ? nil:ordered.map(\.value)
    for layer in document.artboards {
      try Task.checkCancellation();let board=layer.artboard!,bounds=layer.artboardBounds!
      guard board.background.a==0 || board.background.a==1,
        [board.background.r,board.background.g,board.background.b].allSatisfy({(0...1).contains($0)}) else { throw fail("Partial-alpha or extended-range backgrounds require Photato format.") }
      let original=try sourceLayer(layer,depth:document.depth)
      var d=original?.1.descriptor ?? make("artboard",[])
      var rect=try d["artboardRect"].map{try object($0)} ?? make("classFloatRect",[])
      for (key,value) in [("Top ",bounds.y),("Left",bounds.x),("Btom",bounds.y+bounds.height),("Rght",bounds.x+bounds.width)] { number(&rect,key,Double(value)) }
      set(&d,"artboardRect",.object(rect))
      let indices=try board.guides.map { guide -> PSDValue in
        guard let index=positions[.init(owner:layer.id,id:guide.id)] else { throw fail("Missing exported artboard guide.") };return .integer(Int32(index))
      }
      set(&d,"guideIndeces",.list(indices))
      if (try? text(d["artboardPresetName"])) != board.preset { set(&d,"artboardPresetName",.text(Array(board.preset.utf16)+[0])) }
      if original?.1.background != board.background {
        let type:Int32=board.background.a==0 ? 3:board.background == .white ? 1:board.background == .black ? 2:4
        set(&d,"artboardBackgroundType",.integer(type));set(&d,"Clr ",rgb(ArtboardColors.working(board.background,depth:document.depth)))
      }
      if d["Clr "]==nil { set(&d,"Clr ",rgb(.white)) }
      let key=original?.0 ?? "artb"
      output.layers[layer.id]=(key,try encoded(d,original:layer.sourceTags?[key],alignment:4))
    }
    var global=oldGlobal?.1.descriptor ?? make("null",[
      .init("Cnt ",.integer(0)),.init("autoExpandOffset",point(0,0)),.init("origin",point(0,0)),
      .init("autoExpandEnabled",.boolean(true)),.init("autoNestEnabled",.boolean(true)),
      .init("autoPositionEnabled",.boolean(true)),.init("shrinkwrapOnSaveEnabled",.boolean(true)),
      .init("docDefaultNewArtboardBackgroundColor",rgb(.white)),.init("docDefaultNewArtboardBackgroundType",.integer(1))])
    set(&global,"Cnt ",.integer(Int32(document.artboards.count)))
    let origin=document.artboardOrigin ?? .init(),target=ArtboardOrigin(x:-origin.x,y:-origin.y)
    if oldGlobal?.1.origin != target { set(&global,"origin",point(target.x,target.y));set(&global,"autoExpandOffset",point(target.x,target.y)) }
    let key=oldGlobal?.0 ?? "artd"
    output.global=(key,try encoded(global,original:document.sourceMetadata?["psdGlobal_"+key],alignment:1));return output
  }
}

public enum PSDArtboardInterchange {
  /// Cheap shared policy check; the serializer still verifies descriptors and
  /// guide ownership before producing a native file or API response.
  public static func photoshopPersistenceIssue(_ document:CraftDocument)->String? {
    guard document.hasArtboards else { return nil }
    guard document.colorMode == .rgb else { return "Editable non-RGB artboard interchange remains unqualified. Save as Photato." }
    for layer in document.artboards {
      let board=layer.artboard!
      if !(board.background.a==0 || board.background.a==1) || ![board.background.r,board.background.g,board.background.b].allSatisfy({(0...1).contains($0)}) {
        return "Partial-alpha or extended-range artboard backgrounds require Photato format."
      }
      if board.guides.contains(where:{($0.position*32).rounded() != $0.position*32}) {
        return "PSD/PSB artboard guides require positions at 1/32 pixel precision. Save as Photato to retain finer positions."
      }
    }
    return nil
  }
}
