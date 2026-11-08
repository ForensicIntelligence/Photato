import Foundation
import PhotoCraftCore

extension OpenEXR {
  /// IEEE754 binary16 conversion in Swift on both Intel and Apple Silicon.
  /// Round to nearest, ties to even; Float16 itself is unavailable on Intel.
  static func halfValue(_ bits:UInt16)->Float {
    let sign=UInt32(bits & 0x8000)<<16,exponent=Int((bits>>10)&31),fraction=UInt32(bits&1023)
    if exponent==0 {
      if fraction==0{return Float(bitPattern:sign)}
      var f=fraction,e = -14
      while f<1024 {f <<= 1;e -= 1}
      return Float(bitPattern:sign|UInt32(e+127)<<23|(f&1023)<<13)
    }
    if exponent==31{return Float(bitPattern:sign|0x7f800000|fraction<<13)}
    return Float(bitPattern:sign|UInt32(exponent+112)<<23|fraction<<13)
  }
  static func halfBits(_ value:Float)throws->UInt16 {
    let bits=value.bitPattern,sign=UInt16((bits>>16)&0x8000),fraction=bits&0x7fffff
    var exponent=Int((bits>>23)&255)-127
    guard value.isFinite,exponent<=15 else{throw CraftError.invalid("OpenEXR sample overflows Half precision; choose32-bit Float.")}
    if exponent >= -14 {
      var rounded=fraction+4095+((bits>>13)&1)
      if rounded>=0x800000 {rounded=0;exponent += 1}
      guard exponent<=15 else{throw CraftError.invalid("OpenEXR sample overflows Half precision; choose32-bit Float.")}
      return sign|UInt16(exponent+15)<<10|UInt16(rounded>>13)
    }
    if exponent < -25 {return sign}
    let shift = -exponent-1,significand=fraction|0x800000
    var rounded=significand>>shift
    let remainder=significand&((UInt32(1)<<shift)-1),halfway=UInt32(1)<<(shift-1)
    if remainder>halfway || (remainder==halfway && rounded&1==1) {rounded += 1}
    return sign|UInt16(rounded)
  }
}
