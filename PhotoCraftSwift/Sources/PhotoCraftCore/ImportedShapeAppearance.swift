import Foundation

public struct ShapePaintFrame:Codable,Equatable,Sendable {
  public var x:Double,y:Double,width:Double,height:Double
  public init(x:Double,y:Double,width:Double,height:Double){self.x=x;self.y=y;self.width=width;self.height=height}
  public func validate()throws{
    guard [x,y,width,height].allSatisfy({$0.isFinite && abs($0)<=1_000_000}),width>=0,height>=0 else{throw CraftError.invalid("Invalid shape paint frame.")}
  }
}

/// A source cache is valid only for its captured definition. Explicit shape
/// configuration generates native rendering; Undo retains the original data.
public struct ImportedShapeAppearance:Codable,Equatable,Sendable {
  public var definition:ShapeDefinition
  public var pixels:Surface?
  public var x:Int,y:Int
  public var vectorRecord:Data?
  public init(definition:ShapeDefinition,pixels:Surface?=nil,x:Int=0,y:Int=0,vectorRecord:Data?=nil){self.definition=definition;self.pixels=pixels;self.x=x;self.y=y;self.vectorRecord=vectorRecord}
  public var estimatedBytes:Int {definition.estimatedBytes+(pixels?.allocatedBytes ?? 0)+(vectorRecord?.count ?? 0)}
  public func validate(in document:CraftDocument)throws{
    try definition.validate(in:document)
    guard abs(Double(x))<=1_000_000,abs(Double(y))<=1_000_000,(vectorRecord?.count ?? 0)<=4*1024*1024 else{throw CraftError.invalid("Invalid imported shape appearance.")}
    if let pixels {
      guard pixels.depth==document.depth,pixels.width<=32768,pixels.height<=32768,pixels.width*pixels.height<=8_388_608 else{throw CraftError.invalid("Imported shape cache exceeds its supported depth or bounds.")}
      try pixels.validated()
    }
  }
}

public enum ShapeBounds {
  public static func union(_ a:IntRect,_ b:IntRect)throws->IntRect{
    for frame in [a,b] {
      guard frame.width>0,frame.height>0,frame.width<=32768,frame.height<=32768,abs(Double(frame.x))<=1_000_000,abs(Double(frame.y))<=1_000_000 else{throw CraftError.invalid("Invalid shape frame.")}
    }
    let x0=min(a.x,b.x),y0=min(a.y,b.y),x1=max(a.x+a.width,b.x+b.width),y1=max(a.y+a.height,b.y+b.height)
    guard x1>x0,y1>y0,abs(Double(x0))<=1_000_000,abs(Double(y0))<=1_000_000,abs(Double(x1))<=1_000_000,abs(Double(y1))<=1_000_000,x1-x0<=32768,y1-y0<=32768,(x1-x0)*(y1-y0)<=8_388_608 else{throw CraftError.invalid("Shape exceeds the8MP rasterization budget.")}
    return .init(x:x0,y:y0,width:x1-x0,height:y1-y0)
  }
}
extension ShapeContent {
  public func renderBounds()throws->IntRect{
    guard let definition else{return .init(x:0,y:0,width:width,height:height)}
    let bounds=try definition.renderBounds()
    guard let appearance=importedAppearance,appearance.definition==definition,let pixels=appearance.pixels else{return bounds}
    return .init(x:appearance.x,y:appearance.y,width:pixels.width,height:pixels.height)
  }
}
