import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class AdobeDocumentCreationTests: XCTestCase {
  private let profileURL = URL(string: "https://example.test/profile.icc")!
  private func body(_ image: [String: Any], actions: Bool = false) -> [String: Any] {
    var result: [String: Any] = ["image": image, "outputs": [
      ["mediaType": "image/vnd.adobe.photoshop", "destination": ["validityPeriod": 60]],
    ]]
    if actions { result["options"] = ["actions": [["source": ["contentType": "application/json",
      "content": "[{\"_obj\":\"selectAllLayers\",\"_target\":[{\"_ref\":\"layer\",\"_enum\":\"ordinal\",\"_value\":\"targetEnum\"}]}]"]]]] }
    return result
  }
  private func request(_ image: [String: Any], photato: Bool = false) throws -> AdobeActionsRequest {
    try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject: body(image, actions: photato)),
      allowPhotatoOptions: photato, createComposite: !photato)
  }
  private func image(_ mode: DocumentColorMode, _ depth: PixelDepth) -> [String: Any] {
    ["width": 4, "height": 3, "mode": mode.rawValue, "depth": depth == .u8 ? 8 : depth == .u16 ? 16 : 32,
      "name": "Mode creation", "fill": "transparent", "resolution": ["value": 300, "unit": "density_unit"]]
  }
  private func assertStorage(_ actual: CraftDocument, _ expected: CraftDocument,
    file: StaticString = #filePath, line: UInt = #line) throws {
    if expected.colorMode == .rgb {
      guard case .raster(let a) = actual.layers[0].content,
        case .raster(let e) = expected.layers[0].content else { return XCTFail("Missing RGB pixels", file: file, line: line) }
      XCTAssertEqual(try a.rgbaData(depth: actual.depth), try e.rgbaData(depth: expected.depth), file: file, line: line)
      XCTAssertEqual(actual.sourceICC, expected.modeDescriptor?.profile, file: file, line: line)
    } else { XCTAssertEqual(actual.layers[0].nativeMode, expected.layers[0].nativeMode, file: file, line: line) }
  }
  func testDefaultsAndAllSupportedModeDepthsRetainNativePlanesInPSDAndArchive() throws {
    let defaults = try XCTUnwrap(request(["width": 4, "height": 3]).creation).document()
    XCTAssertEqual(defaults.colorMode, .rgb); XCTAssertEqual(defaults.depth, .u8)
    XCTAssertEqual(defaults.name, "Untitled-1"); XCTAssertEqual(defaults.pixelsPerInch, 72)
    XCTAssertEqual(defaults.layers[0].name, "Background")
    for mode in DocumentColorMode.componentModes { for depth in mode.depths {
      let request = try request(image(mode, depth))
      XCTAssertNil(request.input)
      let expected = try DocumentCreation.blank(width: 4, height: 3, depth: depth,
        background: .clear, name: "Mode creation", mode: mode, resolution: 300)
      let created = try XCTUnwrap(request.creation).document()
      XCTAssertEqual(created.name, expected.name); XCTAssertEqual(created.modeDescriptor, expected.modeDescriptor)
      XCTAssertEqual(created.layers[0].nativeMode, expected.layers[0].nativeMode)
      XCTAssertEqual(created.layers[0].name, "Layer 1")
      let bytes = try XCTUnwrap(AdobeActionAssets.execute(request, input: Data()).first).data
      let reopened = try AdobeActionAssets.decode(bytes)
      XCTAssertEqual(reopened.depth, depth); XCTAssertEqual(reopened.colorMode, mode)
      try assertStorage(reopened, created)
      XCTAssertEqual(reopened.pixelsPerInch, 300, accuracy: 0.01)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(created)), created)
    } }
  }
  func testStandardAndCustomProfilesRemainModeSpecificAndBounded() throws {
    for (mode, title) in [(DocumentColorMode.rgb, "Adobe RGB (1998)"), (.rgb, "sRGB IEC61966-2.1"), (.grayscale, "Gray Gamma 2.2")] {
      for depth in mode.depths {
        var raw = image(mode, depth)
        raw["iccProfile"] = ["type": "standard", "name": title, "imageMode": mode.rawValue]
        let created = try XCTUnwrap(request(raw).creation).document()
        try NativeModeProfile.validate(XCTUnwrap(created.modeDescriptor).profile, mode: mode, depth: depth)
        if title == "Adobe RGB (1998)" { XCTAssertNotEqual(created.modeDescriptor?.profile, try NativeModeProfile.standard(mode, depth: depth)) }
      }
    }
    for mode in DocumentColorMode.componentModes {
      var raw = image(mode, .u16)
      raw["iccProfile"] = ["type": "custom", "name": "Owned profile", "source": ["url": profileURL.absoluteString]]
      let creation = try XCTUnwrap(request(raw).creation), bytes = try NativeModeProfile.standard(mode, depth: .u16)
      XCTAssertEqual(creation.resource, profileURL)
      XCTAssertEqual(try creation.document(resources: [profileURL: bytes]).modeDescriptor?.profile, bytes)
      XCTAssertThrowsError(try creation.document())
      XCTAssertThrowsError(try creation.document(resources: [profileURL: Data(count: ICCProfile.maximumBytes + 1)]))
      XCTAssertThrowsError(try creation.document(resources: [profileURL: Data("bad ICC".utf8)]))
      if mode != .rgb { XCTAssertThrowsError(try creation.document(resources: [profileURL: NativeModeProfile.standard(.rgb, depth: .u16)])) }
    }
    var raw = image(.rgb, .f32)
    raw["iccProfile"] = ["type": "custom", "name": "nonlinear", "source": ["url": profileURL.absoluteString]]
    XCTAssertThrowsError(try request(raw).creation?.document(resources: [profileURL: NativeModeProfile.standard(.rgb, depth: .u8)]))
  }
  func testInvalidAndUnsupportedParametersFailBeforeJobsOrAllocations() throws {
    let cases: [([String: Any], Int)] = [
      (["width": true], 400), (["height": 0], 400), (["height": 2.5], 400),
      (["width": 32_001, "height": 32_000], 400), (["mode": "unknown"], 400),
      (["mode": "indexed"], 422), (["depth": 12], 400), (["depth": 1], 422),
      (["mode": "cmyk", "depth": 32], 422), (["name": String(repeating: "x", count: 256)], 400),
      (["unit": "points_unit"], 422), (["unit": "bad"], 400), (["pixelScaleFactor": true], 400),
      (["pixelScaleFactor": 0], 400), (["pixelScaleFactor": 2], 422),
      (["resolution": ["unit": "density_unit", "value": 0]], 400), (["resolution": ["value": 72]], 400),
      (["fill": "red"], 400), (["fill": ["solidColor": ["rgb": ["red": 1, "green": 2, "blue": 3]]]], 400),
      (["iccProfile": NSNull()], 400), (["iccProfile": ["type": "standard", "name": "Apple RGB"]], 422),
      (["iccProfile": ["type": "standard", "name": "Gray Gamma 2.2"]], 400),
      (["iccProfile": ["type": "custom", "name": "x", "source": ["url": "file:///private/profile.icc"]]], 400),
    ]
    for (changes, status) in cases {
      var raw: [String: Any] = ["width": 4, "height": 3]
      raw.merge(changes) { _, new in new }
      XCTAssertThrowsError(try request(raw), "\(changes)") { XCTAssertEqual(($0 as? AdobeAPIError)?.status, status, "\(changes): \($0)") }
    }
    XCTAssertThrowsError(try request(["width": 4]))
    XCTAssertThrowsError(try request(["width": 4, "height": 3, "source": ["url": profileURL.absoluteString]]))
    let execute = try JSONSerialization.data(withJSONObject: body(["width": 4, "height": 3], actions: true))
    XCTAssertThrowsError(try AdobeActionsRequest(data: execute), "Adobe execute-actions must keep its ImageSource contract")
    let white = try request(["width": 2, "height": 2, "fill": "white"]).creation?.document()
    let background = try request(["width": 2, "height": 2, "fill": "background_color"]).creation?.document()
    XCTAssertEqual(white?.layers[0].nativeMode, background?.layers[0].nativeMode)
  }
  func testRGBActionTargetsCannotSilentlyEditDifferentModeComponents() throws {
    let program = try PhotoshopActionProgram(actionJSON: "[{\"_obj\":\"select\",\"_target\":[{\"_ref\":\"channel\",\"_enum\":\"channel\",\"_value\":\"red\"}]}]")
    for mode in [DocumentColorMode.grayscale, .cmyk, .lab] {
      let document = try DocumentCreation.blank(width: 3, height: 2, mode: mode)
      XCTAssertThrowsError(try program.applying(to: document))
      XCTAssertThrowsError(try program.applying(to: document, components: .red))
    }
  }
  @MainActor func testFileNewModeDepthResolutionProfileAndBackgroundUseSameEngine() throws {
    _ = NSApplication.shared
    let controls = NewDocumentOptions()
    controls.widthField.stringValue = "4"; controls.heightField.stringValue = "3"
    controls.resolutionField.stringValue = "300"; controls.backgroundMenu.selectItem(at: 1)
    for mode in DocumentColorMode.componentModes { for depth in mode.depths {
      controls.modeMenu.selectItem(at: try XCTUnwrap(DocumentColorMode.componentModes.firstIndex(of: mode)))
      controls.modeChanged()
      controls.depthMenu.selectItem(at: try XCTUnwrap(PixelDepth.allCases.firstIndex(of: depth)))
      controls.depthChanged()
      let actual = try controls.document(name: "Mode creation")
      let expected = try XCTUnwrap(request(image(mode, depth)).creation).document()
      XCTAssertEqual(actual.layers[0].nativeMode, expected.layers[0].nativeMode)
      XCTAssertEqual(actual.modeDescriptor, expected.modeDescriptor)
      XCTAssertEqual(actual.pixelsPerInch, 300)
    } }
    controls.modeMenu.selectItem(at: 0); controls.modeChanged(); controls.depthMenu.selectItem(at: 2)
    controls.modeMenu.selectItem(at: 2); controls.modeChanged()
    XCTAssertEqual(controls.depth, .u16); XCTAssertFalse(try XCTUnwrap(controls.depthMenu.item(at: 2)).isEnabled)
    let profile = try NativeModeProfile.standard(.cmyk, depth: .u16)
    try controls.setProfile(profile, name: "Owned CMYK")
    XCTAssertThrowsError(try controls.setProfile(NativeModeProfile.standard(.rgb, depth: .u16), name: "Wrong"))
    XCTAssertEqual(controls.profile, profile)
    XCTAssertEqual(try controls.document(name: "ICC").modeDescriptor?.profile, profile)
    controls.depthChanged(); XCTAssertNil(controls.profile)
    controls.resolutionField.stringValue = "nan"; XCTAssertThrowsError(try controls.document(name: "Invalid"))
    controls.resolutionField.stringValue = "72"; controls.widthField.stringValue = "no"; XCTAssertThrowsError(try controls.document(name: "Invalid"))
    let legacy = try CraftNSDocument.blankModel(width: 2, height: 2)
    XCTAssertFalse(legacy.hasNativeModeStorage, "Existing callers retain their legacy document layout")
  }
  @MainActor func testBothHTTPInterfacesCreateNativeDocumentsWithoutFetchingAnImage() async throws {
    let helper = AutomationEncodingOptionsTests(), transport = CreationTransport()
    try await AutomationTests().withService(pressedMouseButtons: { 0 }, resourceTransport: transport) { service, shared in
      let before = shared.store.document, payload = body(image(.cmyk, .u16))
      let disabled = try await AutomationTests().request(service, path: "/v2/create-composite", body: payload)
      XCTAssertEqual(disabled.0.statusCode, 403)
      service.setResourceJobsEnabled(true)
      for mode in DocumentColorMode.componentModes {
        service.setResourceJobsEnabled(false); service.setResourceJobsEnabled(true)
        for depth in mode.depths {
        let raw = image(mode, depth)
        let expected = try XCTUnwrap(request(raw).creation).document()
        for route in ["/v2/create-composite", "/v1/action-jobs"] {
          let output = try await helper.outputs(service, route: route, payload: body(raw, actions: route.hasPrefix("/v1")))
          let actual = try AdobeActionAssets.decode(XCTUnwrap(output.first))
          try assertStorage(actual, expected)
          XCTAssertEqual(actual.colorMode, mode); XCTAssertEqual(actual.depth, depth)
        }
      } }
      let rejected = try await AutomationTests().request(service, path: "/v2/execute-actions", body: body(image(.rgb, .u8), actions: true))
      XCTAssertEqual(rejected.0.statusCode, 422)
      XCTAssertEqual(shared.store.document, before); XCTAssertTrue(service.shares.isEmpty)
      let fetches = await transport.fetches; XCTAssertTrue(fetches.isEmpty)
      let caps = try await AutomationTests().request(service, path: "/v1/capabilities")
      XCTAssertTrue(String(decoding: caps.1, as: UTF8.self).contains("blankDocumentCreation"))
    }
  }
  func testDiscoverableSchemaUsesPinnedImageParametersAndPreservesRequestExamples() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let spec = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("docs/contracts/adobe-photoshop-v2.json"))) as? [String: Any])
    let components = try XCTUnwrap(spec["components"] as? [String: Any])
    let schemas = try XCTUnwrap(components["schemas"] as? [String: Any])
    let pinned = try XCTUnwrap(schemas["ImageParameters"] as? [String: Any])
    let all = try XCTUnwrap(pinned["allOf"] as? [[String: Any]])
    let reference = try XCTUnwrap(all.last?["properties"] as? [String: Any])
    let properties = try XCTUnwrap(AdobeDocumentCreation.parameterSchema["properties"] as? [String: Any])
    XCTAssertEqual(Set(properties.keys), Set(reference.keys))
    XCTAssertEqual(pinned["required"] as? [String], ["height", "width"])
    var examples: [[String: Any]] = []
    for mode in DocumentColorMode.componentModes { for depth in mode.depths {
      let raw = image(mode, depth); _ = try request(raw); examples.append(body(raw))
    } }
    for (mode, name) in [(DocumentColorMode.rgb, "sRGB IEC61966-2.1"), (.rgb, "Adobe RGB (1998)"), (.grayscale, "Gray Gamma 2.2")] {
      var raw = image(mode, .u16); raw["iccProfile"] = ["type": "standard", "name": name, "imageMode": mode.rawValue]
      _ = try request(raw); examples.append(body(raw))
    }
    var raw = image(.cmyk, .u16)
    raw["iccProfile"] = ["type": "custom", "name": "Owned", "source": ["url": profileURL.absoluteString], "imageMode": "cmyk"]
    _ = try request(raw); examples.append(body(raw))
    if let folder = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let url = URL(fileURLWithPath: folder); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      try JSONSerialization.data(withJSONObject: ["requests": examples, "localImageSchema": AdobeDocumentCreation.parameterSchema], options: [.prettyPrinted, .sortedKeys])
        .write(to: url.appendingPathComponent("creation-contract-cases.json"))
    }
  }
  @MainActor func testNewDocumentControlsFitInsideTheirHostedWindow() throws {
    _ = NSApplication.shared
    let controls = NewDocumentOptions()
    let window = NSWindow(contentRect: controls.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = controls
    defer { window.close() }
    controls.layoutSubtreeIfNeeded()
    for child in controls.arrangedSubviews {
      XCTAssertTrue(controls.bounds.insetBy(dx: -1, dy: -1).contains(child.frame), "New document control escaped: \(child.frame)")
    }
    if let folder = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"],
      let bitmap = controls.bitmapImageRepForCachingDisplay(in: controls.bounds) {
      controls.cacheDisplay(in: controls.bounds, to: bitmap)
      let url = URL(fileURLWithPath: folder); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      try bitmap.representation(using: .png, properties: [:])?.write(to: url.appendingPathComponent("new-document.png"))
    }
  }
  @MainActor func testCustomICCJobsFetchOnlyProfileAndRevocationCannotPublishLateOutput() async throws {
    let bytes = try NativeModeProfile.standard(.cmyk, depth: .u16)
    var raw = image(.cmyk, .u16)
    raw["iccProfile"] = ["type": "custom", "name": "Owned", "source": ["url": profileURL.absoluteString], "imageMode": "cmyk"]
    let transport = CreationTransport(resources: [profileURL: bytes], paused: true)
    let jobs = AdobeActionJobs(transport: transport), base = URL(string: "http://127.0.0.1:43210")!
    defer { jobs.revoke() }
    let first = try jobs.submit(request(raw), baseURL: base)
    for _ in 0..<200 { if await transport.started { break }; try await Task.sleep(for: .milliseconds(10)) }
    let started = await transport.started; XCTAssertTrue(started)
    jobs.revoke(); await transport.release()
    let second = try jobs.submit(request(raw), baseURL: base)
    for _ in 0..<200 {
      if [.succeeded, .failed].contains(jobs.snapshot(second.id)?.status) { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertNil(jobs.snapshot(first.id))
    let result = try XCTUnwrap(jobs.snapshot(second.id))
    XCTAssertEqual(result.status, .succeeded, result.error?.message ?? "")
    let output = try XCTUnwrap(result.outputs.first), id = try XCTUnwrap(UUID(uuidString: output.url.lastPathComponent))
    XCTAssertEqual(try AdobeActionAssets.decode(XCTUnwrap(jobs.asset(id)).data).modeDescriptor?.profile, bytes)
    let fetches = await transport.fetches; XCTAssertEqual(fetches, [profileURL, profileURL])
  }
}

private actor CreationTransport: AdobeResourceTransport {
  let resources: [URL: Data]
  var fetches: [URL] = []
  var started = false
  var paused: Bool
  var continuation: CheckedContinuation<Void, Never>?
  init(resources: [URL: Data] = [:], paused: Bool = false) { self.resources = resources; self.paused = paused }
  func fetch(_ url: URL) async throws -> Data {
    fetches.append(url); started = true
    if paused { await withCheckedContinuation { continuation = $0 } }
    guard let bytes = resources[url] else { throw CraftError.invalid("Unexpected resource fetch") }
    return bytes
  }
  func release() { paused = false; continuation?.resume(); continuation = nil }
  func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws { throw CraftError.invalid("Expected hosted output") }
}
