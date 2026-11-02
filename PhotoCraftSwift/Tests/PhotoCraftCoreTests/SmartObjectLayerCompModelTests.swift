import XCTest
@testable import PhotoCraftCore

final class SmartObjectLayerCompModelTests: XCTestCase {
  func model() throws -> SmartObject {
    var object = try SmartObject(fileName: "Owned.photato", mediaType: "application/vnd.photato.document", data: Data([1]), width: 4, height: 3)
    object.layerComps = try .init(entries: [.init(id: UUID(), name: "Red"), .init(id: UUID(), name: "Blue")]); return object
  }
  func testSelectionsChangePresentationIdentityWhileKeepingSharedSourceIdentity() throws {
    let original = try model(); var red = original, blue = original
    red.layerComps?.selectedID = original.layerComps!.entries[0].id; blue.layerComps?.selectedID = original.layerComps!.entries[1].id
    XCTAssertNotEqual(red, blue); XCTAssertNotEqual(red.revision, blue.revision)
    XCTAssertEqual(red.dataFingerprint, blue.dataFingerprint); XCTAssertTrue(red.sharesSource(with: blue)); XCTAssertFalse(red.matchesAppearanceIdentity(blue))
    var legacy = original; legacy.layerComps = nil; XCTAssertTrue(legacy.sharesSource(with: blue))
    var d = try CraftDocument(width: 4, height: 3)
    d.layers[0].smartObject = red; var second = d.layers[0]; second.id = UUID(); second.smartObject = blue; d.layers.append(second)
    XCTAssertNoThrow(try d.validate()); XCTAssertEqual(d.minimumArchiveVersion, 80)
  }
  func testInvalidCataloguesAndSelectionsRejectWithoutChangingAnExistingChoice() throws {
    let object = try model(), choices = object.layerComps!, id = choices.entries[0].id
    XCTAssertThrowsError(try SmartObjectLayerComps(entries: []))
    XCTAssertThrowsError(try SmartObjectLayerComps(entries: [.init(id: id, name: "a"), .init(id: id, name: "b")]))
    XCTAssertThrowsError(try SmartObjectLayerComps(entries: [.init(id: id, name: "")]))
    XCTAssertThrowsError(try SmartObjectLayerComps(entries: choices.entries, selectedID: UUID()))
    var selected = choices; selected.selectedID = id
    let replacement = try SmartObjectLayerComps(entries: [choices.entries[1]])
    XCTAssertThrowsError(try replacement.preservingSelection(from: selected)); XCTAssertEqual(selected.selectedID, id)
  }
  func testNative80RoundTripAtAllDepthsAndOlderObjectsRetainTheirFeatureVersion() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 4, height: 3, depth: depth); d.layers[0].smartObject = try model()
      for data in [try NativeArchive.encode(d), try NativeArchive.encodeChunked(d)] {
        XCTAssertEqual(try NativeArchive.decode(data), d); XCTAssertEqual(try NativeArchive.decodePaged(data), d)
      }
      d.layers[0].smartObject?.layerComps = nil; XCTAssertEqual(d.minimumArchiveVersion, 14)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)), d)
    }
  }
  func testMaximumSourceRevisionReadsAreStableAndSourceMutationInvalidatesTheCachedIdentity() throws {
    var object = try SmartObject(fileName: "Maximum.photato", mediaType: "application/vnd.photato.document", data: Data(repeating: 23, count: SmartObject.maximumSourceBytes), width: 4, height: 3)
    object.layerComps = try model().layerComps
    let selected = object.layerComps?.entries[0].id; object.layerComps?.selectedID = selected
    let original = object.revision, started = ContinuousClock.now
    for _ in 0..<1000 { XCTAssertEqual(object.revision, original) }
    let elapsed = started.duration(to: .now)
    print("SMART_COMP_REVISION_1000_READS", "sourceBytes", SmartObject.maximumSourceBytes, "duration", elapsed)
    object.data = Data([1, 2, 3]); XCTAssertNotEqual(object.revision, original)
    XCTAssertEqual(object.revision, try JSONDecoder().decode(SmartObject.self, from: JSONEncoder().encode(object)).revision)
  }
}
