import AppKit
import ImagePlayground
import SwiftUI

@available(macOS 26.0, *)
struct SystemImagePlayground: NSViewControllerRepresentable {
  var store: EditorStore
  func makeCoordinator() -> Coordinator { Coordinator(store: store) }
  func makeNSViewController(context: Context) -> ImagePlaygroundViewController {
    let controller = ImagePlaygroundViewController()
    // Apple styles use local models on macOS 26 and Private Cloud Compute on macOS 27+.
    // External-provider styles are not enabled by this integration.
    controller.allowedGenerationStyles = [.illustration, .animation, .sketch]
    controller.selectedGenerationStyle = .illustration
    controller.concepts = [.text(store.prompt)]
    controller.delegate = context.coordinator
    if #available(macOS 26.4, *) {
      var options = ImagePlaygroundOptions()
      options.personalization = .disabled
      controller.options = options
    }
    return controller
  }
  func updateNSViewController(_ controller: ImagePlaygroundViewController, context: Context) {}
  @MainActor final class Coordinator: NSObject, ImagePlaygroundViewController.Delegate {
    let store: EditorStore
    init(store: EditorStore) { self.store = store }
    func imagePlaygroundViewController(
      _ imagePlaygroundViewController: ImagePlaygroundViewController, didCreateImageAt imageURL: URL
    ) { store.acceptGeneratedImage(imageURL) }
    func imagePlaygroundViewControllerDidCancel(
      _ imagePlaygroundViewController: ImagePlaygroundViewController
    ) {
      store.showImagePlayground = false
      store.status = "Image generation cancelled"
    }
  }
}
