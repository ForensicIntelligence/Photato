import Foundation
import PhotoCraftCore

// Photato naming schema; no Adobe route/action descriptor is invented.
enum BatchNamingAPI {
  static var schema:[String:Any] {
    BrushAPI.object(["elements":["type":"array","minItems":1,"maxItems":6,"contains":["type":"object","required":["kind"],"properties":["kind":BrushAPI.enumeration(BatchFileNaming.Kind.allCases.filter(\.identifiesSource).map(\.rawValue))]],"items":BrushAPI.object([
      "kind":BrushAPI.enumeration(BatchFileNaming.Kind.allCases.map(\.rawValue)),
      "text":["type":"string","maxLength":128]],required:["kind"])],
      "startingSerial":["type":"integer","minimum":0,"maximum":BatchFileNaming.maximumSerial,"default":1],
      "windows":BrushAPI.flag,"macOS":BrushAPI.flag,"unix":BrushAPI.flag,
      "date":["type":"string","format":"date-time"],"timeZone":["type":"string","minLength":1,"maxLength":128]],required:["elements"])
  }
  static var stateSchema:[String:Any] {
    BrushAPI.object(["active":BrushAPI.flag,"operationID":["type":["string","null"],"format":"uuid"],
      "results":["type":"array","maxItems":256,"items":BrushAPI.object(["source":["type":"string"],"output":["type":["string","null"]],"error":["type":["string","null"]],"cancelled":BrushAPI.flag],required:["source","output","error","cancelled"])],
      "naming":["anyOf":[schema,["type":"null"]]],"namingCapabilities":["type":"object"]],required:["active","operationID","results","naming","namingCapabilities"])
  }
  static var capabilities:[String:Any] {
    ["schema":schema,"stateSchema":stateSchema,"legacy":"Omitting naming retains the existing numbered source/suffix API contract. Explicit naming and suffix are mutually exclusive.",
      "fields":BatchFileNaming.Kind.allCases.map{["id":$0.rawValue,"title":$0.title]},
      "defaults":"Starting serial1; Windows/macOS/UNIX compatibility true per installed Photoshop2026public Batch dictionary. Native initial fields Document Name+extension are chosen pending live default qualification.",
      "date":"One run date/timezone is captured; API may supply ISO8601 date/timeZone for reproducible names. Native captures current date at Run; date interpretation and exact Photoshop defaults remain unqualified.",
      "limits":"1–6fields; document name or number/letter required; names max255UTF8bytes, literals128bytes. Numbers are minimum-width with no truncation; letters beginA independently of startingSerial. Exact Photoshop overflow/date/case/sanitization/uncommon semantics remain open.",
      "publication":"Duplicate planned names reject before any file processing. Compatibility alias checks run before each existing atomic nonoverwriting link. On case-sensitive filesystems an external racing case alias is not an all-files/cross-platform atomic guarantee.",
      "scope":"PhotoshopBatch Open/Save overrides, destinations, subfolders/import/Bridge, conditions/ATN/droplets and fullAUT01remain open. Naming uses the selected Photato output format's extension, not an unimplemented SaveAs override."]
  }
  static func object(_ value:BatchFileNaming)->[String:Any] {
    ["elements":value.elements.map{["kind":$0.kind.rawValue,"text":$0.text]},"startingSerial":value.startingSerial,
      "windows":value.windows,"macOS":value.macOS,"unix":value.unix,
      "date":ISO8601DateFormatter().string(from:value.date),"timeZone":value.timeZone]
  }
  static func parse(_ raw:AutomationValue)throws->BatchFileNaming {
    guard case .object(let fields)=raw,Set(fields.keys).isSubset(of:["elements","startingSerial","windows","macOS","unix","date","timeZone"]),
      case .array(let parts)=fields["elements"],(1...6).contains(parts.count) else {throw AutomationFailure(status:400,message:"Supply1–6naming elements and supported settings.")}
    var result=BatchFileNaming()
    result.elements=try parts.map {raw in
      guard case .object(let part)=raw,Set(part.keys).isSubset(of:["kind","text"]),case .string(let name)=part["kind"],let kind=BatchFileNaming.Kind(rawValue:name)else{throw AutomationFailure(status:400,message:"Invalid naming field.")}
      let text:String
      if let raw=part["text"] {guard case .string(let value)=raw else{throw AutomationFailure(status:400,message:"Naming text must be a string.")};text=value}else{text=""}
      return .init(kind:kind,text:text)
    }
    if let raw=fields["startingSerial"] {guard case .number(let n)=raw,n.isFinite,n.rounded()==n,(0...Double(BatchFileNaming.maximumSerial)).contains(n)else{throw AutomationFailure(status:400,message:"Invalid starting serial number.")};result.startingSerial=Int(n)}
    for (key,path)in [("windows",\BatchFileNaming.windows),("macOS",\BatchFileNaming.macOS),("unix",\BatchFileNaming.unix)] {
      if let raw=fields[key] {guard case .bool(let value)=raw else{throw AutomationFailure(status:400,message:"Compatibility flags must be boolean.")};result[keyPath:path]=value}
    }
    if let raw=fields["timeZone"] {guard case .string(let value)=raw,value.utf8.count<=128 else{throw AutomationFailure(status:400,message:"Invalid naming time zone.")};result.timeZone=value}
    if let raw=fields["date"] {
      guard case .string(let text)=raw else{throw AutomationFailure(status:400,message:"Naming date must be ISO8601 text.")}
      let formatter=ISO8601DateFormatter();var parsed=formatter.date(from:text)
      if parsed==nil {formatter.formatOptions.insert(.withFractionalSeconds);parsed=formatter.date(from:text)}
      guard let date=parsed else{throw AutomationFailure(status:400,message:"Invalid ISO8601 naming date.")};result.date=date
    }
    do{try result.validate()}catch{throw AutomationFailure(status:400,message:error.localizedDescription)}
    return result
  }
}
