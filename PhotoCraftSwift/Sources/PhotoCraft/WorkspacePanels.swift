import AppKit
import PhotoCraftCore
import SwiftUI

extension WorkspaceView {
  func pixelColor(_ pixel: Pixel) -> Color {
    store.displayColor(pixel)
  }
  var colorBinding: Binding<Color> {
    Binding(
      get: { pixelColor(store.brush.color) },
      set: { color in
        if let pixel = store.workingPixel(color) { store.brush.color = pixel }
      })
  }
  var colorComponents: (h: Double, s: Double, b: Double) {
    let color = NSColor(
      red: CGFloat(unit(store.brush.color.r)), green: CGFloat(unit(store.brush.color.g)),
      blue: CGFloat(unit(store.brush.color.b)), alpha: 1)
    return (
      Double(color.hueComponent), Double(color.saturationComponent),
      Double(color.brightnessComponent)
    )
  }
  func setHSB(h: Double, s: Double, b: Double) {
    let color = NSColor(hue: h, saturation: s, brightness: b, alpha: 1)
    store.brush.color = Pixel(
      Float(color.redComponent), Float(color.greenComponent), Float(color.blueComponent))
  }
  func colorPanelContent(_ tab: ColorPanelTab) -> some View {
    VStack(spacing: 0) {
      switch tab {
      case .color:
        HStack(alignment: .top, spacing: 9) {
          ZStack {
            Rectangle().fill(pixelColor(store.backgroundColor)).frame(width: 19, height: 19)
              .overlay(Rectangle().stroke(.white)).offset(x: 5, y: 6)
            CompactColorWell(color: colorBinding).frame(width: 22, height: 22).offset(x: -3, y: -3)
          }.frame(width: 27, height: 35)
          GeometryReader { g in
            ZStack {
              Rectangle().fill(Color(hue: hue, saturation: 1, brightness: 1))
              LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
              LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
              Circle().stroke(.white, lineWidth: 1).background(
                Circle().stroke(.black.opacity(0.7), lineWidth: 3)
              ).frame(width: 8, height: 8)
                .position(
                  x: colorComponents.s * g.size.width, y: (1 - colorComponents.b) * g.size.height)
            }.contentShape(Rectangle()).gesture(
              DragGesture(minimumDistance: 0).onChanged { v in
                setHSB(
                  h: hue, s: min(1, max(0, v.location.x / g.size.width)),
                  b: 1 - min(1, max(0, v.location.y / g.size.height)))
              }
            ).accessibilityLabel("Color saturation and brightness").help(
              "Choose saturation and brightness; use Foreground color for keyboard entry")
          }
          GeometryReader { g in
            ZStack(alignment: .top) {
              LinearGradient(
                colors: (0...12).map { Color(hue: Double($0) / 12, saturation: 1, brightness: 1) },
                startPoint: .top, endPoint: .bottom)
              Rectangle().stroke(.white, lineWidth: 1).frame(height: 4).offset(
                y: hue * max(0, g.size.height - 4))
            }.contentShape(Rectangle()).gesture(
              DragGesture(minimumDistance: 0).onChanged { v in
                hue = min(0.9999, max(0, v.location.y / g.size.height))
                setHSB(h: hue, s: max(0.01, colorComponents.s), b: max(0.01, colorComponents.b))
              }
            ).accessibilityLabel("Hue spectrum")
          }.frame(width: 18)
        }.padding(10)
      case .swatches:
        ScrollView {
          LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 8), spacing: 3
          ) {
            ForEach(0..<40) { i in
              let color =
                i < 8
                ? Color(white: Double(i) / 7)
                : Color(
                  hue: Double(i % 8) / 8, saturation: 0.35 + Double(i / 8) * 0.13, brightness: 0.95)
              Button {
                colorBinding.wrappedValue = color
              } label: {
                Rectangle().fill(color).frame(height: 18)
              }.buttonStyle(.plain).help("Set foreground swatch \(i + 1)")
            }
          }.padding(10)
        }
      case .gradients:
        GradientsPanel(store: store)
      case .patterns:
        PatternsPanel(store: store)
      }
    }.onChange(of: store.brush.color) { _, _ in
      if colorComponents.s > 0.001 { hue = colorComponents.h }
    }
  }
  func propertiesPanelContent(_ tab: PropertiesTab) -> some View {
    VStack(spacing: 0) {
      ScrollView {
        switch tab {
        case .properties: layerProperties
        case .adjustments: adjustmentPanel
        case .libraries:
          unavailable(
            "Libraries",
            detail:
              "Shared color, image and layer libraries are not available yet. Use File → Place Image to add a local image."
          )
        }
      }
    }
  }
  var layerProperties: some View {
    VStack(alignment: .leading, spacing: 13) {
      if let layer = store.activeLayer {
        if (!store.editingMask || store.tool == .adjustmentBrush) && store.pathTarget != .vectorMask(layer.id) {
          Label(layer.kindLabel.capitalized, systemImage: layerIcon(layer)).padding(.bottom, 2)
          Divider()
          if !isAdjustment(layer) {
            DisclosureGroup("Transform") {
              VStack(alignment: .leading, spacing: 9) {
                HStack {
                  labeledValue("W", value: "\(Int(store.activeLayerSize.width)) px", width: 62)
                  labeledValue("H", value: "\(Int(store.activeLayerSize.height)) px", width: 62)
                }.help("Layer bounds in pixels. Use Free Transform to resize or rotate.")
                Button("Free Transform") { store.beginTransform() }.disabled(
                  !store.canTransformActiveLayer
                ).controlSize(.small)
                HStack {
                  numberField(
                    "X",
                    value: layerPositionBinding(layer, horizontal: true),
                    range: -1_000_000...1_000_000, suffix: "px")
                  numberField(
                    "Y",
                    value: layerPositionBinding(layer, horizontal: false),
                    range: -1_000_000...1_000_000, suffix: "px")
                }
                HStack(spacing: 10) {
                  labeledValue(
                    "∠",
                    value:
                      "\((atan2(layer.coordinateTransform.b,layer.coordinateTransform.a)*180 / .pi).formatted(.number.precision(.fractionLength(2))))°",
                    width: 58)
                  iconButton(
                    "arrow.left.and.right.righttriangle.left.righttriangle.right",
                    "Flip layer horizontally", enabled: store.canTransformActiveLayer
                  ) { store.transformLayer(horizontal: true) }
                  iconButton(
                    "arrow.up.and.down.righttriangle.up.righttriangle.down",
                    "Flip layer vertically",
                    enabled: store.canTransformActiveLayer
                  ) { store.transformLayer(vertical: true) }
                }
              }.padding(.top, 9).disabled(store.editingComponent || store.document.isPositionLocked(layer.id))
            }.disclosureGroupStyle(ExpandedSectionStyle())
          }
          if let source = layer.smartObject {
            SmartObjectLayerCompControls(store: store, source: source)
            Text((source.linkedSource == nil ? "Embedded: ":"Linked: ") + source.fileName).font(.caption).lineLimit(2)
            Button("Edit Contents") { store.editSmartObjectContents() }.disabled(!store.canEditSmartObjectContents)
            Button("Replace Contents…") { store.placeEmbedded(replacing: true) }.disabled(!store.canEditSmartObject)
            Button("Export Contents…") { store.exportSmartObjectContents() }
            if source.linkedSource != nil {
              if store.hasRelativePackageLinks {Button("Locate Package Sources…"){store.locatePackageSources()}.disabled(!store.canManageLinkedArtwork)}
              Text(store.linkedArtworkState(source).status.title).font(.caption).foregroundStyle(.secondary)
              HStack {
                Button("Relink…") {store.placeLinked(replacing:true)}.disabled(!store.canUpdateLinkedArtwork)
                Button("Update") {store.updateLinkedArtwork()}.disabled(!store.canUpdateLinkedArtwork)
                Button("Embed") {store.embedLinkedArtwork()}.disabled(!store.canEmbedLinkedArtwork)
              }
            } else {
              Button("Convert to Linked…") {store.convertToLinkedArtwork()}.disabled(!store.canConvertToLinked)
            }
            if source.linkedSource == nil,source.pdfSource != nil { PDFSourceEditControls(store:store,sourceID:source.sourceID) }
          }
          if store.typeEditingDraft != nil { TypeControls(store: store) }
          if case .text = layer.content, store.typeEditingDraft == nil {
            Divider()
            TypeControls(store: store)
          }
          if case .adjustment(let adjustment) = layer.content {
            adjustmentProperties(adjustment, layer: layer)
          }
          if case .fill(let color) = layer.content {
            Divider()
            HStack {
              Text("Solid Color").fontWeight(.semibold)
              Spacer()
              CompactColorWell(
                color: Binding(
                  get: { pixelColor(color) },
                  set: { value in
                    guard let pixel = store.workingPixel(value) else { return }
                    store.setSolidColor(layer.id, color: pixel)
                  }), label: "Fill color", supportsOpacity: false
              )
              .frame(width: 28, height: 24)
              .disabled(store.document.isLocked(layer.id))
            }
          }
          if case .gradientFill(let fill) = layer.content {
            Divider()
            GradientSwatch(gradient: fill.gradient).frame(height: 28)
            Text("\(fill.placement.style.rawValue) · \(fill.gradient.method.rawValue)").font(
              .caption)
            HStack {
              Button("Edit Gradient Fill…") { store.beginGradientFill(editing: layer.id) }
              Button("Save Preset…") { store.beginSaveGradientPreset() }.disabled(
                store.gradients.busy)
            }
          }
          if case .patternFill(let fill) = layer.content {
            Divider()
            if let pattern = store.document.pattern(fill.patternID) {
              HStack {
                PatternSwatch(pattern: pattern).frame(width: 40, height: 40)
                Text(pattern.displayName).lineLimit(2)
              }
            }
            Button("Edit Pattern Fill…") { store.beginPatternFill(editing: layer.id) }
          }
          Divider()
          if !isAdjustment(layer) {
            Text("⌄  Align and Distribute").fontWeight(.medium)
            LayerLayoutControls(store: store)
          }
          Divider()
        }
        if store.pathTarget == .vectorMask(layer.id) {
          Label("Vector Mask", systemImage: "pencil.tip.crop.circle").fontWeight(.medium)
          Text("Edit anchors and handles with Direct Selection.").foregroundStyle(.secondary)
          VectorMaskControls(store: store)
          Button("Edit Layer Content") {
            store.select(layer.id)
            store.layersTab = .layers
          }
          .controlSize(.small)
        }
        if layer.mask != nil && store.pathTarget != .vectorMask(layer.id) {
          Text(store.editingMask ? "Layer Mask · Editing" : "Layer Mask").fontWeight(.medium)
          Text("Black hides · White reveals").foregroundStyle(.secondary)
          MaskControls(store: store, layer: layer)
          HStack {
            Button(store.editingMask ? "Edit Content" : "Edit Mask") {
              if store.editingMask { store.select(layer.id) } else { store.selectMask(layer.id) }
            }
            Button("Invert Mask") { store.perform(.invertMask(layer.id)) }
          }.controlSize(.small).disabled(layer.locked || layer.isBackground)
        }
        Text("⌄  Quick Actions").fontWeight(.medium)
        HStack(spacing: 6) {
          Button("Select Subject") { store.detectSubject() }.disabled(!store.canDetectSubject())
          Button("Remove Background") { store.detectSubject(removeBackground: true) }
            .disabled(!store.canDetectSubject(removeBackground: true))
        }.controlSize(.small)
        Toggle("Sample All Layers", isOn: $store.subjectSampleAllLayers)
          .controlSize(.small).disabled(!store.clipboardTargetAvailable)
        HStack(spacing: 6) {
          Button("Rasterize") { store.rasterize() }.disabled(
            (isRaster(layer) && layer.video == nil) || isAdjustment(layer) || layer.isGroup)
          Button(layer.mask == nil ? "Add Mask" : "Remove Mask") { store.addMask() }
        }.controlSize(.small).disabled(layer.locked || layer.isBackground || store.editingComponent)
      } else {
        Label("Document", systemImage: "doc")
        Text(
          "\(store.document.width) × \(store.document.height) px · \(store.document.colorMode.rawValue.uppercased())/\(depthNumber(store.document.depth))"
        )
      }
    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
  }
  func isAdjustment(_ layer: Layer) -> Bool {
    if case .adjustment = layer.content { true } else { false }
  }
  func isRaster(_ layer: Layer) -> Bool { if case .raster = layer.content { layer.smartObject == nil } else { false } }
  @ViewBuilder func adjustmentProperties(_ a: Adjustment, layer: Layer) -> some View {
    Divider()
    switch a {
    case .source:
      SourceAdjustmentEditor(store:store,layerID:layer.id).id(layer.id).disabled(store.document.isLocked(layer.id))
    case .levels:
      LevelsEditor(store: store, layerID: layer.id)
        .id(layer.id).disabled(store.document.isLocked(layer.id))
    case .curves:
      CurvesEditor(store: store, layerID: layer.id)
        .id(layer.id).disabled(store.document.isLocked(layer.id))
    case .colorLookup:
      ColorLookupEditor(store: store, layerID: layer.id)
    case .modern:
      ModernAdjustmentEditor(store:store,layerID:layer.id).id(layer.id)
    case .classic:
      ClassicAdjustmentEditor(store: store, layerID: layer.id)
        .id(layer.id).disabled(store.document.isLocked(layer.id))
    case .colorBalance:
      ColorBalanceEditor(store: store, layerID: layer.id)
    case .hueSaturation:
      HueSaturationEditor(store: store, layerID: layer.id)
        .id(layer.id).disabled(store.document.isLocked(layer.id))
    case .gradientMap:
      GradientMapEditor(store: store, layerID: layer.id)
        .id(layer.id).disabled(store.document.isLocked(layer.id))
    case .tonalSteps:
      TonalStepsEditor(store: store, layerID: layer.id)
        .id(layer.id).disabled(store.document.isLocked(layer.id))
    case .exposure(let e):
      adjustmentSlider("Exposure", value: e, range: -5...5) { .exposure($0) }
    case .saturation(let s):
      adjustmentSlider("Saturation", value: s, range: 0...2) { .saturation($0) }
    case .brightnessContrast(let b, let c):
      adjustmentSlider("Brightness", value: b, range: -1...1) { .brightnessContrast($0, c) }
      adjustmentSlider("Contrast", value: c, range: 0...3) { .brightnessContrast(b, $0) }
    case .invert: Text("Invert").foregroundStyle(.secondary)
    case .grayscale: Text("Black & White · Luminance conversion").foregroundStyle(.secondary)
    }
  }
  func adjustmentSlider(
    _ title: String, value: Float, range: ClosedRange<Float>, make: @escaping (Float) -> Adjustment
  ) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text(title)
        Spacer()
        Text(value.formatted(.number.precision(.fractionLength(2)))).monospacedDigit()
      }
      Slider(
        value: Binding(
          get: { value },
          set: { v in
            if let layer = store.activeLayer {
              store.perform(.replaceContent(layer.id, .adjustment(make(v))))
            }
          }), in: range, onEditingChanged: { store.coalesce($0) })
    }
  }
  var adjustmentPanel: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Single adjustments").fontWeight(.semibold)
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 14)
      {
        adjustmentButton("Brightness / Contrast", "sun.max", .brightnessContrast(0, 1))
        adjustmentButton("Levels", "chart.bar", .levels(.init()))
        adjustmentButton(
          "Curves", "point.topleft.down.curvedto.point.bottomright.up", .curves(.init()))
        adjustmentButton("Exposure", "plus.forwardslash.minus", .classic(.init(.exposure)))
        adjustmentButton("Vibrance", "triangle", .classic(.init(.vibrance)))
        adjustmentButton("Hue/Saturation", "slider.horizontal.3", .hueSaturation(.init()))
        adjustmentButton("Color Balance", "slider.horizontal.3", .colorBalance(.init()))
        adjustmentButton("Black & White", "rectangle.lefthalf.filled", .classic(.init(.blackWhite)))
        adjustmentButton("Photo Filter", "camera.filters", .classic(.init(.photoFilter)))
        adjustmentButton("Channel Mixer", "circle.grid.2x2", .classic(.init(.channelMixer)))
        adjustmentButton("Color and vibrance", "camera.filters", .modern(.init(.colorVibrance)))
        adjustmentButton("Light", "sun.max", .modern(.init(.light)))
        adjustmentButton("Clarity and dehaze", "cloud.fog", .modern(.init(.clarityDehaze)))
        adjustmentButton("Grain", "circle.dotted", .modern(.init(.grain)))
        adjustmentButton("Color Lookup", "square.grid.3x3", .colorLookup(.init()))
        adjustmentButton("Selective Color", "square.lefthalf.filled", .classic(.init(.selectiveColor)))
        adjustmentButton("Invert", "square.lefthalf.filled", .invert)
        adjustmentButton("Gradient Map", "rectangle.lefthalf.filled", .gradientMap(.init()))
          .disabled(!store.canAddGradientMap)
          .help(
            store.document.depth == .f32
              ? "Gradient Map requires an 8- or 16-bit document"
              : "New Gradient Map adjustment layer")
        adjustmentButton("Posterize", "chart.bar.fill", .tonalSteps(.init(kind: .posterize)))
        adjustmentButton(
          "Threshold", "circle.lefthalf.filled", .tonalSteps(.init(kind: .threshold)))
      }
      Text("Dimmed adjustments are not available yet.").font(.system(size: 10)).foregroundStyle(
        .secondary)
    }.padding(12)
  }
  func adjustmentButton(_ title: String, _ symbol: String, _ adjustment: Adjustment?) -> some View {
    Button {
      if let adjustment {
        if case .colorLookup = adjustment {
          store.addColorLookup()
        } else if case .modern(let value) = adjustment {
          store.addModernAdjustment(value.kind)
        } else if case .classic(let value) = adjustment {
          store.addClassicAdjustment(value.kind)
        } else if case .levels = adjustment {
          store.addLevelsLayer()
        } else if case .curves = adjustment {
          store.addCurvesLayer()
        } else if case .colorBalance = adjustment {
          store.addColorBalanceLayer()
        } else if case .hueSaturation = adjustment {
          store.addHueSaturationLayer()
        } else if case .gradientMap = adjustment {
          store.addGradientMapLayer()
        } else if case .tonalSteps(let settings) = adjustment {
          store.addTonalStepsLayer(settings.kind)
        } else {
          store.adjustment(adjustment, name: title)
        }
        store.propertiesTab = .properties
      }
    } label: {
      VStack(spacing: 5) {
        Image(systemName: symbol).font(.system(size: 17))
        Text(title).font(.system(size: 9)).multilineTextAlignment(.center).frame(height: 26)
      }.frame(maxWidth: .infinity)
    }.buttonStyle(.plain).disabled(adjustment == nil || {if case .modern(let value)=adjustment{return !store.canAddModernAdjustment(value.kind)};return false}()).help(
      adjustment == nil ? "\(title) — not available yet" : "New \(title) adjustment layer")
  }
}

struct ExpandedSectionStyle: DisclosureGroupStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        configuration.isExpanded.toggle()
      } label: {
        HStack(spacing: 5) {
          Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right").font(
            .system(size: 8))
          configuration.label.fontWeight(.medium)
          Spacer()
        }
      }.buttonStyle(.plain)
      if configuration.isExpanded { configuration.content }
    }.onAppear { configuration.isExpanded = true }
  }
}
