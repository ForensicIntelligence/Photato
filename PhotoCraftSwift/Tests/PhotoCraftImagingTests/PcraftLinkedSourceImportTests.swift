import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PcraftLinkedSourceImportTests:XCTestCase {
  let helper=PcraftLinkedCaptureTests()
  func replacingBlock(_ input:Data,with bytes:Data)throws->PcraftProject {
    let old=try PcraftProject.read(input);var root=try XCTUnwrap(JSONSerialization.jsonObject(with:old.rawManifest)as?[String:Any])
    var doc=root["document"]as![String:Any],metadata=doc["metadata"]as![String:Any],blocks=metadata["psd_global_blocks"]as![[String]]
    let hash=try PcraftBLAKE3.hex(bytes);blocks[blocks.count-1][2]=hash;metadata["psd_global_blocks"]=blocks;doc["metadata"]=metadata;root["document"]=doc
    let raw=try JSONSerialization.data(withJSONObject:root,options:[.sortedKeys]);var blobs=old.blobs;blobs[hash]=bytes
    return PcraftProject(rawManifest:raw,manifest:try PcraftJSON.parse(raw),surfaces:old.surfaces,blobs:blobs,layerIDs:old.layerIDs,accountedBytes:old.accountedBytes+bytes.count)
  }
  func testNineReferencesPreserveAll737280InheritedCacheBytesAndExactOriginals()throws {
    var bytes=Data();let old=PcraftSmartImportTests(),specs=try old.entries()
    for entry in try helper.entries(){
      let input=try helper.file(entry.file),document=try PcraftImport.read(input),original=try PcraftProject.read(old.file(entry.original))
      XCTAssertEqual(document.layers.count,entry.layers);XCTAssertEqual(try PcraftImport.read(input),document)
      let spec=try XCTUnwrap(specs.first{$0.file==entry.original}),layer=try XCTUnwrap(document.layers.first)
      let projected=try layer.originalSmartAppearanceLayer() ?? SmartFilterEngine.renderedLayer(layer,in:document)
      let words=try old.samples(projected,entry:spec);XCTAssertEqual(words,try old.expected(spec))
      for value in words{var word=value.littleEndian;withUnsafeBytes(of:&word){bytes.append(contentsOf:$0)}}
      for layer in document.layers{
        let object=try XCTUnwrap(layer.smartObject);XCTAssertNil(object.linkedSource)
        XCTAssertTrue(entry.sources.contains{original.blobs[$0.original_blob]==object.data})
        let child=try SmartObjectIO.sourceDocument(object);XCTAssertEqual(child.width,object.width);XCTAssertEqual(child.height,object.height)
      }
      XCTAssertNil(document.sourceMetadata?["psdGlobal_"+entry.tag]);XCTAssertNotNil(document.sourceMetadata?.first{$0.key.hasPrefix("pcraft.psdGlobal.")})
      XCTAssertEqual(try helper.file(entry.file),input)
    }
    let frozen=try Data(contentsOf:helper.folder.appendingPathComponent("pcraft-linked-original-caches.f32le"))
    XCTAssertEqual(bytes.count,737280);XCTAssertEqual(bytes,frozen)
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]{try bytes.write(to:URL(fileURLWithPath:path).appendingPathComponent("pcraft-linked-migrated-caches.f32le"))}
  }
  func testSharedSourceIdentityPlacementAndNativeRoundTripRemainEditableAtEveryDepth()throws {
    for depth in ["u8","u16","f32"]{
      let input=try helper.file("referenced-shared-\(depth).pcraft"),d=try PcraftImport.read(input)
      XCTAssertEqual(d.layers.count,2);XCTAssertEqual(d.layers[0].smartObject?.sourceID,d.layers[1].smartObject?.sourceID)
      XCTAssertEqual(d.layers[0].smartObject?.data,d.layers[1].smartObject?.data)
      XCTAssertEqual(d.minimumArchiveVersion,70)
      XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(d)),d)
      let legacy=try PcraftImport.read(PcraftSmartImportTests().file("shared-\(depth).pcraft"))
      for(a,b)in zip(d.layers,legacy.layers){
        XCTAssertEqual(a.coordinateTransform,b.coordinateTransform);XCTAssertEqual(a.maskCoordinateTransform,b.maskCoordinateTransform)
        XCTAssertEqual(a.smartFilters,b.smartFilters);XCTAssertEqual(a.smartObject?.data,b.smartObject?.data)
      }
    }
  }
  func testRasterizationAndStackModeKeepHistoryOriginalBytesAndOpaqueMetadata()throws {
    for depth in ["u8","u16","f32"]{
      let input=try helper.file("referenced-stack-mean-\(depth).pcraft"),d=try PcraftImport.read(input),layer=try XCTUnwrap(d.layers.first),object=try XCTUnwrap(layer.smartObject)
      XCTAssertEqual(object.stackMode,.mean);let pixels=try Renderer.composite(d)
      var session=EditorSession(document:d);try session.execute(SmartObjectIO.rasterizationCommand(layer,in:d))
      XCTAssertNil(session.document.layers[0].smartObject);XCTAssertEqual(try Renderer.composite(session.document),pixels)
      try session.undo();XCTAssertEqual(session.document,d)
      try session.execute(ImageStack.command(in:d,layerID:layer.id,mode:.maximum))
      XCTAssertEqual(session.document.layers[0].smartObject?.data,object.data);XCTAssertEqual(session.document.sourceMetadata,d.sourceMetadata)
      try session.undo();XCTAssertEqual(session.document,d)
    }
  }
  func testDuplicateAcrossBlocksMissingReferenceWrongSignatureAndMalformedBlockRejectAtomically()throws {
    let entry=try XCTUnwrap(helper.entries().first),input=try helper.file(entry.file),factory=PcraftImportTests()
    for variant in 0..<5{
      let project=try factory.source(input){doc in
        var metadata=doc["metadata"]as![String:Any],blocks=metadata["psd_global_blocks"]as![[String]]
        if variant<2{var duplicate=blocks.last!;if variant==1{duplicate[1]=Data("lnkD".utf8).map{String(format:"%02x",$0)}.joined()};blocks.append(duplicate)}
        if variant==2{blocks[blocks.count-1][0]="00000000"}
        if variant==3{blocks[blocks.count-1][2]=entry.sources[0].original_blob}
        if variant==4{var layers=doc["layers"]as![[String:Any]],content=layers[0]["content"]as![String:Any];content["source"]=["kind":"linked","path":"/not/authorized/do-not-open.pcraft"];layers[0]["content"]=content;doc["layers"]=layers}
        metadata["psd_global_blocks"]=blocks;doc["metadata"]=metadata
      }
      XCTAssertThrowsError(try factory.convert(project),"variant\(variant)");XCTAssertEqual(try helper.file(entry.file),input)
    }
  }
  func testValidExternalAndAliasRecordsNeverUsePlacedPreviewAsOriginal()throws {
    let entry=try XCTUnwrap(helper.entries().first),input=try helper.file(entry.file),project=try PcraftProject.read(input)
    var object=try XCTUnwrap(LinkedSmartObjectIOTests().fixture().layers[0].smartObject)
    object.sourceID=try XCTUnwrap(UUID(uuidString:entry.sources[0].id));var external=PSDWriter();try PSDLinkedSmartObjects.append(object,to:&external)
    let externalProject=try replacingBlock(input,with:external.data)
    XCTAssertThrowsError(try PcraftImportTests().convert(externalProject))
    var alias=try XCTUnwrap(project.blobs[entry.block_blob]);alias.replaceSubrange(8..<12,with:Data("liFA".utf8))
    XCTAssertThrowsError(try PcraftImportTests().convert(replacingBlock(input,with:alias)))
    XCTAssertEqual(try helper.file(entry.file),input)
  }
  func testKnownButUnreferencedOpaqueBlocksStayInactiveForOrdinaryEmbeddedSources()throws {
    let old=PcraftSmartImportTests(),input=try old.file("affine-cached-u8.pcraft"),project=try PcraftProject.read(input)
    let root=try XCTUnwrap(JSONSerialization.jsonObject(with:project.rawManifest)as?[String:Any]),doc=root["document"]as![String:Any],layers=doc["layers"]as![[String:Any]],content=layers[0]["content"]as![String:Any],source=content["source"]as![String:Any],hash=source["blob"]as!String
    let altered=try PcraftImportTests().source(input){doc in var metadata=doc["metadata"]as![String:Any],blocks=metadata["psd_global_blocks"]as![[String]];blocks.append(["3842494d","6c6e6b32",hash]);metadata["psd_global_blocks"]=blocks;doc["metadata"]=metadata}
    let result=try PcraftImportTests().convert(altered)
    XCTAssertEqual(result.layers[0].smartObject?.data,try PcraftImport.read(input).layers[0].smartObject?.data)
    XCTAssertNil(result.sourceMetadata?["psdGlobal_lnk2"])
    XCTAssertTrue(result.sourceMetadata?.contains{$0.key.hasPrefix("pcraft.psdGlobal.") && $0.value==project.blobs[hash]} ?? false)
  }
  func testSourceBudgetAndCancellationRejectWithoutChangingInput()async throws {
    let input=try helper.file("referenced-affine-cached-f32.pcraft"),before=input
    XCTAssertThrowsError(try PcraftImport.read(input,rasterByteLimit:1))
    let task=Task.detached{withUnsafeCurrentTask{$0?.cancel()};return try PcraftImport.read(input)}
    do{_ = try await task.value;XCTFail("Cancelled import returned a model")}catch is CancellationError{}
    XCTAssertEqual(input,before)
  }
}
