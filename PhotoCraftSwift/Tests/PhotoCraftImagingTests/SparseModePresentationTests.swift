import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class SparseModePresentationTests: XCTestCase {
  func testSparseProjectionMatchesPriorDenseNumericalAlgorithm() throws {
    for mode in DocumentColorMode.componentModes {for depth in mode.depths {
      var d = try DocumentCreation.blank(width:65,height:65,depth:depth,background:Pixel(0.2,0.4,0.6,0.5),mode:mode)
      if d.layers[0].nativeMode == nil {d = try d.convertingMode(.init(mode:mode,depth:depth))}
      var native = try XCTUnwrap(d.layers[0].nativeMode)
      try native.set(0.125,component:0,index:4224);try native.set(0,component:mode.componentCount,index:0)
      d.layers[0].nativeMode=native;d.layers[0].content = .raster(try native.surface())
      let all = Set(0..<mode.componentCount)
      for mask in 1..<(1<<mode.componentCount) {
        let visible=Set((0..<mode.componentCount).filter {mask & (1<<$0) != 0})
        if visible == all && all.count > 1 {continue}
        var proxy=d;proxy.modeDescriptor=nil;proxy.workingICC=nil
        if visible.count==1,let c=visible.first {
          var plane=try Surface(width:65,height:65,depth:depth)
          for y in 0..<65 {for x in 0..<65 {
            let i=y*65+x,sample=native.value(component:c,index:i),gray=mode == .cmyk ? 1-sample:sample
            plane.setPixel(x:x,y:y,Pixel(gray,gray,gray,native.value(component:mode.componentCount,index:i)))
          }}
          proxy.layers[0].nativeMode=nil;proxy.layers[0].content = .raster(plane)
        } else {
          var hidden=native
          for c in all.subtracting(visible) {for i in 0..<4225 {try hidden.set(mode == .lab && c != 0 ? 128/255:0,component:c,index:i)}}
          proxy.layers[0].nativeMode=nil;proxy.layers[0].content = .raster(try hidden.surface())
        }
        XCTAssertEqual(try ModeChannelPresentation.surface(d,visible:visible),try Renderer.composite(proxy),"\(mode)/\(depth)/\(mask)")
      }
    }}
  }
  func testMaximumComponentPreviewAndConversionAreSparse() throws {
    let d=try DocumentCreation.blank(width:300000,height:300000,depth:.u16,background:Pixel(0.2,0.4,0.6,0.5),mode:.cmyk)
    for visible: Set<Int> in [[0],[0,2],[1,2,3]] {
      let pixels=try ModeChannelPresentation.surface(d,visible:visible)
      XCTAssertEqual(pixels.width,300000);XCTAssertLessThan(pixels.allocatedBytes,2_000_000)
      XCTAssertEqual(pixels.tileCount,0)
    }
    let request=DocumentModeRequest(.init(mode:.grayscale,depth:.u16))
    var changed=d;try DocumentModeInput.command(request,in:d).apply(to:&changed)
    XCTAssertEqual(changed.colorMode,.grayscale);XCTAssertLessThan(changed.estimatedBytes,2_000_000)
  }
  func testDenseInterchangeLimitsRejectBeforeAllocating() throws {
    let d=try DocumentCreation.blank(width:300000,height:300000,depth:.u16,mode:.cmyk)
    XCTAssertThrowsError(try PSDModeStorage.validateExport(d))
    XCTAssertThrowsError(try TIFFModeStorage.write(try Renderer.composite(d),document:d,resolution:72,depth:.u16,metadata:nil,options:.init()))
    XCTAssertThrowsError(try ColorProfileInput.command(.init(.assign,profile:try XCTUnwrap(d.modeDescriptor?.profile)),in:d))
  }
}
