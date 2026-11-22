import AppKit
import PhotoCraftCore
import SwiftUI
import PhotoCraftImaging

struct RemoveDistractionControls: View {
  @Bindable var store: EditorStore
  var close: () -> Void
  @State private var overlayOpen = false
  @State private var selectingModel = false
  @State private var error: String?

  private var review: RemoveDistractionReview? { store.removeDraft?.distractionReview }
  private var processing: Bool { store.removeDistractionID != nil }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("General distractions").font(.headline)
        Spacer()
        if review != nil {
          Button { overlayOpen.toggle() } label: { Label("Overlay settings", systemImage: "gearshape") }
            .labelStyle(.iconOnly).help("Adjust overlay opacity")
            .popover(isPresented: $overlayOpen) { opacityControl }
        }
      }
      if processing || selectingModel {
        ProgressView(processing ? "Finding distractions…" : "Checking model…")
          .controlSize(.small)
      } else if let review {
        if review.groups.isEmpty {
          Text("No general distractions found.").foregroundStyle(.secondary)
        } else {
          categories(review)
          if let draft = store.removeDraft, store.removeProcessing(draft.settings, in: draft.original) != .traditional {
            Text("Remove uses the on-device model.").foregroundStyle(.secondary)
          }
        }
      } else {
        Button("Find") { error = nil; store.findGeneralDistractions() }
          .keyboardShortcut(.defaultAction).disabled(!store.canFindGeneralDistractions)
        Button("Choose Detection Model…", action: chooseModel)
        if RemoveDistractionModelPreference.url(bookmark: store.removeDistractionModelBookmark) != nil {
          Label("Extended detection model selected", systemImage: "checkmark.circle")
            .foregroundStyle(.secondary)
          if store.removeDistractionModelBookmark != nil {
            Button("Use Built-in Vision") {
              store.removeDistractionModelBookmark = nil
              UserDefaults.standard.removeObject(forKey: RemoveDistractionModelPreference.key)
              error = nil
            }
          }
        }
      }
      if let error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
      HStack {
        Spacer()
        Button("Cancel") {
          if processing || review != nil { store.cancelRemove() }
          close()
        }.keyboardShortcut(.cancelAction)
        if review != nil {
          Button("Apply") { store.applyRemove(); close() }
            .keyboardShortcut(.defaultAction)
            .disabled(store.removeDraft?.hasMarks != true || store.geometryBusy || store.removeStroke != nil)
        }
      }
    }
    .padding(14)
    .frame(width: 278)
    .controlSize(.small)
  }

  private func categories(_ review: RemoveDistractionReview) -> some View {
    let all = Set(review.groups.map(\.category))
    return VStack(alignment: .leading, spacing: 6) {
      Toggle("Select All", isOn: Binding(get: { self.review?.enabled == all }, set: { update($0 ? all : []) }))
        .accessibilityValue(review.enabled == all ? "All" : review.enabled.isEmpty ? "None" : "Some")
      Divider()
      ForEach(review.groups, id: \.category) { group in
        Toggle(isOn: Binding(get: { self.review?.enabled.contains(group.category) == true }, set: { selected in
          guard var enabled = self.review?.enabled else { return }
          if selected { enabled.insert(group.category) } else { enabled.remove(group.category) }
          update(enabled)
        })) {
          HStack {
            let color = group.category.color
            Circle().fill(Color(red: Double(color.r), green: Double(color.g), blue: Double(color.b)))
              .frame(width: 8, height: 8).accessibilityHidden(true)
            Text(group.category.title)
            Spacer()
            Text(group.count.formatted()).foregroundStyle(.secondary).monospacedDigit()
          }
        }
      }
    }.toggleStyle(.checkbox).disabled(store.geometryBusy || store.removeStroke != nil)
  }

  private var opacityControl: some View {
    let opacity = Binding<Double>(get: { review?.overlayOpacity ?? 0.45 }, set: {
      do { try store.updateGeneralDistractions(opacity: $0) }
      catch { self.error = error.localizedDescription }
    })
    return VStack(alignment: .leading, spacing: 8) {
      Text("Overlay Opacity")
      Slider(value: opacity, in: 0...1) { Text("Overlay Opacity") }.labelsHidden()
        .accessibilityValue(opacity.wrappedValue.formatted(.percent.precision(.fractionLength(0))))
    }.frame(width: 182).padding(12)
  }

  private func update(_ categories: Set<RemoveDistractionCategory>) {
    do { try store.updateGeneralDistractions(categories: categories); error = nil }
    catch { self.error = error.localizedDescription }
  }

  private func chooseModel() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true; panel.canChooseFiles = true
    panel.allowsMultipleSelection = false; panel.prompt = "Choose Model"
    panel.message = "Select the compiled DistractionDetectorV1.mlmodelc model."
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      Task { @MainActor in
        selectingModel = true
        defer { selectingModel = false }
        do {
          guard url.pathExtension.lowercased() == "mlmodelc" else { throw CraftError.invalid("Choose a compiled .mlmodelc model.") }
          let bookmark = try GenerativeFillModelPreference.bookmark(for: url)
          try await Task.detached(priority: .userInitiated) {
            let scope = url.startAccessingSecurityScopedResource()
            defer { if scope { url.stopAccessingSecurityScopedResource() } }
            _ = try CoreMLDistractionDetector(url: url)
          }.value
          store.removeDistractionModelBookmark = bookmark
          UserDefaults.standard.set(bookmark, forKey: RemoveDistractionModelPreference.key)
          error = nil
        } catch { self.error = error.localizedDescription }
      }
    }
  }
}
