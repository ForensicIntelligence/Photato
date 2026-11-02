import AppKit

/// Show app-owned windows immediately. AppKit's default transition can keep a
/// blocking animation worker alive while WindowServer is suspended or locked,
/// eventually preventing document I/O and recovery work from being scheduled.
@MainActor class PhotatoWindow: NSWindow {
  override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
    backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
    super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    animationBehavior = .none
  }
}

@MainActor class PhotatoPanel: NSPanel {
  override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
    backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
    super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    animationBehavior = .none
  }
}
