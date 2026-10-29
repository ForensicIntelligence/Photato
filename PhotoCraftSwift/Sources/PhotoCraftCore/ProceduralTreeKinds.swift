import Foundation

extension ProceduralGeometry {
  enum Leaf {case none,round,oval,needle,heart,blossom,long,frond}
  enum Habit {case branching,conifer,palm,bamboo}
  struct TreeKind {
    var name:String,habit:Habit,levels:Int,children:Int,spread:Float,ratio:Float,trunk:Float,droop:Float,wiggle:Float,thick:Float,leaf:Leaf,leafColor:SIMD3<Float>,bark:SIMD3<Float>,accent:SIMD3<Float>?
    init(_ name:String,_ habit:Habit,_ levels:Int,_ children:Int,_ spread:Float,_ ratio:Float,_ trunk:Float,_ droop:Float,_ wiggle:Float,_ thick:Float,_ leaf:Leaf,_ leafColor:SIMD3<Float>,_ bark:SIMD3<Float>,_ accent:SIMD3<Float>?) {
      self.name=name;self.habit=habit;self.levels=levels;self.children=children;self.spread=spread;self.ratio=ratio;self.trunk=trunk;self.droop=droop;self.wiggle=wiggle;self.thick=thick;self.leaf=leaf;self.leafColor=leafColor;self.bark=bark;self.accent=accent
    }
  }
  static let BROWN=SIMD3<Float>(0.36,0.25,0.16),GREY_BARK=SIMD3<Float>(0.45,0.42,0.38),GREEN=SIMD3<Float>(0.24,0.52,0.16),DARK_GREEN=SIMD3<Float>(0.12,0.36,0.14)
  static let trees:[TreeKind]=[
    TreeKind("Oak", .branching, 5, 3, 38.0, 0.72, 0.35, 0.05, 0.35, 0.035, .round, GREEN, BROWN, nil),
    TreeKind("Maple", .branching, 5, 3, 34.0, 0.74, 0.32, 0.0, 0.25, 0.03, .heart, SIMD3(0.3, 0.55, 0.15), BROWN, nil),
    TreeKind("Pine", .conifer, 3, 2, 70.0, 0.5, 0.15, 0.25, 0.1, 0.025, .needle, DARK_GREEN, BROWN, nil),
    TreeKind("Palm", .palm, 1, 9, 0.0, 0.0, 0.85, 0.0, 0.15, 0.022, .frond, SIMD3(0.25, 0.5, 0.18), SIMD3(0.55, 0.45, 0.32), nil),
    TreeKind("Birch", .branching, 5, 2, 28.0, 0.75, 0.4, 0.1, 0.3, 0.02, .oval, SIMD3(0.45, 0.65, 0.2), SIMD3(0.88, 0.86, 0.82), nil),
    TreeKind("Weeping Willow", .branching, 5, 3, 40.0, 0.78, 0.3, 0.9, 0.2, 0.035, .long, SIMD3(0.45, 0.62, 0.22), GREY_BARK, nil),
    TreeKind("Cherry Blossom", .branching, 5, 3, 42.0, 0.7, 0.3, 0.0, 0.45, 0.03, .blossom, SIMD3(0.98, 0.75, 0.82), SIMD3(0.3, 0.2, 0.17), nil),
    TreeKind("Bamboo", .bamboo, 1, 5, 6.0, 0.0, 1.0, 0.0, 0.05, 0.012, .long, SIMD3(0.35, 0.6, 0.2), SIMD3(0.55, 0.65, 0.3), nil),
    TreeKind("Cypress", .branching, 5, 3, 10.0, 0.8, 0.1, -0.1, 0.1, 0.02, .needle, DARK_GREEN, BROWN, nil),
    TreeKind("Baobab", .branching, 3, 4, 50.0, 0.55, 0.65, 0.0, 0.3, 0.09, .round, SIMD3(0.35, 0.55, 0.2), SIMD3(0.55, 0.47, 0.4), nil),
    TreeKind("Ginkgo", .branching, 4, 3, 30.0, 0.72, 0.35, 0.0, 0.2, 0.025, .heart, SIMD3(0.75, 0.75, 0.2), GREY_BARK, nil),
    TreeKind("Spruce", .conifer, 3, 2, 80.0, 0.45, 0.1, 0.45, 0.08, 0.025, .needle, SIMD3(0.1, 0.3, 0.2), BROWN, nil),
    TreeKind("Bare Winter Tree", .branching, 6, 2, 34.0, 0.74, 0.3, 0.05, 0.35, 0.03, .none, GREEN, SIMD3(0.3, 0.25, 0.22), nil),
    TreeKind("Apple", .branching, 5, 3, 46.0, 0.68, 0.3, 0.1, 0.4, 0.03, .round, GREEN, BROWN, SIMD3(0.85, 0.1, 0.1)),
    TreeKind("Acacia", .branching, 4, 3, 55.0, 0.75, 0.45, -0.25, 0.25, 0.03, .round, SIMD3(0.35, 0.5, 0.18), BROWN, nil),
    TreeKind("Poplar", .branching, 5, 3, 12.0, 0.8, 0.15, -0.15, 0.1, 0.025, .oval, SIMD3(0.3, 0.55, 0.15), GREY_BARK, nil),
    TreeKind("Elm", .branching, 5, 2, 24.0, 0.8, 0.3, 0.15, 0.25, 0.032, .oval, GREEN, BROWN, nil),
    TreeKind("Magnolia", .branching, 4, 3, 40.0, 0.7, 0.3, 0.0, 0.3, 0.03, .blossom, SIMD3(0.98, 0.9, 0.92), SIMD3(0.35, 0.28, 0.25), SIMD3(0.85, 0.5, 0.65)),
    TreeKind("Banana", .palm, 1, 7, 0.0, 0.0, 0.6, 0.0, 0.05, 0.04, .frond, SIMD3(0.45, 0.7, 0.2), SIMD3(0.5, 0.6, 0.3), nil),
    TreeKind("Bonsai", .branching, 4, 3, 60.0, 0.6, 0.45, 0.2, 0.7, 0.05, .round, DARK_GREEN, SIMD3(0.4, 0.3, 0.22), nil),
    TreeKind("Jacaranda", .branching, 5, 3, 44.0, 0.72, 0.3, 0.0, 0.35, 0.03, .blossom, SIMD3(0.6, 0.45, 0.85), BROWN, nil),
    TreeKind("Autumn Maple", .branching, 5, 3, 34.0, 0.74, 0.32, 0.0, 0.25, 0.03, .heart, SIMD3(0.85, 0.3, 0.1), BROWN, nil),
    TreeKind("Golden Autumn", .branching, 5, 3, 36.0, 0.72, 0.33, 0.05, 0.3, 0.03, .round, SIMD3(0.9, 0.7, 0.15), BROWN, nil),
    TreeKind("Olive", .branching, 4, 3, 48.0, 0.68, 0.35, 0.1, 0.6, 0.04, .long, SIMD3(0.5, 0.58, 0.42), GREY_BARK, SIMD3(0.25, 0.28, 0.12)),
    TreeKind("Fir", .conifer, 3, 2, 75.0, 0.5, 0.12, 0.15, 0.05, 0.025, .needle, SIMD3(0.12, 0.38, 0.22), BROWN, nil),
    TreeKind("Cedar", .conifer, 3, 3, 88.0, 0.6, 0.2, 0.0, 0.15, 0.03, .needle, SIMD3(0.2, 0.4, 0.25), BROWN, nil),
    TreeKind("Lemon", .branching, 4, 3, 45.0, 0.68, 0.3, 0.05, 0.35, 0.03, .oval, DARK_GREEN, BROWN, SIMD3(0.98, 0.88, 0.15)),
    TreeKind("Wisteria", .branching, 5, 3, 45.0, 0.72, 0.3, 0.7, 0.3, 0.03, .blossom, SIMD3(0.7, 0.55, 0.9), SIMD3(0.35, 0.3, 0.27), nil),
    TreeKind("Young Sapling", .branching, 3, 2, 30.0, 0.7, 0.45, 0.0, 0.2, 0.015, .oval, SIMD3(0.4, 0.7, 0.2), SIMD3(0.45, 0.35, 0.22), nil),
    TreeKind("Dead Tree", .branching, 5, 2, 45.0, 0.68, 0.4, 0.1, 0.8, 0.035, .none, GREEN, SIMD3(0.32, 0.29, 0.26), nil),
    TreeKind("Coconut Palm", .palm, 1, 11, 0.0, 0.0, 0.88, 0.0, 0.35, 0.018, .frond, SIMD3(0.3, 0.55, 0.15), SIMD3(0.6, 0.5, 0.36), SIMD3(0.4, 0.3, 0.15)),
    TreeKind("Shrub", .branching, 4, 4, 55.0, 0.7, 0.05, 0.0, 0.35, 0.02, .round, GREEN, BROWN, nil),
    TreeKind("Plum Blossom", .branching, 5, 2, 48.0, 0.7, 0.3, 0.1, 0.6, 0.03, .blossom, SIMD3(0.95, 0.6, 0.7), SIMD3(0.25, 0.18, 0.15), nil),
    TreeKind("Cloud Pine", .branching, 4, 3, 70.0, 0.65, 0.35, 0.2, 0.5, 0.035, .needle, SIMD3(0.15, 0.4, 0.2), SIMD3(0.35, 0.27, 0.2), nil),
  ]
}

extension TreeSettings {public static var names:[String] {ProceduralGeometry.trees.map(\.name)}}
