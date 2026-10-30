import Foundation
import PhotoCraftCore

public struct RenderedAction: Sendable {
  public let command: Command
  /// Only present when successful playback performed Copy or Cut.
  public let clipboard: ClipboardContent?
  public let lastIndexedPalette: [PaletteColor]?
}

/// Compositor operations and ordinary Core commands share one atomic playback.
/// The private clipboard never accesses the platform pasteboard.
public enum RecordedActionRenderer {
  public static func prepare(_ action: RecordedAction, in source: CraftDocument,
    clipboard initial: ClipboardContent? = nil, masters: [CraftDocument] = [],
    validateClipboard: @escaping @Sendable (ClipboardContent) throws -> Void = { _ in },
    validate: @Sendable (CraftDocument) throws -> Void = { _ in }) throws -> RenderedAction {
    try validate(source)
    if let initial { try validateClipboard(initial) }
    var result = source, clipboard = initial, wroteClipboard = false
    var lastIndexedPalette: [PaletteColor]?
    try action.apply(to: &result, resolve: { operation, document in
      switch operation {
      case .retouch(let request):
        try RetouchPreparation.command(request, in: document, sources: masters).apply(to: &document)
      case .inkMode(var request):
        // Recorded conversion is portable: destination channel identities belong
        // to the playback document, not the document used to record the action.
        if request.kind == .multichannel { request.plateIDs = InkModeRequest(.multichannel, document: document).plateIDs }
        try request.command(in: document).apply(to: &document)
      case .documentMode(let request):
        try DocumentModeInput.command(request, in: document).apply(to: &document)
      case .restrictedMode(let request):
        try request.command(in: document, masters: masters.filter { $0.id != source.id }).apply(to: &document)
        if case .indexed(let raster) = document.restrictedMode { lastIndexedPalette = raster.palette }
      case .clipboardCopy(let targets, let merged):
        let ids = try Set(targets.map { try $0.resolve(in: document) })
        let content = try ClipboardRenderer.copy(document, layerIDs: ids, merged: merged)
        try validateClipboard(content); clipboard = content
        wroteClipboard = true
      case .clipboardCut(let targets, let background):
        let ids = try targets.map { try $0.resolve(in: document) }
        let content = try ClipboardRenderer.copy(document, layerIDs: Set(ids), merged: false)
        try validateClipboard(content)
        try Command.cut(ids, background: background).apply(to: &document)
        clipboard = content; wroteClipboard = true
      case .clipboardPaste(let placement, let center):
        guard let clipboard else { throw CraftError.invalid("This action requires an initial clipboard image or an earlier Copy/Cut step.") }
        try ClipboardRenderer.pasteCommand(clipboard, into: document, placement: placement, center: center).apply(to: &document)
      default: return false
      }
      return true
    }, validate: validate)
    return RenderedAction(command: .preparedAction(.init(source: source, result: result, title: "Play \(action.name)")),
      clipboard: wroteClipboard ? clipboard : nil, lastIndexedPalette: lastIndexedPalette)
  }
}
