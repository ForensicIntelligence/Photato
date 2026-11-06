import AppKit
import PhotoCraftCore

/// Positive TextKit coordinates around one logical point insertion coordinate.
/// This is layout space, never the size of an allocated raster.
public final class NativeTypeTextContainer:NSTextContainer {
  public static let pointExtent:CGFloat = 32768
  public var verticalWriting=false
  public var pointAnchored=false
  public var fallbackAlignment:NSTextAlignment = .left
  public override var layoutOrientation:NSLayoutManager.TextLayoutOrientation { verticalWriting ? .vertical:.horizontal }

  public override func lineFragmentRect(forProposedRect proposedRect:NSRect,at characterIndex:Int,
    writingDirection:NSWritingDirection,remaining remainingRect:NSRectPointer?)->NSRect {
    var rect=super.lineFragmentRect(forProposedRect:proposedRect,at:characterIndex,
      writingDirection:writingDirection,remaining:remainingRect)
    guard pointAnchored,!rect.isEmpty else{return rect}
    var alignment=fallbackAlignment
    if let storage=layoutManager?.textStorage,characterIndex<storage.length {
      alignment=(storage.attribute(.paragraphStyle,at:characterIndex,effectiveRange:nil)as?NSParagraphStyle)?.alignment ?? alignment
      if alignment == .justified,let data=storage.attribute(NativeParagraphFormatting.key,at:characterIndex,effectiveRange:nil)as?Data,
        let paragraph=try?JSONDecoder().decode(TypeParagraph.self,from:data) {
        if paragraph.formatting?.lastLine == .center {alignment = .center}
        if paragraph.formatting?.lastLine == .right {alignment = .right}
      }
    }
    rect.size.width=Self.pointExtent
    rect.origin.x=alignment == .right ? 0:alignment == .center ? Self.pointExtent/2:Self.pointExtent
    remainingRect?.pointee = .zero
    return rect
  }
}

extension NativeTextLayout {
  public static func usesPointAnchoring(_ text:TextContent)->Bool {
    guard let type=text.typography,type.kind == .point,type.geometry?.isActive != true else{return false}
    return type.defaultParagraph.alignment != .left || type.runs.contains{$0.paragraph.alignment != .left}
  }
  public static func pointAlignment(_ paragraph:TypeParagraph)->NSTextAlignment {
    switch paragraph.alignment {
    case .left:return .left
    case .center:return .center
    case .right:return .right
    case .justified:
      if paragraph.formatting?.lastLine == .center{return .center}
      if paragraph.formatting?.lastLine == .right{return .right}
      return .left
    }
  }
}
