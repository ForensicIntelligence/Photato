import Foundation
import PhotoCraftCore

/// Original dialog values are Float32; source integer seeds use saturating i64
/// followed by truncation to u32. Unknown fields remain explicit import errors.
final class PcraftFilterParameters {
  let node:PcraftNode
  private var consumed:Set<String>=["layer"]
  init(_ node:PcraftNode)throws { self.node=node;if let id=node.optional("layer"){_ = try id.unsigned()} }
  func field(_ key:String)->PcraftNode? {consumed.insert(key);return node.optional(key)}
  func number(_ key:String,_ fallback:Float,_ range:ClosedRange<Float>?=nil)throws->Double {
    let x=try field(key)?.float() ?? fallback
    return Double(range.map{min($0.upperBound,max($0.lowerBound,x))} ?? x)
  }
  func integer(_ key:String,_ fallback:Int64,_ range:ClosedRange<Int64>?=nil)throws->Int64 {
    let result:Int64
    if let n=field(key) {
      if let exact=n.value.int {result=exact}
      else {let x=try n.double();if x>=Double(Int64.max){result=Int64.max}else if x<=Double(Int64.min){result=Int64.min}else{result=Int64(x.rounded())}}
    }else{result=fallback}
    return range.map{min($0.upperBound,max($0.lowerBound,result))} ?? result
  }
  func seed()throws->UInt32 {UInt32(truncatingIfNeeded:try integer("seed",0))}
  func string(_ key:String,_ fallback:String)throws->String {try field(key)?.string() ?? fallback}
  func flag(_ key:String,_ fallback:Bool)throws->Bool {try field(key)?.boolean() ?? fallback}
  func choice<T:RawRepresentable>(_ key:String,_ fallback:T)throws->T where T.RawValue==String {T(rawValue:try string(key,fallback.rawValue)) ?? fallback}
  func color(_ key:String,_ fallback:Pixel)throws->Pixel {
    guard let value=field(key) else{return fallback}
    if let text=value.value.string,text.count==7,text.first=="#",let rgb=UInt32(text.dropFirst(),radix:16){return Pixel(Float((rgb>>16)&255)/255,Float((rgb>>8)&255)/255,Float(rgb&255)/255,1)}
    let a=try value.array();guard (3...4).contains(a.count) else{throw value.invalid}
    return try Pixel(a[0].float(),a[1].float(),a[2].float(),a.count==4 ? a[3].float():1)
  }
  func finish()throws {try node.keys(consumed.sorted().joined(separator:" "))}
}
