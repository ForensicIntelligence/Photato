import Foundation
import PhotoCraftCore

/// Licensed source-format fields map to the existing editable native artboard.
/// Child layers already use document coordinates; they must not be placed twice.
enum PcraftArtboards {
  static func read(_ node:PcraftNode) throws -> (Artboard,IntRect) {
    try node.keys("rect background preset")
    let rect = try node.field("rect");try rect.keys("x0 y0 x1 y1")
    let values = try ["x0","y0","x1","y1"].map { try rect.field($0).integer() }
    guard values.allSatisfy({Int32(exactly:$0) != nil}),values[2] > values[0],values[3] > values[1] else { throw rect.invalid }
    let bounds = IntRect(x:values[0],y:values[1],width:values[2]-values[0],height:values[3]-values[1])
    let field = try node.field("background"),background:Pixel
    switch field.value {
    case .string("white"):background = .white
    case .string("black"):background = .black
    case .string("transparent"):background = .clear
    case .object(let fields) where fields.count == 1 && fields["custom"] != nil:
      background = try PcraftFills.color(field.field("custom"))
    default:throw field.unsupported("Unknown artboard background.")
    }
    let board = Artboard(width:bounds.width,height:bounds.height,background:background,
      preset:try node.optional("preset")?.string() ?? "")
    try board.validate();return(board,bounds)
  }
}
