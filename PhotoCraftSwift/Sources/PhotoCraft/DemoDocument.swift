import Foundation
import PhotoCraftCore

// Original procedural sample artwork; no bundled third-party photos or fonts.
enum DemoDocument {
  static func make() throws -> CraftDocument {
    var d = try CraftDocument(width: 1200, height: 800, depth: .u8, name: "Field Notes")
    d.layers = [Layer(name: "Warm paper", content: .fill(Pixel(0.91, 0.89, 0.82)))]
    var sky = try Surface(width: 1060, height: 470, depth: .u8)
    for y in 0..<470 {
      for x in 0..<1060 {
        let t = Float(y) / 470
        var p = Pixel(0.64 + t * 0.2, 0.72 + t * 0.07, 0.75 - t * 0.02)
        let mountain1 = 220 + 60 * sin(Double(x) * 0.007) + 28 * cos(Double(x) * 0.019)
        let mountain2 = 300 + 50 * sin(Double(x) * 0.010 + 2) + 20 * cos(Double(x) * 0.023)
        let mountain3 = 390 + 26 * sin(Double(x) * 0.012 + 1)
        if hypot(Double(x) - 780, Double(y) - 108) < 48 { p = Pixel(0.96, 0.83, 0.59) }
        if Double(y) > mountain1 { p = Pixel(0.48, 0.58, 0.60) }
        if Double(y) > mountain2 { p = Pixel(0.30, 0.43, 0.45) }
        if Double(y) > mountain3 { p = Pixel(0.16, 0.29, 0.30) }
        sky.setPixel(x: x, y: y, p)
      }
    }
    var landscape = Layer(name: "Mountain study", content: .raster(sky))
    landscape.x = 70
    landscape.y = 250
    d.layers.append(landscape)
    func text(
      _ title: String, _ size: Double, _ x: Int, _ y: Int, _ color: Pixel = Pixel(0.16, 0.22, 0.22)
    ) -> Layer {
      var l = Layer(
        name: title,
        content: .text(
          TextContent(text: title, fontName: "Helvetica Neue", size: size, color: color)))
      l.x = x
      l.y = y
      return l
    }
    d.layers.append(text("FIELD NOTES", 102, 66, 64))
    d.layers.append(text("A STUDY IN STILLNESS", 17, 73, 202))
    d.layers.append(text("01  /  PACIFIC NORTHWEST", 14, 72, 741))
    d.layers.append(text("PHOTATO STUDIO", 14, 929, 741))
    d.activeLayerID = landscape.id
    return d
  }
}
