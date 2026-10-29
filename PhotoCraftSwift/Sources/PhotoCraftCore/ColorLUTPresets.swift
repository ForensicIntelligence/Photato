import Foundation

/// Generated PhotoCraft looks, explicitly dedicated to CC0 by cms/lutfile.rs.
/// These are Photato presets; no Adobe preset assets are bundled.
public enum ColorLUTPreset: String, CaseIterable, Sendable {
  case warm, cool, tealOrange, bleachBypass, fadedFilm, dayForNight, monoContrast, crossProcess
  public var title: String {
    switch self {
    case .warm: "Warm"; case .cool: "Cool"; case .tealOrange: "Teal & Orange"
    case .bleachBypass: "Bleach Bypass"; case .fadedFilm: "Faded Film"
    case .dayForNight: "Day for Night"; case .monoContrast: "Mono High Contrast"; case .crossProcess: "Cross Process"
    }
  }
  public func makeLUT() throws -> ColorLUT {
    func smooth(_ x: Float) -> Float { let x = min(1,max(0,x)); return x*x*(3-2*x) }
    return try ColorLUT.generated(title:title,size:33) { c in
      let l = c.x*0.299+c.y*0.587+c.z*0.114
      var result = SIMD3<Float>.zero
      switch self {
      case .warm: result = SIMD3(c.x*0.92+0.08,c.y*0.97+0.02,c.z*0.85)
      case .cool: result = SIMD3(c.x*0.86,c.y*0.97+0.01,c.z*0.9+0.1)
      case .tealOrange:
        let t = smooth(l), tint = SIMD3<Float>(0,0.5,0.55)*(1-t)+SIMD3<Float>(1,0.62,0.3)*t
        for k in 0..<3 { result[k] = c[k]*0.75+min(1,tint[k]*l*1.1)*0.25+(smooth(c[k])-c[k])*0.3 }
      case .bleachBypass: result = (c*0.45+SIMD3(repeating:l*0.55))*0.5+SIMD3(repeating:smooth(l)*0.5)
      case .fadedFilm: result = (SIMD3(repeating:0.08)+(c*0.8+SIMD3(repeating:l*0.2))*0.84)*SIMD3(1,0.96,0.88)+SIMD3(repeating:0.02)
      case .dayForNight: result = SIMD3(l*0.35,l*0.45+c.y*0.05,l*0.65+c.z*0.15)
      case .monoContrast: result = SIMD3(repeating:smooth(smooth(l)))
      case .crossProcess: result = SIMD3(smooth(c.x)*1.05,c.y*1.1-0.03,c.z*0.7+0.15)
      }
      return SIMD3(min(1,max(0,result.x)),min(1,max(0,result.y)),min(1,max(0,result.z)))
    }
  }
}
