import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

// Neutral, compact chrome measured from the user's open Photoshop 2026 workspace.
enum StudioTheme {
  static let chrome = Color(white: 0.32)
  static let panel = Color(white: 0.29)
  static let tab = Color(white: 0.245)
  static let field = Color(white: 0.25)
  static let selected = Color(white: 0.40)
  static let line = Color.black.opacity(0.25)
  static let accent = Color(red: 0.30, green: 0.60, blue: 0.94)
}

struct WorkspaceView: View {
  @Bindable var store: EditorStore
  var workspace: DocumentWorkspace? = nil
  var floatingPanelGroup: String? = nil
  var activateCanvas: () -> Bool = { true }
  var dockWidth: CGFloat {
    get { CGFloat(store.workspaceLibrary.layout.dockWidth) }
    nonmutating set { store.workspaceLibrary.resizeDock(to: Double(newValue)) }
  }
  @State var columnStartingWidths: [String: Double] = [:]
  @State var openDockGroup: String?
  var propertiesHeight: CGFloat {
    get { CGFloat(store.workspaceLibrary.layout.propertiesHeight) }
    nonmutating set { store.workspaceLibrary.resizeProperties(to: Double(newValue)) }
  }
  @State var dividerStartingHeights: [String: Double]?
  var doubleTools: Bool {
    get { store.workspaceLibrary.layout.doubleTools }
    nonmutating set { store.workspaceLibrary.layout.doubleTools = newValue }
  }
  @State var layerEyeTracking = LayerEyeTracking()
  @State var layerReveal = LayerRevealTracker()
  @State var layerSearch = ""
  @State var layerKind = "All"
  @State var brushPopover = false
  @State var gradientPresetPopover = false
  @State var hue: Double = 0.64
  @ViewBuilder
  var body: some View {
    if let floatingPanelGroup {
      floatingPanelContent(floatingPanelGroup)
        .font(.system(size: 11)).foregroundStyle(Color(white: 0.88))
        .background(StudioTheme.panel).tint(StudioTheme.accent).preferredColorScheme(.dark)
    } else {
      completeWorkspace
    }
  }
  var completeWorkspace: some View {
    VStack(spacing: 0) {
      if store.workspace.options { optionsBar }
      workspaceColumns
      if store.timelineVisible { Divider(); if store.document.videoTimeline != nil { VideoTimelinePanel(store: store) } else { TimelinePanel(store: store) } }
    }
    .font(.system(size: 11)).foregroundStyle(Color(white: 0.88))
    .disabled(store.printBusy)
    .overlay(alignment: .bottom) {
      if store.printBusy {
        HStack { ProgressView().controlSize(.small); Text(store.printJobStatus == "preparing" ? "Preparing print…" : "Printing…")
          if store.printJobStatus == "preparing" { Button("Cancel") { store.printCancellation?() } }
        }.padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding(12)
      }
    }
    .background(StudioTheme.chrome).tint(StudioTheme.accent).preferredColorScheme(.dark)
    .alert(
      "Photato",
      isPresented: Binding(
        get: { store.error != nil || store.workspaceLibrary.error != nil },
        set: {
          if !$0 {
            store.error = nil
            store.workspaceLibrary.error = nil
          }
        })
    ) {
      Button("OK") { store.error = nil }
    } message: {
      Text(store.error ?? store.workspaceLibrary.error ?? "")
    }
    .sheet(isPresented: $store.showAI) { aiSheet }
    .sheet(item: $store.layerProtectionDraft) { draft in
      LayerProtectionSheet(store: store, draft: draft)
    }
    .sheet(item: $store.layerPanelOptionsDraft) { draft in
      LayerPanelOptionsSheet(store: store, draft: draft)
    }
    .sheet(item: $store.channelDialog) { draft in ChannelDialogSheet(store:store,draft:draft) }
    .sheet(item: $store.channelPanelOptionsDraft) { draft in
      ChannelPanelOptionsSheet(store: store, draft: draft)
    }
    .sheet(item:$store.backgroundLayerDraft){draft in BackgroundLayerSheet(store:store,draft:draft)}
    .sheet(item: $store.newLayerDraft) { draft in NewLayerSheet(store: store, draft: draft) }
    .sheet(item:$store.trimDraft){draft in TrimSheet(store:store,draft:draft)}
    .sheet(item: $store.documentDuplicateDraft) { draft in DocumentDuplicateSheet(store:store,draft:draft) }
    .sheet(item: $store.duplicateLayerDraft) { draft in
      DuplicateLayerSheet(store: store, draft: draft)
    }
    .sheet(item: $store.skyWorkspace) { SkySheet(store:store,model:$0) }
    .sheet(item: $store.vanishingWorkspace) { VanishingSheet(store:store,model:$0) }
    .sheet(item:$store.shapedTypeDraft,onDismiss:{store.cancelShapedType()}){ShapedTypeSheet(store:store,model:$0)}
    .sheet(item: $store.shapeDraft,onDismiss:{store.shapePreview=nil;store.render()}) { ShapeSheet(store:store,draft:$0) }
    .sheet(item: $store.frameDraft) { FrameSheet(store: store, draft: $0) }
    .sheet(item: $store.layerFileDraft) { LayerFileSheet(store: store, draft: $0) }
    .sheet(item: $store.imageExportDraft) { ImageExportSheet(store: store, draft: $0) }
    .sheet(item: $store.colorLookupExportDraft) { ColorLookupExportSheet(store: store, draft: $0) }
    .sheet(item:$store.selectionModifyDraft){SelectionModifySheet(store:store,draft:$0)}
    .sheet(item: $store.colorRangeDraft) { ColorRangeSheet(store: store, model: $0) }
    .sheet(item:$store.textFindWorkspace,onDismiss:{store.closeTextFind()}) {workspace in TextFindSheet(store:store,workspace:workspace)}
    .sheet(item: $store.fileInfoDraft) { FileInfoSheet(store: store, draft: $0) }
    .sheet(item:$store.guideDraft) { GuideSheet(store:store,draft:$0) }
    .sheet(item: $store.artboardDraft) { ArtboardSheet(store: store, draft: $0) }
    .sheet(item: $store.newGroupDraft) { draft in NewGroupSheet(store: store, draft: draft) }
    .sheet(item: $store.gradientStopColorDraft, onDismiss: { store.render() }) { _ in
      GradientStopColorSheet(store: store)
    }
    .overlay(alignment: .topTrailing) {
      if store.gradientFillDraft != nil {
        GradientFillEditor(store: store).padding(.top, 50).padding(.trailing, 18)
      } else if store.patternFillDraft != nil {
        PatternFillEditor(store: store).padding(.top, 50).padding(.trailing, 18)
      }
    }
    .sheet(item: $store.patternNameDraft) { draft in PatternNameSheet(store: store, draft: draft) }
    .sheet(
      item: Binding(
        get: { store.gradientMapDraft == nil ? store.gradientNameDraft : nil },
        set: { store.gradientNameDraft = $0 })
    ) { draft in GradientNameSheet(store: store, draft: draft)
    }
    .sheet(isPresented: $store.showGaps) { gapSheet }
    .sheet(isPresented: $store.showFeatherSelection) { FeatherSelectionSheet(store: store) }
    .sheet(item: $store.geometrySheet) { kind in
      if kind == .fitImage {
        if let draft = store.fitImageDraft { FitImageSheet(store: store, draft: draft) }
      } else { GeometrySheet(store: store, kind: kind) }
    }
    .sheet(item: $store.levelsDraft, onDismiss: { store.render() }) { _ in LevelsSheet(store: store)
    }
    .sheet(item: $store.curvesDraft, onDismiss: { store.render() }) { _ in CurvesSheet(store: store)
    }
    .sheet(item: $store.gradientMapDraft, onDismiss: { store.render() }) { _ in
      GradientMapSheet(store: store)
    }
    .sheet(item: $store.layerStyleDraft, onDismiss: { store.render() }) { _ in LayerStyleSheet(store: store) }
    .sheet(item: $store.warpDraft, onDismiss: { store.cancelWarp() }) { draft in WarpSheet(store:store,model:draft) }
    .sheet(item: $store.photoAlignDraft, onDismiss: { store.cancelPhotoAlign() }) { draft in PhotoAlignSheet(store:store,model:draft) }
    .sheet(item: $store.photoBlendDraft, onDismiss: { store.cancelPhotoBlend() }) { draft in PhotoBlendSheet(store:store,model:draft) }
    .sheet(item: $store.inkChannelOptions, onDismiss: { store.render() }) { draft in InkChannelOptionsSheet(store: store, draft: draft) }
    .sheet(item: $store.printWorkspace, onDismiss: { store.finishPrintSheet() }) { draft in PrintSheet(model: draft) }
    .sheet(item: $store.colorProfileWorkspace) { draft in ColorProfileSheet(store: store, model: draft) }
    .sheet(item: $store.proofWorkspace) { draft in ProofSheet(store: store, model: draft) }
    .sheet(item: $store.inkModeWorkspace, onDismiss: { store.render() }) { draft in InkModeSheet(store: store, model: draft) }
    .sheet(item: $store.restrictedModeWorkspace, onDismiss: { store.render() }) { draft in RestrictedModeSheet(store: store, model: draft) }
    .sheet(item: $store.documentModeWorkspace, onDismiss: { store.render() }) { draft in DocumentModeSheet(store: store, model: draft) }
    .sheet(item:$store.channelArithmeticWorkspace,onDismiss:{store.render()}) {draft in ChannelArithmeticSheet(store:store,model:draft)}
    .sheet(item:$store.classicToneWorkspace,onDismiss:{store.render()}) {draft in ClassicToneSheet(store:store,model:draft)}
    .sheet(item: $store.proceduralWorkspace, onDismiss: {store.render()}) {draft in ProceduralSheet(store:store,model:draft)}
    .sheet(item: $store.contentAwareDraft, onDismiss: { store.render() }) { draft in ContentAwareSheet(store:store,model:draft) }
    .sheet(item: $store.selectMaskDraft, onDismiss: { store.render() }) { draft in SelectMaskSheet(store: store, model: draft) }
    .sheet(item: $store.filterDraft, onDismiss: { store.render() }) { _ in FilterSheet(store: store) }
    .sheet(item: $store.tonalStepsDraft, onDismiss: { store.render() }) { _ in
      TonalStepsSheet(store: store)
    }
    .sheet(item: $store.colorLookupDraft, onDismiss: { store.render() }) { _ in ColorLookupSheet(store: store) }
    .sheet(item: $store.classicAdjustmentDraft, onDismiss: { store.render() }) { _ in
      ClassicAdjustmentSheet(store: store)
    }
    .sheet(item: $store.colorBalanceDraft, onDismiss: { store.render() }) { _ in
      ColorBalanceSheet(store: store)
    }
    .sheet(item: $store.hueSaturationDraft, onDismiss: { store.render() }) { _ in
      HueSaturationSheet(store: store)
    }
  }
  var documentTabs: some View {
    let _ = workspace?.revision
    return HStack(spacing: 0) {
      ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 0) {
            if let workspace {
              ForEach(workspace.documents, id: \.store.identity) { doc in
                documentTab(store: doc.store, document: doc).id(doc.store.identity)
              }
            } else {
              documentTab(store: store, document: nil)
            }
          }
        }
        .onChange(of: store.identity) { _, id in proxy.scrollTo(id) }
      }
      // During a live stroke, the canvas itself is the feedback. Do not observe
      // the per-frame busy toggle and rebuild the workspace twice per preview.
      if store.brushGesture == nil && store.cloneDraft == nil && store.rendering {
        ProgressView().controlSize(.mini).padding(.trailing, 8)
      }
    }.frame(height: 29).background(StudioTheme.tab)
      .overlay(alignment: .bottom) { Rectangle().fill(StudioTheme.line).frame(height: 1) }
  }
  func documentTab(store tab: EditorStore, document: CraftNSDocument?) -> some View {
    // Each ForEach child must observe save-state changes, even when its model is unchanged.
    let _ = workspace?.revision
    let name = document?.displayName ?? tab.document.name
    return HStack(spacing: 7) {
      if let document {
        Button {
          workspace?.owner?.requestClose(document)
        } label: {
          Image(systemName: "xmark").font(.system(size: 8))
        }.buttonStyle(.plain).help("Close document")
          .accessibilityLabel("Close document \(name)")
      }
      let title =
        "\(name) @ \(CanvasViewport.percentage(tab.effectiveZoom)) (\(tab.activeLayer?.name ?? "No layer"), \(tab.document.colorMode.rawValue.uppercased())/\(depthNumber(tab.document.depth)))\(document?.isDocumentEdited == true ? " *" : "")"
      if let document, let workspace {
        DocumentTabControl(
          title: title, document: document, workspace: workspace,
          selected: workspace.activeDocument === document && tab === store
        )
        .fixedSize(horizontal: true, vertical: false)
      } else {
        Text(title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
      }
    }.padding(.horizontal, 10).frame(height: 28).background(
      tab === store ? StudioTheme.chrome : StudioTheme.tab
    )
    .overlay(alignment: .trailing) { Rectangle().fill(StudioTheme.line).frame(width: 1) }
  }
  func depthNumber(_ depth: PixelDepth) -> String {
    switch depth {
    case .u8: "8"
    case .u16: "16"
    case .f32: "32"
    }
  }
  var statusBar: some View {
    HStack(spacing: 0) {
      ZoomPercentageField(store: store, activateDocument: activateCanvas).frame(width: 62)
      Divider()
      if store.proofSettings.active || store.proofWorkspace != nil {
        Text(store.proofDisplayError == nil ? "Proof: " + store.effectiveProof.displayName : "Proof unavailable")
          .help(store.proofDisplayError ?? store.effectiveProof.displayName)
      }
      Text(
        "\(store.document.width) px × \(store.document.height) px  ·  \(ColorManagement.name(store.document))"
      ).padding(.horizontal, 14)
      CanvasScroller(store: store, vertical: false, activateDocument: activateCanvas).frame(
        maxWidth: .infinity
      ).frame(height: 14)
      if store.unavailableToolID != nil {
        Image(systemName: "circle.dashed").foregroundStyle(.orange).padding(.horizontal, 6).help(
          store.status)
      }
    }.font(.system(size: 10)).frame(height: 20).background(StudioTheme.chrome)
  }
  var contextualActions: some View {
    HStack(spacing: 10) {
      if store.tool == .crop && store.unavailableToolID == nil {
        Button("Apply Crop") { store.cropToSelection() }
      } else {
        Button("Fill") { store.fill() }
        Button("Add Layer Mask") { store.addMask() }.disabled(store.activeLayer?.mask != nil)
        Button("Generative Fill") { store.showGaps = true }.disabled(true).help(
          "Generative Fill is not available yet")
      }
      Divider().frame(height: 18)
      Button("Deselect") { store.perform(.selection(nil)) }
    }.buttonStyle(.borderless).padding(10).background(
      StudioTheme.chrome, in: RoundedRectangle(cornerRadius: 6)
    )
    .overlay(RoundedRectangle(cornerRadius: 6).stroke(StudioTheme.line)).shadow(radius: 8)
  }
  func iconButton(
    _ symbol: String, _ help: String, enabled: Bool = true, selected: Bool? = nil, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) { Image(systemName: symbol).frame(width: 20, height: 22) }
      .buttonStyle(.plain).background(selected == true ? Color.primary.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 3))
      .disabled(!enabled).help(help).accessibilityLabel(help).accessibilityValue(selected.map { $0 ? "On" : "Off" } ?? "")
  }
  func unavailable(_ title: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: "circle.dashed").font(.system(size: 11, weight: .medium))
      Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(
        horizontal: false, vertical: true)
      Button("View feature map") { store.showGaps = true }.buttonStyle(.link).font(
        .system(size: 10))
    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
  }
  var gapSheet: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Workspace Feature Map").font(.title2.weight(.semibold))
        Spacer()
        Button("Done") { store.showGaps = false }.keyboardShortcut(.cancelAction)
      }
      Text(
        "The workspace follows Photoshop’s layout. The editing engine is still being ported. Unavailable controls are dimmed; selecting an unported tool never changes your image."
      )
      .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          Label("Available now", systemImage: "checkmark.circle").foregroundStyle(.green)
          Text(
            "Move, rectangular selections, Crop to Selection, round Brush, Eraser, Eyedropper, basic Type and shapes, Hand/Zoom, RGB channel previews, layers, opacity/blends, masks, basic adjustments and history."
          ).font(.callout)
          ForEach(WorkspaceGap.all) { gap in
            Divider()
            Text(gap.title).font(.headline)
            Text(gap.detail).foregroundStyle(.secondary).font(.callout)
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
    }.padding(24).frame(width: 620, height: 640).background(StudioTheme.panel)
  }
}
