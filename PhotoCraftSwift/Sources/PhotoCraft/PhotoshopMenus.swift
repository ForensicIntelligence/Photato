import AppKit
import PhotoCraftCore

@MainActor extension AppDelegate {
  /// Bind only implemented operations. Unavailable commands remain visible and disabled.
  func installPhotoshopMenus() {
    var actions: [String: Selector] = [
      "Image > Apply Image…": #selector(applyImageDialog),
      "Image > Calculations…": #selector(calculationsDialog),
      "Image > Variables > Define…": #selector(defineVariables),
      "Image > Variables > Data Sets…": #selector(editVariableDataSets),
      "Image > Apply Data Set…": #selector(applyVariableDataSet),
      "File > Import > Variable Data Sets…": #selector(importVariableDataSets),
      "File > Export > Data Sets as Files…": #selector(exportVariableDataSets),
      "File > Print…": #selector(printDocument),
      "File > Print One Copy": #selector(printOneCopy),
      "Layer > Rasterize > Shape": #selector(rasterizeShape),
      "Type > Warp Text…": #selector(warpType),
      "Window > Glyphs": #selector(showGlyphs),
      "Type > Panels > Glyphs Panel": #selector(showGlyphs),
      "Type > Orientation > Horizontal": #selector(horizontalType),
      "Type > Orientation > Vertical": #selector(verticalType),
      "Type > OpenType > Standard Ligatures": #selector(toggleTypeFeature(_:)),
      "Type > OpenType > Contextual Alternates": #selector(toggleTypeFeature(_:)),
      "Type > OpenType > Discretionary Ligatures": #selector(toggleTypeFeature(_:)),
      "Type > OpenType > Swash": #selector(toggleTypeFeature(_:)),
      "Type > OpenType > Oldstyle": #selector(toggleTypeFeature(_:)),
      "Type > OpenType > Stylistic Alternates": #selector(toggleTypeFeature(_:)),
      "Type > OpenType > Titling Alternates": #selector(toggleTypeFeature(_:)),
      "Type > OpenType > Ornaments": #selector(toggleTypeFeature(_:)),
      "Type > OpenType > Ordinals": #selector(toggleTypeFeature(_:)),
      "Type > OpenType > Fractions": #selector(toggleTypeFeature(_:)),
      "Window > Shapes": #selector(showShapes),
      "Edit > Define Custom Shape…": #selector(defineCustomShape),
      "Layer > New > Frame from Layers…": #selector(frameFromLayers),
      "Layer > New > Convert to Frame": #selector(convertToFrame),
      "Layer > New > Artboard…": #selector(newArtboard),
      "Layer > New > Artboard from Group": #selector(artboardFromGroup),
      "Layer > New > Artboard from Layers…": #selector(artboardFromLayers),
      "View > Fit Artboard on Screen": #selector(fitArtboard),
      "View > Show > Artboard Names": #selector(toggleArtboardNames),
      "View > Show > Artboard Guides": #selector(toggleArtboardGuides),
      "View > Guides > Clear Selected Artboard Guides": #selector(clearArtboardGuides),
      "File > Export > Artboards to Files…": #selector(exportArtboardFiles),
      "File > Export > Artboards to PDF…": #selector(exportArtboardPDF),
      "File > Automate > Batch…": #selector(showBatch),
      "Layer > Video Layers > New Video Layer from File…": #selector(newVideoLayer),
      "Window > Timeline": #selector(showTimeline),
      "Window > Actions": #selector(showActions),
      "Window > Brush Settings": #selector(showBrushSettings),
      "Window > Brushes": #selector(showBrushes),
      "Edit > Define Brush Preset…": #selector(defineBrushPreset),
      "Photato > About Photato…": #selector(about),
      "Photato > Settings… > File Handling…": #selector(fileHandlingPreferences),
      "Edit > Color Settings…": #selector(colorSettingsDialog),
      "Photato > Hide Photato": #selector(hide),
      "Photato > Hide Others": #selector(hideOthers),
      "Photato > Show All": #selector(showAllApplications),
      "Photato > Quit Photato": #selector(quit),
      "File > New…": #selector(newFile),
      "File > New from Clipboard": #selector(newFromClipboard),
      "File > Open…": #selector(openFile),
      "File > Scripts > Load Files into Stack…": #selector(loadImageStack),
      "File > Scripts > Statistics…": #selector(imageStatistics),
      "File > Import > Video Frames to Layers…": #selector(videoFramesToLayers),
      "File > Scripts > Image Processor…": #selector(imageProcessor),
      "File > Automate > Crop and Straighten Photos": #selector(cropAndStraightenPhotos),
      "File > Automate > Contact Sheet II…": #selector(contactSheet),
      "File > Automate > Photomerge…": #selector(photomerge),
      "File > Automate > Merge to HDR Pro…": #selector(hdrMerge),
      "File > Place Embedded…": #selector(placeEmbedded),
      "Layer > Smart Objects > Convert to Smart Object": #selector(convertSmartObject),
      "Filter > Convert for Smart Filters": #selector(convertSmartObject),
      "Layer > Smart Filter > Disable Smart Filters": #selector(smartFilterCommand(_:)),
      "Layer > Smart Filter > Delete Filter Mask": #selector(smartFilterCommand(_:)),
      "Layer > Smart Filter > Disable Filter Mask": #selector(smartFilterCommand(_:)),
      "Layer > Smart Filter > Clear Smart Filters": #selector(smartFilterCommand(_:)),
      "Layer > Smart Objects > New Smart Object via Copy": #selector(independentSmartObjectCopy),
      "Layer > Smart Objects > Edit Contents": #selector(editSmartObjectContents),
      "Layer > Smart Objects > Reset Transform": #selector(resetSmartObjectTransform),
      "Layer > Smart Objects > Replace Contents…": #selector(replaceSmartObjectContents),
      "Layer > Smart Objects > Export Contents…": #selector(exportSmartObjectContents),
      "Layer > Rasterize > Smart Object": #selector(rasterize),
      "File > Place Image…": #selector(place),
      "File > Close": #selector(closeWindow),
      "File > Close All": #selector(closeAllDocuments),
      "File > Close Others": #selector(closeOtherDocuments),
      "File > Save": #selector(save),
      "File > Save As…": #selector(saveAs),
      "File > Save a Copy…": #selector(saveCopy),
      "File > Revert": #selector(revertFile),
      "File > Export > Render Video…": #selector(renderVideo),
      "File > Export > Export As…": #selector(export),
      "File > Export > Export Layers to PSD…": #selector(exportPSD),
      "Edit > Undo": #selector(undo),
      "Edit > Redo": #selector(redo),
      "Edit > Cut": #selector(NSText.cut(_:)),
      "Edit > Copy": #selector(NSText.copy(_:)),
      "Edit > Copy Merged": #selector(copyMerged),
      "Edit > Paste": #selector(NSText.paste(_:)),
      "Edit > Paste Special > Paste in Place": #selector(pasteInPlace),
      "Edit > Paste Special > Paste Into": #selector(pasteInto),
      "Edit > Paste Special > Paste Outside": #selector(pasteOutside),
      "Edit > Clear": #selector(clear),
      "Edit > Auto-Align Layers…": #selector(autoAlignLayers),
      "Edit > Auto-Blend Layers…": #selector(autoBlendLayers),
      "Edit > Content-Aware Fill…": #selector(contentAwareFill),
      "Edit > Content-Aware Scale": #selector(contentAwareScale),
      "Edit > Fill…": #selector(fillDialog),
      "Edit > Free Transform": #selector(freeTransform),
      "Filter > Vanishing Point…": #selector(vanishingPoint),
      "Edit > Transform > Warp": #selector(warpLayer),
      "Layer > Smart Objects > Warp": #selector(warpLayer),
      "Edit > Transform > Scale": #selector(freeTransform),
      "Edit > Transform > Rotate": #selector(freeTransform),
      "Edit > Transform > Rotate 180°": #selector(rotateLayer180),
      "Edit > Transform > Rotate 90° Clockwise": #selector(rotateLayerCW),
      "Edit > Transform > Rotate 90° Counter Clockwise": #selector(rotateLayerCCW),
      "Edit > Transform > Flip Horizontal": #selector(flipH),
      "Edit > Transform > Flip Vertical": #selector(flipV),
      "Edit > Define Pattern…": #selector(definePattern),
      "Edit > Create with Apple Intelligence…": #selector(ai),
      "Image > Adjustments > Levels…": #selector(levels),
      "Image > Adjustments > Curves…": #selector(curves),
      "Image > Adjustments > Hue/Saturation…": #selector(hueSaturation),
      "Image > Adjustments > Vibrance…": #selector(vibrance),
      "Image > Adjustments > Black & White…": #selector(blackWhite),
      "Image > Adjustments > Photo Filter…": #selector(photoFilter),
      "Image > Adjustments > Channel Mixer…": #selector(channelMixer),
      "Image > Adjustments > Color Lookup…": #selector(colorLookup),
      "Image > Adjustments > Selective Color…": #selector(selectiveColor),
      "Image > Adjustments > Color Balance…": #selector(colorBalance),
      "Image > Adjustments > Posterize…": #selector(posterize),
      "Image > Adjustments > Threshold…": #selector(threshold),
      "Image > Adjustments > Gradient Map…": #selector(gradientMap),
      "Image > Adjustments > Desaturate": #selector(desaturate),
      "Image > Auto Tone": #selector(autoTone),
      "Image > Auto Contrast": #selector(autoContrast),
      "Image > Auto Color": #selector(autoColor),
      "Image > Image Size…": #selector(imageSize),
      "Image > Canvas Size…": #selector(canvasSize),
      "Image > Crop": #selector(crop),
      "Layer > New > Layer…": #selector(newLayer),
      "Layer > New > Group…": #selector(newGroup),
      "Layer > New > Group from Layers…": #selector(groupFromLayers),
      "Layer > New > Layer Via Copy": #selector(layerViaCopy),
      "Layer > New > Layer Via Cut": #selector(layerViaCut),
      "Layer > Merge Layers": #selector(mergeLayers),
      "Layer > Merge Visible": #selector(mergeVisible),
      "Layer > Duplicate Layer…": #selector(duplicate),
      "Layer > Rename Layer…": #selector(renameLayer),
      "Layer > Lock Layers…": #selector(lockLayers),
      "Layer > Hide Layers": #selector(toggleLayerVisibility),
      "Layer > Delete > Layer": #selector(delete),
      "Layer > New Fill Layer > Solid Color…": #selector(newSolidColor),
      "Layer > New Fill Layer > Gradient…": #selector(newGradientFill),
      "Layer > New Fill Layer > Pattern…": #selector(newPatternFill),
      "Layer > New Adjustment Layer > Color and vibrance…": #selector(newColorVibrance),
      "Layer > New Adjustment Layer > Light…": #selector(newLight),
      "Layer > New Adjustment Layer > Clarity and dehaze…": #selector(newClarityDehaze),
      "Layer > New Adjustment Layer > Grain…": #selector(newGrain),
      "Layer > New Adjustment Layer > Levels…": #selector(newLevels),
      "Layer > New Adjustment Layer > Curves…": #selector(newCurves),
      "Layer > New Adjustment Layer > Hue/Saturation…": #selector(newHueSaturation),
      "Layer > New Adjustment Layer > Black & White…": #selector(newBlackWhite),
      "Layer > New Adjustment Layer > Photo Filter…": #selector(newPhotoFilter),
      "Layer > New Adjustment Layer > Channel Mixer…": #selector(newChannelMixer),
      "Layer > New Adjustment Layer > Color Lookup…": #selector(newColorLookup),
      "Layer > New Adjustment Layer > Selective Color…": #selector(newSelectiveColor),
      "Layer > New Adjustment Layer > Color Balance…": #selector(newColorBalance),
      "Layer > New Adjustment Layer > Invert…": #selector(invert),
      "Layer > New Adjustment Layer > Posterize…": #selector(newPosterize),
      "Layer > New Adjustment Layer > Threshold…": #selector(newThreshold),
      "Layer > New Adjustment Layer > Gradient Map…": #selector(newGradientMap),
      "Layer > Layer Content Options…": #selector(layerContentOptions),
      "Layer > Layer Mask > Reveal All": #selector(maskRevealAll),
      "Layer > Layer Mask > Hide All": #selector(maskHideAll),
      "Layer > Layer Mask > Reveal Selection": #selector(maskRevealSelection),
      "Layer > Layer Mask > Hide Selection": #selector(maskHideSelection),
      "Layer > Layer Mask > From Transparency": #selector(maskFromTransparency),
      "Layer > Layer Mask > Delete": #selector(maskDelete),
      "Layer > Layer Mask > Apply": #selector(maskApply),
      "Layer > Layer Mask > Enable": #selector(maskEnabled),
      "Layer > Layer Mask > Unlink": #selector(maskLinked),
      "Layer > Vector Mask > Reveal All": #selector(vectorRevealAll),
      "Layer > Vector Mask > Hide All": #selector(vectorHideAll),
      "Layer > Vector Mask > Current Path": #selector(vectorCurrentPath),
      "Layer > Vector Mask > Delete": #selector(vectorDelete),
      "Layer > Vector Mask > Enable": #selector(vectorEnabled),
      "Layer > Vector Mask > Unlink": #selector(vectorLinked),
      "Layer > Create Clipping Mask": #selector(clippingMask),
      "Layer > Rasterize > Layer": #selector(rasterize),
      "Layer > Group Layers": #selector(groupLayers),
      "Layer > Ungroup Layers": #selector(ungroupLayers),
      "Layer > Photato Adjustments > Black & White": #selector(grayscale),
      "Layer > Photato Adjustments > Exposure +1": #selector(exposure),
      "Type > Convert Text Shape Type": #selector(convertTypeShape),
      "Type > Rasterize Type Layer": #selector(rasterizeType),
      "Type > Type Properties": #selector(propertiesPanel),
      "Select > All": #selector(selectAll),
      "Select > Deselect": #selector(deselect),
      "Select > Inverse": #selector(invertSelection),
      "Select > Edit in Quick Mask Mode": #selector(toggleQuickMask),
      "Select > Save Selection…": #selector(saveSelectionChannel),
      "Select > Load Selection…": #selector(loadSelectionChannel),
      "Select > Select and Mask…": #selector(selectAndMask),
      "Select > Focus Area…": #selector(focusArea),
      "Select > Sky": #selector(selectSky),
      "Edit > Sky Replacement…": #selector(skyReplacement),
      "Layer > Mask All Objects": #selector(maskAllObjects),
      "Select > Subject": #selector(selectSubject),
      "Select > All Layers": #selector(selectAllLayers),
      "Select > Modify > Feather…": #selector(featherSelection),
      "View > Zoom In": #selector(zoomIn),
      "View > Zoom Out": #selector(zoomOut),
      "View > Fit on Screen": #selector(fit),
      "View > 100%": #selector(actual),
      "View > Rulers": #selector(rulers),
      "Window > Arrange > Consolidate All to Tabs": #selector(consolidateDocumentWindows),
      "Window > Arrange > Float in Window": #selector(floatDocumentWindow),
      "Window > Arrange > Float All in Windows": #selector(floatAllDocumentWindows),
      "Window > Arrange > Minimize": #selector(minimizeDocumentWindow),
      "Window > Arrange > Bring All to Front": #selector(bringDocumentWindowsToFront),
      "Window > Workspace > Essentials (Default)": #selector(selectEssentialsWorkspace),
      "Window > Workspace > Reset Essentials": #selector(resetWorkspace),
      "Window > Workspace > Lock Workspace": #selector(lockWorkspace),
      "Window > Workspace > New Workspace…": #selector(newWorkspace),
      "Window > Workspace > Delete Workspace…": #selector(deleteWorkspace),
      "Window > Adjustments": #selector(adjustmentsPanel),
      "Window > Channels": #selector(channelsPanel),
      "Window > Clone Source": #selector(cloneSourcePanel),
      "Window > Color": #selector(colorPanel),
      "Window > Gradients": #selector(gradientsPanel),
      "Window > History": #selector(historyPanel),
      "Window > Layers": #selector(layersPanel),
      "Window > Libraries": #selector(librariesPanel),
      "Window > Paths": #selector(pathsPanel),
      "Window > Patterns": #selector(patternsPanel),
      "Window > Properties": #selector(propertiesPanel),
      "Window > Swatches": #selector(swatchesPanel),
      "Help > Photato Help…": #selector(help),
      "Help > Workspace Feature Map…": #selector(featureMap),
      "Help > Port Status & Shortcuts": #selector(help),
      "Help > Open Source & Credits…": #selector(about),
      "Help > Photato Automation API…": #selector(showAutomation),
    ]
    for title in ["None"] + ImageStackMode.allCases.map(\.title) { actions["Layer > Smart Objects > Stack Mode > " + title] = #selector(imageStackMode(_:)) }
    for path in Self.layerStyleMenuPaths { actions[path] = #selector(layerStyleMenu(_:)) }
    for title in Array(Self.proofMenus.keys) + ["Custom…", "Internet Standard RGB (sRGB)", "Monitor RGB"] {
      actions["View > Proof Setup > " + title] = #selector(proofCommand(_:))
    }
    actions["View > Proof Colors"] = #selector(proofCommand(_:))
    actions["View > Gamut Warning"] = #selector(proofCommand(_:))
    for path in Self.inkModeMenus.keys { actions[path] = #selector(inkModeDialog(_:)) }
    for path in Self.restrictedModeMenus.keys { actions[path] = #selector(restrictedModeDialog(_:)) }
    for path in ["Edit > Assign Profile…", "Edit > Convert to Profile…"] { actions[path] = #selector(colorProfileDialog(_:)) }
    for path in Array(Self.documentModeMenus.keys) + Array(Self.documentDepthMenus.keys) { actions[path] = #selector(documentModeDialog(_:)) }
    for path in Self.classicToneMenus.keys {actions[path] = #selector(classicToneDialog(_:))}
    for path in Self.proceduralMenus.keys {actions[path] = #selector(proceduralRenderDialog(_:))}
    for path in Self.filterMenus.keys { actions[path] = #selector(rasterFilterDialog(_:)) }
    func make(_ node: EditorMenuNode, parent: String) -> NSMenuItem {
      if node.title == "-" { return .separator() }
      let path = parent.isEmpty ? node.title : parent + " > " + node.title
      let item = NSMenuItem(title: node.title, action: nil, keyEquivalent: node.key)
      item.identifier = NSUserInterfaceItemIdentifier(path)
      item.keyEquivalentModifierMask = node.modifiers
      if let children = node.children {
        // The initialized Services provider can retain its original menu. Reparent that
        // native menu on rebuild so registration and the visible hierarchy stay identical.
        let submenu =
          (path == "Photato > Services" ? NSApp.servicesMenu : nil) ?? NSMenu(title: node.title)
        if let previous = submenu.supermenu?.items.first(where: { $0.submenu === submenu }) {
          previous.submenu = nil
        }
        for child in children {
          let primary = make(child, parent: path)
          submenu.addItem(primary)
          guard let childPath = primary.identifier?.rawValue else { continue }
          for shortcut in PhotoshopMenuCatalog.alternativeShortcuts[childPath] ?? [] {
            let alternate = make(child, parent: path)
            // Native menu dispatch retains validation and first-responder clipboard routing.
            // Hidden aliases accept factory alternate keys without duplicating visible entries.
            alternate.identifier = NSUserInterfaceItemIdentifier("shortcut-alias:" + childPath)
            alternate.keyEquivalent = shortcut.key
            alternate.keyEquivalentModifierMask = shortcut.modifiers
            alternate.isHidden = true
            alternate.allowsKeyEquivalentWhenHidden = true
            submenu.addItem(alternate)
          }
        }
        item.submenu = submenu
        if path == "Photato > Services" { NSApp.servicesMenu = submenu }
        if children.isEmpty && path != "Photato > Services" && path != "File > Open Recent" { item.isEnabled = false }
        return item
      }
      item.action = actions[path]
      item.target = self
      if ["Edit > Cut", "Edit > Copy", "Edit > Paste"].contains(path) { item.target = nil }
      if parent == "Layer > Align" {
        item.action = #selector(alignLayers(_:))
        item.representedObject = node.title
      } else if parent == "Layer > Distribute" {
        item.action = #selector(distributeLayers(_:))
        item.representedObject = node.title
      } else if parent == "Image > Image Rotation",
        let index = CanvasTurn.allCases.firstIndex(where: { $0.rawValue == node.title })
      {
        item.action = #selector(rotateCanvas(_:))
        item.tag = index
      }
      if item.action == nil {
        item.target = nil
        item.isEnabled = false
        item.toolTip = "Not available yet — see Help → Workspace Feature Map"
      }
      return item
    }
    let main = NSMenu()
    PhotoshopMenuCatalog.menus.forEach { main.addItem(make($0, parent: "")) }
    NSApp.mainMenu = main
    NSApp.servicesMenu =
      main.item(withTitle: "Photato")?.submenu?.item(withTitle: "Services")?.submenu
    NSApp.helpMenu = main.item(withTitle: "Help")?.submenu
    // Own the document list: assigning this to windowsMenu lets AppKit inject a different hierarchy.
    NSApp.windowsMenu = nil
    documentWindowMenu = main.item(withTitle: "Window")?.submenu
    documentWindowMenu?.delegate = self
    workspaceMenu = documentWindowMenu?.item(withTitle: "Workspace")?.submenu
    workspaceMenu?.delegate = self
    recentDocumentsMenu = main.item(withTitle: "File")?.submenu?.item(withTitle: "Open Recent")?.submenu
    recentDocumentsMenu?.delegate = self
  }

  @objc func layerViaCopy() { store?.layerVia(.copy) }
  @objc func layerViaCut() { store?.layerVia(.cut) }
  @objc func mergeLayers() {
    guard let store else { return }
    store.merge(store.menuMergeOperation)
  }
  @objc func mergeVisible() { store?.merge(.visible) }

  @objc func hideOthers() { NSApp.hideOtherApplications(nil) }
  @objc func showAllApplications() { NSApp.unhideAllApplications(nil) }

  @objc func fillDialog() {
    guard let store, store.canUseMenuFill else { return }
    let alert = NSAlert()
    alert.messageText = "Fill"
    alert.informativeText =
      store.editingComponent || store.document.inkMode != nil
      ? "Fill the selected color channel in Normal mode. Other channels and transparency are preserved."
      : "Fill the selection using Normal mode at 100% opacity."
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")
    let contents = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 28))
    contents.addItems(withTitles: [
      "Foreground Color", "Background Color", "Black", "50% Gray", "White",
    ])
    if store.canBeginContentAwareFill { contents.addItem(withTitle:"Content-Aware…") }
    contents.setAccessibilityLabel("Contents")
    let opacity = NSTextField(string: "100")
    opacity.setAccessibilityLabel("Opacity (%)")
    opacity.frame.size = NSSize(width: 80, height: 24)
    if store.editingComponent || store.document.inkMode != nil {
      // NSAlert measures the accessory's frame before presenting. A zero-frame
      // stack overlaps the informative text even though its children have sizes.
      let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 72))
      contents.frame = NSRect(x: 0, y: 42, width: 240, height: 28)
      let label = NSTextField(labelWithString: "Opacity (%):")
      label.frame = NSRect(x: 0, y: 8, width: 110, height: 24)
      opacity.frame = NSRect(x: 120, y: 8, width: 80, height: 24)
      accessory.addSubview(contents)
      accessory.addSubview(label)
      accessory.addSubview(opacity)
      alert.accessoryView = accessory
    } else {
      alert.accessoryView = contents
    }
    guard alert.runModal() == .alertFirstButtonReturn, store.canUseMenuFill else { return }
    guard let percent = Float(opacity.stringValue), percent.isFinite, (0...100).contains(percent)
    else {
      store.error = "Enter an opacity from 0 to 100 percent."
      return
    }
    let colors = [store.brush.color, store.backgroundColor, .black, Pixel(0.5, 0.5, 0.5), .white]
    if contents.indexOfSelectedItem == colors.count { store.beginContentAwareFill(); return }
    guard colors.indices.contains(contents.indexOfSelectedItem) else { return }
    store.fill(color: colors[contents.indexOfSelectedItem], opacity: percent / 100)
  }


}

extension EditorStore {
  var canCopyWholeLayerViaMenu: Bool {
    clipboardTargetAvailable && document.selection == nil && activeLayer != nil
      && clipboardLayerIDs.count == 1
  }
  func copyWholeLayerViaMenu() {
    guard canCopyWholeLayerViaMenu else { return }
    duplicateLayer()
  }
  var canUseMenuPixelEdit: Bool { (!editingComponent || editingChannel != nil || !modeComponentTargets.isEmpty) && canUseMenuFill }
  var canUseMenuFill: Bool {
    if document.inkMode != nil, editingChannel == nil { return canEditInkChannels }
    if editingChannel != nil { return canEditChannels }
    guard !geometryBusy, !hasToneDraft, transformDraft == nil,
      let layer = activeLayer, !document.isLocked(layer.id)
    else { return false }
    if editingMask { return layer.mask != nil }
    if case .raster = layer.content { return !document.isImageLocked(layer.id) }
    return false
  }
}
