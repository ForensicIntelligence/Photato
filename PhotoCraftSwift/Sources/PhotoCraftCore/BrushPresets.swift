import Foundation

public struct BrushPreset:Codable,Equatable,Identifiable,Sendable {
  public var id:UUID
  public var name:String
  public var group:String
  public var brush:Brush
  public var includeSize=true
  public var includeToolSettings=true
  public var includeColor=false
  public init(id:UUID=UUID(),name:String,group:String="My Brushes",brush:Brush) { self.id=id;self.name=name;self.group=group;self.brush=brush }
  public func validate() throws {
    guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.count<=255,group.count<=255 else { throw CraftError.invalid("Brush preset names need1–255 characters; group names allow0–255.") }
    try BrushPainter.validate(brush,points:[])
  }
  public func applying(to current:Brush)->Brush {
    var value=brush;value.erase=current.erase
    value.settings=(brush.settings ?? .init()).picked(over:current.settings ?? .init())
    if includeToolSettings && current.settings?.lockedSections.contains("smoothing") != true { value.settings!.smoothing=brush.settings?.smoothing ?? .init() }
    if !includeSize { value.size=current.size }
    if current.settings?.lockedSections.contains("tip")==true { value.size=current.size;value.hardness=current.hardness }
    if !includeToolSettings { value.opacity=current.opacity;value.settings!.mode=current.settings?.mode ?? .normal;value.settings!.flow=current.settings?.flow ?? 1;value.settings!.pressureSize=current.settings?.pressureSize ?? true;value.settings!.pressureOpacity=current.settings?.pressureOpacity ?? false }
    if !includeColor { value.color=current.color;value.backgroundColor=current.backgroundColor }
    return value
  }
}
public struct BrushPresetFile:Codable,Equatable,Sendable {
  public var version=1
  public var presets:[BrushPreset]
  public init(presets:[BrushPreset]) { self.presets=presets }
  public static let maximumBytes=64*1024*1024
  public func validate() throws {
    guard version==1,presets.count<=512,Set(presets.map(\.id)).count==presets.count else { throw CraftError.invalid("Brush library requires version1 and at most512 unique presets.") }
    var bytes=0
    for p in presets { try p.validate();bytes += p.brush.settings?.bitmapBytes ?? 0;guard bytes<=48*1024*1024 else { throw CraftError.invalid("Brush library bitmaps exceed48MiB.") } }
  }
  public func encoded() throws ->Data {
    try validate();let e=JSONEncoder();e.outputFormatting=[.sortedKeys];let data=try e.encode(self);guard data.count<=Self.maximumBytes else { throw CraftError.invalid("Brush library exceeds64MiB.") };return data
  }
  public static func decode(_ data:Data)throws->Self { guard data.count<=maximumBytes else { throw CraftError.invalid("Brush library exceeds64MiB.") };let file=try JSONDecoder().decode(Self.self,from:data);try file.validate();return file }
}
public enum BrushPresets {
  /// Original PhotoCraft procedural tip designs; no Adobe-owned preset pixels are bundled.
  public static func generatedTip(_ kind:String,size:Int=64,seed:UInt64=7)throws->BrushBitmap {
    guard (8...256).contains(size) else { throw CraftError.invalid("Invalid generated tip size.") };var bytes=Data(count:size*size);let c=Double(size)/2
    let drops=(0..<14).map { i -> (Double,Double,Double) in
      let a=BrushRandom.pixel(i,0,seed+202)*2*Double.pi,d=sqrt(BrushRandom.pixel(i,1,seed+202))*0.38*Double(size),r=(0.03+0.09*pow(BrushRandom.pixel(i,2,seed+202),2))*Double(size)
      return (c+cos(a)*d,c+sin(a)*d,r)
    }
    for y in 0..<size { for x in 0..<size {
      let dx=(Double(x)+0.5-c)/c,dy=(Double(y)+0.5-c)/c;var value=0.0
      switch kind {
      case "bristle":
        let r=hypot(dx,dy*1.8),hair=BrushRandom.pixel(0,Int(Double(y)/1.5),seed+303)
        value=r>1 ? 0:(hair<0.25 ? 0:0.5+0.5*hair)*(1-pow(r,4))
      case "spatter":for (bx,by,r) in drops { value=max(value,min(1,max(0,r+0.5-hypot(Double(x)+0.5-bx,Double(y)+0.5-by)))) }
      case "leaf":
        let radius=abs(dx)+dy*dy;value=min(1,max(0,(0.92-radius)*12));if abs(dx)<0.04 { value *= 0.5 }
      default:
        let grain=BrushRandom.pixel(x,y,seed+101),r=hypot(dx,dy),edge=0.82+0.12*BrushRandom.pixel(Int((atan2(dy,dx)+Double.pi)*8),0,seed)
        value=min(1,max(0,(edge-r)*8))*(grain<0.2 ? 0.2:0.7+0.3*grain)
      }
      bytes[y*size+x]=UInt8((min(1,max(0,value))*255).rounded())
    } }
    return .init(width:size,height:size,bytes:bytes)
  }
  public static func builtins()->[BrushPreset] {
    var out:[BrushPreset]=[]
    func add(_ name:String,_ group:String="General",_ modify:(inout Brush)->Void) {
      var brush=Brush();brush.color = .black;brush.size=30;brush.hardness=1;brush.settings = .init();modify(&brush)
      let index=out.count+1,id=UUID(uuidString:String(format:"18900000-0000-4000-8000-%012d",index))!
      var preset=BrushPreset(id:id,name:name,group:group,brush:brush);preset.includeToolSettings=false;out.append(preset)
    }
    add("Hard Round") { _ in }
    add("Soft Round") { $0.hardness=0;$0.size=45 }
    add("Hard Round Pressure Size") { $0.settings!.shape.enabled=true;$0.settings!.shape.size.control = .penPressure }
    add("Soft Round Pressure Opacity") { $0.hardness=0;$0.settings!.transfer.enabled=true;$0.settings!.transfer.opacity.control = .penPressure }
    add("Calligraphy Flat") { $0.settings!.roundness=0.2;$0.settings!.angle=45;$0.settings!.spacing=0.05 }
    add("Chalk","Dry Media") { $0.size=40;$0.settings!.tip=try? generatedTip("chalk");$0.settings!.shape.enabled=true;$0.settings!.shape.angle.jitter=1;$0.settings!.texture.enabled=true;$0.settings!.texture.depth=0.6 }
    add("Flat Bristle","Dry Media") { $0.size=40;$0.settings!.tip=try? generatedTip("bristle");$0.settings!.spacing=0.08;$0.settings!.shape.enabled=true;$0.settings!.shape.angle.control = .direction }
    add("Airbrush Soft","Wet Media") { $0.size=80;$0.hardness=0;$0.settings!.flow=0.1;$0.settings!.buildUp=true }
    out[out.count-1].includeToolSettings=true
    add("Wet Edge Round","Wet Media") { $0.size=50;$0.hardness=0;$0.settings!.wetEdges=true;$0.settings!.texture.enabled=true;$0.settings!.texture.depth=0.35 }
    add("Spatter","Special Effects") { $0.size=60;$0.settings!.tip=try? generatedTip("spatter");$0.settings!.spacing=0.5;$0.settings!.shape.enabled=true;$0.settings!.shape.angle.jitter=1;$0.settings!.scattering.enabled=true;$0.settings!.scattering.amount.jitter=1.5 }
    add("Leaves","Special Effects") { $0.size=35;$0.settings!.tip=try? generatedTip("leaf");$0.settings!.spacing=0.8;$0.settings!.shape.enabled=true;$0.settings!.shape.angle.control = .direction;$0.settings!.colorDynamics.enabled=true;$0.settings!.colorDynamics.hue=0.1 }
    add("Textured Dual Round","Special Effects") { $0.size=60;$0.hardness=0;$0.settings!.dual.enabled=true;$0.settings!.dual.tip=try? generatedTip("chalk");$0.settings!.dual.size=50;$0.settings!.dual.scatter=0.3 }
    return out
  }
  public static func define(from surface:Surface,bounds:IntRect,selection:SelectionMask?=nil)throws->BrushBitmap {
    guard bounds.width>0,bounds.height>0,bounds.width<=2500,bounds.height<=2500 else { throw CraftError.invalid("A defined brush must fit within2500×2500 pixels.") }
    var bytes=Data(count:bounds.width*bounds.height)
    for y in 0..<bounds.height { try Task.checkCancellation();for x in 0..<bounds.width {
      let px=x+bounds.x,py=y+bounds.y,p=surface.pixel(x:px,y:py),gray=unit(p.r*0.2126+p.g*0.7152+p.b*0.0722),alpha=p.a*(selection?.coverage(x:px,y:py) ?? 1)
      bytes[y*bounds.width+x]=UInt8((unit((1-gray)*alpha)*255).rounded())
    } }
    guard bytes.contains(where:{$0>0}) else { throw CraftError.invalid("The selected image contains no visible brush coverage.") }
    return .init(width:bounds.width,height:bounds.height,bytes:bytes)
  }
}
