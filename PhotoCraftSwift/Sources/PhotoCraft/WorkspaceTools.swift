import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

extension WorkspaceView {
  var toolRail: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        Button {
          doubleTools.toggle()
        } label: {
          Image(systemName: doubleTools ? "chevron.left.2" : "chevron.right.2").font(
            .system(size: 7)
          )
          .frame(height: 15)
        }
        .buttonStyle(.plain).help("Toggle tool columns")
        .accessibilityLabel("Toggle tool columns")
        .accessibilityValue(doubleTools ? "Two columns" : "One column")
        ScrollViewReader { proxy in
          ScrollView(.vertical) {
            LazyVGrid(
              columns: Array(
                repeating: GridItem(.fixed(30), spacing: 0), count: doubleTools ? 2 : 1),
              spacing: 0
            ) {
              ForEach(WorkspaceCatalog.groups.indices, id: \.self) { index in
                let group = WorkspaceCatalog.groups[index]
                let tool = group.first { $0.id == store.rememberedTools[group[0].id] } ?? group[0]
                toolButton(tool, group: group).id(group[0].id)
              }
              iconButton("ellipsis", "Workspace Feature Map") { store.showGaps = true }
            }
          }
          .scrollIndicators(.hidden)
          .onChange(of: store.selectedTool.id) { _, id in
            if let group = WorkspaceCatalog.groups.first(where: { $0.contains { $0.id == id } }) {
              proxy.scrollTo(group[0].id)
            }
          }
        }
        .frame(
          height: min(
            CGFloat(
              (WorkspaceCatalog.groups.count + 1 + (doubleTools ? 1 : 0)) / (doubleTools ? 2 : 1))
              * 26,
            max(0, geometry.size.height - 15 - 118)))
        toolRailFooter.frame(height: 118)
        Spacer(minLength: 0)
      }.frame(maxWidth: .infinity)
    }.frame(width: doubleTools ? 68 : 40).background(StudioTheme.chrome)
      .overlay(alignment: .trailing) { Rectangle().fill(StudioTheme.line).frame(width: 1) }
  }
  var toolRailFooter: some View {
    VStack(spacing: 5) {
      HStack(spacing: 5) {
        iconButton("square.on.square", "Default foreground/background (D)") {
          store.resetColors()
        }
        iconButton("arrow.left.arrow.right", "Swap foreground/background (X)") {
          store.swapColors()
        }
      }.scaleEffect(0.7).frame(width: 34, height: 17)
      ZStack {
        Rectangle().fill(pixelColor(store.backgroundColor)).frame(width: 19, height: 19)
          .overlay(Rectangle().stroke(.white.opacity(0.8))).offset(x: 5, y: 4)
        CompactColorWell(color: colorBinding).frame(width: 23, height: 23).offset(x: -4, y: -4)
      }.frame(height: 30)
      QuickMaskModeButton(store:store).frame(width:32,height:22)
        .contextMenu { Button("Quick Mask Options…") { store.beginChannelDialog(.quickOptions) } }
      iconButton("rectangle.on.rectangle", "Fit canvas to workspace") { store.fit() }
    }.padding(.vertical, 6)
  }
  func toolButton(_ tool: WorkspaceTool, group: [WorkspaceTool]) -> some View {
    Menu {
      ForEach(group) { member in
        Button {
          store.chooseTool(member)
        } label: {
          Label(
            member.title + (member.native == nil ? " — not available yet" : ""),
            systemImage: member.symbol)
        }
      }
    } label: {
      ZStack(alignment: .bottomTrailing) {
        Image(systemName: tool.symbol).font(.system(size: 15, weight: .regular)).frame(
          width: 29, height: 25)
        if group.count > 1 {
          Image(systemName: "triangle.fill").font(.system(size: 4)).rotationEffect(.degrees(135))
            .padding(2)
        }
      }
      .foregroundStyle(tool.native == nil ? Color(white: 0.66) : Color(white: 0.91))
      .background(
        group.contains(store.selectedTool) ? Color(white: 0.22) : .clear,
        in: RoundedRectangle(cornerRadius: 2)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 2).stroke(
          group.contains(store.selectedTool) ? Color.white.opacity(0.25) : .clear))
    } primaryAction: {
      store.chooseTool(tool)
    }
    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 30, height: 26)
    .help(
      "\(tool.title)\(tool.shortcut.isEmpty ? "" : " (\(tool.shortcut))")\(tool.native == nil ? " — not available yet" : "") · Right-click for grouped tools"
    )
    .accessibilityLabel(tool.title + " Tool")
    .contextMenu {
      ForEach(group) { member in
        Button(member.title + (member.native == nil ? " — not available yet" : "")) {
          store.chooseTool(member)
        }
      }
    }
  }
  var optionsBar: some View {
    HStack(spacing: 9) {
      iconButton("house.fill", "New document") {
        NSApp.sendAction(#selector(AppDelegate.newFile), to: nil, from: nil)
      }
      Divider().frame(height: 22)
      Image(systemName: store.selectedTool.symbol).font(.system(size: 16)).frame(width: 25).help(
        store.selectedTool.title)
      Divider().frame(height: 22)
      ScrollView(.horizontal) {
        HStack(spacing: 12) { toolOptions }.frame(height: 33)
      }.scrollIndicators(.hidden).frame(minWidth: 0, maxWidth: .infinity)
        .layoutPriority(-1)
      iconButton("square.and.arrow.up", "Export Image") { store.exportImage() }
      iconButton("sparkles", "Create with Apple Intelligence") { store.showAI = true }
      iconButton("list.bullet.rectangle", "Workspace Feature Map") { store.showGaps = true }
    }.padding(.horizontal, 9).frame(height: 35).background(StudioTheme.chrome)
      .overlay(alignment: .bottom) { Rectangle().fill(StudioTheme.line).frame(height: 1) }
  }
  @ViewBuilder var toolOptions: some View {
    if store.transformDraft != nil,store.transformDraft?.movingPixels != true {
      transformOptions
    } else if store.unavailableToolID != nil {
      Text(store.selectedTool.title).fontWeight(.medium)
      Label("Not available yet", systemImage: "circle.dashed").foregroundStyle(
        .orange.opacity(0.85))
      Button("View feature map") { store.showGaps = true }.buttonStyle(.bordered).controlSize(
        .small)
    } else {
      switch store.tool {
      case .objectSelection,.quickSelection,.selectionBrush:
        SelectionToolOptionsView(store:store)
      case .gradient:
        gradientOptions
      case .magicWand, .paintBucket:
        colorRegionOptions
      case .pen, .freeformPen, .curvaturePen, .pathSelection, .directSelection:
        Text("Path").padding(4).background(StudioTheme.field)
        if store.tool == .freeformPen {Text("Curve Fit");TextField("Curve Fit",value:$store.pathCurveFit,format:.number).frame(width:45);Text("px")}
        Picker(
          "Path operation",
          selection: Binding(
            get: { store.pathOperation },
            set: { store.changePathOperation($0) })
        ) {
          ForEach(PathOperation.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.labelsHidden().frame(width: 100).controlSize(.small)
        Button("Selection") { store.pathToSelection() }.disabled(store.selectedVectorPath == nil)
        Button("Vector Mask") { store.makeVectorMask() }
          .disabled(store.selectedVectorPath == nil || store.activeLayer == nil)
        Button("Finish Path") { store.finishPath() }.disabled(store.penComponent == nil)
        Text(
          store.tool == .freeformPen ? "Drag a path · Return finishes · Escape cancels" : store.tool == .curvaturePen ? "Click curves · Double-click corners · Click first point to close" : store.tool == .pen
            ? "Click anchors · Drag curves · Return finishes · ⌥ Corner"
            : "Drag anchors or handles · ⌥ Independent handle · Delete anchor"
        )
        .foregroundStyle(.secondary)
      case .frame:
        FrameToolOptions(store: store)
      case .artboard:
        ArtboardToolOptions(store: store)
      case .move:
        Toggle("Auto-Select", isOn: $store.autoSelect).toggleStyle(.checkbox).controlSize(.mini)
        Text("Layer").padding(.horizontal, 7).padding(.vertical, 3).background(StudioTheme.field)
        Toggle("Show Layer Bounds", isOn: $store.showLayerBounds).toggleStyle(.checkbox)
          .controlSize(.mini)
        Divider().frame(height: 20)
        LayerLayoutControls(store: store)
      case .blur, .sharpen, .smudge:
        focusOptions
      case .dodge, .burn, .sponge:
        toningOptions
      case .patch, .contentAwareMove, .redEye:
        regionRetouchOptions
      case .spotHealing:
        spotHealingOptions
      case .cloneStamp, .healingBrush:
        cloneOptions
      case .pencil, .colorReplacement, .mixerBrush, .patternStamp, .backgroundEraser, .magicEraser:
        PaintingToolOptionsView(store:store)
      case .adjustmentBrush:
        AdjustmentBrushOptionsView(store:store)
      case .brush, .eraser:
        if store.editingMask {
          Text("Layer Mask").foregroundStyle(.white).padding(4).background(StudioTheme.field)
        }
        Button {
          brushPopover.toggle()
        } label: {
          HStack(spacing: 5) {
            Circle().fill(.white).frame(width: 12, height: 12)
            Text("\(Int(store.brush.size))")
            Image(systemName: "chevron.down").font(.system(size: 8))
          }
        }.buttonStyle(.plain).help("Brush size and hardness").popover(isPresented: $brushPopover) {
          brushSettings
        }
        Picker("Mode:",selection:$store.brushOptions.mode){ForEach(BlendMode.allCases,id: \.self){Text($0.rawValue).tag($0)}}.frame(width:145).controlSize(.small)
        percentField("Opacity:",value:$store.brush.opacity)
        numberField("Flow:",value:Binding(get:{store.brushOptions.flow*100},set:{store.brushOptions.flow=$0/100}),range:0...100,suffix:"%")
        numberField("Smoothing:",value:Binding(get:{store.brushOptions.smoothing.amount*100},set:{store.brushOptions.smoothing.amount=$0/100}),range:0...100,suffix:"%")
        Toggle("Airbrush",isOn:$store.brushOptions.buildUp).help("Build up paint while holding still")
        Toggle("Pressure Size",isOn:$store.brushOptions.pressureSize)
        Toggle("Pressure Opacity",isOn:$store.brushOptions.pressureOpacity)
        Button("Brush Settings"){NSApp.sendAction(#selector(AppDelegate.showBrushSettings),to:nil,from:nil)}
        Menu("Presets"){ForEach(store.brushes.file.presets){p in Button(p.name){do{try store.selectBrush(p.id)}catch{store.error=error.localizedDescription}}};Divider();Button("Brushes…"){NSApp.sendAction(#selector(AppDelegate.showBrushes),to:nil,from:nil)}}
      case .marquee, .ellipticalMarquee, .rowMarquee, .columnMarquee, .lasso, .polygonLasso, .magneticLasso:
        Picker("Selection mode", selection: $store.selectionMode) {
          ForEach(SelectionMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.labelsHidden().frame(width: 105).controlSize(.small).disabled(store.tool == .magneticLasso && store.magneticDraft != nil)
        numberField("Feather:", value: $store.selectionFeather, range: 0...100, suffix: "px").disabled(store.tool == .magneticLasso && store.magneticDraft != nil)
        Toggle("Anti-alias", isOn: $store.selectionAntiAlias).disabled(store.tool == .marquee || store.tool.singlePixelMarquee != nil || (store.tool == .magneticLasso && store.magneticDraft != nil))
        Button("Select and Mask…") { store.beginSelectMask() }.disabled(!store.canBeginSelectMask).controlSize(.small)
        if store.tool == .magneticLasso {
          numberField("Width:",value:$store.magneticSettings.width,range:1...256,suffix:"px").disabled(store.magneticDraft != nil)
          numberField("Contrast:",value:$store.magneticSettings.contrast,range:1...100,suffix:"%").disabled(store.magneticDraft != nil)
          numberField("Frequency:",value:$store.magneticSettings.frequency,range:0...100,suffix:"").disabled(store.magneticDraft != nil)
          Toggle("Tablet Pressure",isOn:$store.magneticSettings.stylusPressure).disabled(store.magneticDraft != nil)
          if store.magneticDraft != nil {Button("Close"){store.finishMagneticLasso()};Button("Cancel"){store.cancelMagneticLasso()}}
        } else if store.tool == .polygonLasso {
          Text("Click vertices · Double-click or Return to close · Esc cancels").foregroundStyle(
            .secondary)
        } else {
          Text("⇧ Add · ⌥ Subtract · ⇧⌥ Intersect at drag start").foregroundStyle(.secondary)
        }
      case .crop:
        cropOptions
      case .text, .verticalText:
        Picker("Font", selection: Binding(get: { store.typeEditor.map { NativeTextLayout.styles($0.typingAttributes, dpi: store.document.pixelsPerInch).0.font } ?? store.fontName }, set: { value in store.fontName = value; if store.typeEditingDraft != nil { store.formatType { s, _ in s.font = value } } })) {
          ForEach(
            Array(Set(NSFontManager.shared.availableFonts + [store.fontName])).sorted(),
            id: \.self
          ) { Text($0).tag($0) }
        }.labelsHidden().frame(width: 150).controlSize(.small).help("Font family")
        numberField("Size:", value: Binding(get: { store.typeEditor.map { NativeTextLayout.styles($0.typingAttributes, dpi: store.document.pixelsPerInch).0.size } ?? store.fontSize }, set: { value in store.fontSize = value; if store.typeEditingDraft != nil { store.formatType { s, _ in s.size = value } } }), range: 1...4096, suffix: "pt")
        ColorPicker("Type color", selection: Binding(get: {
          if let editor = store.typeEditor { let c = NativeTextLayout.styles(editor.typingAttributes, dpi: store.document.pixelsPerInch).0.color; return pixelColor(c) }
          return colorBinding.wrappedValue
        }, set: { value in
          colorBinding.wrappedValue = value
          if store.typeEditingDraft != nil { let color = store.brush.color; store.formatType { s, _ in s.color = color } }
        })).labelsHidden()
        if store.editableType != nil{Button("Warp / Path Text…"){store.beginShapedType()}}
        if store.typeEditingDraft != nil {
          Button("Cancel") { store.finishType(cancel: true) }
          Button("Commit") { store.finishType() }
        } else {
          Text("Click for point text · Drag for paragraph text").foregroundStyle(.secondary)
          if case .text = store.activeLayer?.content {
            Button("Edit Text") { if let layer = store.activeLayer { store.beginType(layer) } }
          }
        }
      case .rectangle, .ellipse, .triangle, .polygon, .star, .line, .customShape:
        ShapeToolOptions(store:store)
      case .eyedropper:
        labeledValue("Sample Size:", value: "Point Sample", width: 100)
        labeledValue("Sample:", value: "All Layers", width: 90)
      case .hand, .zoom:
        Button("100%") { store.setZoom(1) }.controlSize(.small)
        Button("Fit Screen") { store.fit() }.controlSize(.small)
        if store.tool == .zoom {
          Text("Click to zoom in · ⌥ Click to zoom out").foregroundStyle(.secondary)
        } else {
          Text("Drag to pan · Hold Space in any tool").foregroundStyle(.secondary)
        }
      }
    }
  }
  func labeledValue(_ label: String, value: String, width: CGFloat) -> some View {
    HStack(spacing: 4) {
      if !label.isEmpty { Text(label) }
      Text(value).frame(width: width, alignment: .leading).padding(.horizontal, 5).padding(
        .vertical, 3
      ).background(StudioTheme.field).overlay(Rectangle().stroke(.white.opacity(0.08)))
    }
  }
  // Fixed line boxes keep the workspace's 11-point fields aligned across hosts.
  // Preferred TextField heights can otherwise vary by one point at the same font.
  func percentField(_ label: String, value: Binding<Float>) -> some View {
    HStack(spacing: 4) {
      Text(label)
      NativeNumericField(
        store: store, label: label,
        value: Binding(
          get: { Double(value.wrappedValue * 100) },
          set: { value.wrappedValue = Float($0 / 100) }),
        range: 0...100, alignment: .right
      )
      .frame(width: 30, height: 13, alignment: .top)
      .background {
        WorkspaceFieldLayoutProbe(
          owner: store.identity, name: label + ".percent", value: Double(value.wrappedValue))
      }
      .padding(3)
      .background(StudioTheme.field).accessibilityLabel(label)
      Text("%")
    }
  }
  func numberField(
    _ label: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String = ""
  ) -> some View {
    HStack(spacing: 4) {
      Text(label).foregroundStyle(.secondary)
      NativeNumericField(store: store, label: label, value: value, range: range)
        .frame(width: 45, height: 13, alignment: .top)
        .background {
          WorkspaceFieldLayoutProbe(
            owner: store.identity, name: label + ".content", value: value.wrappedValue)
        }
        .padding(3).background(StudioTheme.field)
        .background {
          WorkspaceFieldLayoutProbe(
            owner: store.identity, name: label + ".outer", value: value.wrappedValue)
        }
        .accessibilityLabel(label)
      if !suffix.isEmpty { Text(suffix).foregroundStyle(.secondary) }
    }
  }
  var brushSettings: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Brush Tip").font(.headline)
      numberField("Size", value: $store.brush.size, range: 1...2048, suffix: "px")
      Slider(value: $store.brush.size, in: 1...300)
      percentField("Hardness", value: $store.brush.hardness)
      Slider(value: $store.brush.hardness, in: 0...1)
      Text("Round brush · Pressure controls size").font(.caption).foregroundStyle(.secondary)
      Divider()
      Text("Preset libraries, flow and advanced dynamics are not available yet.").font(.caption)
        .foregroundStyle(.secondary)
    }.padding(18).frame(width: 250)
  }
}
