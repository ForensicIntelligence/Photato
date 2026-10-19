import PhotoCraftCore
import SwiftUI

struct ColorBalanceDraft: Identifiable, Sendable {
  let id: UUID
  var adjustment = ColorBalanceAdjustment()
  var preview = true
}

struct ColorBalanceControls: View {
  @Binding var adjustment: ColorBalanceAdjustment
  var coalesce: (Bool) -> Void = { _ in }
  @State private var tone = ColorBalanceAdjustment.Tone.midtones
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Picker("Tone", selection: $tone) {
        ForEach(ColorBalanceAdjustment.Tone.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }
      control("Cyan", "Red", key: \.cyanRed)
      control("Magenta", "Green", key: \.magentaGreen)
      control("Yellow", "Blue", key: \.yellowBlue)
      Toggle("Preserve Luminosity", isOn: $adjustment.preserveLuminosity)
      HStack {
        Button("Reset Tone") { adjustment[tone] = .init() }
          .disabled(adjustment[tone].isNeutral)
        Spacer()
        Button("Reset All") { adjustment = .init() }
          .disabled(adjustment == .init())
      }.buttonStyle(.bordered)
    }
  }
  func control(
    _ negative: String, _ positive: String, key: WritableKeyPath<ColorBalanceValues, Int>
  ) -> some View {
    let binding = Binding<Double>(
      get: { Double(adjustment[tone][keyPath: key]) },
      set: { value in
        guard value.isFinite else { return }
        var record = adjustment[tone]
        record[keyPath: key] = Int(min(100, max(-100, value)).rounded())
        adjustment[tone] = record
      })
    return VStack(spacing: 4) {
      HStack {
        Text(negative).frame(maxWidth: .infinity, alignment: .leading)
        TextField(
          "\(negative)–\(positive)", value: binding, format: .number.precision(.fractionLength(0))
        )
        .textFieldStyle(.roundedBorder).monospacedDigit().frame(width: 56)
        .accessibilityLabel("\(tone.rawValue) \(negative)–\(positive)")
        Text(positive).frame(maxWidth: .infinity, alignment: .trailing)
      }
      Slider(value: binding, in: -100...100, step: 1, onEditingChanged: coalesce)
        .accessibilityLabel("\(tone.rawValue) \(negative)–\(positive)")
        .accessibilityHint(
          "Negative values add \(negative.lowercased()); positive values add \(positive.lowercased())."
        )
    }
  }
}

struct ColorBalanceEditor: View {
  @Bindable var store: EditorStore
  let layerID: UUID
  var pixelLayer = false
  var body: some View {
    ColorBalanceControls(
      adjustment: Binding(
        get: {
          if pixelLayer { return store.colorBalanceDraft?.adjustment ?? .init() }
          if case .adjustment(.colorBalance(let value)) = store.document.layers.first(where: {
            $0.id == layerID
          })?.content {
            return value
          }
          return .init()
        },
        set: { value in
          if pixelLayer {
            store.colorBalanceDraft?.adjustment = value
            store.render()
          } else {
            store.setColorBalance(layerID, value)
          }
        }), coalesce: { if !pixelLayer { store.coalesce($0) } })
  }
}

struct ColorBalanceSheet: View {
  @Bindable var store: EditorStore
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Color Balance").font(.title2.bold())
      if let draft = store.colorBalanceDraft {
        ColorBalanceEditor(store: store, layerID: draft.id, pixelLayer: true)
      }
      Divider()
      HStack {
        Toggle(
          "Preview",
          isOn: Binding(
            get: { store.colorBalanceDraft?.preview ?? false },
            set: {
              store.colorBalanceDraft?.preview = $0
              store.render()
            }))
        Spacer()
        Button("Cancel") { store.cancelColorBalance() }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitColorBalance() }.keyboardShortcut(.defaultAction)
      }
    }.padding(20).frame(width: 380)
  }
}

extension EditorStore {
  var canBeginColorBalance: Bool { canBeginLevels }
  func beginColorBalance() {
    guard canBeginColorBalance, let layer = activeLayer else { return }
    colorBalanceDraft = .init(id: layer.id)
  }
  func cancelColorBalance() {
    colorBalanceDraft = nil
    render()
  }
  func commitColorBalance() {
    guard let draft = colorBalanceDraft else { return }
    colorBalanceDraft = nil
    performGeometry(.applyAdjustment(draft.id, .colorBalance(draft.adjustment)))
  }
  func addColorBalanceLayer() { addToneLayer(.colorBalance(.init()), name: "Color Balance") }
  func setColorBalance(_ id: UUID, _ adjustment: ColorBalanceAdjustment) {
    guard let layer = document.layers.first(where: { $0.id == id }),
      case .adjustment(.colorBalance) = layer.content
    else { return }
    perform(.replaceContent(id, .adjustment(.colorBalance(adjustment))))
  }
}
