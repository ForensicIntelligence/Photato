import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

extension WorkspaceView {
  var filteredLayers: [Layer] {
    store.layersInPanel()
  }

  func layersPanelContent(_ tab: LayersTab) -> some View {
    VStack(spacing: 0) {
      switch tab {
      case .layers:
        layerControls
        ScrollViewReader { proxy in
          GeometryReader { viewport in
            ScrollView {
              VStack(spacing: 0) {
                LazyVStack(spacing: 1) {
                  ForEach(filteredLayers) { layer in
                    VStack(spacing: 0) {
                      layerRow(layer)
                      if let stack = layer.smartFilters { SmartFilterRows(store: store, layer: layer, stack: stack) }
                    }.id(layer.id)
                  }
                }.padding(.vertical, 3)
                  .background {
                    LayerRevealScrollBridge(
                      store: store, tracker: layerReveal, eyes: layerEyeTracking,
                      request: layerReveal.currentRequest, visibleIDs: filteredLayers.map(\.id),
                      rowHeight: store.workspaceLibrary.layerPanelOptions.thumbnailSize.controlHeight + 6,
                      approach: { proxy.scrollTo($0) }
                    ).accessibilityHidden(true)
                  }
                LayerPanelEmptySelectionArea(store: store).frame(minHeight: 18, maxHeight: .infinity).layoutPriority(-1)
              }.frame(minHeight: viewport.size.height, alignment: .top)
            }
          }
        }
        .onAppear { _ = layerReveal.appear(store) }
        .onChange(of: store.layerNameDraft?.id) { _, _ in _ = layerReveal.rename(store) }
        .onChange(of: LayerRevealObservation(store)) { _, _ in _ = layerReveal.track(store) }
        .onDisappear {
          layerEyeTracking.cancel()
          layerReveal.end()
        }
        .onChange(of: store.identity) { _, _ in layerEyeTracking.cancel() }
        Spacer(minLength: 0)
        layerFooter
      case .channels: ChannelsPanel(store: store)
      case .paths: PathsPanel(store: store)
      }
    }
  }
  var layerControls: some View {
    VStack(spacing: 7) {
      LayerFilterControls(store: store)
      HStack(spacing: 7) {
        Picker(
          "Blend mode",
          selection: Binding(
            get: {
              store.activeLayer?.group?.passThrough == true
                ? "Pass Through"
                : (store.activeLayer?.blendMode.rawValue ?? BlendMode.normal.rawValue)
            },
            set: { value in
              if let layer = store.activeLayer {
                if value == "Pass Through", var group = layer.group {
                  group.passThrough = true
                  store.perform(.groupProperties(layer.id, group))
                } else if let blend = BlendMode(rawValue: value) {
                  store.perform(.blend(layer.id, blend))
                }
              }
            })
        ) {
          if store.activeLayer?.isGroup == true { Text("Pass Through").tag("Pass Through") }
          ForEach(BlendMode.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
        }.labelsHidden().controlSize(.small).frame(maxWidth: .infinity).disabled(
          store.activeLayer == nil || store.activeLayer.map { store.document.isLocked($0.id) } == true)
        LayerOpacityControl(store: store)
      }
      HStack(spacing: 6) {
        Text("Lock:").foregroundStyle(.secondary)
        iconButton("checkerboard.rectangle", "Lock transparent pixels",
          enabled: store.canChangeLayerProtection && store.activeLayer?.protection.locksImage != true,
          selected: store.activeLayer?.protection.locksTransparency == true
        ) { store.toggleLayerProtection(.transparency) }
        iconButton("paintbrush", "Lock image pixels",
          enabled: store.canChangeLayerProtection && store.activeLayer?.locked != true,
          selected: store.activeLayer?.protection.contains(.image) == true
        ) { store.toggleLayerProtection(.image) }
        iconButton("arrow.up.and.down.and.arrow.left.and.right", "Lock position",
          enabled: store.canChangeLayerProtection && store.activeLayer?.locked != true,
          selected: store.activeLayer?.protection.contains(.position) == true
        ) { store.toggleLayerProtection(.position) }
        iconButton("rectangle.dashed", "Prevent auto-nest",
          enabled: store.canChangeLayerProtection && store.activeLayer?.locked != true,
          selected: store.activeLayer?.protection.contains(.autoNest) == true
        ) { store.toggleLayerProtection(.autoNest) }
        iconButton((store.activeLayer?.locked == true || store.activeLayer?.isBackground == true) ? "lock.fill" : "lock", "Lock or unlock layer",
          enabled: store.canChangeLayerProtection,
          selected: store.activeLayer?.protection.fullyLocks == true
        ) { store.toggleFullLayerProtection() }
        Spacer(minLength: 0)
        Button { store.beginLayerStyle() } label: {
          labeledValue("Fill:", value: "\(Int(((store.activeLayer?.style?.fillOpacity ?? 1) * 100).rounded()))%", width: 37)
        }.buttonStyle(.plain).disabled(!store.canBeginLayerStyle).help("Edit Fill opacity in Layer Style")
      }
    }.padding(.horizontal, 8).padding(.vertical, 7)
  }
  func layerRow(_ layer: Layer) -> some View {
    let size = store.workspaceLibrary.layerPanelOptions.thumbnailSize
    return GeometryReader { geometry in
      layerRowContent(
        layer,
        metrics: LayerRowMetrics(
          size: size, layer: layer,
          depth: store.layerPanelDocument.ancestors(of: layer.id).count, availableWidth: geometry.size.width))
    }.frame(height: size.controlHeight + 6)
      .modifier(SmartFilterDropTarget(store: store, layerID: layer.id))
  }
  func layerRowContent(_ layer: Layer, metrics: LayerRowMetrics) -> some View {
    HStack(spacing: 6) {
      LayerEyeControl(
        store: store, layer: layer, tracking: layerEyeTracking, height: metrics.size.controlHeight
      )
      .frame(width: 22, height: metrics.size.controlHeight)
      .background((layer.colorLabel ?? .none).swatch.opacity(0.55))
      Color.clear.frame(width: metrics.indentation)
      if layer.isGroup {
        LayerGroupDisclosureControl(store: store, layer: layer, height: metrics.size.controlHeight)
          .frame(width: 14, height: metrics.size.controlHeight)
      }
      HStack(spacing: 6) {
        if layer.isClipped {
          Image(systemName: "arrow.turn.down.right").font(.system(size: 10)).help(
            "Clipped to the base layer below")
        }
        Button {
          store.select(layer.id, modifiers: NSEvent.modifierFlags)
        } label: {
          layerPreview(layer, component: .content, metrics: metrics).padding(2).border(
            layer.id == store.document.activeLayerID && !store.editingMask
              && store.pathTarget != .vectorMask(layer.id) ? .white : .clear,
            width: 1)
        }.buttonStyle(.plain).accessibilityLabel("Edit content of \(layer.name)")
          .highPriorityGesture(
            TapGesture(count: 2).onEnded {
              if case .gradientFill = layer.content {
                store.select(layer.id)
                store.beginGradientFill(editing: layer.id)
              } else if case .patternFill = layer.content {
                store.select(layer.id)
                store.beginPatternFill(editing: layer.id)
              } else {
                store.select(layer.id)
              }
            })
        if layer.frame != nil {
          Button { store.tool = .frame; store.selectFrameTarget(layer, target: .frame) } label: { Image(systemName: "rectangle.badge.xmark").frame(width: 22, height: 24) }.buttonStyle(.plain).help("Select Frame")
          if let child = store.document.children(of: layer.id).last {
            Button { store.tool = .frame; store.selectFrameTarget(layer, target: .contents) } label: { layerPreview(child, component: .content, metrics: metrics).padding(2).border(store.document.activeLayerID == child.id ? .white : .clear) }.buttonStyle(.plain).help("Select Frame Contents")
          }
        }
        if layer.mask != nil {
          Button {
            store.updateMask(layer.id) { $0.linked.toggle() }
          } label: {
            Image(systemName: layer.effectiveMaskProperties.linked ? "link" : "link.badge.plus")
              .font(.system(size: 9)).foregroundStyle(.secondary)
          }.buttonStyle(.plain)
            .help(layer.effectiveMaskProperties.linked ? "Unlink layer mask" : "Link layer mask")
          layerPreview(layer, component: .pixelMask, metrics: metrics)
            .overlay { if !layer.effectiveMaskProperties.enabled { DisabledMaskMark() } }
            .padding(2).border(
              store.editingMask && layer.id == store.document.activeLayerID ? .white : .gray
            )
            .overlay { MaskThumbnailControl(store: store, layer: layer, kind: .pixel) }
        }
        if let mask = layer.vectorMask {
          layerPreview(layer, component: .vectorMask, metrics: metrics)
            .overlay { if !mask.enabled { DisabledMaskMark() } }
            .padding(2).border(store.pathTarget == .vectorMask(layer.id) ? .white : .gray)
            .overlay { MaskThumbnailControl(store: store, layer: layer, kind: .vector) }
        }
        if let draft = store.layerNameDraft, draft.layerID == layer.id {
          LayerNameField(store: store, draft: draft, visibleIDs: filteredLayers.map(\.id))
            .frame(minWidth: 24, maxWidth: .infinity, minHeight: 16, maxHeight: 18)
            .id(draft.id)
        } else {
          Text(layer.name).font(layer.isBackground ? .system(size:10).italic():.system(size:10)).underline(
            store.document.isClippingBase(layer.id)
          )
          .lineLimit(1).highPriorityGesture(
            TapGesture(count: 2).onEnded { store.beginLayerName(layer.id) })
        }
        Spacer(minLength: 2)
        if layer.linkID != nil,LayerLinks.related(in:store.document,layerIDs:[layer.id]).count>1{LayerLinkBadge(store:store,layer:layer)}
        if !layer.protection.isEmpty {
          Image(systemName: layer.locked || layer.isBackground ? "lock.fill" : "lock").font(.system(size: 10)).padding(.trailing, 8)
        }
      }
      .contentShape(Rectangle())
      .onTapGesture { store.select(layer.id, modifiers: NSEvent.modifierFlags) }
      .draggable(layer.id.uuidString)
      .dropDestination(for: String.self) { items, _ in
        guard let raw = items.first, let source = UUID(uuidString: raw), source != layer.id,
          store.document.layers.contains(where: { $0.id == source }),
          let target = store.document.layers.firstIndex(where: { $0.id == layer.id })
        else { return false }
        if layer.isGroup {
          store.perform(.relocate(source, layer.id, store.document.children(of: layer.id).count))
        } else if let moving = store.document.layers.first(where: { $0.id == source }),
          moving.parentID == layer.parentID
        {
          store.perform(.reorder(source, target))
        } else {
          let position =
            store.document.children(of: layer.parentID).firstIndex { $0.id == layer.id } ?? 0
          store.perform(.relocate(source, layer.parentID, position + 1))
        }
        return true
      }
    }.padding(.vertical, 2).background(
      store.selectedLayerIDs.contains(layer.id)
        || (store.selectedLayerIDs.isEmpty && layer.id == store.document.activeLayerID)
        ? StudioTheme.selected : .clear
    )
    .contextMenu { LayerEditingMenu(store: store, contextLayer: layer.id) }
    .accessibilityElement(children: .contain).accessibilityLabel("Layer \(layer.name)")
  }
  func layerPreview(_ layer: Layer, component: LayerThumbnailComponent, metrics: LayerRowMetrics)
    -> some View
  {
    LayerThumbnail(
      layer: layer, document: store.layerPanelDocument, revision: store.canvasPresentationRevision,
      storeID: store.identity, generation: store.layerPanelGeneration, size: metrics.size,
      contents: store.workspaceLibrary.layerPanelOptions.thumbnailContents,
      thumbnailWidth: metrics.thumbnailWidth, component: component
    ).frame(width: metrics.thumbnailWidth, height: metrics.thumbnailHeight)
  }
  func moveLayer(_ layer: Layer, by delta: Int) {
    let siblings = store.document.children(of: layer.parentID)
    guard let index = siblings.firstIndex(where: { $0.id == layer.id }),
      siblings.indices.contains(index + delta)
    else { return }
    store.perform(.relocate(layer.id, layer.parentID, index + delta))
  }
  var layerFooter: some View {
    HStack(spacing: 9) {
      Spacer(minLength: 0)
      iconButton("link",store.linkMenuUnlinks(store.linkTargets()) ? "Unlink layers (Shift-click toggles participation)":"Link layers",enabled:store.canToggleLayerLinks(),selected:store.linkMenuUnlinks(store.linkTargets())){store.toggleLayerLinks(temporary:NSEvent.modifierFlags.contains(.shift))}
        .toolCursor{flags in ToolCursor.layerLink(modifiers:flags,linked:store.linkedSelection(store.linkTargets()),disabled:store.document.layers.filter{store.groupSelectionIDs.contains($0.id)}.allSatisfy{$0.linkDisabled == true},available:store.canToggleLayerLinks(),unlink:store.linkMenuUnlinks(store.linkTargets()))}
      iconButton("fx", "Layer Style", enabled: store.canBeginLayerStyle) { store.beginLayerStyle() }
      iconButton(
        "rectangle.inset.filled", "Add layer mask (Option-click to hide)",
        enabled: store.canCreateMask(.revealAll)
      ) { store.addMask(hiding: NSEvent.modifierFlags.contains(.option)) }
      Menu {
        Button("Solid Color…") { store.addSolidColorLayer() }
        Button("Gradient…") { store.beginGradientFill() }
        Button("Pattern…") { store.beginPatternFill() }
        Divider()
        Button("Brightness / Contrast") {
          store.adjustment(.brightnessContrast(0, 1), name: "Brightness / Contrast")
        }
        Button("Exposure") { store.adjustment(.classic(.init(.exposure)), name: "Exposure") }
        Button("Saturation") { store.adjustment(.saturation(1), name: "Saturation") }
        Button("Black & White") { store.adjustment(.grayscale, name: "Black & White") }
        Button("Invert") { store.adjustment(.invert, name: "Invert") }
      } label: {
        Image(systemName: "circle.lefthalf.filled")
      }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 18).help(
        "New adjustment layer")
      iconButton(
        "folder",
        "Create a new group (Option-click for options; Shift-click groups layers; Command-click below)",
        enabled: store.canCreateGroup() || store.canCreateGroup(below: true)
          || store.canCreateGroup(fromSelection: true)
      ) {
        store.createGroupFromFooter(modifiers: NSEvent.modifierFlags)
      }
      iconButton(
        "plus.square", "Create a new layer (Option-click for options; Command-click below)",
        enabled: store.canCreatePixelLayer() || store.canCreatePixelLayer(below: true)
      ) {
        store.createPixelLayerFromFooter(modifiers: NSEvent.modifierFlags)
      }
      iconButton(
        "trash", store.layerFooterDeletionHelp,
        enabled: store.canDeleteFromLayerFooter
      ) { store.deleteLayersFromFooter(modifiers: NSEvent.modifierFlags) }
    }.padding(.horizontal, 9).frame(height: 28).background(StudioTheme.panel).overlay(
      alignment: .top
    ) { Rectangle().fill(StudioTheme.line).frame(height: 1) }
  }
  func layerIcon(_ layer: Layer) -> String {
    if layer.smartObject?.linkedSource != nil {return "link"}
    if layer.smartObject != nil { return "doc.on.doc" }
    return switch layer.content {
    case .raster: "photo"
    case .text: "textformat"
    case .shape: "square.on.circle"
    case .fill: "drop.fill"
    case .patternFill: "square.grid.3x3.fill"
    case .gradientFill: "rectangle.lefthalf.inset.filled"
    case .adjustment: "circle.lefthalf.filled"
    case .group: "folder"
    }
  }
}

struct Checkerboard: View {
  var body: some View {
    Canvas { context, size in
      context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.92)))
      for row in 0..<Int(ceil(size.height / 5)) {
        for column in 0..<Int(ceil(size.width / 5)) where (row + column) % 2 == 0 {
          context.fill(
            Path(CGRect(x: column * 5, y: row * 5, width: 5, height: 5)),
            with: .color(Color(white: 0.72)))
        }
      }
    }.clipped()
  }
}
struct LayerThumbnail: View {
  let layer: Layer
  let document: CraftDocument
  let revision: Int
  let storeID: UUID
  let generation: UUID
  let size: LayerThumbnailSize
  let contents: ThumbnailFraming
  let thumbnailWidth: CGFloat
  var component: LayerThumbnailComponent = .content
  @Environment(\.displayScale) private var displayScale
  @State private var image: CGImage?
  private struct Key: Equatable {
    let store: UUID
    let generation: UUID
    let layer: UUID
    let revision: Int
    let size: LayerThumbnailSize
    let contents: ThumbnailFraming
    let pixels: Int
    let component: LayerThumbnailComponent
  }
  private var key: Key {
    Key(
      store: storeID, generation: generation, layer: layer.id, revision: revision,
      size: size, contents: contents,
      pixels: min(512, max(1, Int(ceil(thumbnailWidth * displayScale)))), component: component)
  }
  var body: some View {
    ZStack {
      if component == .content && layer.isGroup {
        Image(systemName: "folder.fill").font(.system(size: min(21, thumbnailWidth)))
          .foregroundStyle(Color(white: 0.72))
      } else if size == .none {
        Image(
          systemName: component == .pixelMask
            ? "rectangle.lefthalf.filled" : component == .vectorMask ? "rectangle.dashed" : "square"
        )
        .font(.system(size: 12)).foregroundStyle(.secondary)
      } else {
        Checkerboard()
        if let image { Image(decorative: image, scale: 1).resizable().scaledToFit() }
      }
      if component == .content, case .adjustment = layer.content {
        Image(systemName: "circle.lefthalf.filled").foregroundStyle(.white).shadow(radius: 1)
      }
    }.task(id: key) {
      image = nil
      guard size != .none, component != .content || !layer.isGroup else { return }
      let layer = layer
      let doc = document
      let framing = contents
      let pixels = key.pixels
      let component = component
      let task = Task.detached(priority: .utility) { () -> CGImage? in
        guard
          let small = try? Renderer.layerThumbnail(
            layer, in: doc, framing: framing, maximumSize: pixels, component: component)
        else { return nil }
        return try? component == .content
          ? ColorManagement.displayImage(small, in: doc) : RasterIO.displayImage(small)
      }
      let result = await withTaskCancellationHandler(
        operation: { await task.value }, onCancel: { task.cancel() })
      if !Task.isCancelled { image = result }
    }
  }
}

/// Disabled masks retain their editing preview under a full-size cross.
struct DisabledMaskMark: View {
  var body: some View {
    Canvas { context, size in
      let inset: CGFloat = 1
      var cross = Path()
      cross.move(to: CGPoint(x: inset, y: inset))
      cross.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset))
      cross.move(to: CGPoint(x: size.width - inset, y: inset))
      cross.addLine(to: CGPoint(x: inset, y: size.height - inset))
      context.stroke(cross, with: .color(.red), lineWidth: 1.5)
    }.allowsHitTesting(false).accessibilityHidden(true)
  }
}
