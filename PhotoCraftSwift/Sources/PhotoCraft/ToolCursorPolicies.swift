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
