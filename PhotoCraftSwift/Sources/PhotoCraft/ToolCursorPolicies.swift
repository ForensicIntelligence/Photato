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
