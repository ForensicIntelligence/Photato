import Foundation
import PhotoCraftCore

/// Adobe resources1026/1072 follow physical layer-record order, including dividers.
enum PSDLayerLinks {
  struct Input {
    let groups:[Int],flags:[UInt8]
    let present:Bool
    private var identifiers:[Int:UUID]=[:]
    init(_ blocks:[PSDImageResources.Block],records:Int)throws {
      let a=blocks.filter{$0.id==1026},b=blocks.filter{$0.id==1072}
      present = !a.isEmpty || !b.isEmpty
      guard a.count<=1,b.count<=1 else{throw CraftError.invalid("Duplicate Photoshop layer-link resources.")}
      if let block=a.first{guard block.data.count==records*2 else{throw CraftError.invalid("Photoshop layer-link group count differs from physical layer records.")};var reader=PSDReader(data:block.data);groups=try (0..<records).map{_ in try reader.u16()}}else{groups=[Int](repeating:0,count:records)}
      if let block=b.first{guard block.data.count==records,block.data.allSatisfy({$0<=1}) else{throw CraftError.invalid("Invalid Photoshop layer-link participation flags.")};flags=Array(block.data)}else{flags=[UInt8](repeating:1,count:records)}
    }
    mutating func apply(_ index:Int,to layer:inout Layer){
      guard present else{return}
      let group=groups[index]
      if layer.sourceTags==nil{layer.sourceTags=[:]}
      layer.sourceTags?["PhFE"]=Data([flags[index]])
      if group != 0{
        if identifiers[group]==nil{identifiers[group]=UUID()}
        layer.linkID=identifiers[group];layer.linkDisabled=flags[index]==0 ? true:nil
        var w=PSDWriter();w.n(group,2);layer.sourceTags?["PhLG"]=w.data
      }
    }
  }
  static func preserved(_ block:PSDImageResources.Block?,id:Int,payload:Data)throws->Data {
    guard let block else{return PSDImageResources.block(id,data:payload)}
    if block.data==payload{return block.raw}
    var reader=PSDReader(data:block.raw);_ = try reader.bytes(6);let count=Int(try reader.u8());_ = try reader.bytes(count);if (count+1)%2 != 0{_ = try reader.bytes(1)}
    let prefix=block.raw.prefix(reader.offset);var writer=PSDWriter();writer.data=Data(prefix);writer.section(payload);if payload.count%2 != 0{writer.n(0,1)};return writer.data
  }
  static func applying(_ resources:Data,entries:[(Layer,Int)])throws->Data{
    let blocks=try PSDImageResources.blocks(resources),existing=blocks.filter{[1026,1072].contains($0.id)}
    guard entries.contains(where:{$0.0.linkID != nil}) || !existing.isEmpty else{return resources}
    guard existing.filter({$0.id==1026}).count<=1,existing.filter({$0.id==1072}).count<=1 else{throw CraftError.invalid("Duplicate Photoshop layer-link resources.")}
    var ids:[UUID:Int]=[:],used=Set<Int>()
    let groups=Dictionary(grouping:entries.filter{$0.1 != 3 && $0.0.linkID != nil}.map{$0.0},by:{$0.linkID!})
    for (layer,section) in entries where section != 3 {
      guard let group=layer.linkID,ids[group]==nil else{continue}
      let preferred=Set((groups[group] ?? []).compactMap{value->Int? in guard let data=value.sourceTags?["PhLG"],data.count==2 else{return nil};return Int(data[0])*256+Int(data[1])})
      if preferred.count==1,let value=preferred.first,value>0,!used.contains(value){ids[group]=value;used.insert(value)}
    }
    for (layer,_) in entries{if let group=layer.linkID,ids[group]==nil{let value=(1...65535).first{!used.contains($0)}!;ids[group]=value;used.insert(value)}}
    var groupData=PSDWriter(),enabled=Data()
    for (layer,section) in entries {
      groupData.n(section==3 ? 0:layer.linkID.flatMap{ids[$0]} ?? 0,2)
      enabled.append(section==3 ? (layer.sourceTags?["PhLF"]?.first ?? 1):layer.linkID==nil ? (layer.sourceTags?["PhFE"]?.first ?? 1):layer.linkDisabled == true ? 0:1)
    }
    let values=[1026:groupData.data,1072:enabled];var result=Data(),written=Set<Int>()
    for block in blocks{if let payload=values[block.id]{result.append(try preserved(block,id:block.id,payload:payload));written.insert(block.id)}else{result.append(block.raw)}}
    for id in [1026,1072] where !written.contains(id){result.append(PSDImageResources.block(id,data:values[id]!))};return result
  }
}
