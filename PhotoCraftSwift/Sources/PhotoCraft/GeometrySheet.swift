import PhotoCraftCore
import SwiftUI

enum GeometrySheetKind: String, Identifiable {
  case imageSize, canvasSize, fitImage
  var id: String { rawValue }
}
enum DimensionUnit: String, CaseIterable {
  case pixels = "Pixels"
  case percent = "Percent"
  case inches = "Inches"
  case centimeters = "Centimeters"
  func pixels(_ value: Double, original: Int, resolution: Double) -> Double {
    switch self {
    case .pixels: value
    case .percent: Double(original) * value / 100
    case .inches: value * resolution
    case .centimeters: value * resolution / 2.54
    }
  }
  func value(_ pixels: Double, original: Int, resolution: Double) -> Double {
    switch self {
    case .pixels: pixels
    case .percent: pixels / Double(original) * 100
    case .inches: pixels / resolution
    case .centimeters: pixels / resolution * 2.54
    }
  }
}

struct GeometrySheet: View {
  @Bindable var store: EditorStore
  let kind: GeometrySheetKind
  @State private var width = ""
  @State private var height = ""
  @State private var resolution = "72"
  @State private var unit = DimensionUnit.pixels
  @State private var resample = true
  @State private var linked = true
  @State private var relative = false
  @State private var anchor = CanvasAnchor.center
  @State private var extensionChoice = "Transparent"
  @State private var interpolation = Resampling.bicubic
  @State private var validation: String?
  private var isCanvas: Bool { kind == .canvasSize }
  private var ppi: Double {
    guard let value = Double(resolution), value.isFinite, value > 0 else {
      return store.document.pixelsPerInch
    }
    return value
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(isCanvas ? "Canvas Size" : "Image Size").font(.title2.bold())
      Text(
        "Current: \(store.document.width) × \(store.document.height) pixels · \(store.document.pixelsPerInch.formatted()) ppi"
      ).foregroundStyle(.secondary)
      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
        GridRow {
          Text("Width:")
          TextField(
            "Width",
            text: Binding(
              get: { width },
              set: {
                width = $0
                dimensionChanged($0, horizontal: true)
              }))
          Picker("Units", selection: Binding(get: { unit }, set: changeUnit)) {
            ForEach(
              DimensionUnit.allCases.filter {
                isCanvas || resample || ($0 != .pixels && $0 != .percent)
              }, id: \.self
            ) { Text($0.rawValue).tag($0) }
          }.labelsHidden().frame(width: 130)
        }
        GridRow {
          Text("Height:")
          TextField(
            "Height",
            text: Binding(
              get: { height },
              set: {
                height = $0
                dimensionChanged($0, horizontal: false)
              }))
          if !isCanvas {
            Toggle("Constrain proportions", isOn: $linked).toggleStyle(.checkbox).disabled(
              !resample)
          }
        }
        if !isCanvas {
          GridRow {
            Text("Resolution:")
            TextField(
              "Resolution",
              text: Binding(
                get: { resolution },
                set: {
                  resolution = $0
                  if !resample { resetDimensions(relative: false) }
                }))
            Text("Pixels/Inch").foregroundStyle(.secondary)
          }
        }
      }.textFieldStyle(.roundedBorder)
      if isCanvas {
        Toggle("Relative", isOn: $relative).onChange(of: relative) { _, v in
          resetDimensions(relative: v)
        }
        HStack(spacing: 20) {
          Text("Anchor:")
          Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            ForEach(0..<3) { row in
              GridRow {
                ForEach(0..<3) { column in
                  let item = CanvasAnchor.allCases[row * 3 + column]
                  Button {
                    anchor = item
                  } label: {
                    Image(systemName: anchor == item ? "circle.fill" : "circle").frame(
                      width: 24, height: 24)
                  }.tint(anchor == item ? .accentColor : .gray).accessibilityLabel(
                    "Anchor \(item.rawValue)")
                }
              }
            }
          }
          Text(store.document.colorMode.isRestricted ? "Existing pixels retain their indices or bits. Pixels outside the new canvas are discarded; Undo restores them." : "Existing pixels stay at their original size. Off-canvas content is retained.").font(
            .caption
          ).foregroundStyle(.secondary).frame(width: 220)
        }
        Picker("Canvas extension", selection: $extensionChoice) {
          ForEach(["Transparent", "White", "Foreground Color", "Background Color"], id: \.self) {
            Text($0)
          }
        }
        if extensionChoice != "Transparent" {
          Text("Colored extension is added on a separate layer.").font(.caption).foregroundStyle(
            .secondary)
        }
      } else {
        HStack {
          Toggle(
            "Resample",
            isOn: Binding(
              get: { resample },
              set: { v in
                resample = v
                if !v {
                  linked = true
                  if unit == .pixels || unit == .percent { unit = .inches }
                }
                resetDimensions(relative: false)
              }))
          Picker("Interpolation", selection: $interpolation) {
            ForEach(Resampling.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }.labelsHidden().disabled(!resample)
        }
        if !resample {
          Text("Pixel dimensions stay unchanged. Physical size and resolution are linked.").font(
            .caption
          ).foregroundStyle(.secondary)
        }
      }
      if let validation { Text(validation).font(.caption).foregroundStyle(.orange) }
      HStack {
        Spacer()
        Button("Cancel") { store.geometrySheet = nil }.keyboardShortcut(.cancelAction)
        Button("OK", action: apply).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
      }
    }.padding(24).frame(width: 520).preferredColorScheme(.dark)
      .onAppear {
        resolution = String(store.document.pixelsPerInch)
        if store.document.colorMode.isRestricted { interpolation = .nearest }
        resetDimensions(relative: false)
      }
  }
  // User-input bindings update dependent fields once. Observing dependent fields with onChange
  // caused unit/resolution changes to feed back into each other and rescale repeatedly.
  private func changeUnit(_ new: DimensionUnit) {
    let w = unit.pixels(Double(width) ?? 0, original: store.document.width, resolution: ppi)
    let h = unit.pixels(Double(height) ?? 0, original: store.document.height, resolution: ppi)
    unit = new
    width = number(new.value(w, original: store.document.width, resolution: ppi))
    height = number(new.value(h, original: store.document.height, resolution: ppi))
  }
  private func number(_ n: Double) -> String {
    n.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))
  }
  private func resetDimensions(relative: Bool) {
    width = number(
      unit.value(
        relative ? 0 : Double(store.document.width), original: store.document.width, resolution: ppi
      ))
    height = number(
      unit.value(
        relative ? 0 : Double(store.document.height), original: store.document.height,
        resolution: ppi))
  }
  private func dimensionChanged(_ value: String, horizontal: Bool) {
    guard let v = Double(value), v > 0, !isCanvas else { return }
    let original = horizontal ? store.document.width : store.document.height
    if !resample && (unit == .inches || unit == .centimeters) {
      let inches = unit == .inches ? v : v / 2.54
      let newPPI = Double(original) / inches
      if abs(newPPI - ppi) > 0.01 { resolution = number(newPPI) }
      let other = horizontal ? store.document.height : store.document.width
      let value = number(unit.value(Double(other), original: other, resolution: newPPI))
      if horizontal { height = value } else { width = value }
    } else if linked {
      let otherOriginal = horizontal ? store.document.height : store.document.width
      let pixels = unit.pixels(v, original: original, resolution: ppi)
      let other = number(
        unit.value(
          pixels * Double(otherOriginal) / Double(original), original: otherOriginal,
          resolution: ppi))
      if horizontal {
        if Double(height) != Double(other) { height = other }
      } else if Double(width) != Double(other) {
        width = other
      }
    }
  }
  private func apply() {
    do {
      guard let w = Double(width), let h = Double(height), let ppi = Double(resolution),
        ppi.isFinite, (1...100_000).contains(ppi)
      else { throw CraftError.invalid("Enter valid dimensions and resolution.") }
      var px = unit.pixels(w, original: store.document.width, resolution: ppi)
      var py = unit.pixels(h, original: store.document.height, resolution: ppi)
      if isCanvas && relative {
        px += Double(store.document.width)
        py += Double(store.document.height)
      }
      guard px.isFinite, py.isFinite, px >= 1, py >= 1, px <= Double(Surface.maxDimension),
        py <= Double(Surface.maxDimension), px * py <= Double(Surface.maxPixels)
      else { throw CraftError.invalid("Enter dimensions from 1 to 300,000 pixels per side (maximum 90 gigapixels).") }
      let command: Command
      if isCanvas {
        let color: Pixel? =
          switch extensionChoice {
          case "White": .white
          case "Foreground Color": store.brush.color
          case "Background Color": store.backgroundColor
          default: nil
          }
        command = .canvasSize(Int(px.rounded()), Int(py.rounded()), anchor, color)
      } else if resample {
        command = .imageSize(Int(px.rounded()), Int(py.rounded()), ppi, interpolation)
      } else {
        command = .resolution(ppi)
      }
      store.applyGeometrySheetCommand(command)
    } catch { validation = error.localizedDescription }
  }
}

@MainActor extension EditorStore {
  func applyGeometrySheetCommand(_ command: Command) {
    // Canvas dimensions change the workspace extent, not the user's magnification.
    if case .canvasSize = command, zoom == 0 { zoom = effectiveZoom }
    geometrySheet = nil
    performGeometry(command)
    if case .canvasSize = command { return }
    fit()
  }
}
