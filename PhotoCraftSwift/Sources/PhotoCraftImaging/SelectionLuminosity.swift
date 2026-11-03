import Foundation
import PhotoCraftCore

/// RGB composite selection uses profile-defined luminosity, not fixed RGB
/// weights. Matrix/shaper profiles are evaluated directly from the public ICC
/// representation so the sample result is independent of ColorSync LUT fitting.
enum ICCSelectionMatrix {
  enum Unrepresented:Error {case profile}
  enum Curve:Sendable {
    case identity,gamma(Double),table([Double]),parametric(Int,[Double])
    func forward(_ raw:Double)->Double {
      if case .identity=self {return raw}
      let x=min(1,max(0,raw))
      switch self {
      case .identity:return x
      case .gamma(let g):return pow(x,g)
      case .table(let values):
        let t=x*Double(values.count-1),i=min(Int(t),values.count-2),f=t-Double(i)
        return values[i]*(1-f)+values[i+1]*f
      case .parametric(let type,let p):
        let g=p[0]
        if type==0{return pow(x,g)}
        let a=p[1],b=p[2]
        if type==1{return x >= -b/a ? pow(max(0,a*x+b),g):0}
        if type==2{return (x >= -b/a ? pow(max(0,a*x+b),g):0)+p[3]}
        if type==3{return x>=p[4] ? pow(max(0,a*x+b),g):p[3]*x}
        return x>=p[4] ? pow(max(0,a*x+b),g)+p[5]:p[3]*x+p[6]
      }
    }
    func inverse(_ raw:Double)->Double {
      let x=min(1,max(0,raw))
      switch self {
      case .identity:return x
      case .gamma(let g):return pow(x,1/g)
      case .table(let values):
        if x<=values[0]{return 0};if x>=values.last!{return 1}
        var low=0,high=values.count-1
        while high-low>1 {let middle=(low+high)/2;if values[middle]<=x{low=middle}else{high=middle}}
        let span=values[high]-values[low]
        return (Double(low)+(span>0 ? (x-values[low])/span:0))/Double(values.count-1)
      case .parametric:
        var low=0.0,high=1.0
        for _ in 0..<48 {let middle=(low+high)*0.5;if forward(middle)<=x{low=middle}else{high=middle}}
        return (low+high)*0.5
      }
    }
  }
  struct Profile {
    let data:Data
    let tags:[String:Range<Int>]
    init(_ data:Data,mode:DocumentColorMode)throws {
      try NativeModeProfile.validate(data,mode:mode,depth:.u16)
      self.data=data
      guard String(decoding:data[20..<24],as:UTF8.self)=="XYZ " else{throw Unrepresented.profile}
      let count=Self.u32(data,128);var ranges:[String:Range<Int>]=[:]
      for i in 0..<count {
        let at=132+i*12,key=String(decoding:data[at..<at+4],as:UTF8.self),start=Self.u32(data,at+4),size=Self.u32(data,at+8)
        ranges[key]=start..<start+size
      }
      guard !["A2B0","A2B1","A2B2","B2A0","B2A1","B2A2"].contains(where:{ranges[$0] != nil}) else{throw Unrepresented.profile}
      tags=ranges
    }
    static func u32(_ data:Data,_ at:Int)->Int {data[at..<at+4].reduce(0){($0<<8)|Int($1)}}
    static func u16(_ data:Data,_ at:Int)->Int {Int(data[at])<<8|Int(data[at+1])}
    static func fixed(_ data:Data,_ at:Int)->Double {Double(Int32(bitPattern:UInt32(u32(data,at))))/65536}
    func xyz(_ name:String)throws->[Double] {
      guard let range=tags[name],range.count>=20,String(decoding:data[range.lowerBound..<range.lowerBound+4],as:UTF8.self)=="XYZ " else{throw Unrepresented.profile}
      return [8,12,16].map{Self.fixed(data,range.lowerBound+$0)}
    }
    func curve(_ name:String)throws->Curve {
      guard let range=tags[name],range.count>=12 else{throw Unrepresented.profile}
      let at=range.lowerBound,kind=String(decoding:data[at..<at+4],as:UTF8.self)
      let result:Curve
      if kind=="curv" {
        let count=Self.u32(data,at+8)
        guard count<=(range.count-12)/2 else{throw CraftError.invalid("Truncated selection tone curve.")}
        if count==0 {result = .identity}
        else if count==1 {
          let gamma=Double(Self.u16(data,at+12))/256
          guard gamma>0 else{throw CraftError.invalid("Invalid selection profile gamma.")}
          result=gamma==1 ? .identity:.gamma(gamma)
        } else {
          let values=(0..<count).map{Double(Self.u16(data,at+12+$0*2))/65535}
          guard zip(values,values.dropFirst()).allSatisfy({$0<=$1}) else{throw Unrepresented.profile}
          result = .table(values)
        }
      } else if kind=="para" {
        let type=Self.u16(data,at+8),counts=[1,3,4,5,7]
        guard counts.indices.contains(type),range.count>=12+counts[type]*4 else{throw Unrepresented.profile}
        let p=(0..<counts[type]).map{Self.fixed(data,at+12+$0*4)}
        guard p[0]>0,(type==0 || p[1]>0) else{throw CraftError.invalid("Invalid parametric selection curve.")}
        result=type==0 && p[0]==1 ? .identity:.parametric(type,p)
      } else {throw Unrepresented.profile}
      let probes=(0...256).map{result.forward(Double($0)/256)}
      guard probes.allSatisfy(\.isFinite),zip(probes,probes.dropFirst()).allSatisfy({$0<=$1}) else{throw Unrepresented.profile}
      return result
    }
    func hasZeroBlackPoint()throws->Bool {try tags["bkpt"] == nil || xyz("bkpt").allSatisfy{abs($0)<1.0/65536}}
  }
  struct Transform:Sendable {
    let rgb:[Curve],gray:Curve,y:[Double]
    init(_ source:Data,_ destination:Data,intent:ModeRenderingIntent,bpc:Bool)throws {
      guard intent != .absoluteColorimetric else{throw Unrepresented.profile}
      let a=try Profile(source,mode:.rgb),b=try Profile(destination,mode:.grayscale)
      rgb=try ["rTRC","gTRC","bTRC"].map{try a.curve($0)};gray=try b.curve("kTRC")
      y=try ["rXYZ","gXYZ","bXYZ"].map{try a.xyz($0)[1]}
      guard y.allSatisfy(\.isFinite),y.allSatisfy({$0>=0}),y.reduce(0,+)>0 else{throw Unrepresented.profile}
      if bpc {guard try a.hasZeroBlackPoint(),try b.hasZeroBlackPoint(),rgb.allSatisfy({abs($0.forward(0))<1.0/65536}),abs(gray.forward(0))<1.0/65536 else{throw Unrepresented.profile}}
    }
    func apply(_ p:Pixel)->Float {
      let value=rgb[0].forward(Double(p.r))*y[0]+rgb[1].forward(Double(p.g))*y[1]+rgb[2].forward(Double(p.b))*y[2]
      return Float(gray.inverse(value))
    }
  }
}

public enum SelectionLuminosity {
  public static func coverage(in document:CraftDocument,settings:ColorSettings = .init())throws->Surface {
    var source=ChannelArithmeticSource(documentID:document.id)
    if document.colorMode == .grayscale || document.colorMode == .duotone {
      source.channel = .component(0)
      return try ChannelArithmeticPreparation.input(source,destination:document,sources:[]).samples
    }
    source.channel = .composite
    let input=try ChannelArithmeticPreparation.input(source,destination:document,sources:[])
    let from=try ColorProfileInput.effectiveProfile(document),to=try settings.profile(.grayscale,depth:document.depth)
    if try FactorySelectionTransfer.supports(document,settings:settings,source:from,gray:to) {
      let table=try FactorySelectionTransfer.shared.get()
      return try input.samples.mappedStoredSamples(encoding:.sRGB) {p in let v=FactorySelectionTransfer.coverage(p,table:table);return Pixel(v,v,v)}
    }
    if document.colorMode == .rgb {
      do {
        let transform=try ICCSelectionMatrix.Transform(from,to,intent:settings.intent,bpc:settings.blackPointCompensation)
        return try input.samples.mappedStoredSamples(encoding:.sRGB) {p in let v=transform.apply(p);return Pixel(v,v,v)}
      } catch ICCSelectionMatrix.Unrepresented.profile {
        // CLUT/absolute/black-point profiles still use their actual profile,
        // through native ColorSync. Their exact Photoshop CMM fidelity is open.
      }
    }
    let transform=try ProofTransform(from,to,intent:settings.intent,bpc:settings.blackPointCompensation)
    return try input.samples.mappedStoredSamples(encoding:.sRGB) {p in
      var values=input.components==1 ? [p.r]:input.components==4 ? [p.r,p.g,p.b,p.a]:[p.r,p.g,p.b]
      if document.colorMode == .cmyk {values=values.map{1-$0}}
      if document.colorMode == .lab {values[1] *= 255/256;values[2] *= 255/256}
      let v=unit(try transform.apply(values)[0]);return Pixel(v,v,v)
    }
  }
}
