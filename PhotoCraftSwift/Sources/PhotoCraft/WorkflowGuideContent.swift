import Foundation
import PhotoCraftCore

enum WorkflowGuideContext: String {
  case document, layer, selection, mask, brush, retouch, crop, transform, navigation, color, type, shape, export, channels, history

  init(tool: EditorTool) {
    switch tool {
    case .move: self = .layer
    case .marquee, .ellipticalMarquee, .rowMarquee, .columnMarquee, .lasso, .polygonLasso,
         .magneticLasso, .objectSelection, .quickSelection, .selectionBrush, .magicWand: self = .selection
    case .brush, .pencil, .eraser, .mixerBrush, .colorReplacement, .adjustmentBrush,
         .paintBucket, .gradient, .patternStamp, .backgroundEraser, .magicEraser: self = .brush
    case .cloneStamp, .healingBrush, .spotHealing, .blur, .sharpen, .smudge, .dodge, .burn,
         .sponge, .patch, .contentAwareMove, .redEye, .remove: self = .retouch
    case .crop: self = .crop
    case .zoom, .hand: self = .navigation
    case .eyedropper: self = .color
    case .text, .verticalText: self = .type
    case .rectangle, .ellipse, .triangle, .polygon, .star, .line, .customShape, .pen, .freeformPen,
         .curvaturePen, .pathSelection, .directSelection, .frame, .artboard: self = .shape
    }
  }

  static func menu(_ path: String) -> Self? {
    let path = path.replacingOccurrences(of: "shortcut-alias:", with: "", options: .anchored)
    if path.hasPrefix("Layer > Layer Mask") { return .mask }
    if path.hasPrefix("Edit > Transform") || path == "Edit > Free Transform" { return .transform }
    if path.hasPrefix("File > Save") || path.hasPrefix("File > Export") || path.contains("Quick Export") { return .export }
    if path.hasPrefix("Image > Mode") || path.hasPrefix("Image > Adjustments")
      || path.hasSuffix(" Profile…") { return .color }
    if path.contains("Selection") && (path.contains("Save") || path.contains("Load")) { return .channels }
    switch path.split(separator: ">").first?.trimmingCharacters(in: .whitespaces) {
    case "Layer": return .layer
    case "Select": return .selection
    case "Filter": return .retouch
    case "Image": return path.contains("Crop") || path.contains("Canvas Size") ? .crop : .document
    case "Type": return .type
    case "View": return .navigation
    case "File": return .document
    case "Window":
      switch path {
      case "Window > Channels": return .channels
      case "Window > Layers": return .layer
      case "Window > History", "Window > Actions": return .history
      case "Window > Brushes", "Window > Brush Settings": return .brush
      case "Window > Character", "Window > Paragraph", "Window > Glyphs": return .type
      case "Window > Color", "Window > Swatches", "Window > Adjustments": return .color
      case "Window > Shapes", "Window > Paths": return .shape
      default: return nil
      }
    case "Edit": return path.contains("Undo") || path.contains("Redo") ? .history : .layer
    default: return nil
    }
  }
}

struct WorkflowGuideStep: Equatable {
  enum Check: String {
    case layerSelected, layerAdded, opacityChanged, visibilityChanged, maskAvailable, maskEditing,
      selectionExists, selectionCleared, selectionSaved, brushTool, cropTool, transformOpen, zoomChanged
  }

  let instruction: String
  let check: Check?
  let target: WorkflowGuideTarget?

  init(_ instruction: String, _ check: Check? = nil, target: WorkflowGuideTarget? = nil) {
    self.instruction = instruction
    self.check = check
    self.target = target
  }
}

struct WorkflowGuideLesson: Identifiable, Equatable {
  enum Requirement: String { case document, layer, selection, mask, unmaskedRaster, raster, transformable, opacity }
  let id: String
  let title: String
  let steps: [WorkflowGuideStep]
  let requirement: Requirement
  let diaryStep: String?

  init(_ id: String, _ title: String, _ requirement: Requirement, diaryStep: String? = nil,
    steps: [WorkflowGuideStep]) {
    self.id = id
    self.title = title
    self.requirement = requirement
    self.diaryStep = diaryStep
    self.steps = steps
  }
}

enum WorkflowGuideContent {
  static let duplicate = WorkflowGuideLesson("duplicate-layer", "Duplicate a layer", .layer, steps: [
    .init("Select the layer you want to copy in Layers.", .layerSelected, target: .control(.layerRow)),
    .init("Choose Layer > Duplicate Layer, enter a name, and confirm.", .layerAdded, target: .menu("Layer > Duplicate Layer", dialog: .duplicateLayer)),
    .init("Use the eye icons in Layers to compare the original and duplicate.", target: .control(.layerEye)),
  ])
  static let opacity = WorkflowGuideLesson("blend-opacity", "Adjust layer opacity", .opacity, steps: [
    .init("Select the layer you want to blend in Layers.", .layerSelected, target: .control(.layerRow)),
    .init("Open the Opacity control above the layer list. Drag its slider or enter a percentage.", .opacityChanged, target: .control(.opacity)),
    .init("Compare the result against the layers underneath. Use Edit > Undo if needed.", target: .control(.canvas)),
  ])
  static let addMask = WorkflowGuideLesson("add-layer-mask", "Hide part of a layer with a mask", .unmaskedRaster, diaryStep: "007", steps: [
    .init("Select the pixel layer you want to mask.", .layerSelected, target: .control(.layerRow)),
    .init("Choose Layer > Layer Mask > Reveal All.", .maskAvailable, target: .menu("Layer > Layer Mask > Reveal All")),
    .init("Click the mask thumbnail beside the layer thumbnail.", .maskEditing, target: .control(.mask)),
    .init("Choose Brush and paint with black to hide pixels. Paint with white to reveal them again.", target: .tool(.brush)),
  ])
  static let paintMask = WorkflowGuideLesson("paint-layer-mask", "Paint on a layer mask", .mask, diaryStep: "007", steps: [
    .init("Click the layer’s mask thumbnail in Layers.", .maskEditing, target: .control(.mask)),
    .init("Choose the Brush tool.", .brushTool, target: .tool(.brush)),
    .init("Use black to hide the layer and white to reveal it. Use a soft brush for a gradual edge.", target: .control(.canvas)),
  ])
  static let transform = WorkflowGuideLesson("free-transform", "Resize or rotate a layer", .transformable, steps: [
    .init("Select the layer you want to transform.", .layerSelected, target: .control(.layerRow)),
    .init("Choose Edit > Free Transform.", .transformOpen, target: .menu("Edit > Free Transform")),
    .init("Drag a corner to resize, or drag just outside a corner to rotate. Press Return to apply or Escape to cancel.", target: .control(.canvas)),
  ])
  static let appearance = WorkflowGuideLesson("layer-visibility", "Compare layer visibility", .layer, steps: [
    .init("In Layers, note the eye icon to the left of the selected layer.", target: .control(.layerEye)),
    .init("Click the eye to toggle that layer.", .visibilityChanged, target: .control(.layerEye)),
    .init("Click it again when you want to restore the previous view.", target: .control(.layerEye)),
  ])
  static let select = WorkflowGuideLesson("create-selection", "Make a selection", .document, diaryStep: "526", steps: [
    .init("Choose Rectangular Marquee, Elliptical Marquee or Lasso from the toolbar.", target: .tool(.marquee)),
    .init("Draw around the area you want to edit.", .selectionExists, target: .control(.canvas)),
    .init("With a Marquee tool active, drag inside the outline to reposition it.", target: .control(.canvas)),
  ])
  static let saveSelection = WorkflowGuideLesson("save-selection", "Save a selection for reuse", .selection, diaryStep: "367", steps: [
    .init("Leave the selection active.", .selectionExists, target: .control(.canvas)),
    .init("Choose Select > Save Selection, name it, and confirm.", .selectionSaved, target: .menu("Select > Save Selection", dialog: .savedSelection)),
    .init("Use Select > Load Selection to restore it, or inspect it in Window > Channels.", target: .menu("Select > Load Selection", dialog: .savedSelection)),
  ])
  static let inverse = WorkflowGuideLesson("invert-selection", "Select everything outside the outline", .selection, steps: [
    .init("Leave the selection active.", .selectionExists, target: .control(.canvas)),
    .init("Choose Select > Inverse.", target: .menu("Select > Inverse")),
    .init("Apply the edit to the newly selected area, then choose Select > Deselect.", target: .menu("Select > Deselect")),
  ])
  static let clearSelection = WorkflowGuideLesson("clear-selection", "Remove the selection outline", .selection, steps: [
    .init("Choose Select > Deselect.", .selectionCleared, target: .menu("Select > Deselect")),
    .init("Continue editing the full layer, or use a selection tool to draw a fresh outline.", target: .tool(.marquee)),
  ])
  static let brush = WorkflowGuideLesson("paint-with-brush", "Paint on a separate layer", .document, diaryStep: "538", steps: [
    .init("Choose Layer > New > Layer and confirm.", .layerAdded, target: .menu("Layer > New > Layer", dialog: .newLayer)),
    .init("Choose the Brush tool.", .brushTool, target: .tool(.brush)),
    .init("Set the foreground color, brush size and opacity in the tool controls. Paint on the new layer.", target: .control(.options)),
  ])
  static let crop = WorkflowGuideLesson("crop-document", "Crop the document", .document, steps: [
    .init("Choose the Crop tool.", .cropTool, target: .tool(.crop)),
    .init("Drag the crop handles around the part of the canvas you want to keep.", target: .control(.canvas)),
    .init("Check Delete Cropped Pixels in the options bar. Press Return to apply or Escape to cancel.", target: .control(.cropDelete)),
  ])
  static let fit = WorkflowGuideLesson("fit-and-inspect", "Fit and inspect the canvas", .document, steps: [
    .init("Choose View > Fit on Screen. The whole canvas should be visible.", target: .menu("View > Fit on Screen")),
    .init("Choose View > 100% or use Zoom to inspect small details.", .zoomChanged, target: .menu("View > 100%")),
    .init("Use the Hand tool to pan. Choose View > Fit on Screen again to return.", target: .tool(.hand)),
  ])
  static let sample = WorkflowGuideLesson("sample-color", "Sample a color from the image", .document, steps: [
    .init("Choose Eyedropper in the toolbar.", target: .tool(.eyedropper)),
    .init("Set the sample size and sample source in the options bar.", target: .control(.options)),
    .init("Click the image and check the foreground swatch before you paint.", target: .control(.foreground)),
  ])
  static let type = WorkflowGuideLesson("add-type", "Add editable text", .document, steps: [
    .init("Choose Horizontal Type or Vertical Type in the toolbar.", target: .tool(.text)),
    .init("Click the canvas, type your text, and use the options bar to set the font and size.", target: .control(.canvas)),
    .init("Commit the text with the checkmark in the options bar. Double-click its thumbnail to edit it later.", target: .control(.options)),
  ])
  static let shape = WorkflowGuideLesson("draw-shape", "Draw an editable shape", .document, steps: [
    .init("Choose Rectangle, Ellipse or another Shape tool.", target: .tool(.rectangle)),
    .init("Set the tool mode to Shape, then choose Fill and Stroke.", target: .control(.options)),
    .init("Drag on the canvas and adjust the shape in Properties.", target: .control(.canvas)),
  ])
  static let export = WorkflowGuideLesson("export-copy", "Export an image copy", .document, steps: [
    .init("Choose File > Export > Export As.", target: .menu("File > Export > Export As", dialog: .imageExport)),
    .init("Choose a format and check the preview and dimensions.", target: .modal(.imageExport, .modalFormat)),
    .init("Choose Export and save the copy to a destination you control.", target: .modal(.imageExport, .modalConfirm)),
  ])
  static let save = WorkflowGuideLesson("save-editable", "Save an editable file", .document, diaryStep: "609", steps: [
    .init("Choose File > Save As.", target: .menu("File > Save As", dialog: .save)),
    .init("Choose Photato for the native document or PSD/PSB for Photoshop interchange.", target: .modal(.save, .modalFormat)),
    .init("Choose a destination. Keep the editable file when exporting a flattened copy.", target: .modal(.save, .modalConfirm)),
  ])
  static let history = WorkflowGuideLesson("undo-and-redo", "Review recent edits", .document, steps: [
    .init("Choose Window > History to see the document’s recent edits.", target: .menu("Window > History")),
    .init("Use Edit > Undo or Edit > Redo to move through the recent edit.", target: .menu("Edit > Undo")),
    .init("Review the canvas before continuing so you know which state is active.", target: .control(.canvas)),
  ])
  static let retouch = WorkflowGuideLesson("spot-cleanup", "Clean up a small blemish", .raster, steps: [
    .init("Select a pixel layer and duplicate it if you want a comparison copy.", target: .control(.layerRow)),
    .init("Choose Spot Healing Brush and set its size to a little larger than the blemish.", target: .tool(.spotHealing)),
    .init("Click or paint over the blemish, then inspect at 100%. Toggle the layer eye to compare.", target: .control(.canvas)),
  ])

  private static let choices: [WorkflowGuideContext: [WorkflowGuideLesson]] = [
    .document: [select, crop, save, export], .layer: [opacity, duplicate, paintMask, addMask, transform, appearance, brush, save],
    .selection: [saveSelection, inverse, clearSelection, select, addMask], .mask: [paintMask, addMask, brush, appearance],
    .brush: [brush, sample, paintMask, opacity], .retouch: [retouch, duplicate, fit, history],
    .crop: [crop, save, export, fit], .transform: [transform, fit, duplicate, history],
    .navigation: [fit, crop, select, history], .color: [sample, opacity, brush, export],
    .type: [type, transform, opacity, export], .shape: [shape, transform, opacity, export],
    .export: [export, save, fit, duplicate], .channels: [saveSelection, select, paintMask, inverse],
    .history: [history, duplicate, appearance, save],
  ]

  static func suggestions(for context: WorkflowGuideContext, state: WorkflowGuideSnapshot, maximum: Int) -> [WorkflowGuideLesson] {
    Array((choices[context] ?? []).filter { lesson in
      switch lesson.requirement {
      case .document: state.documentID != nil
      case .layer: state.layerID != nil
      case .selection: state.hasSelection
      case .mask: state.hasMask
      case .raster: state.isRaster
      case .transformable: state.canTransform
      case .opacity: state.canChangeOpacity
      case .unmaskedRaster: state.isRaster && !state.hasMask && !state.isBackground && !state.isLocked
      }
    }.prefix(maximum))
  }

  static var capability: [String: Any] {
    let byID = Dictionary(choices.values.joined().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let catalogue: [[String: Any]] = byID.values.sorted { $0.id < $1.id }.map { lesson in
      var entry: [String: Any] = [
        "id": lesson.id, "title": lesson.title, "requirement": lesson.requirement.rawValue,
        "steps": lesson.steps.map { step -> [String: Any] in
          var value = ["instruction": step.instruction]
          if let check = step.check { value["observedCheck"] = check.rawValue }
          var fields: [String: Any] = value
          if let target = step.target { fields["target"] = target.capability }
          return fields
        },
      ]
      if let anchor = lesson.diaryStep { entry["diaryAnchor"] = "dev-step-" + anchor }
      return entry
    }
    return [
      "menu": "Window > Workflow Guide", "optional": true, "processing": "local",
      "ranking": "A hand-curated order for the current editor context, filtered for available operations. No usage history is collected.",
      "showMe": "Replay the current step’s highlight in the native guide. Menu cues follow the open path and supported dialogs identify their own controls.",
      "suggestionOrder": Dictionary(uniqueKeysWithValues: choices.map { ($0.key.rawValue, $0.value.map(\.id)) }),
      "lessons": catalogue,
      "scope": "Read-only guidance for authored workflows. The user performs each edit in the native editor.",
    ]
  }
}
