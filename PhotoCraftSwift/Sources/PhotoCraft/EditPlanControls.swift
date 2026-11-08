import PhotoCraftAI
import SwiftUI

struct EditPlanControls: View {
  @Bindable var store: EditorStore
  @State private var inputError: String?
  @State private var showJSON = false
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Review an Edit Plan").font(.headline)
      Text("Suggest edits to the selected pixel layer, inspect the preview, then apply them together. Your document stays unchanged until you choose Apply.")
        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      HStack {
        Picker("Processing", selection: $store.editPlanProvider) {
          ForEach(EditPlanProvider.allCases, id: \.self) { Text($0.title).tag($0) }
        }.frame(maxWidth: 350)
        Spacer()
      }.disabled(store.editPlanBusy)
      Text(store.editPlanProvider.capability.message).font(.caption).foregroundStyle(.secondary)
      Text("Instruction")
      TextEditor(text: $store.editPlanPrompt).frame(height: 55).border(.quaternary)
        .accessibilityLabel("Edit instruction").disabled(store.editPlanBusy)
      HStack {
        Button("Suggest and Preview") { inputError = nil; Task { await store.proposeReviewedEditPlan() } }
          .disabled(!store.canReviewEditPlan || !store.editPlanProvider.capability.available || store.editPlanPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Text("Auto Tone, Auto Contrast, Auto Color, Desaturate and Invert").font(.caption).foregroundStyle(.secondary)
      }
      DisclosureGroup("Review a supplied plan", isExpanded: $showJSON) {
        Text("Paste JSON with a summary and an operations array. This does not run a model.").font(.caption).foregroundStyle(.secondary)
        TextEditor(text: $store.editPlanJSON).font(.system(.caption, design: .monospaced))
          .frame(height: 65).border(.quaternary).accessibilityLabel("Supplied edit plan JSON").disabled(store.editPlanBusy)
        Button("Preview Supplied Plan") {
          inputError = nil
          Task { do { try await store.prepareReviewedEditPlan(NativeEditPlan.decode(Data(store.editPlanJSON.utf8))) }
            catch { inputError = error.localizedDescription } }
        }.disabled(!store.canReviewEditPlan)
      }
      if let review = store.editPlanReview {
        if let plan = review.plan {
          Text(plan.summary).font(.subheadline).textSelection(.enabled)
          Text(plan.operations.enumerated().map { "\($0.offset + 1). \($0.element.title)" }.joined(separator: "  →  "))
            .font(.caption).textSelection(.enabled)
        }
        Text(review.origin.title).font(.caption).foregroundStyle(.secondary)
        if let prepared = review.prepared {
          HStack(spacing: 12) {
            preview(prepared.before, title: "Before")
            preview(prepared.after, title: "After")
          }.frame(maxHeight: .infinity)
        } else if review.busy {
          ProgressView(review.phase == "planning" ? "Planning edits…" : "Preparing preview…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          Text(review.phase == "applied" ? "Edits applied. Use Undo to restore the previous document." : review.phase == "cancelled" ? "Plan cancelled." : "No preview available.")
            .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        if review.phase == "ready", !review.matches(store) { Text("The document changed. Prepare a new preview.").foregroundStyle(.secondary) }
        if let error = review.error { Text(error).foregroundStyle(.red).font(.caption).textSelection(.enabled) }
      } else { Spacer(); Text("No image pixels are sent to a language model.").font(.caption).foregroundStyle(.secondary); Spacer() }
      if let inputError { Text(inputError).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
      HStack {
        if store.editPlanBusy { Button("Cancel Plan") { store.cancelReviewedEditPlan() } }
        Spacer()
        Button("Done") { store.cancelReviewedEditPlan(); store.showAI = false }.keyboardShortcut(.cancelAction)
        Button("Apply Plan") {
          do { if let review = store.editPlanReview { try store.applyReviewedEditPlan(review.id) } }
          catch { inputError = error.localizedDescription }
        }.disabled(!store.canApplyEditPlan).keyboardShortcut(.defaultAction)
      }
    }.padding(20).onDisappear { store.cancelReviewedEditPlan() }
  }
  func preview(_ image: CGImage, title: String) -> some View {
    VStack(spacing: 4) {
      Text(title).font(.caption)
      Image(decorative: image, scale: 1).resizable().scaledToFit()
        .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
        .background(.quaternary).accessibilityLabel("\(title) edit plan preview")
    }
  }
}
