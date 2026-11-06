import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

@MainActor @Observable final class TypeEditingDraft {
  let id = UUID()
  let baseline: CraftDocument
  var layer: Layer
  let isNew: Bool
  var content: TextContent
  init(layer: Layer, content: TextContent, baseline: CraftDocument, isNew: Bool) {
    self.layer = layer; self.content = content; self.baseline = baseline; self.isNew = isNew
  }
}
extension EditorStore {
  var editableType: TextContent? {
    if let draft = typeEditingDraft { return draft.content }
    if case .text(let text) = activeLayer?.content { return text.promoted(dpi: document.pixelsPerInch) }
    return nil
  }
  var canEditType: Bool {
    !editingComponent && !editingMask && (typeEditingDraft != nil ||
      (canBeginLayerCreation && activeLayer.map { !document.isImageLocked($0.id) } == true))
  }
  func beginType(_ layer: Layer) {
    guard canBeginLayerCreation, !editingComponent, !editingMask, !document.isImageLocked(layer.id),
      case .text(let content) = layer.content else { return }
    select(layer.id)
    typeEditingDraft = TypeEditingDraft(layer: layer, content: content.promoted(dpi: document.pixelsPerInch), baseline: document, isNew: false)
    render()
  }
  func beginType(at start: CGPoint, end: CGPoint) {
    guard canBeginLayerCreation, !editingComponent, !editingMask else { return }
    if hypot(end.x - start.x, end.y - start.y) < 4 {
      if let layer=typeLayer(at:start){beginType(layer);return}
    }
    var text = TextContent(text: "", fontName: fontName, size: fontSize, color: brush.color)
    var type = TextTypography();if tool == .verticalText{type.orientation = .vertical};type.defaultStyle.font = fontName
    type.defaultStyle.size = fontSize; type.defaultStyle.color = brush.color
    let box = abs(end.x - start.x) >= 4 && abs(end.y - start.y) >= 4
    if box { type.kind = .paragraph; text.layoutWidth = min(32768, Int(abs(end.x - start.x))); text.layoutHeight = min(32768, Int(abs(end.y - start.y))) }
    text.typography = type
    var layer = Layer(name: "Type", content: .text(text))
    layer.x = Int(box ? min(start.x, end.x) : start.x); layer.y = Int(box ? min(start.y, end.y) : start.y)
    typeEditingDraft = TypeEditingDraft(layer: layer, content: text, baseline: document, isNew: true)
    render()
  }
  @discardableResult func finishType(cancel: Bool = false) -> Bool {
    guard let draft = typeEditingDraft else { return true }
    if !cancel { typeEditor?.unmarkText(); if typeEditor?.updateDraft() == false { return false } }
    guard cancel || draft.baseline == document else { error = "The document changed while text was being edited. Cancel this draft and reopen it."; return false }
    if cancel || (draft.isNew && draft.content.text.isEmpty) { typeEditingDraft = nil; retireTypeEditor(); render(); return true }
    do {
      try draft.content.validate()
      let metrics=try NativeTextLayout.metrics(draft.content,dpi:document.pixelsPerInch)
      if draft.isNew { draft.layer.name = String(draft.content.text.prefix(32)) }
      let command:Command
      if draft.isNew {draft.layer.content = .text(draft.content);if metrics.origin.x != 0 || metrics.origin.y != 0{let transform=draft.layer.coordinateTransform * .translation(metrics.origin.x,metrics.origin.y);draft.layer.x=0;draft.layer.y=0;draft.layer.affine=transform};command = .addLayer(draft.layer)}
      else {command=try ShapedTextLayout.replacement(draft.layer,content:draft.content,document:document)}
      typeEditingDraft = nil
      do { try executeEditorCommand(command) }
      catch { typeEditingDraft = draft; throw error }
      retireTypeEditor()
      return true
    } catch { self.error = error.localizedDescription; return false }
  }
  private func retireTypeEditor() {
    guard let editor = typeEditor else { return }
    if editor.window?.firstResponder === editor { editor.window?.makeFirstResponder(editor.superview) }
    (editor as?CanvasPathTypeEditor)?.stopPathPreview()
    editor.delegate = nil; editor.isEditable = false
    editor.undoManager?.removeAllActions(); typeEditor = nil
  }
  func formatType(paragraph: Bool = false, _ change: (inout TypeStyle, inout TypeParagraph) -> Void) {
    guard canEditType else { return }
    if let typeEditor { typeEditor.format(paragraph: paragraph, change); return }
    guard var text = editableType, var type = text.typography, let id = activeLayer?.id else { return }
    change(&type.defaultStyle, &type.defaultParagraph)
    for i in type.runs.indices { var run = type.runs[i]; change(&run.style, &run.paragraph); type.runs[i] = run }
    text.typography = type
    do { _ = try NativeTextLayout.metrics(text, dpi: document.pixelsPerInch); if let layer=document.layers.first(where:{$0.id==id}){perform(try ShapedTextLayout.replacement(layer,content:text,document:document))} }
    catch { self.error = error.localizedDescription }
  }
  func setTypeFrame(_ kind: TextTypography.Kind, width: Int? = nil, height: Int? = nil) {
    guard canEditType, var text = editableType else { return }
    text.typography?.kind = kind
    if kind == .paragraph { text.layoutWidth = width ?? text.layoutWidth ?? max(1, document.width / 2); text.layoutHeight = height ?? text.layoutHeight ?? max(1, document.height / 2) }
    else { text.layoutWidth = nil; text.layoutHeight = nil }
    if var frame=text.typography?.sourceFrame {
      frame.kind=kind == .paragraph ? .box:.point
      if let width{frame.width=Double(width)};if let height{frame.height=Double(height)}
      text.typography?.sourceFrame=frame
    }
    do {
      _ = try NativeTextLayout.metrics(text, dpi: document.pixelsPerInch)
      if let draft = typeEditingDraft { draft.content = text; typeEditor?.configureContainer(); typeEditor?.superview?.needsLayout = true }
      else if let id = activeLayer?.id { if let layer=document.layers.first(where:{$0.id==id}){perform(try ShapedTextLayout.replacement(layer,content:text,document:document))} }
    } catch { self.error = error.localizedDescription }
  }
}

@MainActor class CanvasTypeEditor: NSTextView, NSTextViewDelegate, @preconcurrency NSLayoutManagerDelegate {
  weak var store: EditorStore?
  let draftID: UUID
  private let nativeStorage: NSTextStorage
  private let typingUndo = UndoManager()
  private var pointDrawingOrigin = NSPoint.zero
  private var applyingParagraphLayout = false
  override var textContainerOrigin:NSPoint {
    // NSTextView centres/right-aligns its oversized container against the view.
    // Point layout already anchors each line, so applying that offset again
    // would move the insertion point outside the visible editor.
    if (textContainer as? NativeTypeTextContainer)?.pointAnchored == true {
      return NSPoint(x:-pointDrawingOrigin.x,y:-pointDrawingOrigin.y)
    }
    return super.textContainerOrigin
  }
  override var undoManager: UndoManager? { typingUndo }
  func undoManager(for view: NSTextView) -> UndoManager? { typingUndo }
  init(store: EditorStore, draft: TypeEditingDraft) throws {
    self.store = store; draftID = draft.id
    let storage = NSTextStorage(), layout = NSLayoutManager(), container = NativeTypeTextContainer(size: NSSize(width: 32768, height: 32768))
    nativeStorage = storage
    storage.addLayoutManager(layout); layout.addTextContainer(container)
    super.init(frame: .zero, textContainer: container)
    allowsUndo = true; isRichText = true; importsGraphics = false
    isAutomaticQuoteSubstitutionEnabled = false; isAutomaticDashSubstitutionEnabled = false
    isAutomaticTextReplacementEnabled = false; isAutomaticSpellingCorrectionEnabled = false
    drawsBackground = false; insertionPointColor = .systemBlue
    textContainerInset = .zero; textContainer?.lineFragmentPadding = 0
    textStorage?.setAttributedString(try NativeTextLayout.attributed(draft.content, dpi: store.document.pixelsPerInch))
    typingAttributes = try NativeTextLayout.attributes(draft.content.typography!.defaultStyle, paragraph: draft.content.typography!.defaultParagraph, dpi: store.document.pixelsPerInch,orientation:draft.content.typography!.writingOrientation)
    delegate = self; layout.delegate = self; configureContainer()
    setAccessibilityLabel("Edit type on canvas")
  }
  required init?(coder: NSCoder) { nil }
  func layoutManager(_ layoutManager:NSLayoutManager,didCompleteLayoutFor textContainer:NSTextContainer?,atEnd layoutFinishedFlag:Bool) {
    guard !applyingParagraphLayout,let textContainer,let storage=layoutManager.textStorage,
      let store else{return}
    applyingParagraphLayout = true
    defer{applyingParagraphLayout = false}
    NativeTextLayout.applyParagraphFormatting(storage:storage,manager:layoutManager,container:textContainer,dpi:store.document.pixelsPerInch)
  }
  func configureContainer() {
    guard let draft = store?.typeEditingDraft, draft.id == draftID else { return }
    let vertical=draft.content.typography?.writingOrientation == .vertical
    let orientation:NSLayoutManager.TextLayoutOrientation=vertical ? .vertical:.horizontal
    if layoutOrientation != orientation{setLayoutOrientation(orientation)}
    isHorizontallyResizable = false; isVerticallyResizable = false
    textContainer?.widthTracksTextView = false; textContainer?.heightTracksTextView = false
    let paragraph=draft.content.typography?.kind == .paragraph,frame=draft.content.typography?.sourceFrame
    let width=paragraph ? (frame?.kind == .box ? frame!.width:Double(draft.content.layoutWidth ?? 1)):32768
    let height=paragraph ? (frame?.kind == .box ? frame!.height:Double(draft.content.layoutHeight ?? 1)):32768
    let anchored=NativeTextLayout.usesPointAnchoring(draft.content)
    if let container=textContainer as?NativeTypeTextContainer {
      container.pointAnchored=anchored;container.verticalWriting=vertical
      container.fallbackAlignment=(typingAttributes[.paragraphStyle]as?NSParagraphStyle)?.alignment
        ?? NativeTextLayout.pointAlignment(draft.content.typography?.defaultParagraph ?? .init())
    }
    textContainer?.containerSize = NSSize(width:anchored ? 65536:(vertical ? height:width),height:vertical ? width:height)
    let metrics=anchored ? try?NativeTextLayout.editingMetrics(draft.content,dpi:store?.document.pixelsPerInch ?? 72):nil
    pointDrawingOrigin=NSPoint(x:metrics?.layoutOrigin.x ?? 0,y:metrics?.layoutOrigin.y ?? 0)
  }
  @discardableResult func updateDraft() -> Bool {
    guard let store, let draft = store.typeEditingDraft, draft.id == draftID, let textStorage else { return false }
    do { draft.content = try NativeTextLayout.content(textStorage, template: draft.content, dpi: store.document.pixelsPerInch); return true }
    catch { store.error = error.localizedDescription; return false }
  }
  func textDidChange(_ notification: Notification) { if updateDraft() { configureContainer() }; superview?.needsLayout = true }
  func textViewDidChangeSelection(_ notification: Notification) { store?.typeSelectionRevision += 1 }
  override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
    guard let replacementString else { return super.shouldChangeText(in: affectedCharRange, replacementString: nil) }
    guard string.utf16.count - affectedCharRange.length + replacementString.utf16.count <= 100_000 else { NSSound.beep(); return false }
    return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
  }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 || ([36, 76].contains(event.keyCode) && event.modifierFlags.contains(.command)) {
      if store?.finishType() == true { window?.makeFirstResponder(superview) }
      return
    }
    super.keyDown(with: event)
  }
  func format(paragraph: Bool, _ change: (inout TypeStyle, inout TypeParagraph) -> Void) {
    guard let store, let textStorage else { return }
    let selection = selectedRange()
    var range = selection
    if paragraph, textStorage.length > 0 { range = (string as NSString).paragraphRange(for: range) }
    do {
      if range.length == 0 {
        var (style, para) = NativeTextLayout.styles(typingAttributes, dpi: store.document.pixelsPerInch)
        change(&style, &para); try style.validate(); try para.validate()
        typingAttributes = try NativeTextLayout.attributes(style, paragraph: para, dpi: store.document.pixelsPerInch,orientation:store.editableType?.typography?.writingOrientation ?? .horizontal)
        if let draft = store.typeEditingDraft, string.isEmpty { draft.content.typography?.defaultStyle = style; draft.content.typography?.defaultParagraph = para }
      } else {
        let replacement = NSMutableAttributedString(attributedString: textStorage.attributedSubstring(from: range))
        var failure: Error?
        replacement.enumerateAttributes(in: NSRange(location: 0, length: replacement.length)) { attrs, local, stop in
          do {
            var (style, para) = NativeTextLayout.styles(attrs, dpi: store.document.pixelsPerInch)
            change(&style, &para); try style.validate(); try para.validate()
            replacement.setAttributes(try NativeTextLayout.attributes(style, paragraph: para, dpi: store.document.pixelsPerInch,orientation:store.editableType?.typography?.writingOrientation ?? .horizontal), range: local)
          } catch { failure = error; stop.pointee = true }
        }
        if let failure { throw failure }
        if shouldChangeText(in: range, replacementString: replacement.string) {
          textStorage.replaceCharacters(in: range, with: replacement); didChangeText()
          setSelectedRange(selection)
        }
      }
      store.typeSelectionRevision += 1
    } catch { store.error = error.localizedDescription }
  }
}

extension CraftCanvas {
  func synchronizeTypeEditor() {
    guard let draft = store.typeEditingDraft else {
      typeOverlay?.delegate = nil; typeOverlay?.removeFromSuperview(); typeOverlay = nil; store.typeEditor = nil; return
    }
    let pathEditing=CanvasPathTypeEditor.supports(draft.content)
    if typeOverlay?.draftID != draft.id || (typeOverlay is CanvasPathTypeEditor) != pathEditing {
      typeOverlay?.delegate = nil; typeOverlay?.removeFromSuperview()
      do {
        let editor:CanvasTypeEditor = pathEditing ? try CanvasPathTypeEditor(store:store,draft:draft):try CanvasTypeEditor(store:store,draft:draft)
        typeOverlay = editor; store.typeEditor = editor; addSubview(editor)
        window?.makeFirstResponder(editor)
      } catch { store.error = error.localizedDescription; _ = store.finishType(cancel: true); return }
    }
    guard let editor = typeOverlay else { return }
    if let pathEditor=editor as?CanvasPathTypeEditor {
      let logical:Transform2D
      if draft.isNew{logical=draft.layer.coordinateTransform}
      else if let source=try?draft.layer.sourceTypeTransform(){logical=source}
      else{let old=draft.layer.typeContent.flatMap{try?NativeTextLayout.metrics($0,dpi:store.document.pixelsPerInch).origin} ?? .init(0,0);logical=draft.layer.coordinateTransform * .translation(-old.x,-old.y)}
      let transform=Transform2D.translation(imageRect.minX,imageRect.minY) * .scale(Double(scale),Double(scale)) * logical
      pathEditor.frame=bounds;pathEditor.bounds=NSRect(origin:.zero,size:bounds.size)
      pathEditor.sourceToView=CGAffineTransform(a:transform.a,b:transform.b,c:transform.c,d:transform.d,tx:transform.tx,ty:transform.ty)
      pathEditor.configureContainer();return
    }
    let metrics = try? NativeTextLayout.editingMetrics(draft.content, dpi: store.document.pixelsPerInch)
    let width = draft.content.typography?.kind == .paragraph ? draft.content.layoutWidth ?? 1 : max(400, (metrics?.width ?? 1) + 100)
    let height = draft.content.typography?.kind == .paragraph ? draft.content.layoutHeight ?? 1 : max(100, (metrics?.height ?? 1) + 60)
    let sourceTransform=try? draft.layer.sourceTypeTransform()
    let origin:(x:Double,y:Double)
    if let sourceTransform { origin=sourceTransform.point(metrics?.origin.x ?? 0,metrics?.origin.y ?? 0) }
    else {
      let oldOrigin=draft.layer.typeContent.flatMap{try?NativeTextLayout.metrics($0,dpi:store.document.pixelsPerInch).origin} ?? .init(0,0)
      origin=draft.layer.coordinateTransform.point((metrics?.origin.x ?? 0)-oldOrigin.x,(metrics?.origin.y ?? 0)-oldOrigin.y)
    }
    editor.frame = NSRect(origin: viewPoint(CGPoint(x: origin.x, y: origin.y)), size: NSSize(width: Double(width) * scale, height: Double(height) * scale))
    let vertical=draft.content.typography?.writingOrientation == .vertical
    editor.bounds = NSRect(x: 0, y: 0, width: vertical ? height:width, height: vertical ? width:height)
    editor.configureContainer()
  }
}

@MainActor extension AppDelegate {
  @objc func convertTypeShape() {
    guard let store, let kind = store.editableType?.typography?.kind else { return }
    store.setTypeFrame(kind == .point ? .paragraph : .point)
  }
  @objc func rasterizeType() { if store?.editableType != nil { store?.rasterize() } }
}
