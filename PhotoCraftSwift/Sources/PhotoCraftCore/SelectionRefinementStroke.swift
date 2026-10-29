import Foundation

public struct SelectionRefinementStroke: Codable, Equatable, Sendable {
  public enum Tool: String, Codable, CaseIterable, Sendable { case add, subtract, refine, eraseRefinement, lassoAdd, lassoSubtract }
  public var tool: Tool
  public var size: Double
  public var hardness: Double
  public var points: [[Double]]
  public init(tool: Tool = .add,size: Double = 30,hardness: Double = 0.8,points: [[Double]] = []) {
    self.tool = tool; self.size = size; self.hardness = hardness; self.points = points
  }
  public func validate() throws {
    guard size.isFinite, (1...5000).contains(size), hardness.isFinite, (0...1).contains(hardness),
      !points.isEmpty, points.count <= 4096, points.allSatisfy({ $0.count == 2 && $0.allSatisfy { $0.isFinite && abs($0) <= 1_000_000 } }) else { throw CraftError.invalid("Invalid refinement brush stroke.") }
  }
}
