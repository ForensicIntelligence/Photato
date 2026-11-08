import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

private struct RichSelectionProbe:ForegroundDetecting,ObjectDetecting,AllObjectsDetecting,PeopleDetecting {
  func mask(for image:Surface) async throws -> SelectionMask {
    let p=image.pixel(x:4,y:3),x=p.r>p.g ? 1:min(8,image.width-3)
    return try .make(.rectangle(.init(x:x,y:1,width:2,height:2)),width:image.width,height:image.height,antiAlias:false)
  }
  func mask(for image:Surface,at point:PathPoint) async throws -> SelectionMask {try await mask(for:image)}
  func masks(for image:Surface) async throws -> [DetectedObjectMask] {[.init(instanceID:1,mask:try await mask(for:image))]}
  func people(in image:Surface) async throws -> [DetectedObjectMask] {try await masks(for:image)}
}

final class SelectionSourceWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8,pixels:Bool = false) throws -> CraftDocument {
    var d=try CraftDocument(width:16,height:8,depth:depth)
    let content:LayerContent = pixels ? .raster(try Surface(width:16,height:8,depth:depth,fill:Pixel(1,0,0))):.fill(Pixel(1,0,0))
    d.layers[0]=Layer(name:"Analysis source",content:content);d.activeLayerID=d.layers[0].id
    d.layers.append(Layer(name:"Unrelated green cover",content:.raster(try Surface(width:16,height:8,depth:depth,fill:Pixel(0,1,0)))))
    return d
  }
  @MainActor func testMagicWandSubjectCapturesItsOwnSamplingAndMatchesHTTPAtEveryDepth() async throws {
    let h=AutomationTests()
    try await h.withService(pressedMouseButtons:{0}) {service,file in
      for depth in PixelDepth.allCases {for all in [false,true] {
        var original=try self.fixture(depth,pixels:true);original.layers[0].locked=true
        let id=try XCTUnwrap(original.activeLayerID)
        file.store.session = .init(document:original);file.store.foregroundDetector=RichSelectionProbe();try service.share(file)
        let native=EditorStore(document:original);defer{native.renderTask?.cancel()}
        native.tool = .magicWand;native.foregroundDetector=RichSelectionProbe()
        native.wandSampleAllLayers=all;native.selectionSampleAllLayers = !all;native.subjectSampleAllLayers = !all
        XCTAssertTrue(native.canSelectSubjectFromToolOptions)
        native.selectSubjectFromToolOptions();XCTAssertTrue(native.geometryBusy)
        native.wandSampleAllLayers = !all
        await native.geometryTask?.value;XCTAssertNil(native.error)
        XCTAssertEqual(native.document.selection,.init(x:all ? 8:1,y:1,width:2,height:2))
        let status=try await h.edit(service,file,"selection.subject",["layerID":id.uuidString,"sampleAllLayers":all])
        XCTAssertEqual(status,200);XCTAssertEqual(file.store.document,native.document)
        XCTAssertEqual(native.document.layers,original.layers);XCTAssertEqual(native.subjectSampleAllLayers,!all)
        XCTAssertEqual(native.session.undoStack.count,1);XCTAssertEqual(file.store.session.undoStack.count,1)
        XCTAssertEqual(try NativeArchive.encodeChunked(native.document),try NativeArchive.encodeChunked(file.store.document))
        let after=native.document;await native.undo();XCTAssertEqual(native.document,original)
        await native.redo();XCTAssertEqual(native.document,after)
      }}
    }
  }
  @MainActor func testMagicWandSubjectReadsExistingSmartObjectsWithoutRasterizing() async throws {
    let h=AutomationTests()
    try await h.withService(pressedMouseButtons:{0}) {service,file in
      let original=try SmartFilterDragTests().fixture(),id=try XCTUnwrap(original.activeLayerID)
      XCTAssertNotNil(original.layers.first{$0.id==id}?.smartObject)
      file.store.session = .init(document:original);file.store.foregroundDetector=RichSelectionProbe();try service.share(file)
      let native=EditorStore(document:original);defer{native.renderTask?.cancel()}
      native.tool = .magicWand;native.foregroundDetector=RichSelectionProbe()
      XCTAssertTrue(native.canSelectSubjectFromToolOptions);native.selectSubjectFromToolOptions()
      await native.geometryTask?.value;XCTAssertNil(native.error)
      let status=try await h.edit(service,file,"selection.subject",["layerID":id.uuidString])
      XCTAssertEqual(status,200);XCTAssertEqual(file.store.document,native.document)
      XCTAssertEqual(native.document.layers,original.layers)
    }
  }
  @MainActor func testObjectFinderRichSourceCachesSamplingSeparatelyAndKeepsOneUndo() async throws {
    let original=try fixture(),store=EditorStore(document:try fixture())
    defer{store.objectFinder.cancel();store.renderTask?.cancel()};store.session = .init(document:original)
    store.allObjectsDetector=RichSelectionProbe();store.tool = .objectSelection
    store.requestObjectFinder();await store.objectFinder.task?.value
    XCTAssertNil(store.objectFinder.error);XCTAssertEqual(store.objectFinder.scene?.objects.first?.bounds.x,1)
    let cache=store.objectFinder.cacheID
    store.selectFoundObject(at:.init(1,1),mode:.replace);await store.geometryTask?.value
    XCTAssertNil(store.error);XCTAssertEqual(store.document.selection,.init(x:1,y:1,width:2,height:2))
    XCTAssertEqual(store.session.undoStack.count,1);XCTAssertEqual(store.objectFinder.cacheID,cache)
    store.selectionSampleAllLayers=true;await store.objectFinder.task?.value
    XCTAssertNotEqual(store.objectFinder.cacheID,cache);XCTAssertEqual(store.objectFinder.scene?.objects.first?.bounds.x,8)
    XCTAssertEqual(store.document.layers,original.layers)
  }
  @MainActor func testHTTPFinderAndPeopleRespectExplicitSourceAndRejectUnavailableContexts() async throws {
    let h=AutomationTests()
    try await h.withService(pressedMouseButtons:{0}) {service,file in
      let original=try self.fixture();file.store.session = .init(document:original)
      file.store.allObjectsDetector=RichSelectionProbe();file.store.peopleDetector=RichSelectionProbe();file.store.peopleFeaturesDetector=nil
      try service.share(file)
      for all in [false,true] {
        let configured=try await h.edit(service,file,"selection.configure",["sampleAllLayers":all]);XCTAssertEqual(configured,200)
        var status=try await h.edit(service,file,"selection.findObjects");XCTAssertEqual(status,200)
        XCTAssertEqual(file.store.objectFinder.scene?.objects.first?.bounds.x,all ? 8:1)
        status=try await h.edit(service,file,"selection.findPeople");XCTAssertEqual(status,200)
        XCTAssertEqual(file.store.peopleWorkspace.scene?.people.first?.bounds.x,all ? 8:1)
        XCTAssertEqual(file.store.document,original);XCTAssertTrue(file.store.session.undoStack.isEmpty)
      }
      var unsupported=original;unsupported.layers[0].content = .adjustment(.invert)
      file.store.session = .init(document:unsupported);file.store.selectionSampleAllLayers=false
      XCTAssertFalse(file.store.canFindObjects);XCTAssertFalse(file.store.canSelectPeople)
      for name in ["selection.findObjects","selection.findPeople"] {
        let status=try await h.edit(service,file,name);XCTAssertEqual(status,422)
      }
      XCTAssertEqual(file.store.document,unsupported);XCTAssertTrue(file.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testNativeAndHTTPObjectPointUseTheSameRichLayerSource() async throws {
    let h=AutomationTests()
    try await h.withService(pressedMouseButtons:{0}) {service,file in
      for all in [false,true] {
        let original=try self.fixture();file.store.session = .init(document:original);file.store.objectDetector=RichSelectionProbe();try service.share(file)
        let native=EditorStore(document:original);defer{native.renderTask?.cancel()}
        native.tool = .objectSelection;native.objectFinderEnabled=false;native.objectDetector=RichSelectionProbe();native.selectionSampleAllLayers=all
        native.selectObject(point:.init(4,3),mode:.replace);await native.geometryTask?.value;XCTAssertNil(native.error)
        let status=try await h.edit(service,file,"selection.object",["region":["point":["x":4,"y":3]],"sampleAllLayers":all,"mode":"replace"])
        XCTAssertEqual(status,200);XCTAssertEqual(file.store.document,native.document)
        XCTAssertEqual(native.document.selection,.init(x:all ? 8:1,y:1,width:2,height:2))
        XCTAssertEqual(file.store.session.undoStack.count,1);XCTAssertEqual(native.document.layers,original.layers)
      }
    }
  }
  @MainActor func testWandSubjectAvailabilityAndCapabilityMappingPreserveOtherPolicies() throws {
    let store=EditorStore(document:try fixture(pixels:true));defer{store.renderTask?.cancel()}
    store.tool = .magicWand;XCTAssertTrue(store.canSelectSubjectFromToolOptions)
    store.geometryBusy=true;XCTAssertFalse(store.canSelectSubjectFromToolOptions);store.geometryBusy=false
    store.aiBusy=true;XCTAssertFalse(store.canSelectSubjectFromToolOptions);store.aiBusy=false
    let id=try XCTUnwrap(store.document.activeLayerID)
    try store.session.execute(.mask(id,try Surface(width:16,height:8,fill:.white)))
    store.maskEditingLayerID=id;XCTAssertFalse(store.canSelectSubjectFromToolOptions)
    let mapping=SelectionToolAPI.subjectSelectionCapability
    XCTAssertEqual((mapping["samplingFieldsByTool"] as? [String:String])?["magicWand"],"magicWand.settings.sampleAllLayers")
    XCTAssertNotNil(MagicWandAPI.capabilities["subjectSelection"])
    XCTAssertEqual(AutomationCommand.definitions.count,267);XCTAssertEqual(ActionLibraryFile.maximumVersion,60)
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:SelectionToolAPI.capabilities))
  }
}
