import AppKit
import PhotoCraftCore
import SwiftUI

struct PathWarpContext {
  let focus: PathTransformTarget
  let choices: [PathTransformChoice]
  let selection: [PathTransformChoice]
  let matrix: ProjectiveTransform
  let bounds: WarpSourceBounds
}

@MainActor extension EditorStore {
  var canBeginPathWarp: Bool {
    guard pathTarget != nil, !geometryBusy, !aiBusy, !hasToneDraft, editingChannel == nil else { return false }
    if let draft = transformDraft {
      guard draft.pathTarget == pathTarget, draft.pathSelectionContext == selectedPathChoices else { return false }
      if let session = selectionTransform, session.warpModel != nil {
        return session.completedPathWarp(for: draft) != nil
      }
      return true
    }
    return canBeginPathTransform
  }

  func beginPathWarp() {
    guard canBeginPathWarp, let focus = pathTarget else { return }
    do {
      if let draft = transformDraft, let session = selectionTransform, let model = session.warpModel {
        guard matchesPathWarp(model), let edit = session.completedPathWarp(for: draft) else {
          throw CraftError.invalid("The path transform source changed.")
        }
        try model.continuePathWarp(with: edit)
        session.close(keepWarp: true)
        selectionTransform = nil
        transformDraft = nil
        warpDraft = model
        status = "Warp Paths · Return applies · Escape cancels"
        return
      }
      let draft = transformDraft
      let matrix = try draft?.selectionProjection ?? .identity
      let choices = draft?.pathChoices ?? pathChoicesForTransform
      let bounds = try PathWarp.sourceBounds(choices, matrix: matrix, in: document)
      let context = PathWarpContext(focus: focus, choices: choices, selection: selectedPathChoices,
                                    matrix: matrix, bounds: bounds)
      finishNumericField()
      finishLayerName()
      cancelSelectionTransform()
      transformDraft = nil
      let model = WarpWorkspace(source: document, path: context, session: sessionGeneration,
                                lifecycle: layerPanelGeneration)
      model.pathPreviewChanged = { [weak self, weak model] in
        guard let self, let model, self.pathWarp === model, model.pathEdit?.source == self.document else { return }
        if context.hasRenderedPaths {
          self.render(startWorkerImmediately: true)
        }
      }
      warpDraft = model
      status = "Warp Paths · Return applies · Escape cancels"
      model.refresh()
    } catch { self.error = error.localizedDescription }
  }

  var canReturnToPathTransform: Bool {
    guard !geometryBusy, let model = pathWarp else { return false }
    return model.ready && matchesPathWarp(model)
  }

  func returnToPathTransform() {
    guard canReturnToPathTransform, let model = pathWarp,
          let context = model.pathContext, let edit = model.pathEdit else { return }
    do {
      let bounds = try edit.bounds()
      model.endGesture()
      var draft = TransformDraft(layerID: context.focus.id, bounds: bounds)
      draft.pathTarget = context.focus
      draft.pathSelection = pathTransformSelection
      draft.pathChoices = context.choices
      draft.pathSelectionContext = context.selection
      draft.selection = true
      draft.selectedPixels = context.hasRenderedPaths
      draft.selectionQuad = draft.selectionCorners
      let session = SelectionTransformSession(document, draft: draft, warp: model)
      session.warpPreviewChanged = { [weak self, weak session] in
        guard let self, let session, self.selectionTransform === session,
              session.original == self.document, context.hasRenderedPaths else { return }
        self.render(startWorkerImmediately: true)
      }
      warpDraft = nil
      selectionTransform = session
      transformDraft = draft
      status = "\(draft.pathTransformTitle) · Return applies · Escape cancels"
      session.task = Task { await session.prepare() }
    } catch { model.error = error.localizedDescription }
  }

  private func matchesPathWarp(_ model: WarpWorkspace) -> Bool {
    guard let context = model.pathContext else { return false }
    return model.sourceSession == sessionGeneration && model.sourceLifecycle == layerPanelGeneration &&
      model.source == document && pathTarget == context.focus && selectedPathChoices == context.selection
  }

  func commitPathWarp() {
    guard let model = pathWarp, model.ready, let edit = model.pathEdit else { return }
    guard matchesPathWarp(model) else {
      model.error = "The Warp source changed. Cancel and start Warp again."
      return
    }
    do {
      try executeCompositePreparedEdit(PreparedEdit(command: .warpPaths(edit), document: document))
      model.close()
      warpDraft = nil
      updatePathChoices(edit.geometry.map(\.choice))
      if document != edit.source { onChange?(.changeDone) }
      status = "Warp Paths"
      render()
    } catch { model.error = error.localizedDescription }
  }
}

private extension PathWarpContext {
  var hasRenderedPaths: Bool {
    choices.contains { if case .saved = $0.target { return false }; return true }
  }
}

extension WorkspaceView {
  func pathWarpOptions(_ model: WarpWorkspace) -> some View {
    HStack(spacing: 8) {
      Button("Free Transform") { store.returnToPathTransform() }
        .help("Switch to Free Transform and keep the pending Warp")
        .disabled(!store.canReturnToPathTransform)
      Picker("Warp", selection: Binding(get: { model.settings.style }, set: model.choose)) {
        ForEach(WarpStyle.allCases, id: \.self) { Text($0.title).tag($0) }
      }.frame(width: 128)
      if model.settings.cylinder == nil {
        Menu("Grid") {
          ForEach([1, 3, 4, 5], id: \.self) { n in
            Button(n == 1 ? "Default" : "\(n) × \(n)") { model.grid(n) }
          }
        }
        Menu("Split") {
          Button("Horizontal") { model.split(vertical: false) }
          Button("Vertical") { model.split(vertical: true) }
          Button("Crosswise") { model.split(vertical: true, cross: true) }
          Button("Remove Horizontal Split") { model.remove(vertical: false) }
            .disabled((model.settings.mesh?.vs.count ?? 0) <= 2)
          Button("Remove Vertical Split") { model.remove(vertical: true) }
            .disabled((model.settings.mesh?.us.count ?? 0) <= 2)
        }
        if model.settings.style != .custom {
          Toggle("Vertical Warp", isOn: Binding(get: { model.settings.vertical }, set: {
            var settings = model.settings
            settings.vertical = $0
            model.change(settings)
          })).help("Change Warp orientation")
          ForEach([("Bend", \WarpDefinition.bend), ("H Distortion", \WarpDefinition.horizontalDistortion),
                   ("V Distortion", \WarpDefinition.verticalDistortion)], id: \.0) { label, key in
            HStack(spacing: 3) {
              Text(label).accessibilityHidden(true)
              TextField(label, value: Binding(get: { model.settings[keyPath: key] }, set: {
                var settings = model.settings
                settings[keyPath: key] = $0
                model.change(settings)
              }), format: .number.precision(.fractionLength(0...2)))
                .frame(width: 46).accessibilityLabel(label + " percent")
              Text("%").accessibilityHidden(true)
            }.disabled(model.settings.style == .none)
          }
        }
      }
      Toggle("Guides", isOn: Binding(get: { model.showGuides }, set: { model.showGuides = $0 }))
      if model.rendering { ProgressView().controlSize(.mini).accessibilityLabel("Preparing Warp preview") }
      if let error = model.error {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help(error)
          .accessibilityLabel(error)
      }
      Button("Reset") { model.change(WarpDefinition()) }
    }.controlSize(.small)
  }
}
