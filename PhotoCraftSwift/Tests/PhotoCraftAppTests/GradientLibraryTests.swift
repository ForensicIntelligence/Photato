import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraft
@testable import PhotoCraftImaging

final class GradientLibraryTests: XCTestCase {
  static func custom() -> GradientDefinition {
    .init(
      name: "Coastal ✓",
      colors: [
        .init(0.12345679, .rgb(Pixel(0.12345679, 0.7123457, 0.3456789)), midpoint: 0.2345679),
        .init(
          0.8765432, .hsb(hue: 123.4567, saturation: 0.654321, brightness: 0.8765432),
          midpoint: 0.7654321),
      ],
      opacity: [.init(0.1111111, 0.2345679), .init(0.8888888, 0.9876543, midpoint: 0.3333333)],
      smoothness: 0.456789, method: .linear)
  }
  static func fixture() throws -> Data {
    var library = GRDLibrary([.blackToWhite, .foregroundToTransparent])
    library.hierarchy = [.group("Imported ✓", [.preset(0), .group("Nested", [.preset(1)])])]
    let data = try GRDCodec.write(library)
    let prefix = try PSDDescriptor.readPrefix(Data(data.dropFirst(6)))
    var root = prefix.descriptor
    guard case .list(var items) = root["GrdL"], case .object(var wrapper) = items[0],
      case .object(var gradient) = wrapper["Grad"]
    else { throw CraftError.invalid("Fixture") }
    PSDGradient.set(&gradient, "GrdF", .enumerated(PSDID("GrdF"), PSDID("ClNs")))
    PSDGradient.set(&gradient, "RndS", .integer(1234))
    PSDGradient.set(&wrapper, "Grad", .object(gradient))
    PSDGradient.set(&wrapper, "Unkn", .text([65, 66, 0]))
    items[0] = .object(wrapper)
    PSDGradient.set(&root, "GrdL", .list(items))
    PSDGradient.set(&root, "Root", .integer(42))
    var output = PSDWriter()
    output.text("8BGR")
    output.n(5, 2)
    output.data.append(try root.encoded())
    output.data.append(data.dropFirst(prefix.consumed + 6))
    return output.data
  }
  private func temporary() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "photato-gradient-library-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
  func testNativeArchivePreservesExactControlsBeyondGRDPrecision() throws {
    var state = GradientPresetState.builtins()
    let gradient = Self.custom()
    let id = try state.add(gradient, into: nil)
    let restored = try GradientPresetState.decode(state.encoded())
    XCTAssertEqual(restored.presets[id]?.gradient, gradient)
    XCTAssertEqual(restored.selected, [id])
    XCTAssertEqual(restored.activePreset, id)
    let before = try GradientRamp(gradient)
    let after = try GradientRamp(XCTUnwrap(restored.presets[id]?.gradient))
    for i in 0...2048 {
      XCTAssertTrue(before.sample(Float(i) / 2048).hasSameBits(as: after.sample(Float(i) / 2048)))
    }
    let grd = try GRDCodec.read(state.exported([id]))
    XCTAssertNotEqual(grd.presets[0].gradient?.colors[0].position, gradient.colors[0].position)
    XCTAssertEqual(
      grd.presets[0].gradient?.colors[0].position,
      (gradient.colors[0].position * 4096).rounded() / 4096)
  }
  func testGroupsReorderingDuplicationDeletionAndSubsetExport() throws {
    var state = GradientPresetState.builtins()
    let a = try state.group("A", into: nil)
    let b = try state.group("B", into: a)
    let first = try state.add(Self.custom(), into: b)
    let second = try state.add(.blackToWhite, into: a)
    try state.move([first], into: a, before: second)
    XCTAssertEqual(state.activePreset, second)
    XCTAssertEqual(state.node(a)?.children?.map(\.id), [b, first, second])
    try state.rename(a, to: "Changed")
    let exported = try GRDCodec.read(state.exported([a, first]))
    XCTAssertEqual(exported.presets.count, 2)
    XCTAssertEqual(
      exported.hierarchy, [.group("Changed", [.group("B", []), .preset(0), .preset(1)])])
    try state.duplicate([a, first], into: nil)
    XCTAssertEqual(state.library.presets.count, 7)
    XCTAssertEqual(state.nodes.count, 3)
    let copy = try XCTUnwrap(state.nodes.last)
    XCTAssertNotEqual(copy.id, a)
    try state.remove([a])
    XCTAssertNil(state.presets[first])
    XCTAssertNil(state.presets[second])
    XCTAssertEqual(state.library.presets.count, 5)
    XCTAssertEqual(try GRDCodec.read(state.exported()).presets.count, 5)
  }
  func testUnavailableRecordsAndWholeImportedFileSurviveNativeSaveAndRename() throws {
    let bytes = try Self.fixture()
    var state = GradientPresetState.builtins()
    let group = try state.install(bytes, name: "External Library", into: nil)
    XCTAssertEqual(try state.exported([group]), bytes)
    state = try GradientPresetState.decode(state.encoded())
    XCTAssertEqual(try state.exported([group]), bytes)
    let unavailable = try XCTUnwrap(state.presetIDs.first { state.presets[$0]?.gradient == nil })
    let original = try XCTUnwrap(state.presets[unavailable])
    try state.add(Self.custom(), into: nil)
    XCTAssertEqual(state.presets[unavailable], original)
    try state.rename(unavailable, to: "Preserved Noise ✓")
    XCTAssertNil(state.presets[unavailable]?.gradient)
    let exported = try state.exported([group])
    let root = try PSDDescriptor.readPrefix(Data(exported.dropFirst(6))).descriptor
    XCTAssertEqual(root["Root"], .integer(42))
    guard case .list(let list) = root["GrdL"], case .object(let wrapper) = list[0],
      case .object(let gradient) = wrapper["Grad"]
    else { return XCTFail() }
    XCTAssertEqual(wrapper["Unkn"], .text([65, 66, 0]))
    XCTAssertEqual(gradient["RndS"], .integer(1234))
    XCTAssertEqual(try GRDCodec.read(exported).presets[0].name, "Preserved Noise ✓")
    XCTAssertNil(try GRDCodec.read(exported).presets[0].gradient)
  }
  func testEmptyGroupsAndInvalidArchiveHierarchyAreBounded() throws {
    var state = GradientPresetState()
    let id = try state.group("Empty", into: nil)
    let data = try state.encoded()
    let restored = try GradientPresetState.decode(data)
    XCTAssertEqual(restored.nodes, [.folder(id, "Empty", [])])
    XCTAssertThrowsError(try restored.exported())
    var plist = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    var nodes = try XCTUnwrap(plist["nodes"] as? [[String: Any]])
    nodes[0]["depth"] = 65
    plist["nodes"] = nodes
    XCTAssertThrowsError(
      try GradientPresetState.decode(
        PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)))
    nodes[0]["depth"] = 1
    plist["nodes"] = nodes
    XCTAssertThrowsError(
      try GradientPresetState.decode(
        PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)))
    for cut in stride(from: 0, to: data.count, by: 13) {
      XCTAssertThrowsError(try GradientPresetState.decode(data.prefix(cut)))
    }
  }
  @MainActor func testFilePersistenceSelectionImportExportAndRestart() async throws {
    let folder = try temporary()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("Gradients.pclibrary")
    let source = folder.appendingPathComponent("External.grd")
    let bytes = try Self.fixture()
    try bytes.write(to: source)
    let library = GradientLibrary(persistenceURL: url)
    try await library.importFile(source, into: nil)
    let imported = library.state.selected
    try await library.edit { try $0.add(Self.custom(), into: nil) }
    let custom = try XCTUnwrap(library.state.activePreset)
    try await library.select(imported, active: nil)
    let restored = GradientLibrary(persistenceURL: url)
    await restored.loadTask?.value
    XCTAssertNil(restored.error)
    XCTAssertEqual(restored.state.nodes, library.state.nodes)
    XCTAssertEqual(restored.state.presets[custom]?.gradient, Self.custom())
    XCTAssertEqual(restored.state.selected, imported)
    XCTAssertEqual(restored.state.activePreset, custom)
    let target = folder.appendingPathComponent("Export.grd")
    try await restored.exportFile(target, selected: true)
    XCTAssertEqual(try Data(contentsOf: target), bytes)
    try await restored.edit { try $0.remove(imported) }
    XCTAssertTrue(restored.state.importedSources.isEmpty)
    XCTAssertEqual(restored.state.library.presets.count, 4)
  }
  @MainActor func testCorruptUnwritableCancelledAndInvalidEditsAreAtomic() async throws {
    let folder = try temporary()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("Corrupt.pclibrary")
    let junk = Data([1, 2, 3, 4])
    try junk.write(to: url)
    let library = GradientLibrary(persistenceURL: url)
    await library.loadTask?.value
    XCTAssertNotNil(library.error)
    let before = library.state
    do {
      try await library.edit { try $0.add(Self.custom(), into: nil) }
      XCTFail()
    } catch {}
    XCTAssertEqual(library.state, before)
    XCTAssertEqual(try Data(contentsOf: url), junk)
    let unwritable = GradientLibrary(persistenceURL: url.appendingPathComponent("Child"))
    let initial = unwritable.state
    do {
      try await unwritable.edit { try $0.add(Self.custom(), into: nil) }
      XCTFail()
    } catch {}
    XCTAssertEqual(unwritable.state, initial)
    let valid = GradientLibrary(persistenceURL: folder.appendingPathComponent("Good.pclibrary"))
    let original = valid.state
    let task = Task { @MainActor in
      withUnsafeCurrentTask { $0?.cancel() }
      do {
        try await valid.edit { try $0.add(Self.custom(), into: nil) }
        XCTFail()
      } catch is CancellationError {} catch { XCTFail("\(error)") }
    }
    await task.value
    XCTAssertEqual(valid.state, original)
    XCTAssertFalse(valid.busy)
    let group = try XCTUnwrap(valid.state.nodes.first?.id)
    do {
      try await valid.edit { try $0.move([group], into: group) }
      XCTFail()
    } catch {}
    XCTAssertEqual(valid.state, original)
  }
  @MainActor func testFailedImportAndConcurrentOperationsPreserveLastCommit() async throws {
    let folder = try temporary()
    defer { try? FileManager.default.removeItem(at: folder) }
    let bad = folder.appendingPathComponent("Bad.grd")
    try Data([1, 2, 3]).write(to: bad)
    let library = GradientLibrary()
    let before = library.state
    do {
      try await library.importFile(bad, into: nil)
      XCTFail()
    } catch {}
    XCTAssertEqual(library.state, before)
    let gate = DispatchSemaphore(value: 0)
    defer { gate.signal() }
    let first = Task {
      try await library.edit {
        _ = gate.wait(timeout: .now() + 5)
        try $0.add(Self.custom(), into: nil)
      }
    }
    for _ in 0..<1000 {
      if library.busy { break }
      await Task.yield()
    }
    XCTAssertTrue(library.busy)
    do {
      try await library.edit { try $0.group("Must not appear", into: nil) }
      XCTFail()
    } catch {}
    gate.signal()
    try await first.value
    XCTAssertEqual(library.state.library.presets.count, 4)
    XCTAssertEqual(library.selectedPreset?.name, Self.custom().name)
    XCTAssertFalse(library.busy)
  }
}
