import XCTest
@testable import PhotoCraftCore

final class SourceSmartModelTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var document=try CraftDocument(width:32,height:24,depth:depth)
    var pixels=try Surface(width:8,height:6,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
    for y in 0..<6{for x in 0..<8{let p=Pixel(Float(x)/8,Float(y)/6,0.25,1);if depth == .f32{pixels.setLinearPixel(x:x,y:y,p)}else{pixels.setPixel(x:x,y:y,p)}}}
    var layer=Layer(name:"Owned source",content:.raster(pixels));layer.smartObject=try .init(fileName:"Owned.png",mediaType:"image/png",data:Data([1,2,3]),width:8,height:6)
    layer.affine = .translation(3,4);document.layers=[layer];document.activeLayerID=layer.id;return document
  }
  func testHomogeneousAffineInverseScaleAndHorizonAdmission()throws {
    let affine=Transform2D.translation(125.25,-57.5) * .rotation(12) * .scale(1.5,0.75),matrix=ProjectiveTransform(affine)
    let p=try matrix.point(3.25,7.5),q=affine.point(3.25,7.5);XCTAssertEqual(p.x,q.x,accuracy:1e-10);XCTAssertEqual(p.y,q.y,accuracy:1e-10)
    let back=try matrix.inverted().point(p.x,p.y);XCTAssertEqual(back.x,3.25,accuracy:1e-10);XCTAssertEqual(back.y,7.5,accuracy:1e-10)
    let scaled=try ProjectiveTransform(matrix.values.map{$0*1e200});XCTAssertEqual(try scaled.point(3.25,7.5).x,p.x,accuracy:1e-10)
    let moved=ProjectiveTransform(.translation(999900,0));XCTAssertEqual(try moved.point(1,2).x,999901,accuracy:1e-6)
    XCTAssertThrowsError(try ProjectiveTransform([1,2]))
    XCTAssertThrowsError(try ProjectiveTransform([1,2,3,2,4,6,0,0,1]))
    let horizon=try ProjectiveTransform([1,0,0,0,1,0,-0.2,0,1]);XCTAssertThrowsError(try horizon.bounds(width:10,height:10))
    let invalid=try JSONDecoder().decode(ProjectiveTransform.self,from:Data("{\"values\":[]}".utf8));XCTAssertThrowsError(try invalid.point(0,0));XCTAssertThrowsError(try invalid.inverted())
  }
  func testProjectiveBoundsAndCompositionUseIndependentCorners()throws {
    let matrix=try ProjectiveTransform([1.2,0.1,3,0.05,0.9,4,0.005,0.002,1])
    let moved=try matrix.followed(by:.translation(10,-2)),a=try matrix.point(8,6),b=try moved.point(8,6)
    XCTAssertEqual(b.x,a.x+10,accuracy:1e-12);XCTAssertEqual(b.y,a.y-2,accuracy:1e-12)
    let bounds=try matrix.bounds(width:8,height:6);XCTAssertEqual(bounds,.init(x:3,y:4,width:10,height:6))
    for p in [PathPoint(0,0),.init(8,0),.init(8,6),.init(0,6)]{let q=try matrix.point(p.x,p.y);XCTAssertGreaterThanOrEqual(q.x,Double(bounds.x));XCTAssertLessThanOrEqual(q.x,Double(bounds.x+bounds.width));XCTAssertGreaterThanOrEqual(q.y,Double(bounds.y));XCTAssertLessThanOrEqual(q.y,Double(bounds.y+bounds.height))}
  }
  func testTranslatedProjectivePlacementPreservesAllSourceWordsAtEachDepth()throws {
    for depth in [PixelDepth.u8,.u16,.f32] {
      let doc=try fixture(depth);guard case .raster(let source)=doc.layers[0].content else{return XCTFail()}
      let mapping=try ProjectiveRaster.mapping(.identity,width:8,height:6,transform:.translation(3,4))
      XCTAssertEqual(mapping.bounds,.init(x:3,y:4,width:8,height:6))
      let output=try WarpRaster.render(source,using:mapping,method:.nearest)
      XCTAssertTrue(output==source)
    }
  }
  func testGeneralProjectiveInverseMappingAndNoInputMutation()throws {
    var doc=try fixture();let original=doc
    doc.layers[0].affine=nil;doc.layers[0].sourceProjection=try .init([1.1,0.1,2,0.05,1,3,0.02,0.01,1])
    let layer=doc.layers[0],rendered=try WarpRaster.baked(layer,in:doc);XCTAssertNil(rendered.sourceProjection)
    let full=try XCTUnwrap(layer.sourceProjection),mapping=try ProjectiveRaster.mapping(full,width:8,height:6,transform:.identity),inverse=try full.inverted()
    for y in 0..<mapping.bounds.height{for x in 0..<mapping.bounds.width{let uv=mapping.uv[y*mapping.bounds.width+x];if uv.x.isFinite {let p=try inverse.point(Double(mapping.bounds.x+x)+0.5,Double(mapping.bounds.y+y)+0.5);XCTAssertEqual(uv.x,p.x,accuracy:1e-10);XCTAssertEqual(uv.y,p.y,accuracy:1e-10)}}}
    XCTAssertEqual(doc.layers[0].sourceProjection,full);XCTAssertEqual(original.layers[0].smartObject,doc.layers[0].smartObject);XCTAssertEqual(original.layers[0].content,doc.layers[0].content)
  }
  func testSourceWarpFramePreservesOffsetAndNativeLegacyDefault()throws {
    var warp=WarpDefinition();warp.style = .arch;warp.bend=30
    let old=warp.point(4,3,width:8,height:6);var shifted=warp;shifted.sourceBounds = .init(x:5,y:-2,width:8,height:6)
    let p=shifted.point(9,1,width:30,height:40);XCTAssertEqual(p.x,old.x+5,accuracy:1e-12);XCTAssertEqual(p.y,old.y-2,accuracy:1e-12)
    XCTAssertNoThrow(try shifted.validate());shifted.sourceBounds = .init(x:5,y:-2,width:0,height:6);XCTAssertThrowsError(try shifted.validate())
  }
  func testOriginalCacheReferenceMaskPlacementInvalidationAndNative70()throws {
    var doc=try fixture(.f32),layer=doc.layers[0]
    let cache=try Surface(width:10,height:8,depth:.f32,fill:Pixel(4,-0.25,0.5,1),colorEncoding:.linearRGB)
    layer.mask=try Surface(width:2,height:2,fill:.white);var mask=MaskProperties();mask.transform = .translation(7,2);layer.maskProperties=mask
    layer.importedSmartAppearance=try .init(layer:layer,pixels:cache,x:5,y:6,placedRecord:Data("OWNED-SMART".utf8));doc.layers=[layer]
    XCTAssertEqual(doc.minimumArchiveVersion,70);try doc.validate()
    let display=try XCTUnwrap(layer.originalSmartAppearanceLayer());XCTAssertNil(display.smartObject);XCTAssertNil(display.smartFilters);XCTAssertEqual(display.maskCoordinateTransform,layer.maskCoordinateTransform)
    guard case .raster(let result)=display.content else{return XCTFail()};XCTAssertTrue(result==cache)
    let reopened=try NativeArchive.decode(NativeArchive.encodeChunked(doc));XCTAssertTrue(reopened==doc)
    var changed=layer;changed.opacity=0.5;XCTAssertNotNil(changed.pristineSmartAppearance);changed.smartObject?.sourceID=UUID();XCTAssertNotNil(changed.pristineSmartAppearance,"An independent copy with identical source/program preserves appearance");changed.affine = .translation(4,4);XCTAssertNil(changed.pristineSmartAppearance)
    changed=layer;changed.smartObject?.data=Data([4]);XCTAssertNil(changed.pristineSmartAppearance)
    changed=layer;changed.smartFilters=SmartFilterStack();XCTAssertNil(changed.pristineSmartAppearance)
  }
  func testNewAppearanceTemporalBudgetAndHeaderAdmission()throws {
    var doc=try fixture(),layer=doc.layers[0]
    layer.sourceProjection=try .init([1,0,0,0,1,0,0.01,0,1]);layer.importedSmartAppearance=try .init(layer:layer,pixels:Surface(width:8,height:6,fill:.white))
    let payload=AnimationLayerPayload(layer);XCTAssertGreaterThan(payload.rasterBytes,0);XCTAssertGreaterThan(payload.metadataBytes,0)
    var copy=doc.layers[0];payload.apply(to:&copy);XCTAssertEqual(copy.sourceProjection,layer.sourceProjection);XCTAssertNotNil(copy.importedSmartAppearance)
    doc.layers=[layer];XCTAssertEqual(doc.minimumArchiveVersion,70)
    XCTAssertTrue(NativeIndexedArchive.supportsHeader(NativeIndexedArchive.containerHeader(70)))
    XCTAssertTrue(NativeIndexedArchive.supportsHeader(NativeIndexedArchive.containerHeader(71)))
    XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(doc,minimumVersion:71))==doc)
    for version in 75...78 {
      XCTAssertTrue(NativeIndexedArchive.supportsHeader(NativeIndexedArchive.containerHeader(version)))
      XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(doc,minimumVersion:version))==doc)
    }
    XCTAssertThrowsError(try NativeArchive.encodeChunked(doc,minimumVersion:999999))
  }
  func testCooperativeWorkerAppliesCommandsWithoutGrowingInlineLayerPayload()async throws {
    let document=try fixture(),id=try XCTUnwrap(document.layers.first?.id)
    let result=try await Task.detached(priority:.utility){var value=document;try Command.renameLayer(id,"Worker rename").apply(to:&value);return value}.value
    XCTAssertEqual(result.layers.first?.name,"Worker rename")
    XCTAssertLessThanOrEqual(MemoryLayout<ImportedSmartAppearance?>.size,16)
    XCTAssertLessThanOrEqual(MemoryLayout<ProjectiveTransform?>.size,16)
    XCTAssertLessThanOrEqual(MemoryLayout<WarpSourceBounds?>.size,16)
  }

  func testCooperativeWorkerCopiesSmartSourcesThroughNestedValidatedCommands()async throws {
    for depth in [PixelDepth.u8,.u16,.f32] {
      var document=try fixture(depth),layer=document.layers[0]
      guard case .raster(let pixels)=layer.content else{return XCTFail()}
      layer.importedSmartAppearance=try .init(layer:layer,pixels:pixels,x:3,y:4)
      document.layers=[layer]
      let original=document,id=layer.id
      let result=try await Task.detached(priority:.userInitiated){
        try PreparedEdit(command:.independentSmartObjectCopy(id),document:original).result
      }.value
      XCTAssertEqual(result.layers.count,2)
      let copy=try XCTUnwrap(result.layers.first{$0.id != id})
      XCTAssertNotEqual(copy.smartObject?.sourceID,layer.smartObject?.sourceID)
      XCTAssertEqual(copy.smartObject?.data,layer.smartObject?.data)
      XCTAssertEqual(copy.content,layer.content)
      XCTAssertNotNil(copy.pristineSmartAppearance)
      XCTAssertEqual(document,original)
      XCTAssertEqual(result.layers.first{$0.id == id},layer)
    }
  }

  func testAffineHomographyKeepsMaximumSparseSmartSourceWithoutDensePreparation()throws {
    let side=Surface.maxDimension,pixels=try Surface(width:side,height:side)
    var layer=Layer(name:"Maximum logical source",content:.raster(pixels));layer.smartObject=try .init(fileName:"Owned.png",mediaType:"image/png",data:Data([1]),width:side,height:side);layer.sourceProjection = .identity
    let doc=try CraftDocument(width:16,height:16),result=try WarpRaster.baked(layer,in:doc)
    guard case .raster(let output)=result.content else{return XCTFail()};XCTAssertEqual(output.width,side);XCTAssertEqual(output.height,side);XCTAssertEqual(output.allocatedBytes,0);XCTAssertNil(result.sourceProjection)
  }
  func testSourceFingerprintChangesWithBytesAndIsRecomputedAfterDecode()throws {
    var source=try XCTUnwrap(fixture().layers.first?.smartObject);let first=source.dataFingerprint
    XCTAssertEqual(source.revision,first);source.data.append(4);XCTAssertNotEqual(source.dataFingerprint,first)
    let encoded=try JSONEncoder().encode(source),object=try XCTUnwrap(JSONSerialization.jsonObject(with:encoded)as?[String:Any]);XCTAssertNil(object["dataDigest"])
    let decoded=try JSONDecoder().decode(SmartObject.self,from:encoded);XCTAssertEqual(decoded.dataFingerprint,source.dataFingerprint);XCTAssertEqual(decoded,source)
  }

}
