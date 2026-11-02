import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

struct FilterDraft: Identifiable, Sendable {
  let id: UUID
  var filter: RasterFilter
  var preview = true
  var channelTarget: ChannelPlaneTarget?
  var modeComponents: Set<Int> = []
  var inkTargets: [InkChannelTarget] = []
  var filterID: UUID?
  var rawDevelopment: RawDevelopment?
  var opacity: Float = 1
  var blendMode: PhotoCraftCore.BlendMode = .normal
  /// Geometry seen by a new filter, or the prefix before an edited Smart Filter.
  func inputLayer(in document:CraftDocument) throws -> Layer {
    guard var layer=document.layers.first(where:{$0.id==id}) else { throw CraftError.invalid("Missing filter target.") }
    if layer.smartObject != nil {
      if let filterID,var stack=layer.smartFilters,let index=stack.filters.firstIndex(where:{$0.id==filterID}) { stack.filters=Array(stack.filters.prefix(index));layer.smartFilters=stack }
      layer=try SmartFilterEngine.renderedLayer(layer,in:document)
    }
    return layer
  }
  func command(in document: CraftDocument) throws -> Command {
    if var rawDevelopment {
      rawDevelopment.adjustments = filter.cameraRaw ?? .init()
      return try RawSourceIO.command(in:document,layerID:id,settings:rawDevelopment)
    }
    if let channelTarget { return .channel(.filter(channelTarget,filter)) }
    if !inkTargets.isEmpty { return .inkChannel(.edit(inkTargets, .filter(filter))) }
    if !modeComponents.isEmpty { return .modeComponents(.init(layerID: id, components: modeComponents, operation: .filter(filter))) }
    guard let filterID else { return .applyFilter(id, filter) }
    guard var stack = document.layers.first(where: { $0.id == id })?.smartFilters,
      let i = stack.filters.firstIndex(where: { $0.id == filterID }) else {
      throw CraftError.invalid("The Smart Filter is no longer available.")
    }
    stack.filters[i].filter = filter; stack.filters[i].opacity = opacity; stack.filters[i].blendMode = blendMode
    return .smartFilters(id, stack)
  }
}

struct FilterSheet: View {
  @Bindable var store: EditorStore
  private var filter: RasterFilter { store.filterDraft?.filter ?? RasterFilter(.gaussianBlur) }
  private func number(_ key: WritableKeyPath<RasterFilter, Double>) -> Binding<Double> {
    Binding(get: { filter[keyPath: key] }, set: {
      store.filterDraft?.filter[keyPath: key] = $0
      store.render()
    })
  }
  private func field(_ title: String, _ key: WritableKeyPath<RasterFilter, Double>, _ range: ClosedRange<Double>, step: Double = 0.1) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(title)
        Spacer()
        TextField(title, value: number(key), format: .number.precision(.fractionLength(0...2)))
          .textFieldStyle(.roundedBorder).frame(width: 82).monospacedDigit()
      }
      Slider(value: number(key), in: range, step: step).accessibilityLabel(title)
    }
  }
  var body: some View {
    if filter.kind == .lightingEffects {LightingSheet(store:store)} else if filter.kind == .relight {RelightSheet(store:store)} else if filter.kind == .shadowsHighlights {ShadowHighlightsSheet(store:store)} else if filter.kind.isClassicDetail {ClassicDetailSheet(store:store)} else if filter.kind.isOtherVideo {OtherVideoSheet(store:store)} else if filter.kind.isRender {RenderSheet(store:store)} else if filter.kind.isStylize {StylizeSheet(store:store)} else if filter.kind.isPixelate { PixelateSheet(store:store) } else if filter.kind.isDistortion { DistortionSheet(store:store) } else if filter.kind == .lensBlur { LensBlurSheet(store:store) } else if filter.kind == .smartSharpen || filter.kind == .reduceNoise { PhotoDetailSheet(store:store) } else if filter.kind == .filterGallery { ArtisticGallerySheet(store:store) } else if filter.kind == .adaptiveWideAngle { WideAngleSheet(store:store) } else if filter.kind == .lensCorrection { LensCorrectionSheet(store:store) } else if filter.kind == .blurGallery { BlurGallerySheet(store:store) } else if filter.kind == .perspectiveWarp { PerspectiveSheet(store:store) } else if filter.kind == .puppetWarp { PuppetSheet(store:store) } else if filter.kind == .liquify { LiquifySheet(store: store) } else if filter.kind == .cameraRaw { CameraRawSheet(store:store) } else { ordinaryBody }
  }
  private var ordinaryBody: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(filter.kind.title).font(.title2.bold())
      switch filter.kind {
      case .lightingEffects, .relight, .shadowsHighlights, .blur, .blurMore, .radialBlur, .shapeBlur, .smartBlur, .surfaceBlur, .despeckle, .dustAndScratches, .median, .sharpen, .sharpenEdges, .sharpenMore, .customFilter, .hsbHsl, .maximum, .minimum, .offset, .deInterlace, .ntscColors, .clouds, .differenceClouds, .fibers, .lensFlare, .diffuse, .emboss, .extrude, .findEdges, .oilPaint, .solarize, .tiles, .traceContour, .wind, .colorHalftone, .crystallize, .facet, .fragment, .mezzotint, .pointillize, .displace, .shear, .wave, .pinch, .spherize, .twirl, .ripple, .polarCoordinates, .zigzag, .liquify, .cameraRaw, .puppetWarp, .perspectiveWarp, .blurGallery, .lensCorrection, .adaptiveWideAngle, .filterGallery, .smartSharpen, .reduceNoise, .lensBlur: EmptyView()
      case .gaussianBlur, .highPass: field("Radius (pixels)", \.radius, 0.1...1000)
      case .boxBlur: field("Radius (pixels)", \.radius, 1...1000, step: 1)
      case .motionBlur:
        field("Angle (degrees)", \.angle, -180...180, step: 1)
        field("Distance (pixels)", \.distance, 1...2000, step: 1)
      case .unsharpMask:
        field("Amount (%)", \.amount, 1...500, step: 1)
        field("Radius (pixels)", \.radius, 0.1...1000)
        field("Threshold (levels)", \.threshold, 0...255, step: 1)
      case .mosaic: field("Cell Size (pixels)", \.cellSize, 2...200, step: 1)
      case .average: Text("Replace the layer colors with their average within the selected area.")
      case .addNoise:
        field("Amount (%)", \.amount, 0.1...400)
        Picker("Distribution", selection: Binding(get: { filter.distribution }, set: {
          store.filterDraft?.filter.distribution = $0; store.render()
        })) {
          Text("Uniform").tag(RasterFilter.Distribution.uniform)
          Text("Gaussian").tag(RasterFilter.Distribution.gaussian)
        }.pickerStyle(.radioGroup)
        Toggle("Monochromatic", isOn: Binding(get: { filter.monochromatic }, set: {
          store.filterDraft?.filter.monochromatic = $0; store.render()
        }))
        Button("New Noise Pattern") {
          store.filterDraft?.filter.seed = UInt32.random(in: .min ... .max); store.render()
        }
      }
      if store.filterDraft?.filterID != nil {
        Picker("Mode", selection: Binding(get: { store.filterDraft?.blendMode ?? .normal }, set: {
          store.filterDraft?.blendMode = $0; store.render()
        })) { ForEach(BlendMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
        HStack {
          Text("Opacity")
          Slider(value: Binding(get: { store.filterDraft?.opacity ?? 1 }, set: {
            store.filterDraft?.opacity = $0; store.render()
          }), in: 0...1)
          Text("\(Int((store.filterDraft?.opacity ?? 1) * 100))%")
        }
      }
      if let error = validationError { Text(error).foregroundStyle(.red).font(.caption) }
      Divider()
      HStack {
        Toggle("Preview", isOn: Binding(get: { store.filterDraft?.preview ?? false }, set: {
          store.filterDraft?.preview = $0; store.render()
        }))
        if store.rendering { ProgressView().controlSize(.small) }
        Spacer()
        Button("Cancel") { store.cancelFilter() }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitFilter() }.keyboardShortcut(.defaultAction)
          .disabled(validationError != nil)
      }
    }.padding(20).frame(width: 420)
  }
  private var validationError: String? {
    do { try filter.validate(); return nil } catch { return error.localizedDescription }
  }
}

extension EditorStore {
  var canBeginFilter: Bool {
    if document.inkMode != nil, editingChannel == nil { return canEditInkChannels }
    if !modeComponentTargets.isEmpty { return canEditModeComponents }
    if editingChannel != nil { return canEditChannels && document.width <= RasterFilterEngine.maximumPixels/document.height }
    guard !editingComponent, !geometryBusy, transformDraft == nil, !hasToneDraft, !editingMask,
      let layer = activeLayer, !document.isImageLocked(layer.id),
      selectedLayerIDs.isEmpty || selectedLayerIDs == [layer.id], case .raster(let pixels) = layer.content else { return false }
    return pixels.width <= RasterFilterEngine.maximumPixels / pixels.height
  }
  func canBeginFilterKind(_ kind: RasterFilter.Kind) -> Bool {
    if kind == .lightingEffects || kind == .relight{return document.colorMode == .rgb && document.inkMode==nil && document.restrictedMode==nil && editingChannel==nil && modeComponentTargets.isEmpty && canBeginFilter}
    if document.inkMode != nil, editingChannel == nil { return canEditInkChannels && InkChannelCommand.filters.contains(kind) }
    if !modeComponentTargets.isEmpty { return canEditModeComponents && ModeComponentEdit.filters.contains(kind) }
    if RasterFilterEngine.pagedFilterKinds.contains(kind),document.colorMode == .rgb,
      editingChannel==nil,!editingComponent,!geometryBusy,transformDraft==nil,!hasToneDraft,!editingMask,
      let layer=activeLayer,!document.isImageLocked(layer.id),
      selectedLayerIDs.isEmpty || selectedLayerIDs==[layer.id],case .raster=layer.content {
      return layer.smartObject==nil || (try? SmartFilterEngine.renderBounds(layer,in:document)) != nil
    }
    if kind == .shadowsHighlights {return canBeginFilter && editingChannel == nil}
    if kind.isClassicDetail {return canBeginFilter && editingChannel == nil && ClassicDetailSettings.depths(kind).contains(document.depth) && document.width<=RasterFilterEngine.maximumPixels/document.height}
    if kind.isOtherVideo {return canBeginFilter && editingChannel == nil && document.width<=RasterFilterEngine.maximumPixels/document.height}
    if kind.isRender {return canBeginFilter && editingChannel == nil && document.width<=RasterFilterEngine.maximumPixels/document.height}
    if kind.isStylize {return canBeginFilter && editingChannel == nil}
    if kind.isPixelate { return canBeginFilter && editingChannel == nil }
    if kind.isDistortion { return canBeginFilter && editingChannel == nil }
    if kind == .lensBlur { return canBeginFilter && editingChannel == nil && document.depth != .f32 }
    if kind == .smartSharpen || kind == .reduceNoise { return canBeginFilter && editingChannel == nil }
    if kind == .filterGallery { return canBeginFilter && editingChannel == nil }
    if kind == .adaptiveWideAngle { return canBeginFilter && editingChannel == nil }
    if kind == .lensCorrection { return canBeginFilter && editingChannel == nil }
    if kind == .blurGallery { return canBeginFilter && editingChannel == nil }
    if kind == .perspectiveWarp { return canBeginFilter && editingChannel == nil && activeLayer.map { (try? PerspectiveEngine.validateTarget(document,layerID:$0.id)) != nil } == true }
    if kind == .puppetWarp { return canBeginFilter && editingChannel == nil && activeLayer.map { (try? PuppetEngine.validateTarget(document,layerID:$0.id)) != nil } == true }
    return canBeginFilter && (editingChannel == nil || (kind != .cameraRaw && kind != .liquify))
  }
  func beginFilter(_ kind: RasterFilter.Kind) {
    guard canBeginFilterKind(kind) else { return }
    if document.inkMode != nil, editingChannel == nil {
      var filter = RasterFilter(kind)
      if kind == .addNoise { filter.seed = UInt32.random(in: .min ... .max) }
      filterDraft = FilterDraft(id: document.id, filter: filter, inkTargets: effectiveInkTargets)
      render(); return
    }
    guard let layer = activeLayer else { return }
    if editingChannel != nil && (kind == .liquify || kind == .cameraRaw) { error = "Select RGB for this filter workspace."; return }
    var filter = RasterFilter(kind)
    if kind.isRender && kind != .lensFlare {filter.renderSettings?.foreground=brush.color;filter.renderSettings?.background=backgroundColor;filter.renderSettings?.seed=UInt32.random(in:.min ... .max)}
    if kind.isImmediateClassicDetail {let request=filter;performGeometry(label:kind.title){_ in .applyFilter(layer.id,request)};return}
    if kind == .ntscColors {let request=filter;performGeometry(label:kind.title){_ in .applyFilter(layer.id,request)};return}
    if kind.isImmediateRender {let request=filter;performGeometry(label:kind.title){_ in .applyFilter(layer.id,request)};return}
    if kind == .tiles {filter.stylize?.foreground=brush.color;filter.stylize?.background=backgroundColor}
    if kind.isImmediateStylize {let request=filter;performGeometry(label:kind.title){_ in .applyFilter(layer.id,request)};return}
    if kind == .pointillize { filter.pixelate?.background=backgroundColor }
    if kind.isImmediatePixelate {
      let request=filter;performGeometry(label:kind.title) { _ in .applyFilter(layer.id,request) };return
    }
    if kind == .filterGallery { filter.artistic?.effects[0].foreground = brush.color;filter.artistic?.effects[0].background = backgroundColor }
    if kind == .addNoise { filter.seed = UInt32.random(in: .min ... .max) }
    filterDraft = FilterDraft(id: layer.id, filter: filter, channelTarget:editingChannel, modeComponents:modeComponentTargets)
    if kind == .lightingEffects || kind == .relight{filterDraft?.preview=false}
    render()
  }
  func cancelFilter() {lightingWorkspace?.close();lightingWorkspace=nil;relightWorkspace?.close();relightWorkspace=nil;shadowWorkspace?.close();shadowWorkspace=nil;classicDetailWorkspace?.close();classicDetailWorkspace=nil;otherVideoWorkspace?.close();otherVideoWorkspace=nil;renderWorkspace?.close();renderWorkspace=nil;stylizeWorkspace?.close();stylizeWorkspace=nil; pixelateWorkspace?.close();pixelateWorkspace=nil; distortionWorkspace?.close();distortionWorkspace=nil; lensBlurWorkspace?.close();lensBlurWorkspace=nil; photoDetailWorkspace?.close();photoDetailWorkspace=nil; artisticGalleryWorkspace?.close();artisticGalleryWorkspace=nil; wideAngleWorkspace?.close();wideAngleWorkspace=nil; lensCorrectionWorkspace?.close();lensCorrectionWorkspace=nil; blurGalleryWorkspace?.close();blurGalleryWorkspace=nil; perspectiveWorkspace?.close();perspectiveWorkspace=nil;puppetWorkspace?.close();puppetWorkspace=nil;filterDraft = nil; render() }
  func commitFilter() {
    guard let draft = filterDraft else { return }
    do { try draft.filter.validate(); try draft.rawDevelopment?.validate() } catch { self.error = error.localizedDescription; return }
    lightingWorkspace?.close();lightingWorkspace=nil;relightWorkspace?.close();relightWorkspace=nil
    shadowWorkspace?.close();shadowWorkspace=nil
    classicDetailWorkspace?.close();classicDetailWorkspace=nil
    otherVideoWorkspace?.close();otherVideoWorkspace=nil
    renderWorkspace?.close();renderWorkspace=nil
    stylizeWorkspace?.close();stylizeWorkspace=nil
    pixelateWorkspace?.close();pixelateWorkspace=nil
    distortionWorkspace?.close();distortionWorkspace=nil
    lensBlurWorkspace?.close();lensBlurWorkspace=nil
    photoDetailWorkspace?.close();photoDetailWorkspace=nil
    artisticGalleryWorkspace?.close();artisticGalleryWorkspace=nil
    wideAngleWorkspace?.close();wideAngleWorkspace=nil
    lensCorrectionWorkspace?.close();lensCorrectionWorkspace=nil
    blurGalleryWorkspace?.close();blurGalleryWorkspace=nil
    perspectiveWorkspace?.close();perspectiveWorkspace=nil;puppetWorkspace?.close();puppetWorkspace=nil
    filterDraft = nil
    performGeometry(label: draft.rawDevelopment == nil ? draft.filter.kind.title : "Develop RAW Source", allowAuxiliary:draft.channelTarget != nil, allowModeComponents:!draft.modeComponents.isEmpty) { try draft.command(in: $0) }
  }
}

@MainActor extension AppDelegate {
  @objc func rasterFilterDialog(_ sender: NSMenuItem) {
    guard let path = sender.identifier?.rawValue,
      let kind = Self.filterMenus[path] else { return }
    store?.beginFilter(kind)
    if let mode = BlurGallerySettings.Mode.allCases.first(where: { path == "Filter > Blur Gallery > " + $0.title + "…" }) { store?.filterDraft?.filter.gallery?.enabled = [mode];store?.render() }
  }
  static let filterMenus: [String: RasterFilter.Kind] = [
    "Filter > Photato > Relight…":.relight,
    "Filter > Photato > Lighting Effects…":.lightingEffects,
    "Filter > Blur > Blur": .blur,
    "Filter > Blur > Blur More": .blurMore,
    "Filter > Blur > Radial Blur…": .radialBlur,
    "Filter > Blur > Shape Blur…": .shapeBlur,
    "Filter > Blur > Smart Blur…": .smartBlur,
    "Filter > Blur > Surface Blur…": .surfaceBlur,
    "Filter > Noise > Despeckle": .despeckle,
    "Filter > Noise > Dust & Scratches…": .dustAndScratches,
    "Filter > Noise > Median…": .median,
    "Filter > Sharpen > Sharpen": .sharpen,
    "Filter > Sharpen > Sharpen Edges": .sharpenEdges,
    "Filter > Sharpen > Sharpen More": .sharpenMore,

    "Filter > Other > Custom…": .customFilter,
    "Filter > Other > HSB/HSL": .hsbHsl,
    "Filter > Other > Maximum…": .maximum,
    "Filter > Other > Minimum…": .minimum,
    "Filter > Other > Offset…": .offset,
    "Filter > Video > De-Interlace…": .deInterlace,
    "Filter > Video > NTSC Colors": .ntscColors,

    "Filter > Render > Clouds": .clouds,
    "Filter > Render > Difference Clouds": .differenceClouds,
    "Filter > Render > Fibers…": .fibers,
    "Filter > Render > Lens Flare…": .lensFlare,

    "Filter > Stylize > Diffuse…": .diffuse,
    "Filter > Stylize > Emboss…": .emboss,
    "Filter > Stylize > Extrude…": .extrude,
    "Filter > Stylize > Find Edges": .findEdges,
    "Filter > Stylize > Oil Paint…": .oilPaint,
    "Filter > Stylize > Solarize": .solarize,
    "Filter > Stylize > Tiles…": .tiles,
    "Filter > Stylize > Trace Contour…": .traceContour,
    "Filter > Stylize > Wind…": .wind,

    "Filter > Pixelate > Color Halftone…": .colorHalftone,
    "Filter > Pixelate > Crystallize…": .crystallize,
    "Filter > Pixelate > Facet": .facet,
    "Filter > Pixelate > Fragment": .fragment,
    "Filter > Pixelate > Mezzotint…": .mezzotint,
    "Filter > Pixelate > Pointillize…": .pointillize,

    "Filter > Distort > Displace…": .displace,
    "Filter > Distort > Shear…": .shear,
    "Filter > Distort > Wave…": .wave,
    "Filter > Distort > Pinch…": .pinch,
    "Filter > Distort > Spherize…": .spherize,
    "Filter > Distort > Twirl…": .twirl,
    "Filter > Distort > Ripple…": .ripple,
    "Filter > Distort > Polar Coordinates…": .polarCoordinates,
    "Filter > Distort > ZigZag…": .zigzag,
    "Filter > Blur > Lens Blur…": .lensBlur,
    "Filter > Sharpen > Smart Sharpen…": .smartSharpen,
    "Filter > Noise > Reduce Noise…": .reduceNoise,
    "Filter > Filter Gallery…": .filterGallery,
    "Filter > Adaptive Wide Angle…": .adaptiveWideAngle,
    "Filter > Lens Correction…": .lensCorrection,
    "Filter > Blur Gallery > Field Blur…": .blurGallery,
    "Filter > Blur Gallery > Iris Blur…": .blurGallery,
    "Filter > Blur Gallery > Tilt-Shift…": .blurGallery,
    "Filter > Blur Gallery > Path Blur…": .blurGallery,
    "Filter > Blur Gallery > Spin Blur…": .blurGallery,
    "Edit > Puppet Warp": .puppetWarp,
    "Edit > Perspective Warp": .perspectiveWarp,
    "Filter > Liquify…": .liquify,
    "Filter > Camera Raw Filter…": .cameraRaw,
    "Filter > Blur > Gaussian Blur…": .gaussianBlur,
    "Filter > Blur > Box Blur…": .boxBlur,
    "Filter > Blur > Motion Blur…": .motionBlur,
    "Filter > Blur > Average": .average,
    "Filter > Sharpen > Unsharp Mask…": .unsharpMask,
    "Filter > Other > High Pass…": .highPass,
    "Filter > Noise > Add Noise…": .addNoise,
    "Filter > Pixelate > Mosaic…": .mosaic,
  ]
}
