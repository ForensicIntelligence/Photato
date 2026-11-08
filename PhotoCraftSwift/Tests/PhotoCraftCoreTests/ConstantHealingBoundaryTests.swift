import XCTest
@testable import PhotoCraftCore

final class ConstantHealingBoundaryTests: XCTestCase {
  func testHarmonicConstantBoundaryPreservesExactFiniteWordsAndKnownSamples() throws {
    let words: [UInt32] = [0,0x80000000,1,0x00800001,0x3d506876,0x3e000001,0x3f000003,0xc1000003,0x41800001,0x537fffff]
    for width in [7,32] {
      let height = width+1
      let unknown = (0..<width*height).map { i in i%width > 1 && i%width < width-2 && i/width > 1 && i/width < height-2 }
      for word in words {
        let constant = Float(bitPattern:word)
        let values = unknown.map { $0 ? Float(1234):constant }
        let output = try HealingSolver.membrane(width:width,height:height,unknown:unknown,values:values)
        XCTAssertEqual(output.map(\.bitPattern),[UInt32](repeating:word,count:output.count),"\(width) word\(word)")
      }
    }
    let allUnknown = [true,true,true,true]
    let original: [Float] = [1,2,3,4]
    XCTAssertEqual(try HealingSolver.membrane(width:2,height:2,unknown:allUnknown,values:original),original)
  }
  func testContentAwareUniformDonorRetainsRGBAWordsThroughColorAdaptation() throws {
    let width = 24,height = 24,count = width*height
    let hole = (0..<count).map { i in (9..<15).contains(i%width) && (9..<15).contains(i/width) }
    let source = hole.map { !$0 }
    let fields: [[Float]] = [[Float(bitPattern:0x3d506876),0.25,0.5,1],
      [Float(bitPattern:0xc1000003),Float(bitPattern:0x41800001),Float(bitPattern:0x3e000001),0.75]]
    for field in fields {
      var image = (0..<count).flatMap { _ in field }
      for i in hole.indices where hole[i] { for c in 0..<3 { image[i*4+c] = Float(c+10) } }
      let expected = (0..<count).flatMap { _ in field }.map(\.bitPattern)
      for adaptation in ContentAwareSettings.ColorAdaptation.allCases {
        var settings = ContentAwareSettings(); settings.colorAdaptation = adaptation
        let result = try ContentAwareSynthesis.fill(width:width,height:height,image:image,hole:hole,source:source,settings:settings,hdr:true)
        let differences = zip(result.map(\.bitPattern),expected).enumerated().compactMap { i,pair in
          pair.0 == pair.1 ? nil:"\(i):\(pair.0)≠\(pair.1)"
        }
        XCTAssertEqual(differences.count,0,"\(adaptation): \(differences.prefix(8))")
      }
    }
  }
}
