import AppKit
import PhotoCraftCore

extension SelectMaskWorkspace {
  func resolvedTool(alternate: Bool) -> SelectionRefinementStroke.Tool {
    guard alternate else { return tool }
    switch tool {
    case .add: return .subtract
    case .subtract: return .add
    case .refine: return .eraseRefinement
    case .eraseRefinement: return .refine
    case .lassoAdd: return .lassoSubtract
    case .lassoSubtract: return .lassoAdd
    }
  }
}

extension LiquifyWorkspace {
  func resolvedTool(alternate: Bool) -> LiquifyTool {
    guard alternate else { return tool }
    switch tool {
    case .freeze: return .thaw
    case .thaw: return .freeze
    case .twirlCw: return .twirlCcw
    case .pucker: return .bloat
    case .bloat: return .pucker
    default: return tool
    }
  }
}

// Pointer semantics are shared with the captured LightingPreview gesture modes.
extension ToolCursor {
  static func lighting(modifiers:NSEvent.ModifierFlags,hasHandle:Bool,canDuplicate:Bool)->Self {
    guard hasHandle else{return .arrow}
    if modifiers.contains(.option) && !canDuplicate{return .unavailable}
    return .symbol(modifiers.contains(.option) ? "plus.square.on.square":"arrow.up.and.down.and.arrow.left.and.right",modifiers.contains(.shift) ? .constrain:nil)
  }
}

extension ToolCursor {
  static func colorRangeSampler(_ sampler:ColorRangeSampler,modifiers:NSEvent.ModifierFlags)->ColorRangeSampler {
    if modifiers.contains(.option) {return .subtract};if modifiers.contains(.shift) {return .add};return sampler
  }
  static func colorRange(_ sampler:ColorRangeSampler)->Self {.symbol("eyedropper",sampler == .add ? .add:sampler == .subtract ? .subtract:nil)}
}

extension ToolCursor {
  static func magnetic(modifiers:NSEvent.ModifierFlags,mode:SelectionMode,active:Bool,alternateReady:Bool=true,nearStart:Bool=false,precision:Bool=false)->Self {
    if active && (nearStart || modifiers.contains(.command)) {return .symbol("checkmark.circle")}
    if active && alternateReady && modifiers.contains(.option) {return .selection("pencil.tip",mode)}
    if precision && !active {return .crosshair}
    return .selection("lasso",mode)
  }
}

extension ToolCursor {
  static func meshWarp(overControl: Bool, dragging: Bool) -> Self {
    if dragging { return .closedHand }
    return overControl ? .openHand : .arrow
  }

  static func cylinderConstrained(_ handle: CylinderHandle?, flags: NSEvent.ModifierFlags) -> Bool {
    (handle == .topRight || handle == .bottomLeft) && flags.contains(.shift)
  }

  static func cylinderWarp(_ handle: CylinderHandle?, dragging: Bool, flags: NSEvent.ModifierFlags) -> Self {
    switch handle {
    case .topRight, .bottomLeft:
      .symbol("arrow.up.right.and.arrow.down.left", cylinderConstrained(handle, flags: flags) ? .constrain : nil)
    case .topRim, .bottomRim: .symbol("arrow.up.and.down")
    case .wrap: .symbol("arrow.left.and.right")
    case .body: dragging ? .closedHand : .openHand
    case nil: .arrow
    }
  }

  static func artworkTransform(_ draft: TransformDraft, handle: Int, flags: NSEvent.ModifierFlags) -> Self {
    if handle == -1 { return .symbol("arrow.up.and.down.and.arrow.left.and.right", flags.contains(.shift) ? .constrain : nil) }
    if handle == 8 { return .symbol("arrow.triangle.2.circlepath", flags.contains(.shift) ? .constrain : nil) }
    let position = draft.handles[handle]
    let angle = atan2(position.y - draft.centerY, position.x - draft.centerX)
    let sector = (Int((angle * 4 / .pi).rounded()) + 4) % 4
    let symbols = ["arrow.left.and.right", "arrow.up.left.and.arrow.down.right", "arrow.up.and.down",
                   "arrow.up.right.and.arrow.down.left"]
    var effective = flags
    if draft.proportional != flags.contains(.shift) { effective.insert(.shift) }
    else { effective.remove(.shift) }
    return .symbol(symbols[sector], geometry(effective))
  }

  static func selectionTransform(_ mode:SelectionTransformMode,handle:Int,flags:NSEvent.ModifierFlags,proportional:Bool=true)->Self {
    if handle == -1{return .symbol("arrow.up.and.down.and.arrow.left.and.right",flags.contains(.shift) ? .constrain:nil)}
    switch mode {
    case .free,.scale:
      var effective=flags
      if proportional != flags.contains(.shift){effective.insert(.shift)}else{effective.remove(.shift)}
      return .symbol("arrow.up.left.and.arrow.down.right",geometry(effective))
    case .rotate:return .symbol("arrow.triangle.2.circlepath",flags.contains(.shift) ? .constrain:nil)
    case .skew:return .symbol("rectangle.on.rectangle.angled")
    case .distort:return .symbol("arrow.up.and.down.and.arrow.left.and.right",geometry(flags))
    case .perspective:return .symbol("viewfinder")
    }
  }
}
