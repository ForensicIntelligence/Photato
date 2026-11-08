import Foundation
import PhotoCraftCore

/// Bounded native port of PhotoCraft psd/abr.rs and io/abr_map.rs. Unmapped data is reported.
public enum ABRCodec {
  public struct Imported:Sendable { public var presets:[BrushPreset];public var warnings:[String];public var version:Int }
  public static let maximumBytes=64*1024*1024
  static func text(_ d:PSDDescriptor,_ key:String)->String? { if case .text(let t)=d[key] { return String(decoding:t,as:UTF16.self).trimmingCharacters(in:CharacterSet(charactersIn:"\0")) };return nil }
  static func object(_ d:PSDDescriptor,_ key:String)->PSDDescriptor? { if case .object(let o)=d[key] { return o };return nil }
  static func number(_ d:PSDDescriptor,_ key:String,_ fallback:Double=0)->Double {
    if case .unit(_,let b)=d[key] { return Double(bitPattern:b) };return d[key]?.number ?? fallback
  }
  static func bool(_ d:PSDDescriptor,_ key:String,_ fallback:Bool=false)->Bool { if case .boolean(let b)=d[key] { return b };return fallback }
  static func enumeration(_ d:PSDDescriptor,_ key:String)->String? { if case .enumerated(_,let b)=d[key] { return b.text };return nil }
  static func string(_ r:inout PSDReader)throws->String {
    let n=try r.u32();guard n<=4096 else { throw CraftError.invalid("ABR name is too long.") };var chars:[UInt16]=[];for _ in 0..<n { chars.append(UInt16(try r.u16())) };return String(decoding:chars,as:UTF16.self).trimmingCharacters(in:CharacterSet(charactersIn:"\0"))
  }
  static func sample(_ r:inout PSDReader,budget:inout Int,warnings:inout [String])throws->BrushBitmap {
    let top=try r.i32(),left=try r.i32(),bottom=try r.i32(),right=try r.i32(),w=right-left,h=bottom-top,depth=try r.u16(),compression=try r.u8()
    guard w>0,h>0,w<=2500,h<=2500,[8,16].contains(depth),compression<=1 else { throw CraftError.unsupported("ABR sample needs1–2500px edges,8/16bit raw or RLE data.") }
    let size=w*h*(depth/8);guard size<=budget else { throw CraftError.invalid("ABR sample memory budget exceeded.") };budget -= size
    var payload=PSDWriter();payload.n(Int(compression),2);payload.data.append(try r.bytes(r.remaining))
    let bytes=try PSDChannelCodec.decode(payload.data,width:w,height:h,depth:depth)
    if depth==8 { return .init(width:w,height:h,bytes:Data(bytes)) }
    warnings.append("16-bit sampled coverage was quantized to8bit.")
    var converted=Data(count:w*h);for i in 0..<(w*h) { converted[i]=UInt8((Int(bytes[2*i])*256+Int(bytes[2*i+1])+128)/257) }
    return .init(width:w,height:h,bytes:converted)
  }
  public static func read(_ data:Data,group:String="Imported Brushes")throws->Imported {
    guard data.count<=maximumBytes else { throw CraftError.invalid("ABR exceeds64MiB.") }
    var r=PSDReader(data:data);let version=try r.u16();var presets:[BrushPreset]=[],warnings:[String]=[],budget=48*1024*1024
    if [1,2].contains(version) {
      let count=try r.u16();guard count<=512 else { throw CraftError.invalid("ABR exceeds512 brushes.") }
      for i in 0..<count {
        try Task.checkCancellation();let type=try r.u16(),length=try r.u32();var body=try r.view(length)
        do {
          _ = try body.u32();let spacing=try body.u16();var b=Brush();b.color = .black;b.settings = .init();b.settings!.spacingEnabled=spacing>0;b.settings!.spacing=spacing==0 ? 0.25:Double(spacing)/100;var name="Brush \(i+1)"
          if type==1 { b.size=Double(try body.u16());b.settings!.roundness=Double(try body.u16())/100;b.settings!.angle=Double(try body.i16());b.hardness=Float(try body.u16())/100 }
          else if type==2 { if version==2 { name=try string(&body) };b.settings!.aliased=try body.u8()==0;_ = try body.bytes(8);let tip=try sample(&body,budget:&budget,warnings:&warnings);b.settings!.tip=tip;b.size=Double(max(tip.width,tip.height)) }
          else { throw CraftError.unsupported("Unknown legacy tip type\(type).") }
          var p=BrushPreset(name:name.isEmpty ? "Brush \(i+1)":name,group:group,brush:b);p.includeToolSettings=false;try p.validate();presets.append(p)
        } catch is CancellationError { throw CancellationError() } catch { warnings.append("Brush\(i+1) skipped: \(error.localizedDescription)") }
      }
      guard r.remaining<=3,try r.bytes(r.remaining).allSatisfy({$0==0}) else { throw CraftError.invalid("Unexpected legacy ABR tail.") }
    } else if (6...10).contains(version) {
      let sub=try r.u16();guard [1,2].contains(sub) else { throw CraftError.unsupported("Unsupported ABR subversion.") }
      var samples:[String:BrushBitmap]=[:],sampleOrder:[String]=[],descriptors:[PSDDescriptor]=[],patterns:[RasterPattern]=[]
      while r.remaining>=12 {
        try Task.checkCancellation();guard try r.string(4)=="8BIM" else { throw CraftError.invalid("Invalid ABR section signature.") }
        let key=try r.string(4),length=try r.u32(),section=try r.bytes(length)
        let pad=(4-length%4)%4
        if pad>0 && r.remaining>=pad { var peek=r;let next=try peek.bytes(min(4,peek.remaining));if next != Data("8BIM".utf8) { guard try r.bytes(pad).allSatisfy({$0==0}) else { throw CraftError.invalid("Invalid ABR padding.") } } }
        switch key {
        case "samp":
          var sr=PSDReader(data:section)
          while sr.remaining>=4 {
            let n=try sr.u32();if n==0 { break };guard samples.count<512 else { throw CraftError.invalid("ABR exceeds512 samples.") }
            var body=try sr.view(n);let padding=(4-n%4)%4;guard try sr.bytes(padding).allSatisfy({$0==0}) else { throw CraftError.invalid("Invalid ABR sample padding.") }
            do { let count=Int(try body.u8()),id=try body.string(count);_ = try body.bytes(sub==1 ? 10:264);guard samples[id]==nil else { throw CraftError.invalid("Duplicate sample identifier.") };samples[id]=try sample(&body,budget:&budget,warnings:&warnings);sampleOrder.append(id) }
            catch is CancellationError { throw CancellationError() } catch { warnings.append("Sample skipped: \(error.localizedDescription)") }
          }
        case "desc":
          let d=try PSDDescriptor.read(section,padding:true);try validateNumbers(d);guard case .list(let list)=d["Brsh"],list.count<=512 else { throw CraftError.invalid("Invalid ABR preset descriptor list.") }
          for value in list { guard case .object(let p)=value else { throw CraftError.invalid("Invalid ABR brush descriptor.") };descriptors.append(p) }
          guard descriptors.count<=512 else { throw CraftError.invalid("ABR exceeds512 presets.") }
        case "patt":
          let remaining=48*1024*1024-patterns.reduce(0){$0+$1.surface.allocatedBytes}
          let decoded=try PSDPatterns.read(section,tileBudget:remaining)
          guard decoded.reduce(0,{$0+$1.surface.allocatedBytes})<=remaining else { throw CraftError.invalid("ABR pattern memory budget exceeded.") }
          patterns += decoded
        default:warnings.append("Unmapped ABR section: \(key).")
        }
      }
      guard try r.bytes(r.remaining).allSatisfy({$0==0}) else { throw CraftError.invalid("Unexpected ABR tail.") }
      if descriptors.isEmpty {
        for (i,id) in sampleOrder.enumerated() { var b=Brush();b.color = .black;b.settings = .init();b.settings!.tip=samples[id];b.size=Double(max(samples[id]!.width,samples[id]!.height));var p=BrushPreset(name:"Sampled Brush \(i+1)",group:group,brush:b);p.includeToolSettings=false;try p.validate();presets.append(p) }
      } else {
        for (i,d) in descriptors.enumerated() {
          try Task.checkCancellation()
          do { var p=try decodePreset(d,samples:samples,patterns:patterns,warnings:&warnings);p.group=group;try p.validate();presets.append(p) }
          catch is CancellationError { throw CancellationError() } catch { warnings.append("Preset\(i+1) skipped: \(error.localizedDescription)") }
        }
      }
    } else { throw CraftError.unsupported("Unsupported ABR version\(version).") }
    return try finish(presets,warnings,version)
  }
  static func finish(_ presets:[BrushPreset],_ warnings:[String],_ version:Int)throws->Imported {
    guard !presets.isEmpty else { throw CraftError.unsupported("No supported brush presets. \(warnings.prefix(5).joined(separator:" "))") };try BrushPresetFile(presets:presets).validate();return .init(presets:presets,warnings:Array(Set(warnings)).sorted(),version:version)
  }
  static func validateNumbers(_ d:PSDDescriptor)throws {
    func visit(_ value:PSDValue)throws {
      switch value {
      case .doubleBits(let bits),.unit(_,let bits):let n=Double(bitPattern:bits);guard n.isFinite,abs(n)<=1_000_000 else { throw CraftError.invalid("Invalid ABR numeric value.") }
      case .object(let obj),.globalObject(let obj):try validateNumbers(obj)
      case .list(let values):for v in values { try visit(v) }
      default:break
      }
    }
    guard Set(d.items.map{$0.key.text}).count==d.items.count else { throw CraftError.invalid("Duplicate ABR descriptor key.") }
    for item in d.items { try visit(item.value) }
  }
  static func dynamic(_ d:PSDDescriptor?)->BrushDynamic {
    guard let d else { return .init() };var v=BrushDynamic();v.jitter=number(d,"jitter")/100;v.minimum=number(d,"Mnm ")/100;v.fadeSteps=Int(number(d,"fStp",25))
    let controls:[BrushControl]=[.off,.fade,.penPressure,.penTilt,.stylusWheel,.initialDirection,.direction,.rotation,.rotation],n=number(d,"bVTy")
    if n.isFinite,n>=0,n<Double(controls.count) { v.control=controls[Int(n)] };return v
  }
  static func mask(_ name:String?)->BrushMaskMode? {
    let map:[String:BrushMaskMode] = ["Mltp":.multiply,"Sbtr":.subtract,"Drkn":.darken,"Ovrl":.overlay,"CDdg":.colorDodge,"CBrn":.colorBurn,"linearBurn":.linearBurn,"hardMix":.hardMix,"linearHeight":.linearHeight,"height":.height,"Hght":.height]
    return name.flatMap{map[$0] ?? BrushMaskMode(rawValue:$0)}
  }
  static func tip(_ d:PSDDescriptor,samples:[String:BrushBitmap])throws->Brush {
    var b=Brush();b.color = .black;b.settings = .init()
    if d.classID.text=="sampledBrush" || d["sampledData"] != nil {
      guard let id=text(d,"sampledData"),let bitmap=samples[id] else { throw CraftError.invalid("Sampled tip is missing.") };b.settings!.tip=bitmap;b.size=Double(max(bitmap.width,bitmap.height))
    } else { guard ["computedBrush","Brsh"].contains(d.classID.text) else { throw CraftError.unsupported("Unsupported brush tip class \(d.classID.text).") } }
    b.size=number(d,"Dmtr",b.size);b.hardness=Float(number(d,"Hrdn",100)/100);b.settings!.roundness=number(d,"Rndn",100)/100;b.settings!.angle=number(d,"Angl");b.settings!.spacing=number(d,"Spcn",25)/100;b.settings!.spacingEnabled=bool(d,"Intr",true);b.settings!.flipX=bool(d,"flipX");b.settings!.flipY=bool(d,"flipY");return b
  }
  static func decodePreset(_ d:PSDDescriptor,samples:[String:BrushBitmap],patterns:[RasterPattern],warnings:inout [String])throws->BrushPreset {
    guard let t=object(d,"Brsh") else { throw CraftError.invalid("Missing brush tip descriptor.") };var brush=try tip(t,samples:samples),b=brush.settings!
    b.shape.enabled=bool(d,"useTipDynamics");b.shape.size=dynamic(object(d,"szVr"));b.shape.angle=dynamic(object(d,"angleDynamics"));b.shape.roundness=dynamic(object(d,"roundnessDynamics"));b.shape.size.minimum=number(d,"minimumDiameter",b.shape.size.minimum*100)/100;b.shape.roundness.minimum=number(d,"minimumRoundness",b.shape.roundness.minimum*100)/100;b.shape.tiltScale=number(d,"tiltScale")/100;b.shape.projection=bool(d,"brushProjection");b.shape.flipX=bool(d,"flipX");b.shape.flipY=bool(d,"flipY")
    b.scattering.enabled=bool(d,"useScatter");b.scattering.amount=dynamic(object(d,"scatterDynamics"));b.scattering.count=Int(number(d,"Cnt ",1));b.scattering.countJitter=dynamic(object(d,"countDynamics"));b.scattering.bothAxes=bool(d,"bothAxes")
    b.texture.enabled=bool(d,"useTexture");b.texture.eachTip=bool(d,"TxtC");b.texture.scale=number(d,"textureScale",100)/100;b.texture.invert=bool(d,"InvT");b.texture.brightness=number(d,"textureBrightness")/150;b.texture.contrast=number(d,"textureContrast")/50;b.texture.depth=number(d,"textureDepth",100)/100;b.texture.depthJitter=dynamic(object(d,"textureDepthDynamics"));b.texture.depthJitter.minimum=number(d,"minimumDepth",b.texture.depthJitter.minimum*100)/100
    if let mode=enumeration(d,"textureBlendMode") { guard let mapped=mask(mode) else { throw CraftError.unsupported("Unsupported brush texture mode.") };b.texture.mode=mapped };b.protectTexture=bool(d,"protectTexture")
    if b.texture.enabled {
      guard let ref=object(d,"Txtr"),let pattern=patterns.first(where:{$0.id==text(ref,"Idnt") || $0.name==text(ref,"Nm  ")}) else { throw CraftError.unsupported("Brush texture pattern is not embedded.") }
      b.texture.bitmap = try BrushTexturePreparation.bitmap(pattern)
    }
    if let dual=object(d,"dualBrush"),bool(dual,"useDualBrush") {
      guard let t=object(dual,"Brsh") else { throw CraftError.invalid("Missing dual tip.") };let q=try tip(t,samples:samples);b.dual.enabled=true;b.dual.tip=q.settings!.tip;b.dual.size=q.size;b.dual.hardness=Double(q.hardness);b.dual.roundness=q.settings!.roundness;b.dual.angle=q.settings!.angle;b.dual.spacing=number(dual,"Spcn",q.settings!.spacing*100)/100;b.dual.scatter=dynamic(object(dual,"scatterDynamics")).jitter;b.dual.count=Int(number(dual,"Cnt ",1));b.dual.bothAxes=bool(dual,"bothAxes");b.dual.flip=bool(dual,"Flip");if let mode=enumeration(dual,"BlnM") { guard let mapped=mask(mode) else { throw CraftError.unsupported("Unsupported dual brush mode.") };b.dual.mode=mapped }
    }
    b.colorDynamics.enabled=bool(d,"useColorDynamics");b.colorDynamics.perTip=bool(d,"colorDynamicsPerTip",true);b.colorDynamics.foregroundBackground=dynamic(object(d,"clVr"));b.colorDynamics.hue=number(d,"H   ")/100;b.colorDynamics.saturation=number(d,"Strt")/100;b.colorDynamics.brightness=number(d,"Brgh")/100;b.colorDynamics.purity=number(d,"purity")/100
    b.transfer.enabled=bool(d,"usePaintDynamics");b.transfer.opacity=dynamic(object(d,"opVr"));b.transfer.flow=dynamic(object(d,"prVr"))
    b.pose.enabled=bool(d,"useBrushPose");b.pose.tiltX=number(d,"brushPoseTiltX")*0.9;b.pose.tiltY=number(d,"brushPoseTiltY")*0.9;b.pose.rotation=number(d,"brushPoseAngle");b.pose.pressure=number(d,"brushPosePressure",100)/100;b.pose.overrideTilt=bool(d,"overridePoseTiltX") || bool(d,"overridePoseTiltY");b.pose.overrideRotation=bool(d,"overridePoseAngle");b.pose.overridePressure=bool(d,"overridePosePressure")
    b.noise=bool(d,"Nose");b.wetEdges=bool(d,"Wtdg");b.buildUp=bool(d,"Rpt ")
    if let to=object(d,"toolOptions") {
      brush.opacity=Float(number(to,"Opct",100)/100);b.flow=number(to,"flow",100)/100;b.pressureSize=bool(to,"usePressureOverridesSize");b.pressureOpacity=bool(to,"usePressureOverridesOpacity");b.smoothing.amount=bool(to,"smoothing",true) ? number(to,"smoothingValue")/100:0;b.smoothing.pulledString=bool(to,"smoothingRadiusMode");b.smoothing.catchUp=bool(to,"smoothingCatchup",true);b.smoothing.catchUpOnEnd=bool(to,"smoothingCatchupAtEnd",true);b.smoothing.adjustForZoom=bool(to,"smoothingZoomCompensation",true)
      if let mode=enumeration(to,"Md  ") { guard let index=PSDLayerStyles.blends.firstIndex(of:mode) else { throw CraftError.unsupported("Unsupported stored brush blend mode.") };b.mode=BlendMode.allCases[index] }
      let known:Set<String>=["Opct","flow","usePressureOverridesSize","usePressureOverridesOpacity","smoothing","smoothingValue","smoothingRadiusMode","smoothingCatchup","smoothingCatchupAtEnd","smoothingZoomCompensation","Md  "]
      for item in to.items where !known.contains(item.key.text) { warnings.append("Unmapped brush tool option: \(item.key.text).") }
    }
    let known:Set<String>=["Nm  ","Brsh","useTipDynamics","flipX","flipY","brushProjection","minimumDiameter","minimumRoundness","tiltScale","szVr","angleDynamics","roundnessDynamics","useScatter","Spcn","Cnt ","bothAxes","countDynamics","scatterDynamics","dualBrush","brushGroup","useTexture","TxtC","textureBlendMode","textureDepth","minimumDepth","textureDepthDynamics","Txtr","textureScale","InvT","protectTexture","textureBrightness","textureContrast","usePaintDynamics","prVr","opVr","useColorDynamics","clVr","H   ","Strt","Brgh","purity","colorDynamicsPerTip","Wtdg","Nose","Rpt ","useBrushPose","overridePoseAngle","overridePoseTiltX","overridePoseTiltY","overridePosePressure","brushPosePressure","brushPoseTiltX","brushPoseTiltY","brushPoseAngle","toolOptions"]
    for item in d.items where !known.contains(item.key.text) { warnings.append("Unmapped brush preset field: \(item.key.text).") }
    brush.settings=b;var p=BrushPreset(name:text(d,"Nm  ") ?? "Imported Brush",brush:brush);p.includeToolSettings=object(d,"toolOptions") != nil;return p
  }
}
