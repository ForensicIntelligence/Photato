import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class LegacyImageStackCaptureTests:XCTestCase {
  func source(_ depth:PixelDepth,variant:Int)throws->CraftDocument {
    var d=try CraftDocument(width:12,height:8,depth:depth);d.layers=[]
    for i in 0..<5 {
      var pixels=try Surface(width:12,height:8,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
      for y in 0..<8{for x in 0..<12{
        let p=Pixel(Float((x*17+y*29+i*31)%257)/128,Float((x*43+y*11+i*7)%257)/256,Float((x*3+y*5+i*47)%257)/256,Float((x+y+i)%5)/4)
        if depth == .f32{pixels.setLinearPixel(x:x,y:y,p)}else{pixels.setPixel(x:x,y:y,p)}
      }}
      var layer=Layer(name:"Owned frame\(i)",content:.raster(pixels))
      if variant==1 && i==2{layer.visible=false}
      if variant==1 && i==0{layer.mask=try Surface(width:12,height:8,depth:depth,fill:Pixel(0.5,0.5,0.5))}
      d.layers.append(layer)
    }
    d.activeLayerID=d.layers.last?.id
    if variant==2{try Command.groupLayers(d.layers.map(\.id),"Owned outer group").apply(to:&d)}
    return d
  }
  func words(_ surface:Surface,depth:PixelDepth)throws->Data {
    var bytes=Data()
    for y in 0..<surface.height{for x in 0..<surface.width{
      let p=depth == .f32 ? surface.linearPixel(x:x,y:y):surface.pixel(x:x,y:y)
      for v in [p.r,p.g,p.b,p.a]{var word=v.bitPattern.littleEndian;withUnsafeBytes(of:&word){bytes.append(contentsOf:$0)}}
    }}
    return bytes
  }
  func testCaptureAllStackModesDepthsVisibilityMasksAndOuterGroups()throws {
    var bytes=Data(),cases=[[String:Any]]()
    for depth in PixelDepth.allCases{for variant in 0..<3{for mode in ImageStackMode.allCases{
      let d=try source(depth,variant:variant),result=try ImageStack.render(d,mode:mode,in:d),data=try words(result,depth:depth)
      cases.append(["mode":mode.rawValue,"depth":depth.rawValue,"variant":variant,"offset":bytes.count,"bytes":data.count]);bytes.append(data)
    }}}
    XCTAssertEqual(cases.count,99);XCTAssertEqual(bytes.count,152064)
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]{
      let folder=URL(fileURLWithPath:path)
      try bytes.write(to:folder.appendingPathComponent("image-stack-small.f32le"))
      try JSONSerialization.data(withJSONObject:cases,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("image-stack-cases.json"))
    }
  }
}
