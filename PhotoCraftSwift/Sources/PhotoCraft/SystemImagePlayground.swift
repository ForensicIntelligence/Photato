import AppKit
import ImagePlayground
import PhotoCraftAI
import SwiftUI

@available(macOS 26.0, *)
struct SystemImagePlayground: NSViewControllerRepresentable {
  var store: EditorStore
  let job:ImageGenerationJob
  func makeCoordinator() -> Coordinator { Coordinator(store: store,job:job) }
  func makeNSViewController(context: Context) -> ImagePlaygroundViewController {
    let controller = Self.makeController(job: job)
    controller.delegate = context.coordinator
    return controller
  }
  static func makeController(
    job: ImageGenerationJob, presentation: ImageGenerationPresentation = .current
  ) -> ImagePlaygroundViewController {
    let controller = ImagePlaygroundViewController()
    // Apple styles use local models on macOS 26 and Private Cloud Compute on macOS 27+.
    // External-provider styles are not enabled by this integration.
    let styles = presentation.styles.compactMap { nativeStyle($0) }
    let allowed = styles.isEmpty ? [.illustration, .animation, .sketch] : styles
    controller.allowedGenerationStyles = allowed
    controller.selectedGenerationStyle = allowed[0]
    controller.concepts = [.text(job.initialPrompt)]
    if job.intent == .background {
      controller.concepts.append(.text("Create a background scene for the referenced subject. Do not add a foreground subject."))
    }
    if let reference=job.referenceImage {
      controller.sourceImage=NSImage(cgImage:reference,size:.init(width:Double(reference.width),height:Double(reference.height)))
    }
    if #available(macOS 26.4, *) {
      var options = ImagePlaygroundOptions()
      options.personalization = .disabled
      if #available(macOS 27.0, *), presentation.usesCanvasSizeHint {
        // The system chooses a supported resolution/aspect ratio. This is a hint,
        // captured with the request, rather than a promise of exact output dimensions.
        options.sizeSpecification = .closest(to: CGSize(
          width: Double(job.sourceWidth), height: Double(job.sourceHeight)))
      }
      controller.options = options
    }
    return controller
  }
  private static func nativeStyle(_ style: ImageGenerationPresentation.Style) -> ImagePlaygroundStyle? {
    switch style {
    case .any:
      if #available(macOS 27.0, *) { return .any }
      return nil
    case .illustration: return .illustration
    case .animation: return .animation
    case .sketch: return .sketch
    }
  }
  func updateNSViewController(_ controller: ImagePlaygroundViewController, context: Context) {}
  static func dismantleNSViewController(_ controller:ImagePlaygroundViewController,coordinator:Coordinator) {
    coordinator.store.imageSystemInterfaceDismissed(coordinator.job.id)
  }
  @MainActor final class Coordinator: NSObject, ImagePlaygroundViewController.Delegate {
    let store: EditorStore
    let job:ImageGenerationJob
    init(store: EditorStore,job:ImageGenerationJob) { self.store = store;self.job=job }
    func imagePlaygroundViewController(
      _ imagePlaygroundViewController: ImagePlaygroundViewController, didCreateImageAt imageURL: URL
    ) { store.acceptGeneratedImage(imageURL,requestID:job.id,resultStyle:imagePlaygroundViewController.selectedGenerationStyle.id) }
    func imagePlaygroundViewControllerDidCancel(
      _ imagePlaygroundViewController: ImagePlaygroundViewController
    ) {
      store.cancelImageGeneration(job.id)
    }
  }
}
