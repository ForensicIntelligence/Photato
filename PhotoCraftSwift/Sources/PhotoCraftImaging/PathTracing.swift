import Foundation
import PhotoCraftCore

/// Marching squares at half coverage, adapted from PhotoCraft vector/trace.rs (MIT).
public enum PathTracing {
  struct Edge:Hashable{var x:Int;var y:Int;var vertical:Bool}
  public static func trace(_ mask:SelectionMask,tolerance:Double)throws->VectorPath {
    guard tolerance.isFinite,(0.5...10).contains(tolerance),mask.width*mask.height<=16_777_216 else{throw CraftError.invalid("Make Work Path supports 0.5–10 pixel tolerance and selections up to 16MP.")}
    var next:[Edge:Edge]=[:],positions:[Edge:PathPoint]=[:]
    func value(_ x:Int,_ y:Int)->Double{x>=0 && y>=0 && x<mask.width && y<mask.height ? Double(mask.byte(at:y*mask.width+x))/255:0}
    func position(_ e:Edge)->PathPoint{let a=value(e.x,e.y),b=value(e.x+(e.vertical ? 0:1),e.y+(e.vertical ? 1:0)),t=abs(b-a)>1e-12 ? (0.5-a)/(b-a):0.5;return .init(Double(e.x)+0.5+(e.vertical ? 0:t),Double(e.y)+0.5+(e.vertical ? t:0))}
    for y in -1..<mask.height {try Task.checkCancellation();for x in -1..<mask.width {
      let a=value(x,y),b=value(x+1,y),c=value(x+1,y+1),d=value(x,y+1),code=(a>=0.5 ? 1:0)+(b>=0.5 ? 2:0)+(c>=0.5 ? 4:0)+(d>=0.5 ? 8:0)
      if code==0 || code==15{continue}
      let top=Edge(x:x,y:y,vertical:false),right=Edge(x:x+1,y:y,vertical:true),bottom=Edge(x:x,y:y+1,vertical:false),left=Edge(x:x,y:y,vertical:true)
      var pairs:[(Edge,Edge)]=[]
      switch code {
      case 1:pairs=[(left,top)];case 2:pairs=[(top,right)];case 3:pairs=[(left,right)];case 4:pairs=[(right,bottom)]
      case 5:pairs=(a+b+c+d)>=2 ? [(left,bottom),(right,top)]:[(left,top),(right,bottom)]
      case 6:pairs=[(top,bottom)];case 7:pairs=[(left,bottom)];case 8:pairs=[(bottom,left)];case 9:pairs=[(bottom,top)]
      case 10:pairs=(a+b+c+d)>=2 ? [(top,left),(bottom,right)]:[(top,right),(bottom,left)]
      case 11:pairs=[(bottom,right)];case 12:pairs=[(right,left)];case 13:pairs=[(right,top)];case 14:pairs=[(top,left)];default:break
      }
      for (start,end) in pairs{next[start]=end;positions[start]=position(start)}
      guard next.count<=PathConstruction.maxSamples else{throw CraftError.invalid("Selection boundary exceeds 100,000 points. Simplify the selection first.")}
    }}
    let keys=next.keys.sorted{a,b in a.y != b.y ? a.y<b.y:a.x != b.x ? a.x<b.x:(!a.vertical && b.vertical)}
    var result=VectorPath()
    for start in keys where next[start] != nil {
      var points:[PathPoint]=[],edge=start
      repeat{guard let end=next.removeValue(forKey:edge),let p=positions[edge] else{throw CraftError.invalid("Selection contour is incomplete.")};points.append(p);edge=end}while edge != start
      guard points.count>=3 else{continue}
      var part=try PathConstruction.fitted(points,tolerance:tolerance,closed:true);part.operation=result.components.isEmpty ? .combine:.exclude;result.components.append(part);try result.validate()
    }
    guard !result.isEmpty else{throw CraftError.invalid("The selection has no boundary at 50% coverage.")};return result
  }
  public static func command(_ document:CraftDocument,tolerance:Double)throws->Command {
    guard document.width*document.height<=16_777_216 else{throw CraftError.invalid("Make Work Path supports selections up to 16MP.")}
    guard document.selectionMask != nil || document.selection != nil else{throw CraftError.invalid("Make a selection before creating a work path.")}
    let mask:SelectionMask
    if let existing=document.selectionMask{mask=existing}else{var bytes=[UInt8](repeating:0,count:document.width*document.height);let r=document.selection!;for y in max(0,r.y)..<min(document.height,r.y+r.height){for x in max(0,r.x)..<min(document.width,r.x+r.width){bytes[y*document.width+x]=255}};mask=try SelectionMask(width:document.width,height:document.height,bytes:bytes)}
    var saved=NamedPath(path:try trace(mask,tolerance:tolerance));if let old=document.paths?.first(where:\.isWorkPath){saved.id=old.id};return .savePath(saved)
  }
}
