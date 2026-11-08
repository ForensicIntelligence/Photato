import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class LegacySoftProofCaptureTests:XCTestCase {
  func fixture(_ depth:PixelDepth,mode:DocumentColorMode?,width:Int=12,height:Int=8)throws->CraftDocument {
    var d=try CraftDocument(width:width,height:height,depth:depth,name:"Owned proof samples")
    var pixels=try Surface(width:width,height:height,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
    for y in 0..<height {for x in 0..<width {
      let r=Float((x*37+y*11)%257)/256,g=Float((x*17+y*23)%257)/256,b=Float((x*5+y*43)%257)/256,a=Float((x+y)%5)/4
      if depth == .f32{pixels.setLinearPixel(x:x,y:y,Pixel(r*1.5,g,b,a))}else{pixels.setPixel(x:x,y:y,Pixel(r,g,b,a))}
    }}
    d.layers[0].content = .raster(pixels)
    if let mode{d=try d.convertingMode(.init(mode:mode,depth:depth))}
    return d
  }
  func programs()throws->[(CraftDocument,ProofSettings)] {
    var result=[(CraftDocument,ProofSettings)]()
    for depth in PixelDepth.allCases {
      let modes:[DocumentColorMode?]=[nil,.rgb,.grayscale]+(depth == .f32 ? []:[.cmyk,.lab])
      for mode in modes {
        let d=try fixture(depth,mode:mode)
        for kind in 0..<8 {
          var p=ProofSettings();p.enabled=true
          switch kind {
          case 0:p.device = .sRGB
          case 1:p.simulateBlack=true
          case 2:p.simulatePaper=true;p.simulateBlack=true
          case 3:p.intent = .perceptual
          case 4:p.enabled=false;p.gamutWarning=true;p.warningColor=Pixel(1,0,1);p.warningOpacity=0.37
          case 5:p.gamutWarning=true;p.warningColor=Pixel(0,1,1);p.warningOpacity=0.5
          case 6:p.plate = .cyan
          default:
            if let native=d.layers[0].nativeMode {p.device = .custom;p.profile=native.profile;p.profileName="Owned same mode";p.preserveNumbers=true}
            else{p.plate = .cmy}
          }
          result.append((d,p))
        }
      }
    }
    return result
  }
  func words(_ value:Surface)throws->Data {
    var data=Data()
    for y in 0..<value.height{for x in 0..<value.width{
      let p=value.pixel(x:x,y:y)
      for v in [p.r,p.g,p.b,p.a] {var word=v.bitPattern.littleEndian;withUnsafeBytes(of:&word){data.append(contentsOf:$0)}}
    }}
    return data
  }
  func testCaptureUnchangedSmallProofProgramsAcrossModesDepthsAndConditions()throws {
    var data=Data(),cases=[[String:Any]]()
    for(index,program)in try programs().enumerated(){
      let(d,p)=program,before=d,result=try SoftProof.surface(d,settings:p),bytes=try words(result)
      cases.append(["index":index,"depth":d.depth.rawValue,"mode":d.colorMode.rawValue,"native":d.hasNativeModeStorage,"offset":data.count,"bytes":bytes.count]);data.append(bytes)
      XCTAssertEqual(d,before)
    }
    XCTAssertEqual(cases.count,104);XCTAssertEqual(data.count,159744)
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]{
      let folder=URL(fileURLWithPath:path)
      try data.write(to:folder.appendingPathComponent("soft-proof-small.f32le"))
      try JSONSerialization.data(withJSONObject:cases,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("soft-proof-cases.json"))
    }
  }
  func testCapturedProofRemainsDisplayOnlyAndAreaReductionUsesProofedColors()throws {
    let d=try fixture(.u16,mode:nil),before=try NativeArchive.encodeChunked(d)
    var p=ProofSettings();p.enabled=true;p.gamutWarning=true;p.warningColor=Pixel(1,0,1)
    let proof=try SoftProof.surface(d,settings:p),small=try RasterPreviewRequest(region:.init(x:1,y:1,width:10,height:6),width:5,height:3).reducing(proof)
    XCTAssertEqual(try NativeArchive.encodeChunked(d),before)
    XCTAssertEqual(small.width,5);XCTAssertEqual(small.height,3)
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]{try words(small).write(to:URL(fileURLWithPath:path).appendingPathComponent("soft-proof-reduced.f32le"))}
  }
}
