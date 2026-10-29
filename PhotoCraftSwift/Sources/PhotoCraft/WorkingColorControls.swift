import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

extension EditorStore {
  func displayColor(_ pixel: Pixel) -> Color {
    guard let color = try? ColorManagement.color(pixel, in: document) else { return .clear }
    return Color(cgColor: color)
  }
  func workingPixel(_ color: Color) -> Pixel? {
    try? ColorManagement.pixel(NSColor(color).cgColor, in: document)
  }
}
