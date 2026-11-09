import AppKit
import PhotoCraftAI
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
  let controller: CraftDocumentController
  override convenience init() { self.init(workspaces: WorkspaceLibrary(), paintPalette: PaintPalette(defaults: .standard), eyedropperPreferences:EyedropperPreferences(defaults:.standard), liquifyMeshes: .shared, lensDefaults: .shared, scriptEvents: .shared) }
  init(workspaces: WorkspaceLibrary, recoveryPreferences: RecoveryPreferencesStore? = nil,
    recoveryIndex: RecoveryIndexStore? = nil, colorSettings: ColorSettingsStore? = nil, paintPalette: PaintPalette? = nil, eyedropperPreferences:EyedropperPreferences? = nil,
    liquifyMeshes: LiquifyMeshLibrary? = nil, lensDefaults: LensDefaultLibrary? = nil, scriptEvents: ScriptEventsStore? = nil) {
    controller = CraftDocumentController(
      workspaces: workspaces, recoveryPreferences: recoveryPreferences, recoveryIndex: recoveryIndex, colorSettings: colorSettings, paintPalette: paintPalette, eyedropperPreferences:eyedropperPreferences, scriptEvents: scriptEvents)
    super.init()
    controller.filterRecall.liquifyMeshes = liquifyMeshes ?? LiquifyMeshLibrary()
    controller.filterRecall.lensDefaults = lensDefaults ?? LensDefaultLibrary()
  }
  let projectLinks = ProjectLinks.bundled()
  private var projectInfoWindow: NSWindowController?
  private var automationWindow: NSWindowController?
  var generatedResultsWindow:GeneratedResultsWindowController?
  var imageProcessorWindow: ImageProcessorWindow?
  var batchWindow: BatchWindow?
  var actionsWindow: NSWindowController?
  var scriptEventsWindow: ScriptEventsWindow?
  var layerCompsWindow: NSWindowController?
  var brushSettingsWindow: NSWindowController?
  var brushesWindow: NSWindowController?
  var shapesWindow: NSWindowController?
  var glyphsWindow: NSWindowController?
  var recoverySettingsWindow: RecoveryPreferencesWindowController?
  var saveFormatsWindow: SaveDialogFormatsWindowController?
  var colorSettingsWindow: ColorSettingsWindowController?
  private(set) lazy var automation = AutomationService(controller: controller)
  var documentWindowMenu: NSMenu?
  var workspaceMenu: NSMenu?
  var recentDocumentsMenu: NSMenu?
  var store: EditorStore? { (controller.currentDocument as? CraftNSDocument)?.store }
  func applicationDidFinishLaunching(_ notification: Notification) {
    buildMenus()
    if CommandLine.arguments.contains("--snapshot-layer-panel-options") {
      layerPanelOptionsSnapshot()
      return
    }
    if CommandLine.arguments.contains("--snapshot-delete-layer") {
      layerDeletionSnapshot()
      return
    }
    if CommandLine.arguments.contains("--snapshot-duplicate-layer") {
      duplicateLayerSnapshot()
      return
    }
    if CommandLine.arguments.contains("--snapshot-new-group") {
      newGroupSnapshot()
      return
    }
    if CommandLine.arguments.contains("--snapshot-new-layer") {
      newLayerSnapshot()
      return
    }
    if CommandLine.arguments.contains("--snapshot-adjustments") {
      adjustmentSnapshot()
      return
    }
    if CommandLine.arguments.contains("--snapshot")
      || CommandLine.arguments.contains("--snapshot-small")
      || CommandLine.arguments.contains("--snapshot-reference")
      || CommandLine.arguments.contains("--snapshot-selection")
      || CommandLine.arguments.contains("--snapshot-mask")
      || CommandLine.arguments.contains("--snapshot-clone")
      || CommandLine.arguments.contains("--snapshot-clone-mask")
      || CommandLine.arguments.contains("--snapshot-healing")
      || CommandLine.arguments.contains("--snapshot-spot-healing")
      || CommandLine.arguments.contains("--snapshot-toning")
      || CommandLine.arguments.contains("--snapshot-sponge")
      || CommandLine.arguments.contains("--snapshot-focus")
      || CommandLine.arguments.contains("--snapshot-sharpen")
      || CommandLine.arguments.contains("--snapshot-smudge")
      || CommandLine.arguments.contains("--snapshot-wand")
      || CommandLine.arguments.contains("--snapshot-bucket")
      || CommandLine.arguments.contains("--snapshot-patterns")
      || CommandLine.arguments.contains("--snapshot-pattern-fill")
      || CommandLine.arguments.contains("--snapshot-gradient-fill")
      || CommandLine.arguments.contains("--snapshot-gradient-tool")
      || CommandLine.arguments.contains("--snapshot-classic-gradient")
      || CommandLine.arguments.contains("--snapshot-gradients")
      || CommandLine.arguments.contains("--snapshot-gradient-map")
    {
      snapshot()
      return
    }
    controller.startIndexedRecovery()
    NSApp.activate(ignoringOtherApps: true)
  }
  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
  // Let AppKit finish recovery before deciding whether launch needs a new document.
  func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func applicationWillTerminate(_ notification: Notification) {
    controller.filterRecall.liquifyMeshes.flush()
    controller.cancelPhotomerge();controller.cancelHDRMerge()
    controller.recoveryDiscoveryGeneration = UUID()
    controller.initialRecoveryTask?.cancel()
    automation.stop()
    try? controller.workspaces.flush()
  }

  func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
    if controller.documentOpening.isActive || controller.documentOpening.hasPendingRequests || controller.documentOpenPanel != nil { return true }
    if controller.recoveryIndex.isDiscovering || controller.initialRecoveryTask != nil
      || (!controller.initialRecoveryFinished
        && controller.recoveryIndex.entries.contains { $0.state != .retired })
    {
      controller.pendingUntitledRequest = true
      return true
    }
    if let document = controller.currentDocument ?? controller.documents.first {
      document.showWindows()
    } else {
      controller.newDocument(nil)
    }
    return true
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    _ = applicationOpenUntitledFile(sender)
    return false
  }
  func buildMenus() { installPhotoshopMenus() }
  func validateMenuItem(_ item: NSMenuItem) -> Bool {
    if [#selector(fit),#selector(actual),#selector(zoomIn),#selector(zoomOut)].contains(item.action),let sky=store?.skyWorkspace{return sky.canNavigate}
    if item.action == #selector(showScriptEvents) { return canShowScriptEvents }
    if let result = validateStylesPanel(item) {return result}
    if let result = validateTypographyPanel(item) { return result }
    if item.action == #selector(repeatLastFilter(_:)) {
      item.title = controller.filterRecall.filter?.kind.title ?? "Last Filter"
      return store?.canRepeatFilter == true
    }
    if item.action == #selector(customizeSaveDialogFileFormats) { return true }
    if item.action == #selector(findLayers) { return store?.canChangeLayerFilter == true }
    if item.action == #selector(isolateLayers) {
      item.state = store?.layerFilterIsolated == true ? .on : .off
      return store.map { $0.canChangeLayerFilter && ($0.layerFilterIsolated || !$0.groupSelectionIDs.isEmpty) } ?? false
    }
    if item.action == #selector(arrangeLayerStack(_:)) { return LayerStackOperation.allCases.first(where: { $0.title == item.title }).map { store?.canArrangeLayerStack($0) == true } ?? false }
    if item.action == #selector(deleteEmptyLayers) { return store?.canDeleteEmptyLayers == true }
    if item.action == #selector(exportLayersToFiles) { return store?.canExportLayerFiles == true }
    if item.action == #selector(exportPathsToIllustrator) { return canPresentIllustratorPathExport }
    if [#selector(export), #selector(exportLayerAssets), #selector(quickExportAssets), #selector(quickExportLayerAssets), #selector(exportPreferences)].contains(item.action) {
      if [#selector(quickExportAssets), #selector(quickExportLayerAssets)].contains(item.action) {
        let format = ImageExportPreferences.load().format; item.title = "Quick Export as " + (format == .jpeg ? "JPG" : format.rawValue.uppercased())
      }
      return store?.canExportImages == true
    }
    if item.action == #selector(packageLinkedSmartObjects){return store?.canPackageLinkedArtwork==true}
    if item.action == #selector(embedAllLinkedSmartObjects){return store?.canEmbedAllLinkedArtwork==true}
    if item.action == #selector(placeLinked) {return store?.clipboardTargetAvailable==true}
    if item.action == #selector(relinkSmartObject) {return store?.canUpdateLinkedArtwork==true}
    if item.action == #selector(updateLinkedSmartObject) {return store?.canUpdateLinkedArtwork==true}
    if item.action == #selector(updateAllLinkedSmartObjects) {return store?.canUpdateAllLinkedArtwork==true}
    if item.action == #selector(embedLinkedSmartObject) {return store?.canEmbedLinkedArtwork==true}
    if item.action == #selector(convertLinkedSmartObject) {return store?.canConvertToLinked==true}
    if item.action == #selector(revealLinkedSmartObject) {return store?.selectedLinkedArtwork != nil}
    if item.action == #selector(applyImageDialog) {return store?.canBeginChannelArithmetic(.applyImage)==true}
    if item.action == #selector(calculationsDialog) {return store?.canBeginChannelArithmetic(.calculations)==true}
    let modern:[Selector:ModernAdjustment.Kind]=[#selector(newColorVibrance):.colorVibrance,#selector(newLight):.light,#selector(newClarityDehaze):.clarityDehaze,#selector(newGrain):.grain]
    if let action=item.action,let kind=modern[action] {return store?.canAddModernAdjustment(kind)==true}

    if let result = validateVariableMenu(item) { return result }
    if item.action == #selector(renderVideo) { return store?.canRenderVideo == true }
    if [#selector(printDocument), #selector(printOneCopy)].contains(item.action) { return (controller.currentDocument as? CraftNSDocument)?.canBeginPrint == true }
    if let result = validateFrameMenu(item) { return result }
    if item.action == #selector(fileInfoDialog) { return store?.canEditFileInfo == true && (controller.currentDocument as? CraftNSDocument)?.canRunFileCommand == true }
    if let result = validateGuidesMenu(item) { return result }
    if let result = validateArtboardMenu(item) { return result }
    if let result = validateRecentMenu(item) { return result }
    if let result = validateDocumentClosingMenu(item) { return result }
    if item.action == #selector(fileHandlingPreferences) || item.action == #selector(colorSettingsDialog) { return true }
    if [#selector(save), #selector(saveAs), #selector(saveCopy)].contains(item.action) {
      return (controller.currentDocument as? CraftNSDocument)?.canRunFileCommand == true
    }
    if item.action == #selector(revertFile) {
      return (controller.currentDocument as? CraftNSDocument)?.canRevertDocument == true
    }
    if item.action == #selector(generatedResults) {return true}
    if let result = validateHistoryMenu(item, in: NSApp.keyWindow) { return result }
    if item.action == #selector(toggleLayerVisibility) {
      item.title = store?.layerVisibilityMenuTitle() ?? "Hide Layers"
      return store?.canOrganizeLayers() == true
    }
    if item.action == #selector(lockLayers) { return store?.canChangeLayerProtection == true }
    if item.action == #selector(toggleQuickMask) { item.state = store?.document.quickMask != nil ? .on:.off; return store?.canEditChannels == true }
    if item.action == #selector(saveSelectionChannel) { return store?.canSaveSelectionChannel == true }
    if item.action == #selector(loadSelectionChannel) { return store?.canLoadSelectionChannel == true }
    if item.action == #selector(crop) {
      guard let store else { return false }
      if let draft = store.cropDraft { return store.cropReadyDraft == draft && store.cropPrepared != nil }
      return store.canBeginCrop && store.document.selection != nil
    }
    if item.action == #selector(contentAwareScale) { return store?.canBeginContentAwareScale == true }
    if [#selector(loadImageStack), #selector(imageStatistics)].contains(item.action) { return controller.canPublishImageStack }
    if item.action == #selector(imageStackMode(_:)) {
      item.state = (store?.activeLayer?.smartObject?.stackMode?.title ?? "None") == item.title ? .on:.off
      return store?.canEditSmartObject == true && store?.activeLayer?.smartObject?.rawDevelopment == nil && store?.activeLayer?.smartObject?.pdfSource == nil
    }
    if item.action == #selector(hdrMerge) { return controller.canPublishHDRMerge }
    if item.action == #selector(videoFramesToLayers) {return controller.movieFramesWorkspace != nil || controller.canFinishMovieFrames}
    if item.action == #selector(imageProcessor) {return true}
    if item.action == #selector(showBatch) { return true }
    if item.action == #selector(newBlankVideoLayer) { return store?.canCreateBlankVideoLayer == true }
    if item.action == #selector(newVideoLayer) { return store?.canImportMovieLayer == true }
    if item.action == #selector(showTimeline) { item.state = store?.timelineVisible == true ? .on : .off; return store != nil }
    if item.action == #selector(showLayerComps) { return true }
    if item.action == #selector(exportLayerCompFiles) || item.action == #selector(exportLayerCompPDF) { return store?.canEditLayerComps == true && !(store?.document.layerComps?.comps.isEmpty ?? true) }
    if item.action == #selector(showActions) || item.action == #selector(showBrushSettings) || item.action == #selector(showBrushes) { return true }
    if item.action == #selector(warpType){return store?.canEditType==true && store?.editableType != nil}
    if item.action == #selector(showGlyphs){return true}
    if item.action == #selector(horizontalType) || item.action == #selector(verticalType){item.state = store?.editableType?.typography?.writingOrientation == (item.action == #selector(verticalType) ? .vertical:.horizontal) ? .on:.off;return store?.canEditType==true && store?.editableType != nil}
    if item.action == #selector(toggleTypeFeature(_:)){guard let store,store.canEditType,store.editableType != nil,let tag=NativeFonts.features.first(where:{$0.name==item.title})?.tag else{return false};item.state=(store.currentTypeStyle.fontOptions?.features.first{$0.tag==tag}?.value ?? (tag=="liga" ? 1:0))==0 ? .off:.on;return (try? NativeFonts.availableFeatures(store.currentTypeStyle.font).contains(tag))==true}
    if item.action == #selector(showShapes) { return true }
    if item.action == #selector(defineCustomShape) { return store?.canDrawShapes == true && (store?.selectedVectorPath != nil || store?.activeLayer?.shape != nil) }
    if item.action == #selector(defineBrushPreset) { return store?.canUseBrush == true }
    if item.action == #selector(cropAndStraightenPhotos) { return (controller.currentDocument as? CraftNSDocument).map {controller.canCropScan($0)} ?? false }
    if item.action == #selector(contactSheet) { return controller.canPublishContactSheet }
    if item.action == #selector(photomerge) { return controller.canPublishPhotomerge }
    if item.action == #selector(vanishingPoint) { return store?.canBeginVanishingPoint == true }
    if item.action == #selector(warpLayer) { return store?.canBeginWarp == true }
    if item.action == #selector(autoAlignLayers) { return store?.canBeginPhotoAlign == true }
    if item.action == #selector(autoBlendLayers) { return store?.canBeginPhotoBlend == true }
    if item.action == #selector(contentAwareFill) { return store?.canBeginContentAwareFill == true }
    if item.action == #selector(colorRange){return store?.canBeginColorRange == true}
    if item.action == #selector(focusArea){return store?.canBeginFocusArea == true}
    if item.action == #selector(selectAndMask) { return store?.canBeginSelectMask == true }
    if item.action == #selector(selectSky) { return store?.canSelectSky == true }
    if item.action == #selector(skyReplacement) { return store?.canReplaceSky == true }
    if item.action == #selector(maskAllObjects) { return store?.canMaskAllObjects() == true }
    if item.action == #selector(selectSubject) { return store?.canDetectSubject() == true }
    if item.action == #selector(renameLayer) {
      item.title = store?.layerPanelTitle(.rename) ?? "Rename Layer…"
      return store?.canPerformLayerPanel(.rename) == true
    }
    if item.action == #selector(delete) { return store?.canPerformLayerPanel(.delete) == true }
    if [#selector(convertTypeShape), #selector(rasterizeType)].contains(item.action) {
      return store?.editableType != nil && store?.canEditType == true && store?.typeEditingDraft == nil
    }
    if item.action == #selector(rasterizeShape) {return store?.activeLayer?.shape != nil && store?.canPerformLayerPanel(.rasterize) == true}
    if item.action == #selector(rasterize) {
      return store?.canPerformLayerPanel(.rasterize) == true
    }
    if item.action == #selector(ungroupLayers) {
      return store?.canPerformLayerPanel(.ungroup) == true
    }
    if item.action == #selector(duplicate) {
      item.title = store?.duplicateMenuTitle ?? "Duplicate Layer…"
      return store?.canBeginDuplicate == true
    }
    if item.action == #selector(newLayer) { return store?.canCreatePixelLayer() == true }
    if item.action == #selector(newGroup) { return store?.canCreateGroup() == true }
    if [#selector(groupLayers), #selector(groupFromLayers)].contains(item.action) {
      return store?.canCreateGroup(fromSelection: true) == true
    }
    if let result = validateWorkspaceMenuItem(item) { return result }
    if let result = validateDocumentWindowMenuItem(item) { return result }
    if item.action == #selector(mergeLayers) {
      let operation = store?.menuMergeOperation ?? .selected
      item.title = store?.menuMergeTitle ?? operation.rawValue
      return store?.canMerge(operation) == true
    }
    if item.action == #selector(trimImage) {return store?.canUseCanvasEdges(.trim(.init())) == true}
    if item.action == #selector(exportColorLookupTables) { return store?.canExportColorLookup == true }
    if item.action == #selector(revealAll) {return store?.canUseCanvasEdges(.revealAll) == true}
    if item.action == #selector(duplicateDocument) { return store?.canDuplicateDocument == true }
    if item.action == #selector(flattenImage) { return store?.canFlattenImage == true }
    if item.action == #selector(mergeVisible) { return store?.canMerge(.visible) == true }
    if item.action == #selector(layerViaCopy) { return store?.canLayerVia(.copy) == true }
    if item.action == #selector(layerViaCut) { return store?.canLayerVia(.cut) == true }

    if item.action == #selector(placeEmbedded) { return store?.clipboardTargetAvailable == true }
    if item.action == #selector(convertSmartObject) { return store?.canConvertSmartObject == true }
    if item.action == #selector(convertSmartObjectToLayers) { return store?.canConvertSmartObjectToLayers() == true }
    if item.action == #selector(editSmartObjectContents) {return store?.canEditSmartObjectContents == true}
    if [#selector(replaceSmartObjectContents),
      #selector(exportSmartObjectContents), #selector(independentSmartObjectCopy),
      #selector(resetSmartObjectTransform)].contains(item.action) { return store?.canEditSmartObject == true }
    if item.action == #selector(fillDialog) { return store?.canUsePixelPaint == true || store?.canUseMenuFill == true }
    if item.action == #selector(strokeSelectionDialog) { return store?.canUsePixelStroke == true }
    if item.action == #selector(invertPixels) { return store?.canInvertPixels == true }
    if item.action == #selector(layerStyleMenu(_:)) {
      return store?.validateLayerStyleMenu(item.identifier?.rawValue ?? "") == true
    }
    if item.action == #selector(smartFilterCommand(_:)) {
      guard let store, store.canEditSmartFilters, let stack = store.activeLayer?.smartFilters else { return false }
      return !(item.identifier?.rawValue.contains("Filter Mask") == true) || stack.mask != nil
    }
    if item.action == #selector(proofCommand(_:)) { return validateProofMenu(item) }
    if item.action == #selector(inkModeDialog(_:)) { return validateInkModeMenu(item) }
    if item.action == #selector(restrictedModeDialog(_:)) { return validateRestrictedModeMenu(item) }
    if item.action == #selector(colorProfileDialog(_:)) { return store?.canBeginColorProfile == true }
    if item.action == #selector(documentModeDialog(_:)) { return validateDocumentModeMenu(item) }
    if item.action == #selector(classicToneDialog(_:)) {guard let kind=Self.classicToneMenus[item.identifier?.rawValue ?? ""] else{return false};return store?.canBeginClassicTone(kind) == true}
    if item.action == #selector(proceduralRenderDialog(_:)) {
      guard let kind=Self.proceduralMenus[item.identifier?.rawValue ?? ""] else{return false}
      return store?.canBeginProcedural(kind) == true
    }
    if item.action == #selector(rasterFilterDialog(_:)) {
      guard let kind = Self.filterMenus[item.identifier?.rawValue ?? ""] else { return false }
      return store?.canBeginFilterKind(kind) == true
    }
    if item.action == #selector(clear) {
      if let text = NSApp.keyWindow?.firstResponder as? NSTextView {
        return text.isEditable && text.selectedRange().length > 0
      }
      return store?.canUseMenuPixelEdit == true
    }
    if item.action == #selector(clippingMask) {
      item.title =
        store?.activeLayer?.isClipped == true ? "Release Clipping Mask" : "Create Clipping Mask"
    }

    if item.action == #selector(alignLayers(_:)), let value = item.representedObject as? String,
      let edge = LayerAlignment(rawValue: value)
    {
      if let menu = item.menu {
        menu.supermenu?.items.first(where: { $0.submenu === menu })?.title =
          store?.document.selection != nil && store?.layoutTarget == .selection
          ? "Align Layers to Selection" : "Align"
      }
      return store?.canLayout(.align(edge)) == true
    }
    if item.action == #selector(distributeLayers(_:)),
      let value = item.representedObject as? String,
      let kind = LayerDistribution(rawValue: value)
    {
      return store?.canLayout(.distribute(kind)) == true
    }
    if item.action == #selector(deselectLayers) { return store?.canDeselectLayers == true }
    if item.action == #selector(selectAllLayers) { return store?.canChangeLayerSelection == true }
    if item.action == #selector(gradientMap) { return store?.canBeginGradientMap == true }
    if item.action == #selector(newGradientMap) { return store?.canAddGradientMap == true }
    if item.action == #selector(newGradientFill) { return store?.canBeginGradientFill == true }
    if item.action == #selector(newPatternFill) {
      return store?.canBeginPatternFill == true
    }
    if item.action == #selector(layerContentOptions) {
      guard let store, let layer = store.activeLayer else {
        return false
      }
      return store.canEditPatternFill(layer.id) || store.canEditGradientFill(layer.id)
    }
    if [
      #selector(exposureAdjustment), #selector(vibrance), #selector(blackWhite), #selector(photoFilter), #selector(channelMixer), #selector(selectiveColor), #selector(colorLookup),
      #selector(levels), #selector(curves), #selector(hueSaturation), #selector(colorBalance),
      #selector(desaturate), #selector(threshold), #selector(posterize),
      #selector(autoTone), #selector(autoContrast),
      #selector(autoColor),
    ]
    .contains(item.action) {
      return store?.canBeginLevels == true
    }
    if [
      #selector(newExposureAdjustment), #selector(newBlackWhite), #selector(newPhotoFilter), #selector(newChannelMixer), #selector(newSelectiveColor), #selector(newColorLookup),
      #selector(newLevels), #selector(newCurves), #selector(newHueSaturation),
      #selector(newColorBalance), #selector(newThreshold), #selector(newPosterize),
    ].contains(
      item.action)
    {
      return store?.geometryBusy == false && store?.transformDraft == nil
        && store?.hasToneDraft == false
    }
    if item.action == #selector(copy(_:)) { return store?.canCopy() == true }
    if item.action == #selector(cut(_:)) { return store?.canCopy(cut: true) == true }
    if item.action == #selector(copyMerged) { return store?.canCopy(merged: true) == true }
    if item.action == #selector(newFromClipboard) { return SystemClipboard.shared.hasImage }
    if item.action == #selector(paste(_:)) {
      return store?.canPaste(.centered) ?? SystemClipboard.shared.hasImage
    }
    for (selector, placement) in [
      (#selector(pasteInPlace), PastePlacement.inPlace), (#selector(pasteInto), .into),
      (#selector(pasteOutside), .outside),
    ] where item.action == selector { return store?.canPaste(placement) == true }

    let maskCreation: [(Selector, LayerMaskCreation)] = [
      (#selector(maskRevealAll), .revealAll), (#selector(maskHideAll), .hideAll),
      (#selector(maskRevealSelection), .revealSelection),
      (#selector(maskHideSelection), .hideSelection),
      (#selector(maskFromTransparency), .fromTransparency),
    ]
    if let (_, kind) = maskCreation.first(where: { $0.0 == item.action }) {
      return store?.canCreateMask(kind) == true
    }
    if [#selector(maskDelete), #selector(maskApply), #selector(maskEnabled), #selector(maskLinked)]
      .contains(item.action)
    {
      guard let store, store.canEditActiveMask, let layer = store.activeLayer, layer.mask != nil
      else { return false }
      if item.action == #selector(maskApply) { return store.canApplyMask(layer) }
      if item.action == #selector(maskEnabled) {
        item.title =
          layer.effectiveMaskProperties.enabled ? "Disable" : "Enable"
      }
      if item.action == #selector(maskLinked) {
        item.title = layer.effectiveMaskProperties.linked ? "Unlink" : "Link"
      }
      return true
    }
    if [
      #selector(vectorRevealAll), #selector(vectorHideAll), #selector(vectorCurrentPath),
      #selector(vectorDelete), #selector(vectorEnabled), #selector(vectorLinked),
    ].contains(item.action) {
      guard let store, let layer = store.activeLayer, !store.document.isLocked(layer.id),
        !store.geometryBusy, store.transformDraft == nil
      else { return false }
      if item.action == #selector(vectorCurrentPath) { return store.selectedVectorPath != nil }
      if item.action == #selector(vectorRevealAll) || item.action == #selector(vectorHideAll) {
        return layer.vectorMask == nil
      }
      if item.action == #selector(vectorEnabled) {
        item.title = layer.vectorMask?.enabled == true ? "Disable" : "Enable"
      }
      if item.action == #selector(vectorLinked) {
        item.title = layer.vectorMask?.linked == true ? "Unlink" : "Link"
      }
      return layer.vectorMask != nil
    }
    if item.action == #selector(definePattern) {
      return store.map {
        !$0.geometryBusy && !$0.hasToneDraft && $0.transformDraft == nil && !$0.patterns.busy
      } ?? false
    }
    if item.action == #selector(linkSelectedLayers){item.title=store.map{$0.linkMenuUnlinks($0.linkTargets()) ? "Unlink Layers":"Link Layers"} ?? "Link Layers";return store?.canToggleLayerLinks() == true}
    if item.action == #selector(selectLinkedLayers){return store?.canSelectLinkedLayers() == true}
    if item.action == #selector(transformSelection){return store?.canBeginSelectionTransform == true}
    if [#selector(transformScaleMode),#selector(transformRotateMode)].contains(item.action){return store?.transformDraft?.selection == true ? store?.geometryBusy == false:store?.canTransformActiveLayer == true}
    if [#selector(transformDistortMode),#selector(transformPerspectiveMode)].contains(item.action),let store{if let draft=store.transformDraft,draft.collectionLayerIDs != nil{return !store.geometryBusy && draft.collectionProjective};if store.transformDraft==nil && !store.editingMask && !store.editingComponent && store.document.selection==nil && store.wantsLayerCollectionTransform{return store.canBeginProjectiveLayerTransform}}
    if item.action == #selector(transformSkewMode),store?.canBeginLayerCollectionTransform == true{return true}
    if [#selector(transformSkewMode),#selector(transformDistortMode),#selector(transformPerspectiveMode)].contains(item.action){return (store?.transformDraft?.selection == true && store?.geometryBusy == false) || store?.canBeginSelectedPixelTransform == true || store?.canBeginPixelMaskTransform == true || store?.canBeginChannelTransform == true}
    if item.action == #selector(backgroundLayerConversion){item.title=store?.activeLayer?.isBackground == true ? "Layer from Background…":"Background from Layer";return store?.canConvertBackground == true}
    if item.action == #selector(reselectPixels){return store?.canReselect == true}
    if [#selector(borderSelection),#selector(smoothSelection),#selector(expandSelection),#selector(contractSelection)].contains(item.action){return store?.canModifySelection == true}
    if [#selector(invertSelection), #selector(featherSelection)].contains(item.action) {
      return store?.document.selection != nil && store?.geometryBusy == false
        && store?.transformDraft == nil
    }
    if [
      #selector(freeTransform), #selector(rotateLayer180), #selector(rotateLayerCW),
      #selector(rotateLayerCCW), #selector(flipH), #selector(flipV),
    ].contains(item.action) {
      if store?.transformDraft?.selection == true,item.action != #selector(freeTransform){return store?.geometryBusy == false}
      return store?.canTransformActiveLayer == true
    }
    if item.action == #selector(findReplaceText) { return store?.canBeginTextFind == true }
    if item.action == #selector(generativeUpscale) {return store?.canBeginUpscale == true}
    if item.action == #selector(fitImage) { return store?.canBeginFitImage == true }
    if item.action == #selector(rulers) { item.state = store?.showRulers == true ? .on : .off }
    if [
      #selector(about), #selector(help), #selector(newFile), #selector(openFile), #selector(hide),
      #selector(quit), #selector(showAutomation),
      #selector(hideOthers),
      #selector(showAllApplications),
    ].contains(item.action) {
      return true
    }
    return store != nil
  }
  @objc func freeTransform() { store?.beginTransform() }
  @objc func imageSize() { if store?.transformDraft == nil { store?.geometrySheet = .imageSize } }
  @objc func canvasSize() { if store?.transformDraft == nil { store?.geometrySheet = .canvasSize } }
  @objc func rotateLayer180() { store?.transformLayer(angle: 180) }
  @objc func rotateLayerCW() { store?.transformLayer(angle: 90) }
  @objc func rotateLayerCCW() { store?.transformLayer(angle: -90) }
  @objc func rotateCanvas(_ sender: NSMenuItem) {
    guard CanvasTurn.allCases.indices.contains(sender.tag) else { return }
    store?.performGeometry(.rotateCanvas(CanvasTurn.allCases[sender.tag]))
    store?.fit()
  }
  @objc func newFile() {
    let alert = NSAlert()
    alert.messageText = "New Document"
    alert.informativeText = "Choose canvas dimensions, color mode and working precision."
    alert.addButton(withTitle: "Create")
    alert.addButton(withTitle: "Cancel")
    let options = NewDocumentOptions(settings: controller.colorSettings.value)
    alert.accessoryView = options
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    do {
      let model = try options.document(name: controller.nextUntitledName,
        background: store?.backgroundColor ?? .white)
      let doc = CraftNSDocument(model: model)
      doc.fileType = CraftNSDocument.nativeType
      controller.addDocument(doc)
      doc.makeWindowControllers()
      doc.showWindows()
    } catch { NSApp.presentError(error) }
  }
  @objc func openFile() { controller.openDocument(nil) }
  @objc func save() {
    guard let doc = controller.currentDocument as? CraftNSDocument, doc.canRunFileCommand else {
      return
    }
    if doc.smartObjectEditLink != nil {
      Task { do { try await doc.commitSmartObjectContents() } catch { NSApp.presentError(error) } }
    } else { doc.save(nil) }
  }
  @objc func saveAs() {
    guard let doc = controller.currentDocument as? CraftNSDocument, doc.canRunFileCommand else {
      return
    }
    doc.saveAs(nil)
  }
  @objc func saveCopy() { (controller.currentDocument as? CraftNSDocument)?.showSaveCopy() }
  @objc func revertFile() { (controller.currentDocument as? CraftNSDocument)?.showRevert() }
  @objc func closeWindow() { close(window: NSApp.keyWindow) }
  func close(window: NSWindow?) {
    if let window,
      !controller.documentWindows.groups.contains(where: { $0.window === window })
    {
      window.performClose(nil)
      return
    }
    if let document =
      (window.flatMap { controller.document(for: $0) }
      ?? controller.currentDocument) as? CraftNSDocument
    {
      controller.documentWindows.requestClose(document)
    } else {
      window?.performClose(nil)
    }
  }
  @objc func hide() { NSApp.hide(nil) }
  @objc func quit() { NSApp.terminate(nil) }
  @objc func undo() { performHistory(redo: false, in: NSApp.keyWindow) }
  @objc func redo() { performHistory(redo: true, in: NSApp.keyWindow) }
  @objc func place() { store?.placeImage() }
  @objc func export() { store?.exportImage() }
  @objc func exportPSD() { store?.exportPSD() }
  @objc func fill() { store?.fill() }
  @objc func clear() {
    if let text = NSApp.keyWindow?.firstResponder as? NSTextView {
      text.delete(nil)
    } else {
      store?.clear()
    }
  }
  @objc func crop() { store?.cropToSelection() }
  @objc func flipH() { store?.transformLayer(horizontal: true) }
  @objc func flipV() { store?.transformLayer(vertical: true) }
  @objc func newLayer() { store?.beginNewLayer() }
  @objc func newSolidColor() { store?.addSolidColorLayer() }
  @objc func levels() { store?.beginLevels() }
  @objc func curves() { store?.beginCurves() }
  @objc func gradientMap() { store?.beginGradientMap() }
  @objc func newGradientMap() { store?.addGradientMapLayer() }
  @objc func threshold() { store?.beginTonalSteps(.threshold) }
  @objc func posterize() { store?.beginTonalSteps(.posterize) }
  @objc func newThreshold() { store?.addTonalStepsLayer(.threshold) }
  @objc func newPosterize() { store?.addTonalStepsLayer(.posterize) }
  @objc func colorBalance() { store?.beginColorBalance() }
  @objc func newColorBalance() { store?.addColorBalanceLayer() }
  @objc func hueSaturation() { store?.beginHueSaturation() }
  @objc func desaturate() { store?.desaturate() }
  @objc func newHueSaturation() { store?.addHueSaturationLayer() }
  @objc func newCurves() { store?.addCurvesLayer() }
  @objc func autoTone() { store?.autoCorrect(.tone) }
  @objc func autoContrast() { store?.autoCorrect(.contrast) }
  @objc func autoColor() { store?.autoCorrect(.color) }
  @objc func newLevels() { store?.addLevelsLayer() }
  @objc func renameLayer() { store?.performLayerPanel(.rename) }
  @objc func lockLayers() {
    if let event = NSApp.currentEvent, event.type == .keyDown,
      event.charactersIgnoringModifiers == "/" { store?.toggleFullLayerProtection() }
    else { store?.beginLayerProtection() }
  }
  @objc func duplicate() { store?.beginDuplicate() }
  @objc func delete() { store?.requestLayerDeletion() }
  @objc func vectorRevealAll() { store?.addVectorMask(reveal: true) }
  @objc func vectorHideAll() { store?.addVectorMask(reveal: false) }
  @objc func vectorCurrentPath() { store?.makeVectorMask() }
  @objc func vectorDelete() {
    if let id = store?.activeLayer?.id { store?.perform(.vectorMask(id, nil)) }
  }
  @objc func vectorEnabled() {
    if let id = store?.activeLayer?.id { store?.updateVectorMask(id) { $0.enabled.toggle() } }
  }
  @objc func vectorLinked() {
    if let id = store?.activeLayer?.id { store?.updateVectorMask(id) { $0.linked.toggle() } }
  }
  @objc func newGroup() { store?.beginNewGroup() }
  @objc func groupFromLayers() { store?.beginNewGroup(fromSelection: true) }
  @objc func groupLayers() { store?.groupSelection() }
  @objc func selectAllLayers() { store?.selectAllLayers() }
  @objc func alignLayers(_ sender: NSMenuItem) {
    if let value = sender.representedObject as? String, let edge = LayerAlignment(rawValue: value) {
      store?.arrangeLayers(.align(edge))
    }
  }
  @objc func distributeLayers(_ sender: NSMenuItem) {
    if let value = sender.representedObject as? String,
      let kind = LayerDistribution(rawValue: value)
    {
      store?.arrangeLayers(.distribute(kind))
    }
  }
  @objc func ungroupLayers() { store?.ungroup() }
  @objc func clippingMask() { store?.toggleClipping() }
  @objc func rasterize() { store?.rasterize() }
  @objc func maskRevealAll() { store?.createMask(.revealAll) }
  @objc func maskHideAll() { store?.createMask(.hideAll) }
  @objc func maskRevealSelection() { store?.createMask(.revealSelection) }
  @objc func maskHideSelection() { store?.createMask(.hideSelection) }
  @objc func maskFromTransparency() { store?.createMask(.fromTransparency) }
  @objc func maskDelete() { store?.deleteMask() }
  @objc func maskApply() { store?.applyMask() }
  @objc func maskEnabled() {
    if let id = store?.activeLayer?.id { store?.updateMask(id) { $0.enabled.toggle() } }
  }
  @objc func maskLinked() {
    if let id = store?.activeLayer?.id { store?.updateMask(id) { $0.linked.toggle() } }
  }
  @objc func invert() { store?.adjustment(.invert, name: "Invert") }
  @objc func grayscale() { store?.adjustment(.grayscale, name: "Black & White") }
  @objc func exposure() { store?.adjustment(.exposure(1), name: "Exposure +1") }
  @objc func selectAll() {
    if let text = NSApp.keyWindow?.firstResponder as? NSTextView {
      text.selectAll(nil)
      return
    }
    if let s = store {
      s.perform(.selection(IntRect(x: 0, y: 0, width: s.document.width, height: s.document.height)))
    }
  }
  @objc func invertSelection() { store?.performGeometry(.invertSelection) }
  @objc func featherSelection() { store?.showFeatherSelection = true }
  @objc func deselect() { store?.perform(.selection(nil)) }
  @objc func blur() { store?.blur() }
  @objc func ai() { store?.showAI = true }
  @objc func featureMap() { store?.showGaps = true }
  @objc func rulers() { store?.showRulers.toggle() }
  @objc func colorPanel() { store?.reveal(ColorPanelTab.color) }
  @objc func swatchesPanel() { store?.reveal(ColorPanelTab.swatches) }
  @objc func gradientsPanel() { store?.reveal(ColorPanelTab.gradients) }
  @objc func patternsPanel() { store?.reveal(ColorPanelTab.patterns) }
  @objc func propertiesPanel() { store?.reveal(PropertiesTab.properties) }
  @objc func adjustmentsPanel() { store?.reveal(PropertiesTab.adjustments) }
  @objc func librariesPanel() { store?.reveal(PropertiesTab.libraries) }
  @objc func layersPanel() { store?.reveal(LayersTab.layers) }
  @objc func channelsPanel() { store?.reveal(LayersTab.channels) }
  @objc func pathsPanel() { store?.reveal(LayersTab.paths) }
  @objc func cloneSourcePanel() { store?.workspaceLibrary.selectPanel(.cloneSource, reveal: true) }
  @objc func historyPanel() { store?.workspaceLibrary.selectPanel(.history, reveal: true) }
  @objc func fit() { if let sky=store?.skyWorkspace{sky.fitViewport()}else{store?.fit()} }
  @objc func actual() { if let sky=store?.skyWorkspace{sky.setZoom(1)}else{store?.setZoom(1)} }
  @objc func zoomIn() { if let sky=store?.skyWorkspace{sky.stepZoom(inward:true)}else{store?.stepZoom(inward:true)} }
  @objc func zoomOut() { if let sky=store?.skyWorkspace{sky.stepZoom(inward:false)}else{store?.stepZoom(inward:false)} }
  @objc func definePattern() { store?.beginDefinePattern() }
  @objc func newGradientFill() { store?.beginGradientFill() }
  @objc func newPatternFill() { store?.beginPatternFill() }
  @objc func layerContentOptions() {
    if let layer = store?.activeLayer {
      if case .gradientFill = layer.content {
        store?.beginGradientFill(editing: layer.id)
      } else {
        store?.beginPatternFill(editing: layer.id)
      }
    }
  }
  @objc func about() {
    if projectInfoWindow == nil {
      let host = NSHostingController(
        rootView: ProjectInfoView(links: projectLinks))
      let window = PhotatoWindow(contentViewController: host)
      window.title = "About Photato"
      window.styleMask = [.titled, .closable]
      window.isReleasedWhenClosed = false
      window.center()
      projectInfoWindow = NSWindowController(window: window)
    }
    projectInfoWindow?.showWindow(nil)
    projectInfoWindow?.window?.makeKeyAndOrderFront(nil)
  }
  @objc func showAutomation() {
    if automationWindow == nil {
      let window = PhotatoWindow(
        contentViewController: NSHostingController(rootView: AutomationView(service: automation)))
      window.title = "Photato Automation API"
      window.styleMask = [.titled, .closable]
      window.isReleasedWhenClosed = false
      window.center()
      automationWindow = NSWindowController(window: window)
    }
    automationWindow?.showWindow(nil)
    automationWindow?.window?.makeKeyAndOrderFront(nil)
  }
  @objc func help() {
    let a = NSAlert()
    a.messageText = "Swift port in progress"
    a.informativeText =
      "Working: nested layer groups, clipping masks, 27 blend modes, mask painting, rectangular/elliptical/lasso selections, feathering, Free Transform, image/canvas size, brush, eraser, move, shapes, text, adjustments, blur, undo/redo, PNG/JPEG/TIFF, .photato documents.\n\nPSD supports RGB/8/16/32 pixel layers, nested groups, clipping and raster masks, raw/RLE/ZIP/prediction import, and ZIP export. Flattened RGB files also open. Mask density, feather, enable and link controls are available. Unsupported rich layers are rejected.\n\nAdditional native workflows include supported PhotoCraft project import, embedded Smart Objects and Smart Filters, text editing, layer styles, Liquify, Select and Mask, saved alpha channels, Quick Mask, Content-Aware Fill and Scale, and expanded/straightened cropping.\n\nStill incomplete: full PSD/PSB fidelity, RAW, professional color modes, remaining advanced workflows and plug-ins. Exact Photoshop results remain under qualification.\n\nV Move · M Marquee · L Lasso (⇧L cycles) · B Brush · E Eraser · U Shapes (⇧U cycles) · T Type · I Eyedropper · C Crop · H Hand · Z Zoom\n[ / ] brush size · Esc deselect · ⌘0 fit · ⌘G group · ⇧⌘G ungroup · ⌥⌘G clipping mask\n\nOptional prompt refinement runs on-device. Image Playground uses local models on macOS 26 and Apple's Private Cloud Compute on macOS 27 and later, subject to system availability. Generative fill is not implemented."
    a.runModal()
  }
  func snapshot() {
    do {
      let reference = CommandLine.arguments.contains("--snapshot-reference")
      let patternFillSnapshot = CommandLine.arguments.contains("--snapshot-pattern-fill")
      var doc =
        try reference
        ? CraftNSDocument.blankModel(width: 921, height: 921, background: .clear)
        : DemoDocument.make()
      let cloneMaskSnapshot = CommandLine.arguments.contains("--snapshot-clone-mask")
      let healingSnapshot = CommandLine.arguments.contains("--snapshot-healing")
      let focusSnapshot =
        CommandLine.arguments.contains("--snapshot-focus")
        || CommandLine.arguments.contains("--snapshot-sharpen")
        || CommandLine.arguments.contains("--snapshot-smudge")
      let toningSnapshot =
        CommandLine.arguments.contains("--snapshot-toning")
        || CommandLine.arguments.contains("--snapshot-sponge")
      let spotSnapshot = CommandLine.arguments.contains("--snapshot-spot-healing")
      let cloneSnapshot =
        CommandLine.arguments.contains("--snapshot-clone") || cloneMaskSnapshot || healingSnapshot
      if cloneMaskSnapshot, let index = doc.activeIndex {
        doc.layers[index].mask = try Surface(width: 64, height: 64, fill: Pixel(0.4, 0.4, 0.4))
        var properties = MaskProperties()
        properties.outside = 1
        properties.transform = .translation(100, 100)
        doc.layers[index].maskProperties = properties
      }
      let maskSnapshot = CommandLine.arguments.contains("--snapshot-mask")
      let selectionSnapshot = CommandLine.arguments.contains("--snapshot-selection") || maskSnapshot
      if selectionSnapshot {
        try Command.selectShape(
          .ellipse(IntRect(x: 140, y: 280, width: 850, height: 360)), .replace, true, 8
        ).apply(to: &doc)
      }
      if patternFillSnapshot || CommandLine.arguments.contains("--snapshot-gradient-fill") {
        doc.selection = .init(x: 190, y: 150, width: 680, height: 420)
      }
      var snapshotGradients: GradientLibrary?
      if CommandLine.arguments.contains("--snapshot-gradients") {
        var state = GradientPresetState.builtins()
        let basics = state.nodes[0].id
        let group = try state.group("Photato", into: nil)
        let coastal = try state.add(
          .init(
            name: "Coastal Light",
            colors: [
              .init(0, .rgb(Pixel(0.08, 0.16, 0.37))), .init(0.45, .rgb(Pixel(0.18, 0.62, 0.70))),
              .init(1, .rgb(Pixel(1, 0.68, 0.24))),
            ]), into: group)
        try state.add(
          .init(
            name: "Golden Hour",
            colors: [
              .init(0, .rgb(Pixel(0.25, 0.08, 0.33))), .init(1, .rgb(Pixel(1, 0.68, 0.24))),
            ]), into: group)
        try state.move([group], into: nil, before: basics)
        state.selected = [coastal]
        state.activePreset = coastal
        snapshotGradients = GradientLibrary(initialState: state)
      }
      let s = EditorStore(
        document: doc, cloneState: CloneSources(),
        patterns: CommandLine.arguments.contains("--snapshot-patterns") || patternFillSnapshot
          ? PatternLibrary() : nil, gradients: snapshotGradients)
      if patternFillSnapshot {
        guard let preset = s.patterns.items.first(where: { $0.name == "Bricks" }) else {
          throw CraftError.invalid("Missing snapshot pattern.")
        }
        var fill = PatternFill(patternID: preset.id)
        fill.placement.scale = 250
        fill.placement.angle = 25
        let layer = Layer(name: "Pattern Fill", content: .patternFill(fill))
        s.perform(.addPatternFill(layer, preset, true))
        s.patterns.selectedID = preset.id
        s.colorTab = .patterns
        s.beginPatternFill(editing: layer.id)
      }
      if CommandLine.arguments.contains("--snapshot-gradient-fill") {
        s.brush.color = Pixel(0.12, 0.32, 0.85)
        s.backgroundColor = Pixel(1, 0.63, 0.15)
        s.beginGradientFill()
        if let draft = s.gradientFillDraft {
          var fill = draft.fill
          fill.placement.angle = 35
          fill.placement.scale = 1.15
          let layer = Layer(name: "Gradient Fill", content: .gradientFill(fill))
          s.gradientFillDraft = nil
          s.perform(.addGradientFill(layer, true))
          s.beginGradientFill(editing: layer.id)
        }
      }
      if CommandLine.arguments.contains("--snapshot-patterns") {
        s.chooseTool(WorkspaceCatalog.tool("paintBucket"))
        s.bucketUsesPattern = true
        s.colorTab = .patterns
        s.patterns.selectedID = s.patterns.items.first { $0.name == "Bricks" }?.id
        s.status = "Pattern Paint Bucket · Define, import and reuse tiles"
      }
      if CommandLine.arguments.contains("--snapshot-gradient-tool")
        || CommandLine.arguments.contains("--snapshot-classic-gradient")
        || CommandLine.arguments.contains("--snapshot-gradients")
      {
        s.chooseTool(WorkspaceCatalog.tool("gradient"))
        let classic = CommandLine.arguments.contains("--snapshot-classic-gradient")
        s.gradientOptions.mode = classic ? .classic : .live
        s.gradientOptions.gradient = .init(
          name: "Coastal Light",
          colors: [
            .init(0, .rgb(Pixel(0.08, 0.16, 0.37))),
            .init(0.45, .rgb(Pixel(0.18, 0.62, 0.70))),
            .init(1, .rgb(Pixel(1, 0.68, 0.24))),
          ])
        if classic { s.addPixelLayer() }
        s.beginGradient(at: .init(190, 440), zoom: 1)
        s.dragGradient(to: .init(930, 220))
        if let command = s.gradientGesture?.command {
          s.gradientGesture = nil
          s.perform(command)
        }
        if !classic, let id = s.activeLayer?.id { s.gradientSelectedStop = (id, 1) }
        s.status =
          classic
          ? "Classic Gradient · Drag to paint · Shift constrains angle · Esc cancels"
          : "Gradient · Drag endpoints or stops · Click line to add a stop · Double-click to edit color"
      }
      if CommandLine.arguments.contains("--snapshot-gradient-map") {
        s.gradientOptions.gradient = .init(
          name: "Photato Duotone",
          colors: [
            .init(0, .rgb(Pixel(0.08, 0.12, 0.28))), .init(0.48, .rgb(Pixel(0.68, 0.23, 0.31))),
            .init(1, .rgb(Pixel(1, 0.91, 0.65))),
          ])
        if CommandLine.arguments.contains("--stripes") {
          s.gradientOptions.gradient.method = .stripes
        }
        s.addGradientMapLayer()
        s.status = "Gradient Map · Map image tones to gradient colors"
      }
      if CommandLine.arguments.contains("--snapshot-gradients") { s.colorTab = .gradients }
      if CommandLine.arguments.contains("--snapshot-wand")
        || CommandLine.arguments.contains("--snapshot-bucket")
      {
        s.chooseTool(
          WorkspaceCatalog.tool(
            CommandLine.arguments.contains("--snapshot-wand") ? "magicWand" : "paintBucket"))
        s.status =
          s.tool == .magicWand
          ? "Magic Wand · Click a color · ⇧ Add · ⌥ Subtract · ⇧⌥ Intersect"
          : "Paint Bucket · Click to fill a color region · ⌥ Sample color"
      }
      if cloneMaskSnapshot { s.maskEditingLayerID = s.activeLayer?.id }
      if focusSnapshot {
        s.chooseTool(
          WorkspaceCatalog.tool(
            CommandLine.arguments.contains("--snapshot-smudge")
              ? "smudge" : CommandLine.arguments.contains("--snapshot-sharpen") ? "sharpen" : "blur"
          ))
        s.retouchSettings.brush.size = 145
        s.retouchSettings.brush.hardness = 0.8
        s.status = "\(s.tool.rawValue) · Paint to adjust local detail"
      }
      if toningSnapshot {
        s.chooseTool(
          WorkspaceCatalog.tool(
            CommandLine.arguments.contains("--snapshot-sponge") ? "sponge" : "dodge"))
        s.retouchSettings.brush.size = 145
        s.retouchSettings.brush.hardness = 0.8
        s.status = "\(s.tool.rawValue) · Paint to adjust local tones"
      }
      if spotSnapshot {
        s.chooseTool(WorkspaceCatalog.tool("spotHealing"))
        s.retouchSettings.brush.size = 145
        s.retouchSettings.brush.hardness = 0.8
        s.status = "Spot Healing Brush · Paint over an imperfection"
      }
      if cloneSnapshot {
        s.chooseTool(WorkspaceCatalog.tool(healingSnapshot ? "healing" : "clone"))
        s.retouchSettings.brush.size = 145
        s.retouchSettings.brush.hardness = 0.75
        s.retouchSettings.brush.flow = 0.6
        s.setCloneSource(at: PathPoint(850, 358))
        s.cloneState.slots[0].width = 120
        s.cloneState.slots[0].height = 120
        s.cloneState.slots[0].rotation = -15
        let sample = try s.cloneRequest().sample()
        s.cloneOverlay = CloneOverlayImage(
          image: try RasterIO.displayImage(sample.surface), transform: sample.transform,
          outside: sample.outside)
        s.status = "\(s.tool.rawValue) · Option-click to set a source"
      }
      if selectionSnapshot {
        s.addMask()
        s.tool = .ellipticalMarquee
        s.selectionFeather = 8
        if maskSnapshot, let id = s.activeLayer?.id {
          s.updateMask(id) {
            $0.density = 0.75
            $0.feather = 4
            $0.linked = false
          }
        }
      }
      if reference { s.zoom = 1 }
      s.workspaceLibrary.layout.doubleTools = CommandLine.arguments.contains(
        "--snapshot-two-column-tools")
      if CommandLine.arguments.contains("--snapshot-panel-dock") {
        s.workspaceLibrary.movePanels(
          .panel(.gradients), to: .group("properties", before: .properties))
        s.workspaceLibrary.selectPanel(.gradients)
        s.workspaceLibrary.movePanels(.group("layers"), to: .beforeGroup("color"))
        s.workspaceLibrary.togglePanelGroup("color")
      }
      if CommandLine.arguments.contains("--snapshot-dock-columns") {
        let library = s.workspaceLibrary
        library.movePanels(.group("properties"), to: .newColumn(.left, before: nil))
        library.movePanels(
          .panel(.gradients), to: .newColumn(.right, before: PanelDockColumn.primaryID))
        for column in library.panelDock.orderedColumns where column.id != PanelDockColumn.primaryID
        {
          library.resizeColumn(column.id, width: 300)
        }
        if CommandLine.arguments.contains("--snapshot-dock-icons") {
          for column in library.panelDock.orderedColumns {
            library.setColumnCollapsed(column.id, true)
            if CommandLine.arguments.contains("--snapshot-dock-labels") {
              library.resizeColumn(column.id, width: 140, icons: true)
            }
          }
        }
      }
      if CommandLine.arguments.contains("--snapshot-history-panel"), let id = s.activeLayer?.id {
        s.perform(.renameLayer(id, "History study"))
        s.perform(.opacity(id, 0.75))
        s.perform(.visibility(id, false))
        s.selectHistoryState(1)
        s.workspaceLibrary.selectPanel(.history, reveal: true)
      }
      if CommandLine.arguments.contains("--snapshot-clone-panel") {
        s.workspaceLibrary.selectPanel(.cloneSource, reveal: true)
        if CommandLine.arguments.contains("--snapshot-clone-panel-narrow"),
          let group = s.workspaceLibrary.panelDock.groups.first(where: {
            $0.panels.contains(.cloneSource)
          })
        {
          s.workspaceLibrary.resizeColumn(group.dockColumnID, width: 275)
        }
      }
      if CommandLine.arguments.contains("--snapshot-layer-name"), let id = s.activeLayer?.id {
        s.beginLayerName(id)
      }
      if CommandLine.arguments.contains("--snapshot-layer-organization") {
        let selected = s.document.layers.map(\.id)
        for (index, id) in selected.enumerated() {
          s.perform(.layerColor([id], [.orange, .seafoam, .violet][index % 3]))
        }
        var hidden = Layer(name: "Hidden notes", content: .fill(.clear))
        hidden.visible = false
        hidden.colorLabel = .blue
        s.perform(.addLayer(hidden))
        if let id = selected.dropFirst().first { s.select(id) }
        s.selectedLayerIDs = Set(selected.suffix(2))
        if CommandLine.arguments.contains("--snapshot-layer-isolation"), let id = s.activeLayer?.id
        {
          s.toggleLayerVisibility(id, modifiers: .option)
        }
      }
      if CommandLine.arguments.contains("--snapshot-layer-visibility-drag"),
        let id = s.activeLayer?.id, let token = s.beginLayerVisibilityDrag(id)
      {
        s.extendLayerVisibilityDrag(token, over: Array(s.document.layers.prefix(2).map(\.id)))
      }
      if CommandLine.arguments.contains("--snapshot-group-disclosure") {
        let ids = s.document.layers.map(\.id)
        if ids.count >= 3 {
          s.perform(.groupLayers(Array(ids.dropFirst()), "Artwork"))
          let outer = s.document.activeLayerID
          s.perform(.groupLayers([ids[1]], "Scene"))
          if let outer { s.select(outer) }
          s.workspaceLibrary.resizeProperties(to: 160)
          if CommandLine.arguments.contains("--snapshot-groups-collapsed") {
            s.collapseAllLayerGroups()
          }
        }
      }
      if let index = CommandLine.arguments.firstIndex(of: "--snapshot-thumbnail-size"),
        CommandLine.arguments.indices.contains(index + 1),
        let size = LayerThumbnailSize(rawValue: CommandLine.arguments[index + 1])
      {
        try s.workspaceLibrary.setLayerPanelOptions(
          .init(
            thumbnailSize: size,
            thumbnailContents: CommandLine.arguments.contains("--snapshot-layer-bounds")
              ? .layerBounds : .entireDocument))
        s.workspaceLibrary.resizeProperties(to: 160)
        s.workspaceLibrary.resizeDock(to: 275)
      }
      if CommandLine.arguments.contains("--snapshot-thumbnail-masks") {
        var preview = Layer(
          name: "Mask preview study",
          content: .raster(
            try Surface(
              width: 128, height: 64, fill: Pixel(0.2, 0.6, 0.8))))
        preview.x = 80
        preview.y = 120
        preview.affine = .scale(4, 4)
        preview.visible = false
        var mask = try Surface(width: 128, height: 64, fill: .black)
        for y in 0..<64 { for x in 0..<128 where x < 2 * y { mask.setPixel(x: x, y: y, .white) } }
        preview.mask = mask
        preview.maskProperties = MaskProperties()
        preview.vectorMask = VectorMask(
          path: VectorPath(components: [
            PathComponent(
              knots: [
                PathKnot(PathPoint(80, 120)), PathKnot(PathPoint(592, 120)),
                PathKnot(PathPoint(592, 376)),
              ], closed: true)
          ]))
        if CommandLine.arguments.contains("--snapshot-thumbnail-masks-disabled") {
          preview.maskProperties?.enabled = false
          preview.vectorMask?.enabled = false
        }
        s.perform(.addLayer(preview))
        s.perform(.reorder(preview.id, s.document.layers.count - 1))
        s.select(preview.id)
      }
      let stackSnapshot = CommandLine.arguments.contains("--snapshot-floating-stack")
      let floatingSnapshot =
        CommandLine.arguments.contains("--snapshot-floating-panel") || stackSnapshot
      if floatingSnapshot {
        s.workspaceLibrary.floatPanels(
          .group("color"),
          frame: FloatingPanelFrame(
            NSRect(x: 100, y: 100, width: 360, height: 360)))
        s.workspaceLibrary.selectPanel(.gradients)
      }
      var floatingID = floatingSnapshot ? "color" : nil
      if stackSnapshot {
        s.workspaceLibrary.stackPanels(.group("layers"), hostID: "color", before: nil)
        floatingID = s.workspaceLibrary.panelDock.groups.first { $0.id == "color" }?.floatingHostID
        if CommandLine.arguments.contains("--snapshot-stack-collapsed") {
          s.workspaceLibrary.togglePanelGroup("color")
        }
      }
      // Freeze only after every diagnostic edit. History/organization setup can
      // otherwise restart asynchronous rendering after the supposedly frozen image.
      s.renderTask?.cancel()
      s.surface = try Renderer.composite(s.previewDocument)
      s.selectionPath = try s.document.selectionMask.map { try SelectionOutline.path($0).path }
      s.image = try ColorManagement.displayImage(
        s.surface ?? Surface(width: 1, height: 1), in: s.document)
      if CommandLine.arguments.contains("--snapshot-channels") {
        s.layersTab = .channels
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot-channel-size"),
          CommandLine.arguments.indices.contains(index + 1),
          let size = ChannelThumbnailSize(rawValue: CommandLine.arguments[index + 1])
        {
          try s.workspaceLibrary.setChannelPanelOptions(.init(thumbnailSize: size))
        }
        if CommandLine.arguments.contains("--snapshot-channel-red"), var preview = s.surface {
          s.displayChannel = 0
          s.renderTask?.cancel()
          preview.mapPixels { _, _, p in Pixel(p.r, p.r, p.r, p.a) }
          s.image =
            try s.channelView.visible.count == 1
            ? RasterIO.displayImage(preview) : ColorManagement.displayImage(preview, in: s.document)
        }
      }
      if let id = s.document.activeLayerID,
        let index = CommandLine.arguments.firstIndex(of: "--snapshot-mask-view"),
        CommandLine.arguments.indices.contains(index + 1),
        let mode = MaskViewMode(rawValue: CommandLine.arguments[index + 1]),
        let layer = s.activeLayer, layer.mask != nil
      {
        s.maskEditingLayerID = id
        s.layerMaskView = LayerMaskView(layerID: id, generation: s.layerPanelGeneration, mode: mode)
        s.renderedMaskView = s.layerMaskView
        s.maskViewImage = try RasterIO.displayImage(
          Renderer.maskPresentation(
            layer, mode: mode, width: s.document.width, height: s.document.height))
      }
      s.rendering = false
      let host = NSHostingView(
        rootView: WorkspaceView(store: s, floatingPanelGroup: floatingID)
          .overlay(alignment: .topTrailing) {
            if cloneSnapshot {
              CloneSourcePanel(state: s.cloneState, target: s)
                .background(StudioTheme.chrome, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(StudioTheme.line))
                .padding(.top, 75).padding(.trailing, 18)
            }
          })
      host.frame =
        reference
        ? NSRect(x: 0, y: 0, width: 1700, height: 1174)
        : CommandLine.arguments.contains("--snapshot-small")
          ? NSRect(x: 0, y: 0, width: 1000, height: 650)
          : NSRect(x: 0, y: 0, width: 1380, height: 900)
      if floatingSnapshot { host.frame = NSRect(x: 0, y: 0, width: 360, height: 338) }
      if stackSnapshot, let floatingID,
        let frame = s.workspaceLibrary.panelDock.floatingGroups(floatingID).first?.floatingFrame
      {
        let sizing = FloatingPanelStackSizing(
          dock: s.workspaceLibrary.panelDock, hostID: floatingID,
          visibility: s.workspace, expandedHeight: frame.height - FloatingPanelWindow.titlebarHeight
        )
        host.frame = NSRect(x: 0, y: 0, width: 360, height: sizing.naturalHeight)
      }
      let w = PhotatoWindow(
        contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
      let captureView: NSView =
        CommandLine.arguments.contains("--snapshot-native-container")
        ? PanelTearOffContainer(
          content: host, coordinator: controller.documentWindows.panelDragging)
        : host
      w.contentView = captureView
      w.appearance = NSAppearance(named: .darkAqua)
      w.layoutIfNeeded()
      captureView.layoutSubtreeIfNeeded()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [w, host] in
        do {
          w.layoutIfNeeded()
          host.layoutSubtreeIfNeeded()
          if cloneSnapshot || spotSnapshot || toningSnapshot || focusSnapshot {
            @MainActor func locate(_ view: NSView, depth: Int = 0) -> CraftCanvas? {
              if let canvas = view as? CraftCanvas { return canvas }
              guard depth < 32 else { return nil }
              for child in view.subviews {
                if let canvas = locate(child, depth: depth + 1) { return canvas }
              }
              return nil
            }
            if let canvas = locate(host) {
              canvas.cloneHover = CGPoint(x: spotSnapshot ? 850 : 520, y: 358)
              canvas.needsDisplay = true
            }
          }
          // Keep the capture boundary identical for wrapped and unwrapped diagnostics.
          guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw CraftError.invalid("Snapshot allocation failed.")
          }
          host.cacheDisplay(in: host.bounds, to: rep)
          guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CraftError.invalid("Snapshot encoding failed.")
          }
          let args = CommandLine.arguments
          let output = args.last ?? "/tmp/photato-workspace.png"
          try data.write(to: URL(fileURLWithPath: output))
          print("Snapshot: \(output)")
          WorkspaceLayoutDiagnostics.snapshot(host, store: s, phase: "first")
          if WorkspaceLayoutDiagnostics.enabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [w, host] in
              w.layoutIfNeeded()
              host.layoutSubtreeIfNeeded()
              WorkspaceLayoutDiagnostics.snapshot(host, store: s, phase: "late")
              try? WorkspaceLayoutDiagnostics.writeImage(
                host, to: URL(fileURLWithPath: output + ".late.png"))
              NSApp.terminate(nil)
            }
          } else {
            NSApp.terminate(nil)
          }
        } catch {
          fputs("Snapshot failed: \(error)\n", stderr)
          NSApp.terminate(nil)
        }
      }
    } catch {
      fputs("Snapshot failed: \(error)\n", stderr)
      NSApp.terminate(nil)
    }
  }
}
@main struct PhotatoApp {
  @MainActor static func main() {
    if let i = CommandLine.arguments.firstIndex(of: "--benchmark-color-balance"),
      CommandLine.arguments.count > i + 1
    {
      do {
        try Benchmark.colorBalance(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
      } catch {
        print("Color Balance benchmark failed: \(error)")
        exit(1)
      }
      return
    }
    if let i = CommandLine.arguments.firstIndex(of: "--benchmark-expanded-clone"),
      i + 1 < CommandLine.arguments.count
    {
      do {
        try Benchmark.expandedClone(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
      } catch {
        print(error.localizedDescription)
        exit(1)
      }
      return
    }
    if let i = CommandLine.arguments.firstIndex(of: "--gradient-atlas"),
      i + 1 < CommandLine.arguments.count
    {
      do {
        try Benchmark.gradientAtlas(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
      } catch {
        print(error.localizedDescription)
        exit(1)
      }
      return
    }
    if let i = CommandLine.arguments.firstIndex(of: "--inspect-gradients"),
      i + 2 < CommandLine.arguments.count
    {
      do {
        try Benchmark.inspectGradients(
          at: URL(fileURLWithPath: CommandLine.arguments[i + 1]),
          to: URL(fileURLWithPath: CommandLine.arguments[i + 2]))
      } catch {
        print(error.localizedDescription)
        exit(1)
      }
      return
    }
    if let i = CommandLine.arguments.firstIndex(of: "--inspect-patterns"),
      i + 2 < CommandLine.arguments.count
    {
      do {
        try Benchmark.inspectPatterns(
          at: URL(fileURLWithPath: CommandLine.arguments[i + 1]),
          to: URL(fileURLWithPath: CommandLine.arguments[i + 2]))
      } catch {
        print(error.localizedDescription)
        exit(1)
      }
      return
    }
    if let i = CommandLine.arguments.firstIndex(of: "--benchmark-pattern-fill"),
      i + 1 < CommandLine.arguments.count
    {
      do { try Benchmark.patternFill(to: URL(fileURLWithPath: CommandLine.arguments[i + 1])) } catch
      {
        print(error.localizedDescription)
        exit(1)
      }
      return
    }
    if let i = CommandLine.arguments.firstIndex(of: "--benchmark-color-region")
      ?? CommandLine.arguments.firstIndex(of: "--benchmark-patterns"),
      i + 1 < CommandLine.arguments.count
    {
      do {
        try Benchmark.colorRegion(
          to: URL(fileURLWithPath: CommandLine.arguments[i + 1]),
          pattern: CommandLine.arguments[i] == "--benchmark-patterns")
      } catch {
        fputs("Color-region benchmark failed: \(error)\n", stderr)
        exit(1)
      }
      return
    }
    if let i = CommandLine.arguments.firstIndex(of: "--benchmark-focus"),
      i + 1 < CommandLine.arguments.count
    {
      do { try Benchmark.focus(to: URL(fileURLWithPath: CommandLine.arguments[i + 1])) } catch {
        print(error.localizedDescription)
        exit(1)
      }
      return
    }
    if let i = CommandLine.arguments.firstIndex(of: "--benchmark-toning"),
      i + 1 < CommandLine.arguments.count
    {
      do { try Benchmark.toning(to: URL(fileURLWithPath: CommandLine.arguments[i + 1])) } catch {
        print(error.localizedDescription)
        exit(1)
      }
      return
    }
    if let i = CommandLine.arguments.firstIndex(of: "--benchmark-spot-healing"),
      i + 1 < CommandLine.arguments.count
    {
      do { try Benchmark.spotHealing(to: URL(fileURLWithPath: CommandLine.arguments[i + 1])) } catch
      {
        print(error.localizedDescription)
        exit(1)
      }
      return
    }
    if let i = CommandLine.arguments.firstIndex(of: "--benchmark-healing"),
      i + 1 < CommandLine.arguments.count
    {
      do { try Benchmark.healing(to: URL(fileURLWithPath: CommandLine.arguments[i + 1])) } catch {
        print(error.localizedDescription)
        exit(1)
      }
      return
    }
    if let i = CommandLine.arguments.firstIndex(of: "--benchmark-clone"),
      i + 1 < CommandLine.arguments.count
    {
      do { try Benchmark.cloneStamp(to: URL(fileURLWithPath: CommandLine.arguments[i + 1])) } catch
      { print("Clone Stamp benchmark failed: \(error)") }
      return
    }
    if let i = CommandLine.arguments.firstIndex(of: "--benchmark-hue-saturation"),
      CommandLine.arguments.count > i + 1
    {
      do {
        try Benchmark.hueSaturation(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
      } catch {
        print("Hue/Saturation benchmark failed: \(error)")
        exit(1)
      }
      return
    }
    if let i = CommandLine.arguments.firstIndex(of: "--benchmark-curves"),
      CommandLine.arguments.count > i + 1
    {
      do { try Benchmark.curves(to: URL(fileURLWithPath: CommandLine.arguments[i + 1])) } catch {
        print("Curves benchmark failed: \(error)")
        exit(1)
      }
      return
    }
    if let i = CommandLine.arguments.firstIndex(of: "--benchmark-levels"),
      i + 1 < CommandLine.arguments.count
    {
      do { try Benchmark.levels(to: URL(fileURLWithPath: CommandLine.arguments[i + 1])) } catch {
        print("Levels benchmark failed: \(error)")
      }
      return
    }
    if let i = CommandLine.arguments.firstIndex(where: {
      $0 == "--benchmark-packing" || $0 == "--benchmark-packing-24mp"
    }), i + 1 < CommandLine.arguments.count {
      do {
        try Benchmark.packing(
          to: URL(fileURLWithPath: CommandLine.arguments[i + 1]),
          large: CommandLine.arguments[i] == "--benchmark-packing-24mp")
      } catch { print("Packing benchmark failed: \(error)") }
      return
    }
    if let i = CommandLine.arguments.firstIndex(of: "--benchmark-clipboard"),
      i + 1 < CommandLine.arguments.count
    {
      do { try Benchmark.clipboard(to: URL(fileURLWithPath: CommandLine.arguments[i + 1])) } catch {
        print("Clipboard benchmark failed: \(error)")
      }
      return
    }
    if let i = CommandLine.arguments.firstIndex(of: "--benchmark-masks"),
      i + 1 < CommandLine.arguments.count
    {
      do { try Benchmark.masks(to: URL(fileURLWithPath: CommandLine.arguments[i + 1])) } catch {
        print("Mask benchmark failed: \(error)")
      }
      return
    }
    if let i = CommandLine.arguments.firstIndex(of: "--benchmark"),
      i + 1 < CommandLine.arguments.count
    {
      do { try Benchmark.run(to: URL(fileURLWithPath: CommandLine.arguments[i + 1])) } catch {
        print("Benchmark failed: \(error)")
      }
      return
    }
    // Install the custom document controller before AppKit can create its default
    // singleton while initializing application UI.
    // Owned UI qualification bundles can launch normally without reading or
    // writing the user's workspace, recovery index or color preferences.
    let isolatedSession = CommandLine.arguments.contains(where: { $0.hasPrefix("--snapshot") })
      || ProcessInfo.processInfo.environment["PHOTATO_ISOLATED_UI_SESSION"] == "1"
    let delegate = makeDelegate(isolatedSession: isolatedSession)
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
  }

  /// The normal app and owned UI sessions use the same tested startup factory.
  @MainActor static func makeDelegate(isolatedSession: Bool) -> AppDelegate {
    AppDelegate(
      workspaces: isolatedSession
        ? WorkspaceLibrary() : .shared,
      recoveryPreferences: isolatedSession
        ? RecoveryPreferencesStore() : .shared,
      recoveryIndex: isolatedSession
        ? RecoveryIndexStore() : .shared,
      colorSettings: isolatedSession
        ? ColorSettingsStore() : .shared,
      paintPalette: PaintPalette(defaults: isolatedSession ? nil : .standard),
      eyedropperPreferences:EyedropperPreferences(defaults:isolatedSession ? nil:.standard),
      liquifyMeshes: isolatedSession ? LiquifyMeshLibrary() : .shared,
      lensDefaults: isolatedSession ? LensDefaultLibrary() : .shared,
      scriptEvents: isolatedSession ? ScriptEventsStore() : .shared)
  }
}
