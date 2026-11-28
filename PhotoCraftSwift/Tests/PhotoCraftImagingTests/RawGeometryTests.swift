import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class RawGeometryTests: XCTestCase {
  func testOffsetsAndAspectPreservingConstrainedFraming() throws {
    let width = 100, height = 80
    let source = try Surface.linearPatch(width: width, height: height) { x, y in
      Pixel(Float(x) / 32, Float(y) / 64, 0.375, 1)
    }
    XCTAssertEqual(try RawGeometryRenderer.develop(source, geometry: nil, crop: nil), source)
    var geometry = RawGeometrySettings()
    geometry.offsetX = 10
    geometry.offsetY = -5
    let shifted = try RawGeometryRenderer.develop(source, geometry: geometry, crop: nil)
    XCTAssertEqual([shifted.width, shifted.height], [width, height])
    XCTAssertEqual(shifted.linearPixel(x: 5, y: 20), .clear)
    XCTAssertEqual(shifted.linearPixel(x: 30, y: 1), .clear)
    let moved = shifted.linearPixel(x: 60, y: 30)
    XCTAssertEqual(moved.r, (60 - 6.44) / 32, accuracy: 0.000_01)
    XCTAssertEqual(moved.g, (30 - 2.72) / 64, accuracy: 0.000_01)

    geometry.constrainCrop = true
    let trimmed = try RawGeometryRenderer.develop(source, geometry: geometry, crop: nil)
    XCTAssertEqual([trimmed.width, trimmed.height], [93, 74])
    XCTAssertTrue(try trimmed.allStoredSamplesSatisfy { $0.a > 0.999_99 })

    let recorded = try RawCropBounds(left: 0, top: 0, right: 1, bottom: 1)
    let reopened = try RawGeometryRenderer.develop(source, geometry: geometry, crop: recorded)
    XCTAssertEqual([reopened.width, reopened.height], [width, height])
    XCTAssertTrue(try reopened.allStoredSamplesSatisfy { $0.a > 0.999_99 })
  }

  func testProjectiveControlsUseTheTransformedCropAndRetainLinearHighlights() throws {
    let width = 180, height = 176
    let source = try Surface.linearPatch(width: width, height: height) { _, _ in
      Pixel(1.5, 0.75, 0.25, 1)
    }
    var geometry = RawGeometrySettings()
    geometry.vertical = 30
    geometry.horizontal = -20
    geometry.rotation = 4.5
    geometry.aspect = 12
    geometry.scale = 105
    geometry.constrainCrop = true
    let cropped = try RawGeometryRenderer.develop(source, geometry: geometry, crop: nil)
    XCTAssertLessThan(cropped.width * cropped.height, width * height)
    XCTAssertTrue(try cropped.allStoredSamplesSatisfy { $0.a > 0.999_99 })
    XCTAssertEqual(cropped.linearPixel(x: cropped.width / 2, y: cropped.height / 2).r, 1.5, accuracy: 0.000_01)
    let bounds = try RawCropBounds(left: 0.25, top: 0.25, right: 0.75, bottom: 0.75)
    let explicitCrop = try RawGeometryRenderer.develop(source, geometry: geometry, crop: bounds)
    XCTAssertEqual([explicitCrop.width, explicitCrop.height], [90, 88])
  }

  func testManualGeometryXMPRoundTripAndPartialJSONUpdate() throws {
    let packet = Data("""
      <x:xmpmeta xmlns:x="adobe:ns:meta/">
      <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
      <rdf:Description rdf:about="" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
        crs:PerspectiveVertical="+30" crs:PerspectiveHorizontal="-20" crs:PerspectiveRotate="+4.5"
        crs:PerspectiveAspect="+12" crs:PerspectiveScale="105" crs:PerspectiveX="+7.50" crs:PerspectiveY="-4.50"
        crs:CropConstrainToWarp="1" crs:HasCrop="True" crs:CropTop="0.097292"
        crs:CropLeft="0.073798" crs:CropBottom="1" crs:CropRight="0.976506" crs:CropAngle="0" />
      </rdf:RDF></x:xmpmeta>
      """.utf8)
    let stored = try CameraRawXMP.read(packet, into: RawDevelopment())
    var expected = RawGeometrySettings()
    expected.vertical = 30
    expected.horizontal = -20
    expected.rotation = 4.5
    expected.aspect = 12
    expected.scale = 105
    expected.offsetX = 7.5
    expected.offsetY = -4.5
    expected.constrainCrop = true
    XCTAssertEqual(stored.geometry, expected)
    XCTAssertEqual(stored.crop, try RawCropBounds(left: 0.073798, top: 0.097292, right: 0.976506, bottom: 1))
    XCTAssertEqual(try CameraRawXMP.read(CameraRawXMP.write(stored), into: RawDevelopment()), stored)
    let updated = try RawDevelopment.decodeJSON(Data(#"{"geometry":{"offsetX":0}}"#.utf8), base: stored)
    expected.offsetX = 0
    XCTAssertEqual(updated.geometry, expected)
    XCTAssertEqual(updated.crop, stored.crop)
    XCTAssertThrowsError(try RawDevelopment.decodeJSON(Data(#"{"geometry":{"rotation":true}}"#.utf8), base: stored))
    let cleared = try RawDevelopment.decodeJSON(Data(#"{"geometry":null}"#.utf8), base: stored)
    let reset = try CameraRawXMP.write(cleared, replacing: packet)
    XCTAssertNil(try CameraRawXMP.read(reset, into: RawDevelopment()).geometry)
    XCTAssertEqual(try CameraRawXMP.read(reset, into: RawDevelopment()).crop, stored.crop)
  }
}
