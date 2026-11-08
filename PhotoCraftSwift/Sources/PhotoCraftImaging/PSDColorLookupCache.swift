import Foundation
import PhotoCraftCore

/// ICC.1:2022 §§10.16/10.16.2.4. Accept a redundant single float CLUT only
/// when every sample is the embedded file's table. Never execute an ICC profile.
enum PSDColorLookupCache {
  /// ICC.1 float device link for the embedded uniform table. No vendor cache or
  /// copyrighted profile metadata is used to construct a new lookup record.
  static func encode(_ table:ColorLUT)throws->Data {
    try table.validate()
    guard table.domainMin == [0,0,0],table.domainMax == [1,1,1],table.curve==nil,table.inputGrid==nil else {
      throw CraftError.unsupported("Editable Photoshop lookup export requires a uniform unit-domain table without a shaper.")
    }
    guard table.size*table.size*table.size*12+4096<=PSDDescriptor.maxBytes else {
      throw CraftError.unsupported("This editable Photoshop lookup cache exceeds the descriptor budget. Keep the Photato original.")
    }
    func u16(_ value:Int)->Data {Data([UInt8((value>>8)&255),UInt8(value&255)])}
    func u32(_ value:Int)->Data {Data([UInt8((value>>24)&255),UInt8((value>>16)&255),UInt8((value>>8)&255),UInt8(value&255)])}
    func text(_ value:String)->Data {Data(value.utf8)}
    func mluc(_ value:String)->Data {
      let bytes=value.data(using:.utf16BigEndian)!
      return text("mluc")+Data(count:4)+u32(1)+u32(12)+text("enUS")+u32(bytes.count)+u32(28)+bytes
    }
    var clut=text("clut")+Data(count:4)+u16(3)+u16(3)+Data(repeating:UInt8(table.size),count:3)+Data(count:13)
    for red in 0..<table.size {try Task.checkCancellation();for green in 0..<table.size {for blue in 0..<table.size {
      let offset=((blue*table.size+green)*table.size+red)*3
      for channel in 0..<3{clut.append(u32(Int(table.values[offset+channel].bitPattern)))}
    }}}
    let process=text("mpet")+Data(count:4)+u16(3)+u16(3)+u32(1)+u32(24)+u32(clut.count)+clut
    let tags:[(String,Data)]=[("desc",mluc(table.title)),("cprt",mluc("")),("pseq",text("pseq")+Data(count:4)+u32(0)),("D2B0",process)]
    var profile=Data(count:128)
    func put(_ offset:Int,_ bytes:Data){profile.replaceSubrange(offset..<offset+bytes.count,with:bytes)}
    put(8,u32(0x04400000));put(12,text("link"));put(16,text("RGB "));put(20,text("RGB "))
    // Fixed valid metadata date makes repeated saves deterministic.
    put(24,u16(2000)+u16(1)+u16(1)+u16(0)+u16(0)+u16(0))
    put(36,text("acsp"));put(40,text("APPL"));put(68,u32(0xf6d6)+u32(0x10000)+u32(0xd32d));put(80,text("Ptto"))
    profile.append(u32(tags.count));var offset=132+tags.count*12,body=Data()
    for (key,data) in tags {
      profile.append(text(key)+u32(offset)+u32(data.count));body.append(data)
      let padding=(4-data.count%4)%4;body.append(Data(count:padding));offset+=data.count+padding
    }
    profile.append(body);put(0,u32(profile.count));try validate(profile,table:table);return profile
  }
  static func validate(_ data:Data,table:ColorLUT)throws {
    guard data.count>=132,data.count<=16*1024*1024 else{throw CraftError.invalid("Invalid lookup cache size.")}
    guard table.domainMin == [0,0,0],table.domainMax == [1,1,1],table.curve==nil,table.inputGrid==nil else {
      throw CraftError.unsupported("This lookup cache contains unqualified input-domain or shaper semantics.")
    }
    var header=PSDReader(data:data)
    guard try header.u32()==data.count else{throw CraftError.invalid("Invalid lookup cache length.")}
    _=try header.bytes(4)
    guard try header.bytes(1)==Data([4]) else{throw CraftError.unsupported("Lookup cache requires ICC v4.")}
    _=try header.bytes(3)
    guard try header.bytes(4)==Data("link".utf8),try header.bytes(4)==Data("RGB ".utf8),try header.bytes(4)==Data("RGB ".utf8) else {
      throw CraftError.unsupported("Lookup cache requires an RGB device link.")
    }
    _=try header.bytes(12)
    guard try header.bytes(4)==Data("acsp".utf8) else{throw CraftError.invalid("Invalid lookup cache signature.")}
    var tags=PSDReader(data:Data(data.dropFirst(128)));let count=try tags.u32()
    guard count>0,count<=128,132+count*12<=data.count else{throw CraftError.invalid("Invalid lookup cache tag table.")}
    let otherTransforms:Set<String>=["A2B0","A2B1","A2B2","B2A0","B2A1","B2A2","B2D0","B2D1","B2D2","D2B1","D2B2","D2B3"]
    var seen=Set<String>(),transform:Data?
    for _ in 0..<count {
      let key=String(decoding:try tags.bytes(4),as:UTF8.self),offset=try tags.u32(),size=try tags.u32()
      guard seen.insert(key).inserted,offset>=132+count*12,offset%4==0,size>=8,offset<=data.count,size<=data.count-offset else{throw CraftError.invalid("Invalid lookup cache tag extent.")}
      guard !otherTransforms.contains(key) else{throw CraftError.unsupported("Additional lookup cache transforms are not represented by the embedded table.")}
      if key=="D2B0"{transform=Data(data[offset..<offset+size])}
    }
    guard let transform else{throw CraftError.unsupported("Lookup cache has no supported float transform.")}
    var process=PSDReader(data:transform)
    guard try process.bytes(4)==Data("mpet".utf8),try process.u32()==0,try process.u16()==3,try process.u16()==3,try process.u32()==1 else {
      throw CraftError.unsupported("Lookup cache requires one RGB float CLUT.")
    }
    let offset=try process.u32(),size=try process.u32()
    guard offset>=24,offset%4==0,offset<=transform.count,size==28+table.size*table.size*table.size*12,size==transform.count-offset else {
      throw CraftError.invalid("Invalid lookup cache element extent.")
    }
    var element=PSDReader(data:Data(transform.dropFirst(offset)))
    guard try element.bytes(4)==Data("clut".utf8),try element.u32()==0,try element.u16()==3,try element.u16()==3 else {
      throw CraftError.unsupported("Lookup cache contains unsupported processing elements.")
    }
    let grid=try element.bytes(16)
    guard Array(grid.prefix(3))==[UInt8(table.size),UInt8(table.size),UInt8(table.size)],grid.dropFirst(3).allSatisfy({$0==0}) else {
      throw CraftError.invalid("Lookup cache grid differs from its embedded table.")
    }
    // ICC first input varies slowest; Cube's red input varies fastest.
    for red in 0..<table.size {for green in 0..<table.size {for blue in 0..<table.size {
      try Task.checkCancellation()
      for channel in 0..<3 {
        let bits=UInt32(try element.u32()),expected=table.values[((blue*table.size+green)*table.size+red)*3+channel]
        guard Float(bitPattern:bits).isFinite,bits==expected.bitPattern else{throw CraftError.unsupported("Lookup cache samples differ from the embedded table.")}
      }
    }}}
    guard element.remaining==0 else{throw CraftError.invalid("Trailing lookup cache samples.")}
  }
}
