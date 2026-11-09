import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class AppleRGBProofTests: XCTestCase {
  func testGeneratedICCMatchesIndependentStandardColorimetryFacts() throws {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
      .appendingPathComponent("apple-rgb-proof/reference-facts.json")
    let facts = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let expected = try XCTUnwrap(facts["standard_tags"] as? [String: Any])
    let profile = try NativeModeProfile.appleRGB()
    func n(_ i: Int) -> Int { profile[i..<i+4].reduce(0) { ($0 << 8) | Int($1) } }
    var found = Set<String>()
    for i in 0..<n(128) {
      let row = 132 + 12 * i, key = String(decoding: profile[row..<row+4], as: UTF8.self), start = n(row+4)
      guard let value = expected[key] else { continue }
      if let vector = value as? [Double] {
        XCTAssertEqual((0..<3).map { Double(n(start+8+$0*4)) / 65536 }, vector, key)
      } else {
        let gamma = try XCTUnwrap(value as? [String: Double])
        XCTAssertEqual(Double(Int(profile[start+12]) * 256 + Int(profile[start+13])) / 256, gamma["gamma"], key)
      }
      found.insert(key)
    }
    XCTAssertEqual(found, Set(expected.keys)); XCTAssertEqual(n(0), profile.count)
    if let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      try profile.write(to: URL(fileURLWithPath: path).appendingPathComponent("native-apple-rgb.icc"))
    }
    XCTAssertEqual(try NativeModeProfile.appleRGB(), profile)
    XCTAssertNotEqual(profile, try NativeModeProfile.standard(.rgb, depth: .u16))
    XCTAssertNotEqual(profile, try XCTUnwrap(NSColorSpace.genericRGB.cgColorSpace?.copyICCData() as Data?))
    for depth in PixelDepth.allCases {
      let bytes = try NativeModeProfile.appleRGB(depth: depth)
      try NativeModeProfile.validate(bytes, mode: .rgb, depth: depth)
      XCTAssertEqual(try ICCProfile.isLinear(bytes), depth == .f32)
      if depth != .f32 { XCTAssertEqual(bytes, profile) }
    }
  }

  func testLegacyPresetResetsPriorProofConditionToObservedDefaults() throws {
    var old = ProofSettings(); old.profile = try NativeModeProfile.standard(.cmyk, depth: .u16)
    old.gamutWarning = true; old.intent = .saturation; old.simulatePaper = true; old.simulateBlack = true; old.plate = .cyan
    old.warningColor = Pixel(1, 0, 1); old.warningOpacity = 0.3
    let selected = old.selectingLegacyMacintosh()
    XCTAssertEqual(selected.device, .legacyMacintoshRGB); XCTAssertEqual(selected.profileName, "Apple RGB")
    XCTAssertEqual(selected.displayName, "Macintosh"); XCTAssertNil(selected.profile)
    XCTAssertTrue(selected.enabled); XCTAssertTrue(selected.preserveNumbers); XCTAssertFalse(selected.gamutWarning); XCTAssertFalse(selected.gamutWarningAvailable)
    XCTAssertEqual(selected.intent, .relativeColorimetric); XCTAssertFalse(selected.blackPointCompensation)
    XCTAssertFalse(selected.simulatePaper); XCTAssertFalse(selected.simulateBlack); XCTAssertEqual(selected.plate, .composite)
    XCTAssertEqual(selected.warningColor, old.warningColor); XCTAssertEqual(selected.warningOpacity, old.warningOpacity)
    XCTAssertEqual(try selected.resolvedProfile(), try NativeModeProfile.appleRGB())
    XCTAssertEqual(try JSONDecoder().decode(ProofSettings.self, from: JSONEncoder().encode(selected)), selected)
    var invalid = selected; invalid.profile = try NativeModeProfile.standard(.rgb, depth: .u16)
    XCTAssertThrowsError(try invalid.validate())
  }

  @MainActor func testNativeDraftCancelCommitAndMenuBindingPreservePixelsAndHistory() async throws {
    let store = EditorStore(document: try CraftNSDocument.blankModel(width: 4, height: 3))
    defer { store.renderTask?.cancel() }
    let before = store.document, original = store.proofSettings
    store.beginProof(); let draft = try XCTUnwrap(store.proofWorkspace)
    draft.settings = draft.settings.selectingLegacyMacintosh(); store.previewProof()
    XCTAssertEqual(store.effectiveProof.device, .legacyMacintoshRGB); XCTAssertEqual(store.proofSettings, original)
    store.cancelProof(); XCTAssertEqual(store.proofSettings, original)
    store.beginProof(); store.proofWorkspace?.settings = original.selectingLegacyMacintosh(); store.commitProof()
    await store.renderTask?.value
    XCTAssertNil(store.proofDisplayError); XCTAssertNil(store.proofWorkspace)
    XCTAssertEqual(store.proofSettings, original.selectingLegacyMacintosh())
    XCTAssertEqual(store.document, before); XCTAssertTrue(store.session.undoStack.isEmpty)
    try PhotoshopMenuTests().withMenus { app, menu in
      let item = try XCTUnwrap(PhotoshopMenuTests().allItems(menu).first {
        $0.identifier?.rawValue == "View > Proof Setup > Legacy Macintosh RGB (Gamma 1.8)"
      })
      XCTAssertEqual(item.action, #selector(AppDelegate.proofCommand(_:)))
      XCTAssertTrue(item.keyEquivalent.isEmpty); XCTAssertFalse(app.validateMenuItem(item))
    }
  }

  @MainActor func testHTTPPresetMatchesNativeProofWithoutChangingOrdinaryExports() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let store = document.store
      var source = store.document; source.layers[0].content = .raster(try Surface(width: 4, height: 3, fill: Pixel(0.2, 0.5, 0.8)))
      store.session = EditorSession(document: source)
      try service.share(document)
      let id = try XCTUnwrap(service.shares.first?.id), revision = service.revision(store)
      let normal = try AutomationService.png(source), psd = try DocumentIO.encode(source, format: .psd)
      let expected = store.proofSettings.selectingLegacyMacintosh()
      let status = try await helper.edit(service, document, "proof.configure", ["settings": ["device": "legacyMacintoshRGB"]]); XCTAssertEqual(status, 200)
      await store.renderTask?.value
      XCTAssertEqual(store.proofSettings, expected); XCTAssertNil(store.proofDisplayError)
      let preview = try await helper.request(service, path: "/v1/documents/\(id)/proof-preview.png")
      XCTAssertEqual(preview.0.statusCode, 200); XCTAssertEqual(preview.1, try AutomationService.png(source, proof: expected))
      XCTAssertNotEqual(preview.1, normal)
      XCTAssertEqual(try AutomationService.png(store.document), normal)
      XCTAssertEqual(try DocumentIO.encode(store.document, format: .psd), psd)
      XCTAssertEqual(store.document, source); XCTAssertFalse(document.isDocumentEdited); XCTAssertTrue(store.session.undoStack.isEmpty)
      let stale = try await helper.edit(service, document, "proof.configure", ["settings": ["enabled": false]], revision: revision); XCTAssertEqual(stale, 409)
      XCTAssertEqual(store.proofState["gamutWarningAvailable"] as? Bool, false)
      for value: [String: Any] in [["device": "legacyMacintoshRGB", "plate": "cyan"],
        ["device": "legacyMacintoshRGB", "gamutWarning": true],
        ["device": "legacyMacintoshRGB", "profile": try NativeModeProfile.standard(.rgb, depth: .u16).base64EncodedString()],
        ["device": "legacyMacintoshRGB", "warningOpacity": 2]] {
        let status = try await helper.edit(service, document, "proof.configure", ["settings": value])
        XCTAssertGreaterThanOrEqual(status, 400); XCTAssertEqual(store.proofSettings, expected)
      }
      store.beginProof()
      let busy = try await helper.edit(service, document, "proof.configure", ["settings": ["device": "legacyMacintoshRGB"]]); XCTAssertEqual(busy, 409)
      store.cancelProof(); service.revoke(id)
      let revoked = try await helper.request(service, path: "/v1/documents/\(id)/proof-preview.png"); XCTAssertEqual(revoked.0.statusCode, 404)
    }
  }

  @MainActor func testNonRGBProofUsesColorConversionAndSharesTheNativeResult() async throws {
    let helper = AutomationTests()
    for mode in [DocumentColorMode.grayscale, .cmyk, .lab] {
      try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
        var rgb = document.store.document
        rgb.layers[0].content = .raster(try Surface(width: 4, height: 3, fill: Pixel(0.2, 0.5, 0.8)))
        let source = try rgb.convertingMode(.init(mode: mode, depth: .u16))
        let store = document.store; store.session = EditorSession(document: source)
        try service.share(document)
        let expected = store.proofSettings.selectingLegacyMacintosh(preserveNumbers: false)
        let status = try await helper.edit(service, document, "proof.configure", ["settings": ["device": "legacyMacintoshRGB"]])
        XCTAssertEqual(status, 200); XCTAssertEqual(store.proofSettings, expected)
        await store.renderTask?.value
        XCTAssertNil(store.proofDisplayError); XCTAssertEqual(store.document, source)
        XCTAssertTrue(store.session.undoStack.isEmpty); XCTAssertFalse(document.isDocumentEdited)
        let id = try XCTUnwrap(service.shares.first?.id)
        let preview = try await helper.request(service, path: "/v1/documents/\(id)/proof-preview.png")
        XCTAssertEqual(preview.0.statusCode, 200); XCTAssertEqual(preview.1, try AutomationService.png(source, proof: expected))
      }
    }
  }

  func testProofUsesAppleRGBAtAllDepthsAndKeepsMaximumLogicalGeometrySparse() throws {
    let settings = ProofSettings().selectingLegacyMacintosh()
    for depth in PixelDepth.allCases {
      func source(_ side: Int) throws -> CraftDocument {
        var document = try CraftDocument(width: side, height: side, depth: depth)
        document.layers[0].content = .raster(try Surface(width: side, height: side, depth: depth,
          fill: Pixel(0.25, 0.5, 0.75), colorEncoding: depth == .f32 ? .linearRGB : .sRGB))
        return document
      }
      let small = try source(1), large = try source(300000), before = large
      let proof = try SoftProof.surface(large, settings: settings), expected = try SoftProof.surface(small, settings: settings)
      XCTAssertEqual(proof.width, 300000); XCTAssertEqual(proof.height, 300000); XCTAssertEqual(proof.tileCount, 0)
      XCTAssertEqual(proof.pixel(x: 299999, y: 299999), expected.pixel(x: 0, y: 0)); XCTAssertEqual(large, before)
      var custom = settings; custom.device = .custom; custom.profile = try NativeModeProfile.appleRGB()
      XCTAssertEqual(try SoftProof.surface(small, settings: custom), expected)
    }
  }

  func testAdobeCreationAndOutputUseSharedAppleProfileAtEverySupportedDepth() throws {
    for depth in PixelDepth.allCases {
      let profile = try NativeModeProfile.appleRGB(depth: depth)
      let image: [String: Any] = ["width": 4, "height": 3, "mode": "rgb", "depth": depth == .u8 ? 8 : depth == .u16 ? 16 : 32,
        "iccProfile": ["type": "standard", "name": "Apple RGB", "imageMode": "rgb"]]
      let body: [String: Any] = ["image": image, "outputs": [["mediaType": "image/vnd.adobe.photoshop", "destination": ["validityPeriod": 60]]]]
      let request = try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject: body), createComposite: true)
      let created = try XCTUnwrap(request.creation).document()
      XCTAssertEqual(created.modeDescriptor?.profile, profile)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(created)), created)
      let output = try AdobeOutputProfile(["type": "standard", "name": "Apple RGB", "imageMode": "rgb"])
      XCTAssertEqual(try output.data(resources: [:], depth: depth), profile)
      let source = try DocumentCreation.blank(width: 4, height: 3, depth: depth)
      let converted = try output.convert(source, resources: [:], rasterOutput: false)
      var native = source; try ColorProfileInput.command(.init(.convert, profile: profile), in: native).apply(to: &native)
      XCTAssertEqual(converted.workingICC, native.workingICC); XCTAssertEqual(converted.layers, native.layers)
      let encoded = try XCTUnwrap(AdobeActionAssets.execute(request, input: Data()).first).data
      XCTAssertEqual(try PSDCodec.read(encoded).sourceICC, profile)
    }
    let mismatch = try AdobeOutputProfile(["type": "standard", "name": "Apple RGB", "imageMode": "grayscale"])
    XCTAssertThrowsError(try mismatch.data(resources: [:], depth: .u16))
    XCTAssertTrue((AdobeDocumentCreation.capabilities["standardProfiles"] as? [String])?.contains("Apple RGB") == true)
  }
}
