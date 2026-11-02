import Foundation

public struct DocumentGuide: Codable, Equatable, Sendable, Identifiable {
  public enum Axis: String, Codable, Sendable { case horizontal, vertical }
  public var id: UUID
  public var axis: Axis
  public var position: Double
  public var color: Pixel
  public init(id: UUID = UUID(), axis: Axis, position: Double, color: Pixel = Pixel(0,1,1,1)) {
    self.id=id;self.axis=axis;self.position=position;self.color=color
  }
  public func validate() throws {
    guard position.isFinite, abs(position)<=1_000_000, color.isFinite,
      [color.r,color.g,color.b,color.a].allSatisfy({(0...1).contains($0)}) else {
      throw CraftError.invalid("Invalid document guide position or color.")
    }
  }
  public static let maximumCount=100_000
}

public struct GuideLayout: Codable, Equatable, Sendable {
  public var columns=0,rows=0
  public var columnGutter=0.0,rowGutter=0.0
  public var left=0.0,right=0.0,top=0.0,bottom=0.0
  public var clearExisting=false
  public var color=Pixel(0,1,1,1)
  public init() {}
  public func guides(width:Int,height:Int) throws -> [DocumentGuide] {
    guard (0...10_000).contains(columns),(0...10_000).contains(rows),
      [columnGutter,rowGutter,left,right,top,bottom].allSatisfy({$0.isFinite && $0>=0 && $0<=1_000_000}),
      left+right<Double(width),top+bottom<Double(height) else {throw CraftError.invalid("Guide layout requires valid margins, gutters and counts.")}
    var result:[DocumentGuide]=[]
    func lines(_ count:Int,_ extent:Double,_ leading:Double,_ trailing:Double,_ gutter:Double,_ axis:DocumentGuide.Axis)throws {
      let span=extent-leading-trailing
      if count>0 {
        let cell=(span-Double(count-1)*gutter)/Double(count)
        guard cell>0 else{throw CraftError.invalid("Guide gutters exceed the available layout size.")}
        result.append(.init(axis:axis,position:leading,color:color))
        for i in 1..<count {
          let edge=leading+Double(i)*cell+Double(i-1)*gutter
          result.append(.init(axis:axis,position:edge,color:color))
          if gutter>0 {result.append(.init(axis:axis,position:edge+gutter,color:color))}
        }
        result.append(.init(axis:axis,position:extent-trailing,color:color))
      }else if leading>0 || trailing>0 {
        result.append(.init(axis:axis,position:leading,color:color));result.append(.init(axis:axis,position:extent-trailing,color:color))
      }
    }
    try lines(columns,Double(width),left,right,columnGutter,.vertical)
    try lines(rows,Double(height),top,bottom,rowGutter,.horizontal)
    guard result.count<=DocumentGuide.maximumCount else{throw CraftError.invalid("Too many document guides.")}
    for line in result {try line.validate()};return result
  }
}

public enum GuideCommand: Sendable {
  case clearAll
  case add([DocumentGuide]), replace([DocumentGuide]), update([DocumentGuide]), delete(Set<UUID>)
  public var label:String {switch self {case .add:"New Guides";case .replace:"Guide Layout";case .update:"Edit Guides";case .delete,.clearAll:"Clear Guides"}}
  public func apply(to document:inout CraftDocument)throws {
    var lines=document.guides ?? []
    switch self {
    case .clearAll:
      lines=[]
      for i in document.layers.indices {if var group=document.layers[i].group,var board=group.artboard {board.guides=[];group.artboard=board;document.layers[i].content = .group(group)}}
    case .add(let values):lines+=values
    case .replace(let values):lines=values
    case .update(let values):
      let ids=Set(values.map(\.id));guard ids.count==values.count,ids.isSubset(of:Set(lines.map(\.id)))else{throw CraftError.invalid("Choose existing distinct guides.")}
      let changes=Dictionary(uniqueKeysWithValues:values.map{($0.id,$0)})
      lines=lines.map{changes[$0.id] ?? $0}
    case .delete(let ids):
      guard ids.isSubset(of:Set(lines.map(\.id)))else{throw CraftError.invalid("A selected guide no longer exists.")};lines.removeAll{ids.contains($0.id)}
    }
    try CraftDocument.validateGuides(lines);document.guides=lines
  }
}

extension CraftDocument {
  public static func validateGuides(_ guides:[DocumentGuide])throws {
    guard guides.count<=DocumentGuide.maximumCount,Set(guides.map(\.id)).count==guides.count else{throw CraftError.invalid("Too many or duplicate document guides.")}
    for line in guides {try Task.checkCancellation();try line.validate()}
  }
  /// Orthogonal document geometry keeps guides as lines. Oblique crop rotations
  /// cannot represent tilted guides and reject rather than silently dropping them.
  mutating func mapGuides(_ transform:Transform2D)throws {
    guard let guides else{return}
    self.guides=try guides.map {value in
      var result=value
      let p=value.axis == .vertical ? transform.point(value.position,0):transform.point(0,value.position)
      let direction=value.axis == .vertical ? (transform.c,transform.d):(transform.a,transform.b)
      if abs(direction.0)<1e-12 {result.axis = .vertical;result.position=p.x}
      else if abs(direction.1)<1e-12 {result.axis = .horizontal;result.position=p.y}
      else {throw CraftError.unsupported("Oblique document transforms require rotated guide support. Clear guides or use an orthogonal transform.")}
      try result.validate();return result
    }
  }
  /// Positions and bounds are in document pixels; tolerance is converted from
  /// view pixels by the caller. Ties use the original guide order.
  public func snappedToGuides(_ bounds:IntRect,dx:Double,dy:Double,tolerance:Double)->(Double,Double) {
    guard tolerance.isFinite,tolerance>=0,dx.isFinite,dy.isFinite else{return(dx,dy)}
    func offset(_ axis:DocumentGuide.Axis,_ initial:Double,_ anchors:[Double])->Double {
      var result=initial,best=tolerance.nextUp
      for line in guides ?? [] where line.axis==axis {
        for anchor in anchors {let gap=line.position-anchor-initial
          if abs(gap)<best,abs(gap)<=tolerance {best=abs(gap);result=initial+gap}
        }
      };return result
    }
    return(offset(.vertical,dx,[Double(bounds.x),Double(bounds.x)+Double(bounds.width)/2,Double(bounds.x+bounds.width)]),
      offset(.horizontal,dy,[Double(bounds.y),Double(bounds.y)+Double(bounds.height)/2,Double(bounds.y+bounds.height)]))
  }
}

public enum GuidePosition {
  public static func parse(_ text:String,extent:Double,resolution:Double)throws->Double {
    let text=text.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
    var number=text,factor=1.0
    for (suffix,value) in [("px",1.0),("in",resolution),("cm",resolution/2.54),("mm",resolution/25.4),("pt",resolution/72),("pc",resolution/6),("%",extent/100)] where text.hasSuffix(suffix) {
      number=String(text.dropLast(suffix.count)).trimmingCharacters(in:.whitespaces);factor=value;break
    }
    guard let value=Double(number),value.isFinite,factor.isFinite,abs(value*factor)<=1_000_000 else{throw CraftError.invalid("Enter a guide position in px, %, in, cm, mm, pt or pc.")};return value*factor
  }
}
