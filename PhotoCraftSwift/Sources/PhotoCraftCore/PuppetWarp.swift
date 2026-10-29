import Foundation

/// Pin program and coverage mesh translated from photocraft algo/puppet.rs (MIT OR Apache-2.0).
public struct PuppetPin: Codable, Equatable, Sendable {
  public var source:PathPoint
  public var destination:PathPoint
  public var rotation:Double?
  public var depth:Int = 0
  public init(source:PathPoint,destination:PathPoint?=nil,rotation:Double?=nil,depth:Int=0) { self.source=source;self.destination=destination ?? source;self.rotation=rotation;self.depth=depth }
}
public struct PuppetSettings: Codable, Equatable, Sendable {
  public enum Mode:String,Codable,CaseIterable,Sendable { case rigid,normal,distort }
  public enum Density:String,Codable,CaseIterable,Sendable { case fewer,normal,more;var cells:Double { self == .fewer ? 12:self == .normal ? 20:32 } }
  public var pins:[PuppetPin] = []
  public var mode:Mode = .normal
  public var density:Density = .normal
  public var expansion:Double = 2
  public var interpolation:Resampling = .bicubic
  public init() {}
  public var isIdentity:Bool { pins.allSatisfy { $0.source == $0.destination && ($0.rotation ?? 0).truncatingRemainder(dividingBy:360) == 0 } }
  public var estimatedBytes:Int { pins.count*64 }
  public func validate() throws {
    guard pins.count<=64,expansion.isFinite,(-200...200).contains(expansion) else { throw CraftError.invalid("Puppet Warp supports64 pins and−200…200 pixel mesh expansion.") }
    for (i,p) in pins.enumerated() {
      guard [p.source.x,p.source.y,p.destination.x,p.destination.y].allSatisfy({$0.isFinite && abs($0)<=1_000_000}),p.rotation.map({$0.isFinite && (-360...360).contains($0)}) ?? true,(-1000...1000).contains(p.depth) else { throw CraftError.invalid("Invalid Puppet Warp pin coordinates, rotation or depth.") }
      guard !pins.prefix(i).contains(where:{hypot($0.source.x-p.source.x,$0.source.y-p.source.y)<1e-6}) else { throw CraftError.invalid("Puppet pins cannot occupy the same source position.") }
    }
  }
  public func transformed(_ matrix:Transform2D) -> Self {
    var value=self
    for i in value.pins.indices { value.pins[i].source=pins[i].source.transformed(matrix);value.pins[i].destination=pins[i].destination.transformed(matrix);if matrix.a*matrix.d-matrix.b*matrix.c<0,let rotation=pins[i].rotation { value.pins[i].rotation = -rotation } }
    return value
  }
  public static func decodeJSON(_ data:Data) throws -> Self {
    guard data.count<=65536,var object=try JSONSerialization.jsonObject(with:data) as? [String:Any],Set(object.keys).isSubset(of:["pins","mode","density","expansion","interpolation"]) else { throw CraftError.invalid("Invalid Puppet Warp program.") }
    let defaults=try JSONSerialization.jsonObject(with:JSONEncoder().encode(Self())) as! [String:Any]
    for (key,value) in defaults where object[key] == nil { object[key]=value }
    guard var pins=object["pins"] as? [[String:Any]],pins.count<=64 else { throw CraftError.invalid("Puppet Warp needs a bounded pin array.") }
    for i in pins.indices {
      guard Set(pins[i].keys).isSubset(of:["source","destination","rotation","depth"]),let source=pins[i]["source"] as? [String:Any],Set(source.keys)==["x","y"] else { throw CraftError.invalid("Invalid Puppet Warp source pin.") }
      if pins[i]["destination"] == nil { pins[i]["destination"]=source }
      guard let destination=pins[i]["destination"] as? [String:Any],Set(destination.keys)==["x","y"] else { throw CraftError.invalid("Invalid Puppet Warp destination pin.") }
      if pins[i]["depth"] == nil { pins[i]["depth"]=0 }
    };object["pins"]=pins
    let result=try JSONDecoder().decode(Self.self,from:JSONSerialization.data(withJSONObject:object));try result.validate();return result
  }
}
public struct PuppetMesh: Equatable,Sendable {
  public var vertices:[PathPoint]
  public var triangles:[[Int]]
  public var spacing:Double
  public init(vertices:[PathPoint],triangles:[[Int]],spacing:Double) { self.vertices=vertices;self.triangles=triangles;self.spacing=spacing }
  public static let maximumVertices=8192
  public static func build(_ source:Surface,density:PuppetSettings.Density,expansion:Double) throws -> Self {
    guard source.width<=WarpRaster.maximumPixels/source.height,expansion.isFinite,(-200...200).contains(expansion) else { throw CraftError.invalid("Invalid Puppet mesh extent.") }
    guard let bounds=try source.contentBounds() else { return Self(vertices:[],triangles:[],spacing:2) }
    let spacing=max(2,Double(max(bounds.width,bounds.height))/density.cells),g=max(1,Int(floor(spacing/4)))
    let pad=Int(ceil(max(0,expansion)))+g,x0=bounds.x-pad,y0=bounds.y-pad
    let bw=(bounds.width+2*pad+g-1)/g,bh=(bounds.height+2*pad+g-1)/g
    guard bw<=4_194_304/bh else { throw CraftError.unsupported("Puppet coverage grid exceeds its memory budget.") }
    var covered=[Bool](repeating:false,count:bw*bh)
    for y in bounds.y..<(bounds.y+bounds.height) { try Task.checkCancellation();for x in bounds.x..<(bounds.x+bounds.width) where source.pixel(x:x,y:y).a>0.05 { covered[((y-y0)/g)*bw+(x-x0)/g]=true } }
    let radius=Int((abs(expansion)/Double(g)).rounded())
    if radius>0 {
      // Same disk stamp as upstream, with explicit resource admission before work.
      guard Double(bw)*Double(bh)*Double(2*radius+1)*Double(2*radius+1)<=134_217_728 else { throw CraftError.unsupported("Puppet expansion exceeds the coverage work budget; reduce expansion or use a larger source.") }
      let original=covered,grow=expansion>0
      for y in 0..<bh { try Task.checkCancellation();for x in 0..<bw {
        var hit = !grow
        stamp: for dy in -radius...radius { for dx in -radius...radius where dx*dx+dy*dy<=radius*radius {
          let xx=x+dx,yy=y+dy,v=xx>=0 && yy>=0 && xx<bw && yy<bh && original[yy*bw+xx]
          if grow && v { hit=true;break stamp };if !grow && !v { hit=false;break stamp }
        } };covered[y*bw+x]=hit
      } }
    }
    let cw=Int(ceil(Double(bw*g)/spacing)),ch=Int(ceil(Double(bh*g)/spacing))
    guard cw<=1_048_576/max(1,ch) else { throw CraftError.unsupported("Puppet mesh grid exceeds its work budget.") }
    var indices=[Int](repeating:-1,count:(cw+1)*(ch+1)),vertices=[PathPoint](),triangles=[[Int]]()
    func vertex(_ i:Int,_ j:Int) throws -> Int {
      let k=j*(cw+1)+i
      if indices[k]<0 { guard vertices.count<maximumVertices else { throw CraftError.unsupported("Puppet Warp supports8192 mesh vertices.") };indices[k]=vertices.count;vertices.append(PathPoint(Double(x0)+Double(i)*spacing,Double(y0)+Double(j)*spacing)) }
      return indices[k]
    }
    for j in 0..<ch { try Task.checkCancellation();for i in 0..<cw {
      let bx0=Int(floor(Double(i)*spacing/Double(g))),by0=Int(floor(Double(j)*spacing/Double(g)))
      let bx1=min(bw,Int(ceil(Double(i+1)*spacing/Double(g)))),by1=min(bh,Int(ceil(Double(j+1)*spacing/Double(g))))
      guard (by0..<by1).contains(where:{ y in (bx0..<bx1).contains(where:{covered[y*bw+$0]}) }) else { continue }
      let a=try vertex(i,j),b=try vertex(i+1,j),c=try vertex(i+1,j+1),d=try vertex(i,j+1)
      triangles += (i+j)%2 == 0 ? [[a,b,c],[a,c,d]]:[[a,b,d],[b,c,d]]
    } };return Self(vertices:vertices,triangles:triangles,spacing:spacing)
  }
}
