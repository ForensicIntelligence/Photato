import Foundation
import CoreGraphics
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class PagedSoftProofTests:XCTestCase {
  var folder:URL {Bundle.module.url(forResource:"Fixtures",withExtension:nil)!.appendingPathComponent("paged-soft-proof")}
  func constant(_ depth:PixelDepth = .u8,mode:DocumentColorMode?=nil,width:Int=300_000,height:Int=300_000)throws->CraftDocument {
    var d=try CraftDocument(width:width,height:height,depth:depth)
    d.layers[0].content = .raster(try Surface(width:width,height:height,depth:depth,fill:Pixel(0.25,0.5,0.75),colorEncoding:depth == .f32 ? .linearRGB:.sRGB))
    if let mode {
      var n=try NativeModeRaster(width:width,height:height,mode:mode,depth:depth)
      for c in 0..<mode.componentCount{n=try n.replacingChannel(c,with:Surface(width:width,height:height,depth:depth,fill:Pixel(0.25,0.25,0.25)))}
      n=try n.replacingOpacity(with:Surface(width:width,height:height,depth:depth,fill:.white))
      d.modeDescriptor=try .init(mode:mode,depth:depth,profile:n.profile);d.layers[0].nativeMode=n;d.layers[0].content = .raster(try n.surface())
    }
    return d
  }
  func testAll104ProgramsMatchEveryFrozenLegacyAndPagedSampleBit()throws {
    let helper=LegacySoftProofCaptureTests(),expected=try Data(contentsOf:folder.appendingPathComponent("soft-proof-small.f32le"))
    var ordinary=Data(),paged=Data()
    for (d,p)in try helper.programs(){ordinary.append(try helper.words(SoftProof.surface(d,settings:p)));paged.append(try helper.words(PagedSoftProof.surface(d,settings:p)))}
    XCTAssertEqual(ordinary,expected);XCTAssertEqual(paged,expected);XCTAssertEqual(expected.count,159744)
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]{
      try paged.write(to:URL(fileURLWithPath:path).appendingPathComponent("soft-proof-paged-small.f32le"))
      try ordinary.write(to:URL(fileURLWithPath:path).appendingPathComponent("soft-proof-current-small.f32le"))
    }
  }
  func testProofBeforeAreaReductionMatchesFrozenAndPatchBoundaries()throws {
    let helper=LegacySoftProofCaptureTests(),d=try helper.fixture(.u16,mode:nil)
    var p=ProofSettings();p.enabled=true;p.gamutWarning=true;p.warningColor=Pixel(1,0,1)
    let request=try RasterPreviewRequest(region:.init(x:1,y:1,width:10,height:6),width:5,height:3)
    let reduced=try helper.words(request.reducing(PagedSoftProof.surface(d,settings:p)))
    XCTAssertEqual(reduced,try Data(contentsOf:folder.appendingPathComponent("soft-proof-reduced.f32le")))
    for(depth,mode)in [(PixelDepth.u8,Optional<DocumentColorMode>.none),(.u16,.cmyk),(.f32,.grayscale)] {
      let d=try helper.fixture(depth,mode:mode,width:2113,height:67)
      let full=try SoftProof.surface(d,settings:p),paged=try PagedSoftProof.surface(d,settings:p)
      XCTAssertEqual(try helper.words(paged),try helper.words(full),"\(depth) \(String(describing:mode)) patch rows/columns")
    }
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]{try reduced.write(to:URL(fileURLWithPath:path).appendingPathComponent("soft-proof-paged-reduced.f32le"))}
  }
  func testMaximumSparseRGBAndNativeModesRetainNumbersGeometryAndSource()throws {
    for depth in PixelDepth.allCases {for mode:DocumentColorMode? in [nil,.rgb,.grayscale]+(depth == .f32 ? []:[.cmyk,.lab]) {
      let d=try constant(depth,mode:mode),before=d
      var p=ProofSettings();p.enabled=true;p.simulateBlack=true;p.gamutWarning=true
      if let native=d.layers[0].nativeMode{p.device = .custom;p.profile=native.profile;p.preserveNumbers=true}
      XCTAssertNoThrow(try SoftProof.validate(p,in:d))
      let result=try SoftProof.surface(d,settings:p)
      XCTAssertEqual(result.width,300000);XCTAssertEqual(result.height,300000);XCTAssertEqual(result.depth,.f32)
      XCTAssertEqual(result.tileCount,0);XCTAssertEqual(d,before)
      let small=try constant(depth,mode:mode,width:1,height:1),expected=try SoftProof.surface(small,settings:p)
      XCTAssertEqual(result.pixel(x:299999,y:299999),expected.pixel(x:0,y:0))
      XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(d)),d)
    }}
  }
  func testCustomRGBWorkingProfileSurvivesPagedProofAtIntegerAndFloatDepths()throws {
    let helper=LegacySoftProofCaptureTests(),profile=try XCTUnwrap(CGColorSpace(name:CGColorSpace.displayP3)?.copyICCData()as Data?)
    for depth in [PixelDepth.u16,.f32] {
      var d=try helper.fixture(depth,mode:nil,width:67,height:65)
      d.workingICC=try ColorManagement.importedProfile(profile,depth:depth);try d.validate()
      for preserve in [false,true] {
        var p=ProofSettings();p.enabled=true;p.device = .custom;p.profile=profile;p.profileName="Owned Display P3";p.preserveNumbers=preserve;p.gamutWarning=true
        XCTAssertEqual(try helper.words(PagedSoftProof.surface(d,settings:p)),try helper.words(SoftProof.surface(d,settings:p)))
      }
    }
  }
  func testActualDensePagedSourceAboveEightMegapixelsMatchesLegacyAtEdges()throws {
    let width=4096,height=2049,helper=LegacySoftProofCaptureTests(),small=try helper.fixture(.u8,mode:nil,width:64,height:64)
    guard case .raster(let patch)=small.layers[0].content else{return XCTFail("Missing owned samples")}
    let builder=try Surface.PagedBuilder(width:width,height:height,depth:.u8,fill:.clear,colorEncoding:.sRGB)
    for y in stride(from:0,to:height,by:64){for x in stride(from:0,to:width,by:64){try builder.append(y+64<=height ? patch:patch.cropped(to:.init(x:0,y:0,width:64,height:1)),atX:x,atY:y)}}
    let pixels=try builder.finish();var d=try CraftDocument(width:width,height:height);d.layers[0].content = .raster(pixels)
    XCTAssertGreaterThan(pixels.mappedBytes,128*1024*1024);XCTAssertGreaterThan(width*height,SoftProof.maximumPixels)
    var p=ProofSettings();p.enabled=true;p.gamutWarning=true
    let output=try SoftProof.surface(d,settings:p),expected=try SoftProof.surface(small,settings:p)
    for(x,y)in [(0,0),(63,63),(64,64),(2047,1023),(2048,1024),(4095,2047),(0,2048),(4095,2048)]{
      XCTAssertEqual(output.pixel(x:x,y:y),expected.pixel(x:x%64,y:y%64))
    }
    XCTAssertGreaterThan(output.mappedBytes,0);XCTAssertEqual(d.layers[0].content,.raster(pixels))
  }
  func testBoundedImageUsesProofedSourceAndPreservesPrintBudget()throws {
    let d=try constant(),before=d;var p=ProofSettings();p.enabled=true;p.simulatePaper=true;p.simulateBlack=true
    let request=try RasterPreviewRequest(region:.init(x:100,y:200,width:96,height:64),width:48,height:32)
    let image=try SoftProof.image(d,settings:p,request:request)
    XCTAssertEqual(image.width,48);XCTAssertEqual(image.height,32)
    let expected=try RasterIO.displayImage(request.reducing(SoftProof.surface(d,settings:p)))
    XCTAssertEqual(image.dataProvider?.data as Data?,expected.dataProvider?.data as Data?)
    XCTAssertThrowsError(try PrintLayout(document:d,settings:.init()));XCTAssertEqual(SoftProof.maximumPixels,8388608)
    XCTAssertEqual(d,before)
    let invalid=try RasterPreviewRequest(region:.init(x:299999,y:0,width:1,height:1),width:1,height:1),small=try constant(width:10,height:10)
    XCTAssertThrowsError(try SoftProof.image(small,settings:p,request:invalid))
  }
  func testInvalidPreserveProfileAndCancellationDoNotPublish()async throws {
    let d=try constant(),before=d;var p=ProofSettings();p.enabled=true;p.preserveNumbers=true
    XCTAssertThrowsError(try SoftProof.surface(d,settings:p));XCTAssertEqual(d,before)
    p=ProofSettings();p.device = .custom;p.profile=Data(repeating:0,count:132)
    XCTAssertThrowsError(try PagedSoftProof.surface(d,settings:p))
    p=ProofSettings();p.enabled=true;let settings=p
    let task=Task.detached{withUnsafeCurrentTask{$0?.cancel()};return try SoftProof.surface(d,settings:settings)}
    do{_ = try await task.value;XCTFail("Cancelled proof returned a surface")}catch is CancellationError{}
    XCTAssertEqual(d,before)
  }
}
