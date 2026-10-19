import AppKit
import PhotoCraftCore
import SwiftUI

extension EditorStore {
  func selectionMode(modifiers: NSEvent.ModifierFlags) -> SelectionMode {
    if modifiers.contains([.shift, .option]) { return .intersect }
    if modifiers.contains(.shift) { return .add }
    if modifiers.contains(.option) { return .subtract }
    return selectionMode
  }
  func selectShape(_ shape: SelectionShape, mode: SelectionMode) {
    performGeometry(.selectShape(shape, mode, selectionAntiAlias, selectionFeather))
  }
}

// CGPath is not annotated Sendable by the SDK. This wrapper only exposes an immutable
// copy; the worker's CGMutablePath is never shared across actors.
struct SelectionContour: @unchecked Sendable {
  let path: CGPath
  init(_ path: CGPath) { self.path = path.copy()! }
}

enum SelectionOutline {
  /// Half-coverage contour in document coordinates. Merge adjacent unit edges into runs.
  static func path(_ mask: SelectionMask) throws -> SelectionContour {
    let path = CGMutablePath()
    func selected(_ x: Int, _ y: Int) -> Bool { mask.coverage(x: x, y: y) >= 0.5 }
    for y in 0...mask.height {
      try Task.checkCancellation()
      var start: Int?
      for x in 0...mask.width {
        let edge = x < mask.width && selected(x, y - 1) != selected(x, y)
        if edge && start == nil { start = x }
        if !edge, let from = start {
          path.move(to: CGPoint(x: from, y: y))
          path.addLine(to: CGPoint(x: x, y: y))
          start = nil
        }
      }
    }
    for x in 0...mask.width {
      try Task.checkCancellation()
      var start: Int?
      for y in 0...mask.height {
        let edge = y < mask.height && selected(x - 1, y) != selected(x, y)
        if edge && start == nil { start = y }
        if !edge, let from = start {
          path.move(to: CGPoint(x: x, y: from))
          path.addLine(to: CGPoint(x: x, y: y))
          start = nil
        }
      }
    }
    return SelectionContour(path)
  }
}

struct FeatherSelectionSheet: View {
  @Bindable var store: EditorStore
  @State private var radius = 1.0
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Feather Selection").font(.title2.bold())
      HStack {
        Text("Feather Radius:")
        TextField("Pixels", value: $radius, format: .number).frame(width: 85)
        Text("pixels")
      }
      Text("Softens the selection edge. Range: 0–100 pixels.").font(.caption).foregroundStyle(
        .secondary)
      HStack {
        Spacer()
        Button("Cancel") { store.showFeatherSelection = false }.keyboardShortcut(.cancelAction)
        Button("OK") {
          store.showFeatherSelection = false
          store.performGeometry(.featherSelection(radius))
        }.keyboardShortcut(.defaultAction).disabled(!radius.isFinite || !(0...100).contains(radius))
      }
    }.padding(24).frame(width: 380).preferredColorScheme(.dark)
  }
}
