import Foundation
import ImageIO
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class AnimationGIFTests: XCTestCase {
  var fixture: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/animation/owned-disposal.gif") }
  func source() throws -> CraftDocument { try AnimationGIF.read(Data(contentsOf: fixture), name: "Owned disposal") }
  func testIndependentPartialFramesTransparencyDisposalTimingAndLoops() throws {
    let d = try source(), a = try XCTUnwrap(d.animation)
    XCTAssertEqual(a.frames.count,4); XCTAssertEqual(a.loopCount,3)
    for (f,delay) in zip(a.frames,[0.03,0.07,0.11,0]) { XCTAssertEqual(f.delay,delay,accuracy:0.000001) }
    let images = try a.frames.map { try Renderer.composite(d.animationDocument(at:$0.id)) }
    for y in 0..<3 { for x in 0..<4 { XCTAssertEqual(images[0].pixel(x:x,y:y),Pixel(1,0,0)) } }
    XCTAssertEqual(images[1].pixel(x:1,y:1),Pixel(0,1,0))
    XCTAssertEqual(images[1].pixel(x:2,y:1),Pixel(1,0,0),"Transparent pixel retains previous frame")
    XCTAssertEqual(images[2].pixel(x:1,y:1),Pixel(1,0,0),"Disposal3 restores previous composition")
    XCTAssertEqual(images[2].pixel(x:0,y:0),Pixel(0,0,1))
    XCTAssertEqual(images[3].pixel(x:0,y:0),.clear,"Disposal2 clears only the previous rectangle")
    XCTAssertEqual(images[3].pixel(x:3,y:2),Pixel(0,1,0))
    XCTAssertEqual(images[3].pixel(x:2,y:2),Pixel(1,0,0))
    XCTAssertEqual(try RasterIO.read(Data(contentsOf:fixture)).animation?.frames.count,4)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)),d)
  }
  func testGIFExportPreservesEveryCompositeAndLoopVariantsAndZeroDelay() throws {
    var d = try source()
    for loops in [0,1,3,65_535] {
      d.animation!.loopCount = loops
      let bytes = try AnimationGIF.encode(d), read = try AnimationGIF.read(bytes,name:d.name)
      XCTAssertEqual(read.animation?.loopCount,loops)
      for (frame,out) in zip(d.animation!.frames,read.animation!.frames) {
        XCTAssertEqual(frame.delay,out.delay,accuracy:0.000001)
        XCTAssertEqual(try Renderer.composite(d.animationDocument(at:frame.id)),try Renderer.composite(read.animationDocument(at:out.id)))
      }
      if let directory = ProcessInfo.processInfo.environment["PHOTATO_ANIMATION_OUTPUT_DIR"] {
        try bytes.write(to:URL(fileURLWithPath:directory).appendingPathComponent("export-loop-\(loops).gif"))
      }
    }
  }
  func testExplicitBinaryAlphaAndCentisecondRounding() throws {
    var d = try CraftDocument(width:2,height:1)
    var pixels = try Surface(width:2,height:1);pixels.setPixel(x:0,y:0,Pixel(1,0,0,0.3));pixels.setPixel(x:1,y:0,.clear)
    let l = Layer(name:"Alpha",content:.raster(pixels));d.layers=[l];d.activeLayerID=l.id
    d.animation = FrameAnimation(layers:d.layers);d.animation!.frames[0].delay=0.034
    let standard = try AnimationGIF.read(AnimationGIF.encode(d),name:"Default")
    XCTAssertEqual(try Renderer.composite(standard).pixel(x:0,y:0).a,0)
    let low = try AnimationGIF.read(AnimationGIF.encode(d,alphaThreshold:0.2),name:"Low")
    XCTAssertEqual(try Renderer.composite(low).pixel(x:0,y:0),Pixel(1,0,0))
    XCTAssertEqual(try Renderer.composite(low).pixel(x:1,y:0),.clear)
    let s=try XCTUnwrap(CGImageSourceCreateWithData(try AnimationGIF.encode(d) as CFData,nil))
    let props=try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(s,0,nil) as? [CFString:Any])
    let gif=try XCTUnwrap(props[kCGImagePropertyGIFDictionary] as? [CFString:Any])
    XCTAssertEqual(try XCTUnwrap(gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double),0.03,accuracy:0.000001)
  }
  func testMalformedMemoryLimitAndUnsupportedDelayReject() throws {
    let bytes=try Data(contentsOf:fixture)
    XCTAssertThrowsError(try AnimationGIF.read(bytes,name:"Too large",rasterByteLimit:1))
    XCTAssertThrowsError(try AnimationGIF.read(Data(bytes.prefix(25)),name:"Truncated"))
    var d=try source();d.animation!.frames[0].delay=656
    XCTAssertThrowsError(try AnimationGIF.encode(d))
    XCTAssertThrowsError(try AnimationGIF.encode(source(),alphaThreshold:Double.nan))
    XCTAssertThrowsError(try AnimationGIF.encode(CraftDocument(width:2,height:2)))
    var huge=bytes;huge[6]=255;huge[7]=255
    XCTAssertThrowsError(try AnimationGIF.read(huge,name:"Invalid dimensions"))
  }
  func testCancelledEncodingStopsBeforeRendering() async throws {
    let d=try source()
    let task=Task { try Task.checkCancellation(); return try AnimationGIF.encode(d) }
    task.cancel()
    do { _=try await task.value;XCTFail("Cancelled export completed") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
  }
}
