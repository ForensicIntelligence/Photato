import AppKit
import PhotoCraftCore
import SwiftUI

extension WorkspaceView {
  private func gradientBinding<T>(
    _ key: WritableKeyPath<GradientToolOptions, T>
  ) -> Binding<T> {
    Binding(
      get: { store.gradientOptions[keyPath: key] },
      set: { store.changeGradientOption(key, $0) })
  }
  var gradientOptions: some View {
    Group {
      Picker("Gradient mode", selection: gradientBinding(\.mode)) {
        ForEach(GradientToolMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }.labelsHidden().frame(width: 145)
      Button {
        gradientPresetPopover.toggle()
      } label: {
        HStack(spacing: 5) {
          GradientSwatch(gradient: store.creationToolGradient).frame(width: 95, height: 19)
          Image(systemName: "chevron.down").font(.system(size: 9))
        }
      }.buttonStyle(.plain).fixedSize().help("Gradient presets")
        .accessibilityLabel("Gradient presets")
        .popover(isPresented: $gradientPresetPopover) {
          GradientsPanel(store: store, compact: true, creationOnly: true).frame(width: 320, height: 310)
        }
      HStack(spacing: 2) {
        ForEach(GradientStyle.allCases, id: \.self) { style in
          let selected =
            store.gradientOptions.style
            == style
          Button {
            store.changeGradientOption(\.style, style)
          } label: {
            Image(systemName: gradientStyleSymbol(style)).frame(width: 24, height: 23)
              .background(selected ? StudioTheme.field : .clear)
              .overlay { if selected { Rectangle().strokeBorder(StudioTheme.line) } }
          }.buttonStyle(.plain).help("\(style.rawValue) Gradient")
            .accessibilityLabel("\(style.rawValue) Gradient")
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
      }
      Picker(
        "Method",
        selection: Binding(
          get: { store.gradientOptions.gradient.method },
          set: { store.changeGradientMethod($0) })
      ) {
        ForEach(GradientMethod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }.frame(width: 145)
      Picker(
        "Mode",
        selection: gradientBinding(\.blend)
      ) {
        ForEach(BlendMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }.frame(width: 150)
      percentField(
        "Opacity:",
        value: gradientBinding(\.opacity))
      Toggle(
        "Reverse",
        isOn: gradientBinding(
          \.reverse))
      Toggle(
        "Dither", isOn: gradientBinding(\.dither))
      if !store.liveGradientMode {
        Toggle("Transparency", isOn: gradientBinding(\.transparency))
      }
      if let widget = store.activeGradientWidget {
        Button("Edit Gradient…") { store.beginGradientFill(editing: widget.layer.id) }
          .disabled(store.document.isLocked(widget.layer.id))
        if store.gradientSelectedStop?.id == widget.layer.id {
          Button("Stop Color…") { store.editSelectedGradientStop() }
            .disabled(store.document.isLocked(widget.layer.id))
        }
      }
    }.controlSize(.small).disabled(!store.canConfigureGradientCreation)
  }
  private func gradientStyleSymbol(_ style: GradientStyle) -> String {
    switch style {
    case .linear: "rectangle.lefthalf.filled"
    case .radial: "circle.inset.filled"
    case .angle: "circle.lefthalf.filled"
    case .reflected: "rectangle.center.inset.filled"
    case .diamond: "diamond.inset.filled"
    }
  }
}

struct GradientStopColorSheet: View {
  @Bindable var store: EditorStore
  private var color: Binding<Color> {
    Binding(
      get: {
        guard let draft = store.gradientStopColorDraft else { return .black }
        let p = draft.fill.gradient.colors[draft.index].color.resolved(
          foreground: .black, background: .white)
        return store.displayColor(p)
      },
      set: {
        guard let color = store.workingPixel($0),
          let draft = store.gradientStopColorDraft
        else { return }
        store.gradientStopColorDraft?.fill.gradient.colors[draft.index].color = .rgb(
          color)
        store.render()
      })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Color Picker (Stop Color)").font(.headline)
      ColorPicker("Color", selection: color, supportsOpacity: false)
      if let draft = store.gradientStopColorDraft {
        GradientSwatch(gradient: draft.fill.gradient).frame(height: 35)
      }
      HStack {
        Spacer()
        Button("Cancel") { store.finishGradientStopColor(apply: false) }.keyboardShortcut(
          .cancelAction)
        Button("OK") { store.finishGradientStopColor(apply: true) }.keyboardShortcut(.defaultAction)
      }
    }.padding(22).frame(width: 350)
  }
}

extension CraftCanvas {
  func drawGradientOverlay(in c: CGContext) {
    func view(_ p: PathPoint) -> CGPoint { viewPoint(CGPoint(x: p.x, y: p.y)) }
    func line(_ a: CGPoint, _ b: CGPoint) {
      for width in [3.0, 1.0] {
        c.setLineWidth(width)
        c.setStrokeColor(
          (width == 3 ? NSColor.black.withAlphaComponent(0.7) : NSColor.white).cgColor)
        c.move(to: a)
        c.addLine(to: b)
        c.strokePath()
      }
    }
    guard store.tool == .gradient else { return }
    if let stroke = store.gradientGesture?.stroke {
      c.saveGState()
      line(view(stroke.start), view(stroke.end))
      c.restoreGState()
      return
    }
    guard let widget = store.shownGradientWidget else { return }
    c.saveGState()
    let a = view(widget.start)
    let b = view(widget.end)
    let radius = hypot(b.x - a.x, b.y - a.y)
    c.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
    c.setLineWidth(1)
    switch widget.fill.placement.style {
    case .radial, .angle:
      c.strokeEllipse(
        in: CGRect(x: a.x - radius, y: a.y - radius, width: radius * 2, height: radius * 2))
    case .diamond:
      let dx = b.x - a.x
      let dy = b.y - a.y
      c.move(to: b)
      c.addLine(to: CGPoint(x: a.x - dy, y: a.y + dx))
      c.addLine(to: CGPoint(x: a.x - dx, y: a.y - dy))
      c.addLine(to: CGPoint(x: a.x + dy, y: a.y - dx))
      c.closePath()
      c.strokePath()
    case .reflected:
      c.setLineDash(phase: 0, lengths: [5, 4])
      c.move(to: a)
      c.addLine(to: CGPoint(x: 2 * a.x - b.x, y: 2 * a.y - b.y))
      c.strokePath()
      c.setLineDash(phase: 0, lengths: [])
    case .linear: break
    }
    line(a, b)
    for i in widget.fill.gradient.colors.indices {
      guard let t = widget.midpoint(i) else { continue }
      let p = view(widget.point(t))
      c.move(to: CGPoint(x: p.x, y: p.y - 4))
      c.addLine(to: CGPoint(x: p.x + 4, y: p.y))
      c.addLine(to: CGPoint(x: p.x, y: p.y + 4))
      c.addLine(to: CGPoint(x: p.x - 4, y: p.y))
      c.closePath()
      c.setFillColor(NSColor.white.cgColor)
      c.setStrokeColor(NSColor.black.cgColor)
      c.drawPath(using: .fillStroke)
    }
    for p in [a, b] {
      c.setLineWidth(3.5)
      c.setStrokeColor(NSColor.black.withAlphaComponent(0.65).cgColor)
      c.strokeEllipse(in: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16))
      c.setLineWidth(2)
      c.setStrokeColor(NSColor.white.cgColor)
      c.strokeEllipse(in: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16))
    }
    for (i, stop) in widget.fill.gradient.colors.enumerated() {
      let p = view(widget.point(stop.position))
      let color = stop.color.resolved(foreground: .black, background: .white)
      c.setFillColor(
        NSColor(
          srgbRed: CGFloat(color.r), green: CGFloat(color.g),
          blue: CGFloat(color.b), alpha: 1
        ).cgColor)
      let selected =
        store.gradientSelectedStop.map { $0.id == widget.layer.id && $0.index == i } ?? false
      c.setStrokeColor((selected ? NSColor.controlAccentColor : .white).cgColor)
      c.setLineWidth(1.5)
      c.fillEllipse(in: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
      c.strokeEllipse(in: CGRect(x: p.x - 5.5, y: p.y - 5.5, width: 11, height: 11))
    }
    c.restoreGState()
  }
}
