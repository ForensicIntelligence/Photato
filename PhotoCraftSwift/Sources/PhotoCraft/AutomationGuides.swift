import Foundation
import PhotoCraftCore

enum GuideAPI {
  static var lineSchema:[String:Any] { ["type":"object","additionalProperties":false,"required":["axis","position"],"properties":["id":["type":"string","format":"uuid"],"axis":["type":"string","enum":["horizontal","vertical"]],"position":["type":"number","minimum":-1_000_000,"maximum":1_000_000],"color":AutomationCommand.artboardSchema("background")]] }
  static func schema(_ key:String)->[String:Any] {
    switch key {
    case "operation":return["type":"string","enum":["add","replace","update","delete","clear","clearAll","layout"]]
    case "guides":return["type":"array","maxItems":DocumentGuide.maximumCount,"items":lineSchema]
    case "ids":return["type":"array","uniqueItems":true,"items":["type":"string","format":"uuid"]]
    case "visible","locked","snap","enabled":return["type":"boolean"]
    case "layout":
      var properties:[String:Any]=[:]
      for name in ["columns","rows"]{properties[name]=["type":"integer","minimum":0,"maximum":10_000]}
      for name in ["columnGutter","rowGutter","left","right","top","bottom"]{properties[name]=["type":"number","minimum":0,"maximum":1_000_000]}
      properties["clearExisting"]=["type":"boolean"];properties["color"]=AutomationCommand.artboardSchema("background")
      return["type":"object","additionalProperties":false,"properties":properties]
    default:return[:]
    }
  }
  static var capabilities:[String:Any] { ["edit":"guides.edit","view":"guides.view","operations":["add","replace","update","delete","clear","clearAll","layout"],"maximumGuides":DocumentGuide.maximumCount,"nativeArchiveVersion":78,"coordinates":"Document pixels; New Guide also accepts px, %, in, cm, mm, pt and pc. Ruler labels and layout distances currently use pixels.","interchange":"Original source guides and PSD/PSB resource1032; older native opaque guide resources migrate on shared file/API admission; unchanged PSD records are retained. Edited PSD positions quantize to1/32 pixel. Guide colors persist natively; PSD/PSB rejects custom guide colors until modern per-guide color records are implemented.","snapping":"Move-tool layer bounds/center snap within8 view points with the existing integer layer-position precision when enabled; Shift+Option selects multiple guides, Option changes orientation during drag, Shift snaps to pixel ruler ticks; Command temporarily suppresses layer snapping.","actions":"Guide identity/selection Actions recording and Adobe guide descriptors remain unsupported; no Adobe route is invented.","remaining":["Modern colored-guide PSD records","arbitrary rotated guides","ruler origin/unit preferences","grid and Smart Guides","full target/snap/preferences/live Photoshop/platform/performance qualification"]] }
}

extension AutomationCommand {
  private func guideColor(_ value:AutomationValue)throws->Pixel {
    guard case .object(let fields)=value,Set(fields.keys)==["r","g","b","a"]else{throw AutomationFailure(status:400,message:"Guide color requires RGBA.")}
    let values=try ["r","g","b","a"].map {key->Float in guard case .number(let n)=fields[key],n.isFinite,(0...1).contains(n)else{throw AutomationFailure(status:400,message:"Invalid guide color.")};return Float(n)}
    return Pixel(values[0],values[1],values[2],values[3])
  }
  func guideCommand(in document:CraftDocument)throws->Command {
    let operation=try string("operation")
    let fields:Set<String>
    switch operation {case "add","replace","update":fields=["operation","guides"];case "delete":fields=["operation","ids"];case "clear","clearAll":fields=["operation"];case "layout":fields=["operation","layout"];default:throw AutomationFailure(status:400,message:"Unknown guide operation.")}
    guard Set(parameters.keys)==fields else{throw AutomationFailure(status:400,message:"Missing or irrelevant guide parameters.")}
    if operation=="clearAll"{return .guides(.clearAll)}
    if operation=="clear"{return .guides(.delete(Set((document.guides ?? []).map(\.id))))}
    if operation=="delete" {
      guard case .array(let values)=parameters["ids"],values.count<=DocumentGuide.maximumCount else{throw AutomationFailure(status:400,message:"Expected guide IDs.")}
      let ids=try values.map {value->UUID in guard case .string(let text)=value,let id=UUID(uuidString:text)else{throw AutomationFailure(status:400,message:"Invalid guide UUID.")};return id}
      guard Set(ids).count==ids.count else{throw AutomationFailure(status:400,message:"Duplicate guide IDs.")};return .guides(.delete(Set(ids)))
    }
    if operation=="layout" {
      guard case .object(let fields)=parameters["layout"],Set(fields.keys).isSubset(of:["columns","rows","columnGutter","rowGutter","left","right","top","bottom","clearExisting","color"])else{throw AutomationFailure(status:400,message:"Invalid guide layout fields.")}
      var layout=GuideLayout()
      func n(_ key:String)throws->Double {guard let raw=fields[key]else{return 0};guard case .number(let n)=raw,n.isFinite,n>=0,n<=1_000_000 else{throw AutomationFailure(status:400,message:"Invalid guide layout number.")};return n}
      let columns=try n("columns"),rows=try n("rows");guard columns.rounded()==columns,rows.rounded()==rows,columns<=10_000,rows<=10_000 else{throw AutomationFailure(status:400,message:"Invalid guide row/column count.")}
      layout.columns=Int(columns);layout.rows=Int(rows);layout.columnGutter=try n("columnGutter");layout.rowGutter=try n("rowGutter");layout.left=try n("left");layout.right=try n("right");layout.top=try n("top");layout.bottom=try n("bottom")
      if let value=fields["color"]{layout.color=try guideColor(value)}
      if let value=fields["clearExisting"] {guard case .bool(let b)=value else{throw AutomationFailure(status:400,message:"clearExisting must be boolean.")};layout.clearExisting=b}
      let lines=try layout.guides(width:document.width,height:document.height);return .guides(layout.clearExisting ? .replace(lines):.add(lines))
    }
    guard case .array(let values)=parameters["guides"],values.count<=DocumentGuide.maximumCount else{throw AutomationFailure(status:400,message:"Expected guides array.")}
    let lines=try values.map {value->DocumentGuide in
      guard case .object(let fields)=value,Set(fields.keys).isSubset(of:["id","axis","position","color"]),case .string(let axis)=fields["axis"],let axis=DocumentGuide.Axis(rawValue:axis),case .number(let p)=fields["position"],p.isFinite,abs(p)<=1_000_000 else{throw AutomationFailure(status:400,message:"Invalid guide.")}
      var id=UUID()
      if let value=fields["id"]{guard case .string(let text)=value,let parsed=UUID(uuidString:text)else{throw AutomationFailure(status:400,message:"Invalid guide UUID.")};id=parsed}
      else if operation=="update"{throw AutomationFailure(status:400,message:"Updating a guide requires its ID.")}
      let existing=document.guides?.first{$0.id==id}
      let color=try fields["color"].map{try guideColor($0)} ?? existing?.color ?? Pixel(0,1,1,1)
      return DocumentGuide(id:id,axis:axis,position:p,color:color)
    }
    return .guides(operation=="replace" ? .replace(lines):operation=="update" ? .update(lines):.add(lines))
  }
  @MainActor func applyGuideView(_ store:EditorStore)throws {
    guard !parameters.isEmpty,Set(parameters.keys).isSubset(of:["visible","locked","snap","enabled"])else{throw AutomationFailure(status:400,message:"Use guide view booleans visible, locked, snap or enabled.")}
    func flag(_ key:String)throws->Bool? {guard let raw=parameters[key]else{return nil};guard case .bool(let b)=raw else{throw AutomationFailure(status:400,message:"Guide view flags must be boolean.")};return b}
    let visible=try flag("visible"),locked=try flag("locked"),snap=try flag("snap"),enabled=try flag("enabled")
    store.configureGuideView(visible:visible,locked:locked,snap:snap,enabled:enabled)
  }
}
