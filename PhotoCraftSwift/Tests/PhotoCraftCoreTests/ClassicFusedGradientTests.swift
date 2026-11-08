import Foundation
import XCTest
@testable import PhotoCraftCore

final class ClassicFusedGradientTests: XCTestCase {
  struct Reference: Decodable {
    var name: String; var positions: [Int]; var midpoints: [Int]; var colors: [[Int]]
    var smoothness: Int; var expected: [[Int]]
    var gradient: GradientDefinition {
      .init(name:name,colors:positions.indices.map { i in
        let c=colors[i];return .init(Float(positions[i])/4096,.rgb(Pixel(Float(c[0])/32768,Float(c[1])/32768,Float(c[2])/32768)),midpoint:Float(midpoints[i])/100)
      },smoothness:Float(smoothness)/4096,method:.classic)
    }
  }
  func testFreshIndependentPhotoshopLinearAndCurvedRampsExactly() throws {
    let url=try XCTUnwrap(Bundle.module.url(forResource:"classic-fused486",withExtension:"json",subdirectory:"Fixtures"))
    let refs=try JSONDecoder().decode([Reference].self,from:Data(contentsOf:url))
    XCTAssertEqual(refs.count,3)
    for ref in refs {
      let transfer=try GradientMapTransfer(.init(gradient:ref.gradient),depth:.u16)
      var differences=0;var first:[Int]=[]
      for t in 0...4096 {
        let p=transfer.apply(Pixel(Float(t)/4096,Float(t)/4096,Float(t)/4096))
        for (c,v) in [p.r,p.g,p.b].enumerated() {
          if v.bitPattern != (Float(ref.expected[t][c])/32768).bitPattern {differences+=1;if first.count<8{first.append(t)}}
        }
        XCTAssertEqual(p.a,1)
      }
      XCTAssertEqual(differences,0,"\(ref.name): first \(first)")
    }
  }
}
