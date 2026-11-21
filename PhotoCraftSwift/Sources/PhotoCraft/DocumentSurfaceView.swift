import SwiftUI

/// A document canvas has its own viewport; editing panels and dialogs live in the application frame.
struct DocumentSurfaceView: View {
  @Bindable var store: EditorStore
  var compact = false
  var isActive = true
  var activateDocument: () -> Bool = { true }
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        ZStack(alignment: .bottom) {
          CanvasHost(
            store: store, revision: store.cropRevision + store.regionRetouchRevision, zoom: store.zoom,
            pan: store.pan, selection: store.document.selection,
            showRulers: store.showRulers, showLayerBounds: store.showLayerBounds,
            activateDocument: activateDocument
          )
          .id(store.identity)
          .workflowGuideAnchor(.canvas, when: isActive)
          if isActive && store.transformDraft == nil && store.cropDraft == nil && store.regionRetouchDraft == nil {
            if store.document.selection != nil {
              WorkspaceView(store: store).contextualActions.padding(.bottom, 18)
            } else if !store.geometryBusy && !store.aiBusy && store.generativeFillDraft == nil && !store.showAI &&
              (store.canBeginLocalImage || store.harmonizeTarget != nil || store.backgroundReplacementSubject != nil || store.canBeginLocalBackground || store.canStartBackgroundGeneration ||
                (store.activeLayer?.smartObject == nil && store.canDetectSubject(removeBackground: true))) {
              WorkspaceView(store: store).backgroundContextualActions.padding(.bottom, 18)
            }
          }
          if store.geometryBusy {
            HStack {
              ProgressView().controlSize(.small)
              Text(store.status)
              Button("Cancel") { store.cancelActiveOperation() }
            }.padding(12).background(StudioTheme.chrome, in: RoundedRectangle(cornerRadius: 8))
              .padding(.bottom, 18)
          }
        }
        CanvasScroller(store: store, vertical: true, activateDocument: activateDocument).frame(
          width: 14)
      }
      if compact {
        CanvasScroller(store: store, vertical: false, activateDocument: activateDocument).frame(
          height: 14
        ).padding(.trailing, 14)
      } else {
        WorkspaceView(store: store, activateCanvas: activateDocument).statusBar
      }
    }
    .font(.system(size: 11)).foregroundStyle(Color(white: 0.88))
    .background(StudioTheme.chrome).tint(StudioTheme.accent).preferredColorScheme(.dark)
  }
}
