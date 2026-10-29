import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class OnionSkinTests:XCTestCase {
  func document(depth:PixelDepth = .u8)throws->CraftDocument {
    let colors:[Pixel]=[Pixel(1,0,0),Pixel(0,1,0),Pixel(0,0,1)]
    let frames=try colors.enumerated().map { i,color in
      var s=try Surface(width:12,height:4,depth:depth,fill:.clear)
      for y in 0..<4{for x in i*4..<i*4+4{s.setPixel(x:x,y:y,color)}};return s
    }
    var d=try CraftDocument(width:12,height:4,depth:depth);d.layers[0].video=VideoClip(frames:frames,frameRate:4)
    d.videoTimeline = .init(frameRate:4,durationFrames:3);try d.selectVideoFrame(1)
    d.videoTimeline!.onionSkin = .init(enabled:true,blendMode:.normal);return d
  }
  func testGhostAlphaAndCurrentFrameAcrossDepthsWithoutChangingExport()throws {
    for depth in [PixelDepth.u8,.u16,.f32] {
      let d=try document(depth:depth),ordinary=try Renderer.composite(d),preview=try OnionSkinRenderer.render(d)
      XCTAssertEqual(ordinary.pixel(x:1,y:1),.clear);XCTAssertEqual(ordinary.pixel(x:9,y:1),.clear)
      XCTAssertEqual(preview.pixel(x:1,y:1),Pixel(1,0,0,0.5));XCTAssertEqual(preview.pixel(x:5,y:1),Pixel(0,1,0));XCTAssertEqual(preview.pixel(x:9,y:1),Pixel(0,0,1,0.5))
      XCTAssertEqual(try Renderer.composite(d),ordinary)
      var disabled=d;disabled.videoTimeline!.onionSkin!.enabled=false;XCTAssertEqual(try OnionSkinRenderer.render(disabled),ordinary)
    }
  }
  func testOpacityBlendModesAndBoundaryFrames()throws {
    var d=try document();for i in d.layers[0].video!.frames.indices{d.layers[0].video!.frames[i]=try Surface(width:12,height:4,fill:Pixel(i==0 ? 1:0,i==1 ? 1:0,i==2 ? 1:0))};try d.selectVideoFrame(1)
    let preview=try OnionSkinRenderer.render(d);XCTAssertEqual(preview.pixel(x:0,y:0),Pixel(0.25,0.25,0.5))
    d.videoTimeline!.onionSkin!.blendMode = .multiply;XCTAssertEqual(try OnionSkinRenderer.render(d).pixel(x:0,y:0),Pixel(0,0.25,0))
    try d.selectVideoFrame(0);d.videoTimeline!.onionSkin!.blendMode = .normal
    XCTAssertEqual(try OnionSkinRenderer.render(d).pixel(x:0,y:0),Pixel(0.5,0.5,0))
  }
  func testWorkAreaVideoExportAndRationalPlan()throws {
    var d=try document();d.videoTimeline!.workArea = .init(startFrame:1,endFrame:3)
    let plan=try VideoRenderOptions(codec:.uncompressed,useWorkArea:true).plan(for:d)
    XCTAssertEqual(plan.sourceStart,0.25);XCTAssertEqual(plan.frameCount,2);XCTAssertEqual(plan.duration,0.5)
    XCTAssertThrowsError(try VideoRenderOptions(firstFrame:1,useWorkArea:true).plan(for:d))
    let output=try VideoRender.render(d,options:.init(codec:.uncompressed,preserveAlpha:true,useWorkArea:true));defer{output.discard()}
    let movie=try MovieIO.read(output.url),frames=try XCTUnwrap(movie.layers[0].video?.frames);XCTAssertEqual(frames.count,2)
    XCTAssertEqual(frames[0].pixel(x:1,y:1),.clear);XCTAssertEqual(frames[0].pixel(x:5,y:1).g,1);XCTAssertEqual(frames[1].pixel(x:9,y:1).b,1)
    if let root=ProcessInfo.processInfo.environment["PHOTATO_WORKSPACE_OUTPUT_DIR"]{try output.publish(to:URL(fileURLWithPath:root).appendingPathComponent("work-area.mov"))}
  }
  func testCancellationAndInvalidBaseAreRejected()async throws {
    let d=try document();XCTAssertThrowsError(try OnionSkinRenderer.render(d,base:Surface(width:1,height:1)))
    let worker=Task.detached{while !Task.isCancelled{await Task.yield()};return try OnionSkinRenderer.render(d)};worker.cancel()
    do{_=try await worker.value;XCTFail("Cancelled onion preview succeeded")}catch is CancellationError{}
  }
}
