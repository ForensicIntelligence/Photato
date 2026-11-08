import AppKit
import ImagePlayground
import PhotoCraftAI
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class ImageGenerationPresentationWorkflowTests: XCTestCase {
  @MainActor func job(width: Int, height: Int) throws -> ImageGenerationJob {
    _ = NSApplication.shared
    return ImageGenerationJob(source: try CraftDocument(width: width, height: height),
      revision: UUID(), lifecycle: UUID(), prompt: "Owned red apple in a studio", processing: .privateCloudCompute)
  }

  @MainActor func testModernNativeControllerUsesAnyStyleAndClosestCapturedCanvas() throws {
    guard LocalAI.platform.available else {
      XCTAssertFalse(LocalAI.imageCapability.available)
      return
    }
    guard #available(macOS 27.0, *) else { throw XCTSkip("Modern system configuration requires macOS27") }
    for size in [(1920, 1080), (1080, 1920), (512, 512)] {
      let request = try job(width: size.0, height: size.1)
      let controller = SystemImagePlayground.makeController(job: request,
        presentation: ImageGenerationPresentation(majorVersion: 27))
      XCTAssertEqual(controller.allowedGenerationStyles, [.any, .illustration, .animation, .sketch])
      XCTAssertEqual(controller.selectedGenerationStyle, .any)
      XCTAssertFalse(controller.allowedGenerationStyles.contains(.externalProvider))
      XCTAssertEqual(controller.options.personalization, .disabled)
      XCTAssertEqual(controller.options.sizeSpecification,
        .closest(to: CGSize(width: Double(size.0), height: Double(size.1))))
      XCTAssertEqual(controller.concepts.count, 1)
    }
  }

  @MainActor func testLegacyNativeConfigurationRetainsStylesAndSystemSizeDefault() throws {
    guard LocalAI.platform.available else {
      XCTAssertFalse(LocalAI.imageCapability.available)
      return
    }
    guard #available(macOS 26.0, *) else { throw XCTSkip("System image creation requires macOS26") }
    let controller = SystemImagePlayground.makeController(job: try job(width: 1920, height: 1080),
      presentation: ImageGenerationPresentation(majorVersion: 26))
    XCTAssertEqual(controller.allowedGenerationStyles, [.illustration, .animation, .sketch])
    XCTAssertEqual(controller.selectedGenerationStyle, .illustration)
    XCTAssertFalse(controller.allowedGenerationStyles.contains(.externalProvider))
    if #available(macOS 26.4, *) { XCTAssertEqual(controller.options.personalization, .disabled) }
    if #available(macOS 27.0, *) {
      XCTAssertEqual(controller.options.sizeSpecification, ImagePlaygroundOptions().sizeSpecification)
    }
  }

  @MainActor func testCapturedDimensionsSurviveSourceReplacementAndCancellation() throws {
    let helper = ImageGenerationLifecycleTests(), store = try helper.store()
    defer { store.cancelAIWork(); store.renderTask?.cancel() }
    let request = try helper.begin(store)
    XCTAssertEqual(request.sourceWidth, 8); XCTAssertEqual(request.sourceHeight, 6)
    store.session = EditorSession(document: try CraftDocument(width: 12, height: 4))
    store.cancelImageGeneration(request.id)
    XCTAssertNil(request.original); XCTAssertEqual(request.phase, .cancelled)
    XCTAssertEqual(request.sourceWidth, 8); XCTAssertEqual(request.sourceHeight, 6)
    let current = try XCTUnwrap(AIImageAPI.state(store)["job"] as? [String: Any])
    XCTAssertEqual(current["sourceCanvasSize"] as? [String: Int], ["width": 8, "height": 6])
    XCTAssertEqual(store.document.width, 12); XCTAssertEqual(store.document.height, 4)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }

  @MainActor func testHTTPReportsCapturedCanvasWithStrictSchemaAndExistingNativeApproval() async throws {
    let helper = AutomationTests(), lifecycle = ImageGenerationLifecycleTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: try CraftDocument(width: 8, height: 6))
      defer { document.store.cancelAIWork(); document.store.renderTask?.cancel() }
      let request = try lifecycle.begin(document.store)
      try service.share(document)
      let share = try XCTUnwrap(service.shares.first)
      let path = "/v1/documents/\(share.id)/ai"
      let response = try await helper.request(service, path: path)
      XCTAssertEqual(response.0.statusCode, 200)
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      let job = try XCTUnwrap(state["job"] as? [String: Any])
      XCTAssertEqual(job["sourceCanvasSize"] as? [String: Int], ["width": 8, "height": 6])
      XCTAssertEqual(state["requiresNativeApproval"] as? Bool, true)
      let value = try JSONDecoder().decode(AutomationValue.self, from: JSONSerialization.data(withJSONObject: job))
      XCTAssertNoThrow(try BrushAPI.merge(value, schema: AIImageAPI.jobSchema))
      for invalid: Any in [0, 300001, true] {
        var malformed = job
        malformed["sourceCanvasSize"] = ["width": invalid, "height": 6]
        let bad = try JSONDecoder().decode(AutomationValue.self,
          from: JSONSerialization.data(withJSONObject: malformed))
        XCTAssertThrowsError(try BrushAPI.merge(bad, schema: AIImageAPI.jobSchema))
      }
      let caps = AIImageAPI.presentationCapabilities
      let expected = ImageGenerationPresentation.current
      XCTAssertEqual(caps["styleKeys"] as? [String], expected.styles.map(\.rawValue))
      XCTAssertEqual(caps["canvasSizeHintConfigured"] as? Bool, expected.usesCanvasSizeHint)
      XCTAssertEqual(caps["externalProviderStylesEnabled"] as? Bool, false)
      XCTAssertEqual(AutomationCommand.definitions.count, 267)
      let cancelled = try await helper.request(service, path: path, body: ["operation": "cancel",
        "revision": service.revision(document.store), "requestID": request.id.uuidString])
      XCTAssertEqual(cancelled.0.statusCode, 200)
      XCTAssertEqual(request.phase, .cancelled)
      XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
  }
}
