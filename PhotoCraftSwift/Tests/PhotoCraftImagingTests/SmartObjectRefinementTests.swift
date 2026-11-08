import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class SmartObjectRefinementTests: XCTestCase {
  func fixture(_ depth:PixelDepth = .u8) throws -> CraftDocument {
    var d=try SmartObjectTests().converted(depth)
    d.selection = .init(x:3,y:3,width:4,height:3)
    return d
  }
  func testAllOutputsRetainTheSourceAndOnlyCopiesBecomeRasterAtEveryDepth() throws {
    for depth in PixelDepth.allCases { for output in SelectionRefinementOutput.allCases {
      let original=try fixture(depth),id=original.layers[0].id
      let input=try SelectionRefinementInput.prepare(original,layerID:id)
      XCTAssertNotNil(input.materializedLayer)
      let edit=try input.edit(settings:.init(),output:output),result=try edit.applied(to:original)
      let mask=try XCTUnwrap(original.coverageSelection())
      XCTAssertEqual(edit.mask,mask)
      if output == .selection {
        XCTAssertEqual(result.layers,original.layers);XCTAssertEqual(try result.coverageSelection(),mask)
      } else if output == .layerMask {
        XCTAssertEqual(result.layers[0].smartObject,original.layers[0].smartObject)
        XCTAssertEqual(result.layers[0].content,original.layers[0].content)
        XCTAssertNotNil(result.layers[0].mask)
      } else {
        let copy=try XCTUnwrap(result.layers.first{$0.id==result.activeLayerID})
        XCTAssertNil(copy.smartObject);XCTAssertNil(copy.smartFilters)
        XCTAssertNotEqual(copy.id,id)
        XCTAssertEqual(copy.mask != nil,output == .newLayerWithMask || output == .newDocumentWithMask)
        if !output.createsDocument {
          var retained=original.layers[0];retained.visible=false
          XCTAssertEqual(result.layers[0],retained)
        }
      }
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)),result)
      if !output.createsDocument {
        var session=EditorSession(document:original)
        try session.execute(.selectionRefinement(edit));XCTAssertEqual(session.undoStack.count,1)
        let committed=session.document
        try session.undo();XCTAssertEqual(session.document,original)
        try session.redo();XCTAssertEqual(session.document,committed)
      }
    }}
  }
  func testSmartFilterAndAffineAppearanceIsBakedOnlyInRasterCopies() throws {
    var original=try fixture();original.layers[0].affine = .scale(1.5,1.25)
    var stack=SmartFilterStack();var filter=RasterFilter(.boxBlur);filter.radius=1
    stack.filters=[SmartFilter(filter:filter)];original.layers[0].smartFilters=stack
    original.layers[0].sourceTags=["SoLd":try PSDSmartObjects.placedDescriptor(original.layers[0])]
    let input=try SelectionRefinementInput.prepare(original,layerID:original.layers[0].id)
    let prepared=try XCTUnwrap(input.materializedLayer)
    XCTAssertNil(prepared.smartObject);XCTAssertNil(prepared.smartFilters);XCTAssertNil(prepared.sourceTags?["SoLd"])
    var all=original;all.selection=nil
    let full=try SelectionMask(width:all.width,height:all.height,bytes:Array(repeating:255,count:all.width*all.height))
    let result=try input.edit(settings:.init(),output:.newLayerWithMask,initial:full).applied(to:original)
    XCTAssertEqual(try Renderer.composite(result),try Renderer.composite(original))
    XCTAssertEqual(result.layers[0].smartFilters,stack)
    XCTAssertEqual(result.layers[0].smartObject,original.layers[0].smartObject)
    XCTAssertEqual(result.layers[1].coordinateTransform,prepared.coordinateTransform)
  }
  func testExistingMaskAndDecontaminatedCopiesUseTheirRenderedCoordinates() throws {
    var original=try fixture(.f32)
    original.layers[0].mask=try Surface(width:6,height:4,depth:.f32,fill:Pixel(0.5,0.5,0.5))
    var props=MaskProperties();props.density=0.25;props.feather=2;original.layers[0].maskProperties=props
    let input=try SelectionRefinementInput.prepare(original,layerID:original.layers[0].id,fromLayerMask:true)
    XCTAssertTrue(try input.mask.bytes.contains{ $0==128 })
    var settings=SelectionRefinement();settings.decontaminate=true;settings.feather=1
    let edit=try input.edit(settings:settings,output:.layerMask)
    XCTAssertEqual(edit.output,.newLayerWithMask);XCTAssertNotNil(edit.corrected)
    let result=try edit.applied(to:original)
    XCTAssertEqual(result.layers[0].content,original.layers[0].content)
    XCTAssertEqual(result.layers[0].smartObject,original.layers[0].smartObject)
    XCTAssertNil(result.layers[1].smartObject)
    XCTAssertEqual(try input.previewGuide(mask:edit.mask,settings:settings).width,original.width)
  }
  func testLockedReadOnlySelectionAndNewDocumentPreserveSourceButMaskAndLayerEditsReject() throws {
    var original=try fixture();original.layers[0].locked=true
    let input=try SelectionRefinementInput.prepare(original,layerID:original.layers[0].id)
    for output in SelectionRefinementOutput.allCases {
      let edit=try input.edit(settings:.init(),output:output)
      if output == .selection || output.createsDocument {XCTAssertNoThrow(try edit.applied(to:original))}
      else {XCTAssertThrowsError(try edit.applied(to:original))}
    }
    XCTAssertThrowsError(try FocusAreaInput.prepare(original,layerID:original.layers[0].id))
  }
  func testUnpreparedOrMismatchedSmartCopiesRejectWithoutMutatingSource() throws {
    let original=try fixture(),id=original.layers[0].id,mask=try XCTUnwrap(original.coverageSelection())
    XCTAssertThrowsError(try SelectionRefinementEdit(layerID:id,output:.newLayerWithMask,mask:mask).applied(to:original))
    var materialized=try XCTUnwrap(SelectionRefinementInput.prepare(original,layerID:id).materializedLayer);materialized.id=UUID()
    XCTAssertThrowsError(try SelectionRefinementEdit(layerID:id,output:.newLayerWithMask,mask:mask,materialized:materialized).applied(to:original))
    XCTAssertNotNil(original.layers[0].smartObject)
  }
  func testOwnedPhotoshopReferencesConfirmEditableMaskAndRasterCopyOutput() throws {
    let base=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/select-mask-smart")
    let first=try PSDCodec.read(Data(contentsOf:base.appendingPathComponent("observed-smart-object-layer-mask.psd")))
    let second=try PSDCodec.read(Data(contentsOf:base.appendingPathComponent("observed-new-layer-with-mask.psd")))
    let smart=try XCTUnwrap(first.layers.first{$0.smartObject != nil});XCTAssertNotNil(smart.mask)
    let copy=try XCTUnwrap(second.layers.first{$0.name=="Layer 0 copy"})
    XCTAssertNil(copy.smartObject);XCTAssertNotNil(copy.mask)
    XCTAssertNotNil(second.layers.first{$0.smartObject != nil})
    let input=try SelectionRefinementInput.prepare(first,layerID:smart.id,fromLayerMask:true)
    XCTAssertTrue(try input.mask.bytes.allSatisfy{$0==255})
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {try Data(input.mask.bytes).write(to:URL(fileURLWithPath:path).appendingPathComponent("photoshop-neutral-smart-mask.mask"))}
    let result=try input.edit(settings:.init(),output:.newLayerWithMask).applied(to:first)
    XCTAssertNil(result.layers.first{$0.id==result.activeLayerID}?.smartObject)
  }
  func testOpaqueAnnotationBytesSurvivePSDPSBAndNativeRoundTrips() throws {
    // The second payload exercises opaque retention, not annotation interpretation.
    let empty=Data([0,2,0,1,0,0,0,0]),opaque=Data([0,2,0,1,0,0,0,1,0,0,0,12,116,120,116,65,0,0,0,0])
    for bytes in [empty,opaque] {for format in PSDFileFormat.allCases {
      var d=try CraftDocument(width:4,height:3);d.sourceMetadata=["psdGlobal_Anno":bytes]
      let decoded=try PSDCodec.read(PSDCodec.writeRasterLayers(d,format:format))
      XCTAssertEqual(decoded.sourceMetadata?["psdGlobal_Anno"],bytes)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(decoded)).sourceMetadata?["psdGlobal_Anno"],bytes)
      XCTAssertEqual(try PSDCodec.read(PSDCodec.writeRasterLayers(decoded,format:format)).sourceMetadata?["psdGlobal_Anno"],bytes)
    }}
  }
  func versionInfo(_ flag:UInt8) -> Data {
    var out=PSDWriter();out.n(1,4);out.n(Int(flag),1);out.n(0,4);out.n(0,4);out.n(1,4);return out.data
  }
  func addingVersionInfo(_ data:Data,payload:Data) -> Data {
    func number(_ at:Int)->Int {data[at..<at+4].reduce(0){($0<<8)|Int($1)}}
    let at=26+4+number(26),length=number(at),begin=at+4
    let block=PSDImageResources.block(1057,data:payload)
    var result=Data(data.prefix(at)),size=UInt32(length+block.count).bigEndian
    withUnsafeBytes(of:&size){result.append(contentsOf:$0)}
    result.append(data[begin..<begin+length]);result.append(block);result.append(data.dropFirst(begin+length));return result
  }
  func testExplicitMissingCompositeUsesLayersButOtherFlagsKeepExactCacheChecks() throws {
    for depth in PixelDepth.allCases {for format in PSDFileFormat.allCases {
      var d=try CraftDocument(width:4,height:3,depth:depth);d.layers[0].content = .raster(try Surface(width:4,height:3,depth:depth,fill:Pixel(0.2,0.4,0.6)))
      let valid=try PSDCodec.writeRasterLayers(d,format:format),bad=valid+Data([35,127,64,2])
      XCTAssertThrowsError(try PSDCodec.read(bad))
      XCTAssertThrowsError(try PSDCodec.read(addingVersionInfo(bad,payload:versionInfo(1))))
      XCTAssertThrowsError(try PSDCodec.read(addingVersionInfo(bad,payload:Data(versionInfo(0).dropLast()))))
      let parsed=try PSDCodec.read(addingVersionInfo(bad,payload:versionInfo(0)))
      XCTAssertEqual(try Renderer.composite(parsed).rgbaData(depth:depth),try Renderer.composite(d).rgbaData(depth:depth))
      let rewritten=try PSDCodec.writeRasterLayers(parsed,format:format)
      XCTAssertNoThrow(try PSDCodec.read(rewritten))
      XCTAssertThrowsError(try PSDCodec.read(rewritten+Data([99])))
      let duplicate=addingVersionInfo(addingVersionInfo(bad,payload:versionInfo(0)),payload:versionInfo(0))
      XCTAssertThrowsError(try PSDCodec.read(duplicate))
    }}
  }
  func testAbsentCompositeCannotDiscardAuxiliaryChannelsOrReplaceMissingLayers() throws {
    let d=try CraftDocument(width:4,height:3),encoded=try PSDCodec.writeRasterLayers(d)
    var extra=encoded;let channels=Int(encoded[12])*256+Int(encoded[13]);extra[12]=UInt8((channels+1)>>8);extra[13]=UInt8((channels+1)&255)
    XCTAssertThrowsError(try PSDCodec.read(addingVersionInfo(extra,payload:versionInfo(0))))
    var flat=Data(encoded.prefix(26));flat.append(Data(repeating:0,count:12));flat.append(Data([0,0]));flat.append(Data(repeating:0,count:4*3*channels))
    XCTAssertNoThrow(try PSDCodec.read(flat))
    XCTAssertThrowsError(try PSDCodec.read(addingVersionInfo(flat,payload:versionInfo(0))))
  }
  func testCancelledSmartPreparationAndRefinementNeverPublish() async throws {
    let original=try fixture(),task=Task {
      while !Task.isCancelled {await Task.yield()}
      return try SelectionRefinementInput.prepare(original,layerID:original.layers[0].id).edit(settings:.init(),output:.layerMask)
    }
    task.cancel()
    do {_ = try await task.value;XCTFail("Cancelled refinement succeeded")}
    catch is CancellationError {} catch {XCTFail("Unexpected cancellation error: \(error)")}
    XCTAssertNotNil(original.layers[0].smartObject)
  }
}
