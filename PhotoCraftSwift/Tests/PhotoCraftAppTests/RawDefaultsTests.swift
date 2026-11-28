import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class RawDefaultsTests: XCTestCase {
  private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Raw")

  private func preset(_ exposure: String) -> RawDefaults.Choice {
    let xmp = Data("""
      <x:xmpmeta xmlns:x="adobe:ns:meta/">
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about="" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
            crs:Exposure2012="\(exposure)" />
        </rdf:RDF>
      </x:xmpmeta>
      """.utf8)
    return .init(mode: .preset, name: "Exposure \(exposure)", xmp: xmp)
  }

  @MainActor func testDefaultsChooseExactBodyThenModelThenMasterAndPersist() throws {
    let body = RawDefaults.Camera(make: "Nikon", model: "D70s", serial: "000123")
    let domain = "Photato.CameraRawDefaultsTests." + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = CameraRawPreferences(defaults: defaults)
    XCTAssertEqual(preferences.rawDefaults, .init())
    let cameraChoice = RawDefaults.Choice(mode: .camera)
    let bodyChoice = preset("0.75")
    var policy = RawDefaults(useOverrides: true, rules: [
      .init(camera: body.withoutSerial, choice: cameraChoice), .init(camera: body, choice: bodyChoice),
    ])
    let originalRevision = preferences.revision
    try preferences.setRawDefaults(policy)
    let revision = preferences.revision
    XCTAssertNotEqual(originalRevision, revision)
    try preferences.setRawDefaults(policy)
    XCTAssertEqual(preferences.revision, revision)
    XCTAssertEqual(CameraRawPreferences(defaults: defaults).rawDefaults, policy)
    XCTAssertEqual(policy.choice(for: .init(make: "NIKON", model: "d70S", serial: "000123")), bodyChoice)
    XCTAssertEqual(policy.choice(for: .init(make: "Nikon", model: "D70s", serial: "123")), cameraChoice)
    XCTAssertEqual(policy.choice(for: .init(make: "Other", model: "D70s")), policy.master)
    XCTAssertEqual(policy.choice(for: nil), policy.master)

    policy.rules.append(.init(camera: .init(make: "NIKON", model: "D70s"), choice: .init()))
    XCTAssertThrowsError(try preferences.setRawDefaults(policy))
    XCTAssertEqual(preferences.revision, revision)
    XCTAssertEqual(CameraRawPreferences(defaults: defaults).rawDefaults, preferences.rawDefaults)
    policy.rules.removeLast()
    policy.useOverrides = false
    try preferences.setRawDefaults(policy)
    XCTAssertEqual(preferences.rawDefaults.choice(for: body), policy.master)
    XCTAssertEqual(preferences.rawDefaults.rules.count, 2)
  }

  func testRawOpenAndPlacementUseSameSensorPixelsAndKeepSavedSettings() throws {
    let fixture = fixtures.appendingPathComponent("synthetic-bayer.dng")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("New.dng")
    let original = try Data(contentsOf: fixture)
    try original.write(to: source)
    let camera = try RawSourceIO.cameraIdentity(at: source)
    let chosen = preset("0.75")
    let policy = RawDefaults(master: .init(mode: .camera), useOverrides: true,
      rules: [.init(camera: camera.withoutSerial, choice: chosen)])
    try policy.validate()

    let factory = try PreparedLocalDocument.read(source, format: .raw).model
    let native = try PreparedLocalDocument.read(source, format: .raw, dngStorage: .embedXMP, rawDefaults: policy).model
    let placed = try XCTUnwrap(PreparedEmbeddedSource.read(source, rawDefaults: policy).document)
    let cameraSettings = try RawSourceIO.open(original, fileName: source.lastPathComponent,
      rawDefaults: .init(master: .init(mode: .camera)))
    let cameraDefault = try development(cameraSettings)
    XCTAssertEqual(try development(factory).shadowBoost, 1)
    XCTAssertEqual(cameraDefault.adjustments.exposure, 0)
    var expected = cameraDefault
    expected.adjustments.exposure = 0.75
    let explicit = try RawSourceIO.open(original, fileName: source.lastPathComponent, settings: expected)
    XCTAssertEqual(try development(native), expected)
    XCTAssertEqual(try development(placed), expected)
    XCTAssertTrue(native.layers[0].content == explicit.layers[0].content)
    XCTAssertTrue(placed.layers[0].content == explicit.layers[0].content)
    XCTAssertFalse(native.layers[0].content == factory.layers[0].content)

    let savedSidecar = try XCTUnwrap(preset("-1.25").xmp)
    let companion = source.deletingPathExtension().appendingPathExtension("xmp")
    try savedSidecar.write(to: companion)
    let edited = try PreparedLocalDocument.read(source, format: .raw, dngStorage: .embedXMP, rawDefaults: policy).model
    XCTAssertEqual(try development(edited).adjustments.exposure, -1.25)
    let placedSaved = try XCTUnwrap(PreparedEmbeddedSource.read(source, rawDefaults: policy).document)
    XCTAssertEqual(try development(placedSaved).adjustments.exposure, -1.25)
    let ignored = try PreparedLocalDocument.read(source, format: .raw, dngStorage: .ignoreSidecarXMP, rawDefaults: policy).model
    XCTAssertEqual(try development(ignored), expected)
    let embedded = try RawSourceIO.prepareLocalSettings(fixtures.appendingPathComponent("raw-with-embedded-xmp.dng"),
      rawDefaults: .init(master: chosen))
    XCTAssertEqual(try development(embedded.document).adjustments.exposure, 0.75)
    XCTAssertEqual(try development(embedded.document).adjustments.contrast, 21)
    XCTAssertEqual(try Data(contentsOf: source), original)
    XCTAssertEqual(try Data(contentsOf: companion), savedSidecar)
  }

  @MainActor func testAuthenticatedDefaultsAreRevisionedAndUploadsOptIn() async throws {
    let original = try Data(contentsOf: fixtures.appendingPathComponent("synthetic-bayer.dng"))
    let chosen = preset("1.5")
    let policy = RawDefaults(master: chosen)
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, initial in
      defer { for doc in service.controller.documents where doc !== initial { doc.close() } }
      service.setDocumentTransfersEnabled(true)
      let route = AutomationService.cameraRawPreferencesPath
      let state = try await helper.request(service, path: route)
      let body = try XCTUnwrap(JSONSerialization.jsonObject(with: state.1) as? [String: Any])
      let revision = try XCTUnwrap(body["revision"] as? String)
      let update: [String: Any] = ["revision": revision, "rawDefaults": policy.apiState]
      let denied = try await helper.request(service, path: route, body: update)
      XCTAssertEqual(denied.0.statusCode, 403)
      service.setPhotoshopPreferenceChangesEnabled(true)
      let invalid = try await helper.request(service, path: route, body: ["revision": revision,
        "openAsSmartObject": true, "rawDefaults": ["useOverrides": true]])
      XCTAssertEqual(invalid.0.statusCode, 400)
      XCTAssertFalse(service.controller.cameraRawPreferences.openAsSmartObject)
      let accepted = try await helper.request(service, path: route, body: update)
      XCTAssertEqual(accepted.0.statusCode, 200, String(decoding: accepted.1, as: UTF8.self))
      XCTAssertEqual(service.controller.cameraRawPreferences.rawDefaults, policy)
      let stale = try await helper.request(service, path: route, body: update)
      XCTAssertEqual(stale.0.statusCode, 409)

      let upload = AutomationOpeningTests()
      let cases: [([String: String], Float)] = [
        ([:], 0), (["X-Photato-Raw-Defaults": "desktop"], 1.5),
        (["X-Photato-Raw-Defaults": "desktop", "X-Photato-Raw-XMP": try XCTUnwrap(preset("-0.5").xmp).base64EncodedString()], -0.5),
      ]
      for (headers, expected) in cases {
        let imported = try await upload.upload(service, bytes: original, type: "image/x-adobe-dng", headers: headers)
        XCTAssertEqual(imported.0.statusCode, 201, String(decoding: imported.1, as: UTF8.self))
        let document = try XCTUnwrap(service.shares.last?.document)
        XCTAssertEqual(try development(document.store.document).adjustments.exposure, expected)
      }
    }
  }

  private func development(_ document: CraftDocument) throws -> RawDevelopment {
    try XCTUnwrap(document.layers.first?.smartObject?.rawDevelopment)
  }
}
