import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class PreviewOrderingTests: XCTestCase {
  private func fixture() throws -> CraftDocument {
    var d = try CraftDocument(width: 64, height: 48)
    var p = try Surface(width: 64, height: 48)
    p.mapPixels { x, y, _ in Pixel(Float(x % 11) / 12, Float(y % 9) / 10, 0.4) }
    d.layers[0].content = .raster(p); return d
  }
  private let points: [StrokePoint] = [.init(x: 20, y: 20), .init(x: 26, y: 24), .init(x: 34, y: 28)]
  func testRetouchOlderPrefixesAndPostCommitPreviewsAreCancelledWithoutLosingCoverage() async throws {
    let d = try fixture()
    for tool in RecordedRetouchTool.allCases where tool != .healingBrush && tool != .spotHealing {
      var request = RecordedRetouchStroke(tool: tool, target: .active, points: points)
      request.brush.size = 6; request.focus.protectDetail = false
      request.mapping = .init(source: .init(8, 9), anchor: .init(20, 20))
      if tool.toning == nil { request.source = .init(layer: .active) }
      let command = try RetouchPreparation.command(request, in: d)
      let worker = try XCTUnwrap(InteractiveRetouchPreview(document: d, command: command))
      _ = try await worker.snapshot(base: d, points: Array(points.prefix(2)), previous: nil)
      do { _ = try await worker.snapshot(base: d, points: [.init(x: 1, y: 1)], previous: nil); XCTFail("Changed prefix was accepted") } catch is CancellationError { XCTFail("Changed input must remain an error") } catch {}
      do { _ = try await worker.snapshot(base: d, points: [points[0]], previous: nil); XCTFail("Old work was accepted") } catch is CancellationError {} catch { XCTFail("\(error)") }
      let latest = try await worker.snapshot(base: d, points: points, previous: nil)
      var expected = d; try command.apply(to: &expected)
      XCTAssertTrue(latest?.document == expected, "\(tool)")
      let result = try await worker.prepareCommit(base: d, points: points)
      let prepared = try XCTUnwrap(result)
      var session = EditorSession(document: d); try session.executePrepared(prepared); XCTAssertTrue(session.document == expected)
      do { _ = try await worker.snapshot(base: d, points: points, previous: nil); XCTFail("Finished work was accepted") } catch is CancellationError {} catch { XCTFail("\(error)") }
    }
  }
  func testBrushOlderPrefixesAndPostCommitPreviewsAreCancelledWithoutLosingCoverage() async throws {
    let d = try fixture(); var brush = Brush(); brush.settings = .init(); brush.size = 6
    let command = Command.stroke(d.layers[0].id, points, brush)
    let worker = try XCTUnwrap(InteractiveBrushPreview(document: d, command: command))
    _ = try await worker.snapshot(base: d, points: Array(points.prefix(2)), previous: nil)
    do { _ = try await worker.snapshot(base: d, points: [.init(x: 1, y: 1)], previous: nil); XCTFail("Changed prefix was accepted") } catch is CancellationError { XCTFail("Changed input must remain an error") } catch {}
    do { _ = try await worker.snapshot(base: d, points: [points[0]], previous: nil); XCTFail("Old work was accepted") } catch is CancellationError {} catch { XCTFail("\(error)") }
    let latest = try await worker.snapshot(base: d, points: points, previous: nil)
    var expected = d; try command.apply(to: &expected); XCTAssertTrue(latest?.document == expected)
    let result = try await worker.prepareCommit(base: d, points: points)
    let prepared = try XCTUnwrap(result)
    var session = EditorSession(document: d); try session.executePrepared(prepared); XCTAssertTrue(session.document == expected)
    do { _ = try await worker.snapshot(base: d, points: points, previous: nil); XCTFail("Finished work was accepted") } catch is CancellationError {} catch { XCTFail("\(error)") }
  }
}
