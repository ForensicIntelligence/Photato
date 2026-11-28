import AppKit
import SwiftUI

enum RawFilmstripPresentation: String, CaseIterable {
  case loupe = "Loupe"
  case grid = "Grid"
}

enum RawGridDetails: String, CaseIterable {
  case image = "Thumbnail Only"
  case fileName = "File Name"
  case marking = "Rating and Color Label"
  case all = "All Information"

  var showsName: Bool { self == .fileName || self == .all }
  var showsMarking: Bool { self == .marking || self == .all }

  func advanced(by step: Int) -> Self {
    let options = Self.allCases
    let index = options.firstIndex(of: self) ?? 0
    return options[(index + step + options.count) % options.count]
  }
}

@MainActor extension RawFilmstripWorkspace {
  func resizeGrid(_ value: Double) {
    guard value.isFinite else { return }
    gridThumbnailSize = min(Self.gridSizeRange.upperBound, max(Self.gridSizeRange.lowerBound, value))
  }

  func openInLoupe(_ id: UUID) {
    guard !busy, !closed, displayedPhotos.contains(where: { $0.id == id }) else { return }
    if selection.contains(id) { activate(id) }
    else { select(id) }
    presentation = .loupe
  }

  func moveGridSelection(_ direction: MoveCommandDirection, columns: Int, extending: Bool) {
    guard presentation == .grid, !busy, !closed, columns > 0 else { return }
    let displayed = displayedPhotos
    guard let index = displayed.firstIndex(where: { $0.id == activeID }) else { return }
    let destination: Int
    switch direction {
    case .left: destination = index - 1
    case .right: destination = index + 1
    case .up: destination = index - columns
    case .down: destination = index + columns
    @unknown default: return
    }
    guard displayed.indices.contains(destination) else { return }
    select(displayed[destination].id, extending: extending)
  }

  func handleHDRMergeKey(_ event: NSEvent) -> Bool {
    guard canMergeHDR(), !(event.window?.firstResponder is NSTextView),
      event.charactersIgnoringModifiers?.lowercased() == "m" else { return false }
    let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
    guard modifiers == .option || modifiers == [.option, .shift] else { return false }
    beginHDRMerge(skipPreview: modifiers.contains(.shift))
    return true
  }

  func handlePresentationKey(_ event: NSEvent) -> Bool {
    guard !busy, !closed, !photos.isEmpty, !(event.window?.firstResponder is NSTextView),
      let key = event.charactersIgnoringModifiers else { return false }
    let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
    if flags.isEmpty && key == "g" {
      presentation = .grid
      return true
    }
    guard presentation == .grid else { return false }
    switch (flags, key) {
    case ([], "."): gridDetails = gridDetails.advanced(by: 1)
    case ([], ","): gridDetails = gridDetails.advanced(by: -1)
    case (.option, "-"): resizeGrid(gridThumbnailSize - 24)
    case (.option, "="), (.option, "+"), ([.option, .shift], "+"): resizeGrid(gridThumbnailSize + 24)
    default: return false
    }
    return true
  }
}
