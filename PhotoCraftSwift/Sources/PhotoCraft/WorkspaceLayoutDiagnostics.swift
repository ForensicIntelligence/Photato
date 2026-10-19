import AppKit
import Foundation
import SwiftUI

struct WorkspaceFieldLayoutProbe: View {
  let owner: UUID
  let name: String
  let value: Double
  var body: some View {
    if WorkspaceLayoutDiagnostics.enabled {
      GeometryReader { geometry in
        Color.clear.onChange(of: geometry.frame(in: .global), initial: true) { _, frame in
          WorkspaceLayoutDiagnostics.log(
            "numeric.geometry",
            [
              "owner": owner.uuidString, "name": name, "value": value,
              "frame": WorkspaceLayoutDiagnostics.rect(frame),
            ])
        }
      }
    }
  }
}

/// Opt-in diagnostics for original sample documents. No timer or tracing runs in normal use.
@MainActor enum WorkspaceLayoutDiagnostics {
  static var enabled: Bool {
    CommandLine.arguments.contains("--snapshot-layout-trace")
      || ProcessInfo.processInfo.environment["PHOTATO_LAYOUT_TRACE"] == "1"
  }
  static func log(_ event: String, _ values: [String: Any] = [:]) {
    guard enabled else { return }
    var values = values
    values["event"] = event
    values["uptime"] = ProcessInfo.processInfo.systemUptime
    guard JSONSerialization.isValidJSONObject(values) else { return }
    if let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
      let text = String(data: data, encoding: .utf8)
    {
      print("LAYOUT_TRACE " + text)
    }
  }
  static func rect(_ r: NSRect) -> [Double] {
    [r.minX, r.minY, r.width, r.height].map { $0.isFinite ? Double($0) : 0 }
  }
  static func snapshot(_ host: NSView, store: EditorStore, phase: String) {
    guard enabled else { return }
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let views = descendants(host).filter {
      $0 is NSTextField || $0 is NSScrollView || $0 is LayerEyeButton
    }
    var rows: [[String: Any]] = []
    for view in views {
      var row: [String: Any] = [
        "class": String(describing: type(of: view)),
        "frame": rect(view.frame), "bounds": rect(view.bounds),
        "visible": rect(view.visibleRect.intersection(view.bounds)),
        "windowFrame": rect(view.convert(view.bounds, to: nil)),
        "backing": rect(view.convertToBacking(view.bounds)), "hidden": view.isHidden,
      ]
      if let field = view as? NSTextField {
        row["text"] = field.stringValue
        row["label"] = field.accessibilityLabel() ?? ""
        row["editing"] = field.currentEditor() != nil
        if let cell = field.cell {
          row["drawingRect"] = rect(cell.drawingRect(forBounds: field.bounds))
        }
      }
      if let field = view as? LayerNameField.NameField {
        row["draft"] = field.draftID?.uuidString ?? ""
        row["needsFocus"] = field.needsInitialFocus
      }
      if let eye = view as? LayerEyeButton { row["layer"] = eye.layerID.uuidString }
      if let scroll = view as? NSScrollView {
        row["clip"] = rect(scroll.contentView.bounds)
        if let document = scroll.documentView { row["document"] = rect(document.frame) }
      }
      rows.append(row)
    }
    log(
      "snapshot",
      [
        "phase": phase, "views": rows,
        "draft": store.layerNameDraft?.id.uuidString ?? "",
        "active": store.document.activeLayerID?.uuidString ?? "",
        "canBegin": store.canBeginLayerCreation,
        "firstResponder": host.window?.firstResponder.map { String(describing: type(of: $0)) }
          ?? "nil",
      ])
  }
  static func writeImage(_ host: NSView, to url: URL) throws {
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    host.cacheDisplay(in: host.bounds, to: rep)
    if let data = rep.representation(using: .png, properties: [:]) { try data.write(to: url) }
  }
}
