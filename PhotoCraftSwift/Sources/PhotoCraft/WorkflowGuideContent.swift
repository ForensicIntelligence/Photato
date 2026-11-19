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

  init(_ instruction: String, _ check: Check? = nil) {
    self.instruction = instruction
    self.check = check
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
    .init("Select the layer you want to copy in Layers.", .layerSelected),
    .init("Choose Layer > Duplicate Layer, enter a name, and confirm.", .layerAdded),
    .init("Use the eye icons in Layers to compare the original and duplicate."),
  ])
  static let opacity = WorkflowGuideLesson("blend-opacity", "Adjust layer opacity", .opacity, steps: [
    .init("Select the layer you want to blend in Layers.", .layerSelected),
    .init("Open the Opacity control above the layer list. Drag its slider or enter a percentage.", .opacityChanged),
    .init("Compare the result against the layers underneath. Use Edit > Undo if needed."),
  ])
  static let addMask = WorkflowGuideLesson("add-layer-mask", "Hide part of a layer with a mask", .unmaskedRaster, diaryStep: "007", steps: [
    .init("Select the pixel layer you want to mask.", .layerSelected),
    .init("Choose Layer > Layer Mask > Reveal All.", .maskAvailable),
    .init("Click the mask thumbnail beside the layer thumbnail.", .maskEditing),
    .init("Choose Brush and paint with black to hide pixels. Paint with white to reveal them again."),
  ])
  static let paintMask = WorkflowGuideLesson("paint-layer-mask", "Paint on a layer mask", .mask, diaryStep: "007", steps: [
    .init("Click the layer’s mask thumbnail in Layers.", .maskEditing),
    .init("Choose the Brush tool.", .brushTool),
    .init("Use black to hide the layer and white to reveal it. Use a soft brush for a gradual edge."),
  ])
  static let transform = WorkflowGuideLesson("free-transform", "Resize or rotate a layer", .transformable, steps: [
    .init("Select the layer you want to transform.", .layerSelected),
    .init("Choose Edit > Free Transform.", .transformOpen),
    .init("Drag a corner to resize, or drag just outside a corner to rotate. Press Return to apply or Escape to cancel."),
  ])
  static let appearance = WorkflowGuideLesson("layer-visibility", "Compare layer visibility", .layer, steps: [
    .init("In Layers, note the eye icon to the left of the selected layer."),
    .init("Click the eye to toggle that layer.", .visibilityChanged),
    .init("Click it again when you want to restore the previous view."),
  ])
  static let select = WorkflowGuideLesson("create-selection", "Make a selection", .document, diaryStep: "526", steps: [
    .init("Choose Rectangular Marquee, Elliptical Marquee or Lasso from the toolbar."),
    .init("Draw around the area you want to edit.", .selectionExists),
    .init("With a Marquee tool active, drag inside the outline to reposition it."),
  ])
  static let saveSelection = WorkflowGuideLesson("save-selection", "Save a selection for reuse", .selection, diaryStep: "367", steps: [
    .init("Leave the selection active.", .selectionExists),
    .init("Choose Select > Save Selection, name it, and confirm.", .selectionSaved),
    .init("Use Select > Load Selection to restore it, or inspect it in Window > Channels."),
  ])
  static let inverse = WorkflowGuideLesson("invert-selection", "Select everything outside the outline", .selection, steps: [
    .init("Leave the selection active.", .selectionExists),
    .init("Choose Select > Inverse."),
    .init("Apply the edit to the newly selected area, then choose Select > Deselect."),
  ])
  static let clearSelection = WorkflowGuideLesson("clear-selection", "Remove the selection outline", .selection, steps: [
    .init("Choose Select > Deselect.", .selectionCleared),
    .init("Continue editing the full layer, or use a selection tool to draw a fresh outline."),
  ])
  static let brush = WorkflowGuideLesson("paint-with-brush", "Paint on a separate layer", .document, diaryStep: "538", steps: [
    .init("Choose Layer > New > Layer and confirm.", .layerAdded),
    .init("Choose the Brush tool.", .brushTool),
    .init("Set the foreground color, brush size and opacity in the tool controls. Paint on the new layer."),
  ])
  static let crop = WorkflowGuideLesson("crop-document", "Crop the document", .document, steps: [
    .init("Choose the Crop tool.", .cropTool),
    .init("Drag the crop handles around the part of the canvas you want to keep."),
    .init("Check Delete Cropped Pixels in the options bar. Press Return to apply or Escape to cancel."),
  ])
  static let fit = WorkflowGuideLesson("fit-and-inspect", "Fit and inspect the canvas", .document, steps: [
    .init("Choose View > Fit on Screen. The whole canvas should be visible."),
    .init("Choose View > 100% or use Zoom to inspect small details.", .zoomChanged),
    .init("Use the Hand tool to pan. Choose View > Fit on Screen again to return."),
  ])
  static let sample = WorkflowGuideLesson("sample-color", "Sample a color from the image", .document, steps: [
    .init("Choose Eyedropper in the toolbar."),
    .init("Set the sample size and sample source in the options bar."),
    .init("Click the image and check the foreground swatch before you paint."),
  ])
  static let type = WorkflowGuideLesson("add-type", "Add editable text", .document, steps: [
    .init("Choose Horizontal Type or Vertical Type in the toolbar."),
    .init("Click the canvas, type your text, and use the options bar to set the font and size."),
    .init("Commit the text with the checkmark in the options bar. Double-click its thumbnail to edit it later."),
  ])
  static let shape = WorkflowGuideLesson("draw-shape", "Draw an editable shape", .document, steps: [
    .init("Choose Rectangle, Ellipse or another Shape tool."),
    .init("Set the tool mode to Shape, then choose Fill and Stroke."),
    .init("Drag on the canvas and adjust the shape in Properties."),
  ])
  static let export = WorkflowGuideLesson("export-copy", "Export an image copy", .document, steps: [
    .init("Choose File > Export > Export As."),
    .init("Choose a format and check the preview and dimensions."),
    .init("Choose Export and save the copy to a destination you control."),
  ])
  static let save = WorkflowGuideLesson("save-editable", "Save an editable file", .document, diaryStep: "609", steps: [
    .init("Choose File > Save As."),
    .init("Choose Photato for the native document or PSD/PSB for Photoshop interchange."),
    .init("Choose a destination. Keep the editable file when exporting a flattened copy."),
  ])
  static let history = WorkflowGuideLesson("undo-and-redo", "Review recent edits", .document, steps: [
    .init("Choose Window > History to see the document’s recent edits."),
    .init("Use Edit > Undo or Edit > Redo to move through the recent edit."),
    .init("Review the canvas before continuing so you know which state is active."),
  ])
  static let retouch = WorkflowGuideLesson("spot-cleanup", "Clean up a small blemish", .raster, steps: [
    .init("Select a pixel layer and duplicate it if you want a comparison copy."),
    .init("Choose Spot Healing Brush and set its size to a little larger than the blemish."),
    .init("Click or paint over the blemish, then inspect at 100%. Toggle the layer eye to compare."),
  ])

  private static let choices: [WorkflowGuideContext: [WorkflowGuideLesson]] = [
    .document: [save, select, crop, export], .layer: [duplicate, addMask, paintMask, opacity, transform, appearance, brush, save],
    .selection: [saveSelection, inverse, clearSelection, select, addMask], .mask: [paintMask, addMask, brush, appearance],
    .brush: [brush, sample, paintMask, opacity], .retouch: [retouch, duplicate, fit, history],
    .crop: [crop, fit, save, export], .transform: [transform, duplicate, fit, history],
    .navigation: [fit, crop, select, history], .color: [sample, opacity, brush, export],
    .type: [type, transform, opacity, export], .shape: [shape, transform, opacity, export],
    .export: [export, save, fit, duplicate], .channels: [saveSelection, select, paintMask, inverse],
    .history: [history, duplicate, appearance, save],
  ]

  static func suggestions(for context: WorkflowGuideContext, state: WorkflowGuideSnapshot) -> [WorkflowGuideLesson] {
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
    }.prefix(4))
  }

  static var capability: [String: Any] {
    let byID = Dictionary(choices.values.joined().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let catalogue: [[String: Any]] = byID.values.sorted { $0.id < $1.id }.map { lesson in
      var entry: [String: Any] = [
        "id": lesson.id, "title": lesson.title, "requirement": lesson.requirement.rawValue,
        "steps": lesson.steps.map { step -> [String: Any] in
          var value = ["instruction": step.instruction]
          if let check = step.check { value["observedCheck"] = check.rawValue }
          return value
        },
      ]
      if let anchor = lesson.diaryStep { entry["diaryAnchor"] = "dev-step-" + anchor }
      return entry
    }
    return [
      "menu": "Window > Workflow Guide", "optional": true, "processing": "local",
      "suggestionOrder": Dictionary(uniqueKeysWithValues: choices.map { ($0.key.rawValue, $0.value.map(\.id)) }),
      "lessons": catalogue,
      "scope": "Read-only guidance for authored workflows. The user performs each edit in the native editor.",
    ]
  }
}
