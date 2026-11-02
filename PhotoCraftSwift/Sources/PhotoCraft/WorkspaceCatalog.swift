import Foundation
import PhotoCraftCore

public enum EditorTool: String, CaseIterable, Identifiable, Sendable {
  case move = "Move"
  case frame = "Frame"
  case artboard = "Artboard"
  case marquee = "Rectangular Marquee"
  case ellipticalMarquee = "Elliptical Marquee"
  case lasso = "Lasso"
  case polygonLasso = "Polygonal Lasso"
  case magneticLasso = "Magnetic Lasso"
  case objectSelection = "Object Selection"
  case quickSelection = "Quick Selection"
  case selectionBrush = "Selection Brush"
  case magicWand = "Magic Wand"
  case paintBucket = "Paint Bucket"
  case gradient = "Gradient"
  case cloneStamp = "Clone Stamp"
  case healingBrush = "Healing Brush"
  case blur = "Blur"
  case sharpen = "Sharpen"
  case smudge = "Smudge"
  case dodge = "Dodge"
  case burn = "Burn"
  case sponge = "Sponge"
  case patch = "Patch"
  case contentAwareMove = "Content-Aware Move"
  case redEye = "Red Eye"
  case spotHealing = "Spot Healing Brush"
  case pencil = "Pencil"
  case colorReplacement = "Color Replacement"
  case mixerBrush = "Mixer Brush"
  case patternStamp = "Pattern Stamp"
  case backgroundEraser = "Background Eraser"
  case magicEraser = "Magic Eraser"
  case adjustmentBrush = "Adjustment Brush"
  case brush = "Brush"
  case eraser = "Eraser"
  case rectangle = "Rectangle"
  case ellipse = "Ellipse"
  case triangle = "Triangle"
  case polygon = "Polygon"
  case star = "Star"
  case line = "Line"
  case customShape = "Custom Shape"
  case text = "Horizontal Type"
  case verticalText = "Vertical Type"
  case eyedropper = "Eyedropper"
  case hand = "Hand"
  case crop = "Crop"
  case zoom = "Zoom"
  case pen = "Pen"
  case freeformPen = "Freeform Pen"
  case curvaturePen = "Curvature Pen"
  case pathSelection = "Path Selection"
  case directSelection = "Direct Selection"
  var usesRetouchStroke: Bool {
    samplesRetouchSource || self == .spotHealing || toningTool != nil || focusTool != nil
  }
  var focusTool: FocusTool? {
    switch self {
    case .blur: .blur
    case .sharpen: .sharpen
    case .smudge: .smudge
    default: nil
    }
  }
  var toningTool: ToningTool? {
    switch self {
    case .dodge: .dodge
    case .burn: .burn
    case .sponge: .sponge
    default: nil
    }
  }
  var samplesRetouchSource: Bool { self == .cloneStamp || self == .healingBrush }
  public var id: String { rawValue }
  var symbol: String { WorkspaceCatalog.tools.first { $0.native == self }?.symbol ?? "cursorarrow" }
  var shortcut: String { WorkspaceCatalog.tools.first { $0.native == self }?.shortcut ?? "" }
}

struct WorkspaceTool: Identifiable, Equatable, Sendable {
  let id: String
  let title: String
  let symbol: String
  let shortcut: String
  let native: EditorTool?
  init(_ id: String, _ title: String, _ symbol: String, _ key: String, _ native: EditorTool? = nil)
  {
    self.id = id
    self.title = title
    self.symbol = symbol
    shortcut = key
    self.native = native
  }
}

enum WorkspaceCatalog {
  // Ordered from the observed Photoshop 2026 workspace. Symbols are native SF Symbols.
  static let groups: [[WorkspaceTool]] = [
    [
      .init("move", "Move", "arrow.up.and.down.and.arrow.left.and.right", "V", .move),
      .init("artboard", "Artboard", "square.dashed.inset.filled", "V", .artboard),
    ],
    [
      .init("marquee", "Rectangular Marquee", "rectangle.dashed", "M", .marquee),
      .init("ellipticalMarquee", "Elliptical Marquee", "circle.dashed", "M", .ellipticalMarquee),
      .init("rowMarquee", "Single Row Marquee", "rectangle", ""),
      .init("columnMarquee", "Single Column Marquee", "rectangle.portrait", ""),
    ],
    [
      .init("lasso", "Lasso", "lasso", "L", .lasso),
      .init(
        "polygonLasso", "Polygonal Lasso", "point.topleft.down.curvedto.point.bottomright.up", "L",
        .polygonLasso),
      .init("magneticLasso", "Magnetic Lasso", "lasso", "L", .magneticLasso),
      .init("selectionBrush", "Selection Brush", "paintbrush.pointed", "", .selectionBrush),
    ],
    [
      .init("objectSelection", "Object Selection", "rectangle.dashed.badge.record", "W", .objectSelection),
      .init("quickSelection", "Quick Selection", "paintbrush", "W", .quickSelection),
      .init("magicWand", "Magic Wand", "wand.and.stars", "W", .magicWand),
    ],
    [
      .init("crop", "Crop", "crop", "C", .crop),
      .init("perspectiveCrop", "Perspective Crop", "crop.rotate", "C"),
      .init("slice", "Slice", "scissors", "C"),
    ],
    [.init("frame", "Frame", "rectangle.badge.xmark", "K", .frame)],
    [
      .init("eyedropper", "Eyedropper", "eyedropper", "I", .eyedropper),
      .init("colorSampler", "Color Sampler", "eyedropper.halffull", "I"),
      .init("ruler", "Ruler", "ruler", "I"), .init("count", "Count", "number", "I"),
    ],
    [
      .init("spotHealing", "Spot Healing Brush", "bandage", "J", .spotHealing),
      .init("remove", "Remove", "eraser.badge.sparkles", "J"),
      .init("healing", "Healing Brush", "bandage", "J", .healingBrush),
      .init("patch", "Patch", "rectangle.dashed", "J", .patch),
      .init(
        "contentAwareMove", "Content-Aware Move", "arrow.up.and.down.and.arrow.left.and.right", "J", .contentAwareMove),
      .init("redEye", "Red Eye", "eye", "J", .redEye),
    ],
    [
      .init("brush", "Brush", "paintbrush.pointed", "B", .brush),
      .init("pencil", "Pencil", "pencil", "B", .pencil),
      .init("colorReplacement", "Color Replacement", "paintbrush", "B", .colorReplacement),
      .init("mixerBrush", "Mixer Brush", "paintbrush.pointed.fill", "B", .mixerBrush),
    ],
    [.init("adjustmentBrush", "Adjustment Brush", "paintbrush.pointed.fill", "", .adjustmentBrush)],
    [
      .init("clone", "Clone Stamp", "seal", "S", .cloneStamp),
      .init("patternStamp", "Pattern Stamp", "seal.fill", "S", .patternStamp),
    ],
    [
      .init("historyBrush", "History Brush", "clock.arrow.circlepath", "Y"),
      .init("artHistoryBrush", "Art History Brush", "paintbrush", "Y"),
    ],
    [
      .init("eraser", "Eraser", "eraser", "E", .eraser),
      .init("backgroundEraser", "Background Eraser", "eraser.fill", "E", .backgroundEraser),
      .init("magicEraser", "Magic Eraser", "wand.and.rays", "E", .magicEraser),
    ],
    [
      .init("gradient", "Gradient", "rectangle.lefthalf.filled", "G", .gradient),
      .init("paintBucket", "Paint Bucket", "drop.fill", "G", .paintBucket),
    ],
    [
      .init("blur", "Blur", "drop", "", .blur),
      .init("sharpen", "Sharpen", "triangle", "", .sharpen),
      .init("smudge", "Smudge", "hand.point.up.left", "", .smudge),
    ],
    [
      .init("dodge", "Dodge", "circle.lefthalf.filled", "O", .dodge),
      .init("burn", "Burn", "flame", "O", .burn),
      .init("sponge", "Sponge", "circle.dotted", "O", .sponge),
    ],
    [
      .init("pen", "Pen", "pencil.tip.crop.circle", "P", .pen),
      .init("freeformPen", "Freeform Pen", "pencil.tip", "P", .freeformPen),
      .init(
        "curvaturePen", "Curvature Pen", "point.topleft.down.curvedto.point.bottomright.up", "P", .curvaturePen),
    ],
    [
      .init("text", "Horizontal Type", "textformat", "T", .text),
      .init("verticalType", "Vertical Type", "textformat.alt", "T", .verticalText),
      .init("typeMask", "Type Mask", "t.square", "T"),
    ],
    [
      .init("pathSelection", "Path Selection", "cursorarrow", "A", .pathSelection),
      .init("directSelection", "Direct Selection", "cursorarrow", "A", .directSelection),
    ],
    [
      .init("rectangle", "Rectangle", "rectangle", "U", .rectangle),
      .init("ellipse", "Ellipse", "circle", "U", .ellipse),
      .init("triangle", "Triangle", "triangle", "U", .triangle), .init("polygon", "Polygon", "pentagon", "U", .polygon),
      .init("star", "Star", "star", "U", .star),
      .init("line", "Line", "line.diagonal", "U", .line),
      .init("customShape", "Custom Shape", "star", "U", .customShape),
    ],
    [
      .init("hand", "Hand", "hand.draw", "H", .hand),
      .init("rotateView", "Rotate View", "rotate.right", "R"),
    ],
    [.init("zoom", "Zoom", "magnifyingglass", "Z", .zoom)],
  ]
  static let tools = groups.flatMap { $0 }
  static func tool(_ id: String) -> WorkspaceTool { tools.first { $0.id == id } ?? tools[0] }
}

enum ColorPanelTab: String, CaseIterable, Codable {
  case color = "Color"
  case swatches = "Swatches"
  case gradients = "Gradients"
  case patterns = "Patterns"
}
enum PropertiesTab: String, CaseIterable, Codable {
  case properties = "Properties"
  case adjustments = "Adjustments"
  case libraries = "Libraries"
}
enum LayersTab: String, CaseIterable, Codable {
  case layers = "Layers"
  case channels = "Channels"
  case paths = "Paths"
}

struct WorkspaceGap: Identifiable, Sendable {
  let id: String
  let title: String
  let detail: String
  static let all: [WorkspaceGap] = [
    .init(
      id: "selections", title: "Selections & masks",
      detail:
        "Object/quick selection, magnetic lasso, Select and Mask, Quick Mask and mask Free Transform. Magic Wand has point sampling, tolerance, contiguous/global matching, antialiasing, layer sampling and selection modes; averaged samples and exact Photoshop output remain open. Density/feather, enable/link controls and unlinked mask Move are available."
    ),
    .init(
      id: "retouch", title: "Retouch & brush tools",
      detail:
        "Additional Blur/Sharpen/Smudge blend modes, timed airbrush, Remove, Patch, Pencil, Mixer Brush, history brushes, advanced tips and smoothing. Dodge/Burn tonal controls and Sponge saturation are available. Spot Healing has three automatic repair types; sampled Healing Brush and Clone Stamp share source controls. Pattern, Replace, Diffusion and exact Photoshop output remain open."
    ),
    .init(
      id: "geometry", title: "Transform & vectors",
      detail:
        "Selected-pixel transforms, skew, perspective, warp, Freeform/Curvature Pen, path Free Transform, artboards and advanced shape controls. Whole-layer scale/rotate, image resize and canvas sizing are available."
    ),
    .init(
      id: "layers", title: "Layer structure",
      detail:
        "Layer styles, Fill opacity, smart objects, editable smart filters and channel editing. Groups and clipping masks are implemented; full Photoshop compositing compatibility is still being qualified."
    ),
    .init(
      id: "adjustments", title: "Adjustments & color",
      detail:
        "Levels/Curves eyedroppers, clipping preview, complete Auto Options, Curves freehand and targeted editing; Hue/Saturation prominent-color detection and targeted image sampling, LUTs, professional color modes and proofing. RGB Levels/Curves, Hue/Saturation with feathered ranges and Colorize, Color Balance with all three tones and Preserve Luminosity, histograms, ALV/ACV/AHU presets and automatic tonal corrections are available; exact Photoshop results remain under qualification."
    ),
    .init(
      id: "type", title: "Typography",
      detail:
        "In-canvas type editing, paragraph layout, type on a path, vertical type and advanced typography."
    ),
    .init(
      id: "assets", title: "Libraries & presets",
      detail:
        "Gradient Map supports editable layers and pixel adjustments in 8- and 16-bit documents with Classic, Linear, Perceptual and Stripes methods. Smooth and exact Photoshop pixels remain open. Gradient presets support saved folders, search, rename, duplicate, reorder, GRD import/export and Save Preset. Gradient and Classic Gradient tools provide editable fills, pixel/mask painting and on-canvas color stops. Pattern Fill, Define Pattern, a flat pattern library, PAT import/export and pattern Paint Bucket are available. Pattern Stamp, editable layer styles, Actions/Batch and layer protection are available. Adjustment Brush paints editable local masks. Pattern folders, shared assets and complete preferences remain open."
    ),
    .init(
      id: "ai", title: "Generative image editing",
      detail: "On-device fill, expand, removal, references and high-resolution image models."),
  ]
}
