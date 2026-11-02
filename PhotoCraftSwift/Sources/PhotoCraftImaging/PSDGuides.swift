import Foundation
import PhotoCraftCore

/// Public resource1032 stores guide positions at 1/32 pixel precision. Raw
/// records are reused while unchanged, including order and grid header words.
enum PSDGuides {
  static func decode(_ data:Data)throws->[DocumentGuide] {
    var r=PSDReader(data:data)
    guard data.count>=16,try r.u32()==1 else{throw CraftError.unsupported("Unsupported Photoshop grid/guide resource.")}
    _ = try r.u32();_ = try r.u32();let count=try r.u32()
    guard count<=DocumentGuide.maximumCount,r.remaining==count*5 else{throw CraftError.invalid("Invalid Photoshop guide count or length.")}
    var lines:[DocumentGuide]=[];lines.reserveCapacity(count)
    for _ in 0..<count {
      try Task.checkCancellation();let word=UInt32(try r.u32()),axis=try r.u8()
      guard axis<=1 else{throw CraftError.invalid("Invalid Photoshop guide orientation.")}
      let line=DocumentGuide(axis:axis==0 ? .vertical:.horizontal,position:Double(Int32(bitPattern:word))/32)
      try line.validate();lines.append(line)
    };return lines
  }
  static func read(into document:inout CraftDocument)throws {
    let blocks=try PSDImageResources.blocks(document.sourceMetadata?["psdResources"] ?? Data()).filter{$0.id==1032}
    guard blocks.count<=1 else{throw CraftError.invalid("Duplicate Photoshop grid/guide resource.")}
    if let block=blocks.first {let lines=try decode(block.data);if !lines.isEmpty {document.guides=lines}}
  }
  static func applying(_ data:Data,document:CraftDocument)throws->Data {
    if let issue=DocumentGuideInput.photoshopPersistenceIssue(document){throw CraftError.unsupported(issue)}
    guard let lines=document.guides else{return data}
    try CraftDocument.validateGuides(lines)
    let blocks=try PSDImageResources.blocks(data),old=blocks.filter{$0.id==1032}
    guard old.count<=1 else{throw CraftError.invalid("Duplicate Photoshop grid/guide resource.")}
    if let block=old.first {
      let prior=try decode(block.data)
      if zip(prior,lines).allSatisfy({$0.axis==$1.axis && $0.position.bitPattern==$1.position.bitPattern}),prior.count==lines.count {return data}
    }
    var payload=PSDWriter();payload.n(1,4)
    if let block=old.first {payload.data.append(block.data.subdata(in:4..<12))}
    else {payload.n(576,4);payload.n(576,4)}
    payload.n(lines.count,4)
    for line in lines {
      try Task.checkCancellation()
      let scaled=(line.position*32).rounded()
      guard scaled>=Double(Int32.min),scaled<=Double(Int32.max) else{throw CraftError.invalid("Guide position exceeds Photoshop fixed-point storage.")}
      payload.n(Int(UInt32(bitPattern:Int32(scaled))),4);payload.n(line.axis == .vertical ? 0:1,1)
    }
    var result=Data();for block in blocks where block.id != 1032 {result.append(block.raw)}
    result.append(PSDImageResources.block(1032,data:payload.data));return result
  }
}

public enum DocumentGuideInput {
  public static func photoshopPersistenceIssue(_ document:CraftDocument)->String? {
    document.guides?.contains(where:{$0.color != Pixel(0,1,1,1)})==true
      ? "Custom guide colors require Photato format. Save a native copy, or use cyan guides for PSD/PSB." : nil
  }

  /// Earlier native previews retained opaque resource1032. Promote it at the
  /// shared file/API admission boundary before adding or clearing typed guides.
  public static func adoptingLegacyGuides(_ document:CraftDocument)throws->CraftDocument {
    guard document.guides==nil,document.sourceMetadata?["psdResources"] != nil else{return document}
    var result=document;try PSDGuides.read(into:&result)
    if var lines=result.guides {
      for i in lines.indices {lines[i].id=PcraftImport.identity(Data(document.id.uuidString.utf8),role:"legacy-psd-guide",id:UInt64(i))}
      result.guides=lines;try result.validate()
    };return result
  }
}
