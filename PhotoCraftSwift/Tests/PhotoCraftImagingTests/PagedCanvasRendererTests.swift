import Foundation
import XCTest
import CryptoKit
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PagedCanvasRendererTests:XCTestCase {
  func testAll24PriorNativeStacksRemainBitExactThroughPagedComposition() throws {
    let folder=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/paged-composition")
    let manifest=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("manifest.json")))as?[[String:Any]])
    XCTAssertEqual(manifest.count,24)
    for (di,depth) in PixelDepth.allCases.enumerated(){for variant in 0..<8 {
      let name="\(di)-\(variant).rgba",bytes=try Data(contentsOf:folder.appendingPathComponent(name))
      let hash=SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
      XCTAssertEqual(manifest.first{$0["file"]as?String==name}?["sha256"]as?String,hash)
      let doc=try PagedCompositionFixture.document(depth:depth,variant:variant)
      let result=try PagedCanvasRenderer.composite(doc,region:.init(x:0,y:0,width:doc.width,height:doc.height))
      XCTAssertEqual(try result.rgbaData(depth:.f32,colorEncoding:depth == .f32 ? .linearRGB:.sRGB),bytes,name)
    }}
  }

  func hierarchy(side:Int,depth:PixelDepth) throws -> CraftDocument {
    var doc=try CraftDocument(width:side,height:side,depth:depth)
    let encoding:SurfaceColorEncoding=depth == .f32 ? .linearRGB:.sRGB
    var pixels=try Surface(width:side,height:side,depth:depth,fill:Pixel(0.2,0.4,0.6),colorEncoding:encoding)
    pixels.setPixel(x:64,y:64,Pixel(0.8,0.1,0.3))
    var base=Layer(name:"Base",content:.raster(pixels))
    var mask=try Surface(width:side,height:side,depth:.f32,fill:.white)
    mask.setPixel(x:side-1,y:side-1,.black);base.mask=mask
    let group=Layer(name:"Group",content:.group(GroupContent(passThrough:false)))
    var upper=Layer(name:"Upper",content:.raster(try Surface(width:side,height:side,depth:depth,fill:Pixel(0.8,0.2,0.4,0.5),colorEncoding:encoding)))
    upper.parentID=group.id;upper.opacity=128/255
    var clip=Layer(name:"Clip",content:.raster(try Surface(width:side,height:side,depth:depth,fill:Pixel(0.1,0.6,0.8,0.25),colorEncoding:encoding)))
    clip.parentID=group.id;clip.clipped=true
    doc.layers=[base,upper,clip,group];doc.activeLayerID=upper.id;try doc.validate();return doc
  }
  func testMaximumSparseHierarchyUsesActualGlobalOpacityAndImplicitPixels() throws {
    for depth in PixelDepth.allCases {
      let doc=try hierarchy(side:300_000,depth:depth),before=doc
      let result=try Renderer.composite(doc),small=try Renderer.composite(hierarchy(side:129,depth:depth))
      XCTAssertLessThanOrEqual(result.tileCount,4);XCTAssertLessThan(result.allocatedBytes,1024*1024)
      for (x,y,sx,sy) in [(0,0,0,0),(150_000,150_000,32,32),(64,64,64,64),(299_999,299_999,128,128)] {
        let a=depth == .f32 ? result.linearPixel(x:x,y:y):result.pixel(x:x,y:y)
        let b=depth == .f32 ? small.linearPixel(x:sx,y:sy):small.pixel(x:sx,y:sy)
        XCTAssertTrue(a.hasSameBits(as:b),"\(depth):\(x),\(y)")
      }
      XCTAssertEqual(doc,before)
    }
  }

  func testUnalignedRegionalCompositionAndAdjustmentInputRetainLegacyBytes() throws {
    let doc=try PagedCompositionFixture.document(depth:.f32,variant:5)
    let region=IntRect(x:13,y:7,width:109,height:57)
    let legacy=try Renderer.composite(doc,region:region)
    let paged=try PagedCanvasRenderer.composite(doc,region:region)
    XCTAssertEqual(try paged.rgbaData(depth:.f32,colorEncoding:.linearRGB),try legacy.rgbaData(depth:.f32,colorEncoding:.linearRGB))
    let target=try XCTUnwrap(doc.layers.last?.id),input=try Renderer.adjustmentInput(target,in:doc)
    do {
      _ = try PagedCanvasRenderer.composite(doc,region:.init(x:0,y:0,width:doc.width,height:doc.height),inputTarget:target)
      XCTFail("Missing adjustment input boundary")
    }catch let captured as AdjustmentInputReached {
      XCTAssertEqual(try captured.surface.rgbaData(depth:.f32,colorEncoding:.linearRGB),try input.rgbaData(depth:.f32,colorEncoding:.linearRGB))
    }
  }

  func testActual40MPGroupedLinearRasterPreservesEveryStoredSample() throws {
    let w=8000,h=5000,builder=try Surface.PagedBuilder(width:w,height:h,depth:.f32,colorEncoding:.linearRGB)
    for y in stride(from:0,to:h,by:64){for x in stride(from:0,to:w,by:2048){
      var patch=try Surface(width:min(2048,w-x),height:min(64,h-y),depth:.f32,colorEncoding:.linearRGB)
      for py in 0..<patch.height {for px in 0..<patch.width {
        patch.setLinearPixel(x:px,y:py,Pixel(Float((x+px)%257)/256,Float((y+py)%251)/250,Float((x+px+3*(y+py))%239)/238,Float((x+px+y+py)%5)/4))
      }}
      if x<=4095 && 4095<x+patch.width && y==64 {patch.setLinearPixel(x:4095-x,y:0,Pixel(2,-0.25,-0.0,0.5))}
      try builder.append(patch,atX:x,atY:y)
    }}
    let source=try builder.finish();var doc=try CraftDocument(width:w,height:h,depth:.f32)
    let group=Layer(name:"Dense group",content:.group(GroupContent(passThrough:false)))
    var child=Layer(name:"Dense source",content:.raster(source));child.parentID=group.id
    doc.layers=[child,group];doc.activeLayerID=child.id
    let result=try Renderer.composite(doc)
    XCTAssertGreaterThan(result.mappedBytes,36_000_000);XCTAssertLessThan(result.allocatedBytes,8*1024*1024)
    for y in stride(from:0,to:h,by:64) {
      let region=IntRect(x:0,y:y,width:w,height:min(64,h-y))
      XCTAssertEqual(try result.cropped(to:region).rgbaData(depth:.f32,colorEncoding:.linearRGB),
        try source.cropped(to:region).rgbaData(depth:.f32,colorEncoding:.linearRGB),"All samples in band\(y)")
    }
  }

  func testMaskCacheSeparatesUnmaskedVariantsAndCancellationAfterWrittenPatch() async throws {
    let doc=try PagedCompositionFixture.document(depth:.f32,variant:4),layer=doc.layers[1],facts=CompositionFacts(doc)
    var unmasked=layer;unmasked.mask=nil;unmasked.maskProperties=nil
    XCTAssertNil(try facts.mask(unmasked))
    let actual=try XCTUnwrap(facts.mask(layer)),expected=try XCTUnwrap(LayerMaskSampler.make(layer:layer,document:doc))
    XCTAssertEqual(actual.coverage(x:64.5,y:64.5),expected.coverage(x:64.5,y:64.5))
    XCTAssertNil(try facts.mask(unmasked))
    let before=doc
    let worker=Task.detached {
      try PagedCanvasRenderer.composite(doc,region:.init(x:0,y:0,width:doc.width,height:doc.height),
        onPatch:{_ in withUnsafeCurrentTask {$0?.cancel()}})
    }
    do {_ = try await worker.value;XCTFail("Cancelled partial composition accepted")}catch is CancellationError {}
    XCTAssertEqual(doc,before)
    var unsafe=try hierarchy(side:300_000,depth:.u8)
    unsafe.layers[0].maskProperties=MaskProperties();unsafe.layers[0].maskProperties?.feather=1
    XCTAssertThrowsError(try Renderer.composite(unsafe))
    unsafe.layers[0].maskProperties=nil;unsafe.layers[0].vectorMask=VectorMask(path:VectorPath())
    unsafe.layers[0].vectorMask?.feather=1
    XCTAssertThrowsError(try Renderer.composite(unsafe))
  }
}
