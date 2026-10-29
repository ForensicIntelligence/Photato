import PhotoCraftCore
import SwiftUI

extension WorkspaceView {
  func scaleOption<T>(_ key: WritableKeyPath<TransformDraft,T>,default value: T) -> Binding<T> {
    Binding(get:{ store.transformDraft?[keyPath:key] ?? value },set:{ value in guard var d = store.transformDraft else { return };d[keyPath:key] = value;store.updateTransform(d) })
  }
  func scaleDimension(_ key: WritableKeyPath<TransformDraft,Double>) -> Binding<Double> {
    Binding(get:{ store.transformDraft?[keyPath:key] ?? 100 },set:{ value in
      guard value.isFinite,value > 0,var d = store.transformDraft else { return };let point = d.referencePoint,old = d[keyPath:key];d[keyPath:key] = value
      if d.proportional,old > 0 { if key == \.scaleX { d.scaleY *= value/old } else { d.scaleX *= value/old } }
      let f = d.referenceAnchor.fractions;d.centerX = point.x-(f.0-0.5)*Double(d.bounds.width)*d.scaleX/100;d.centerY = point.y-(f.1-0.5)*Double(d.bounds.height)*d.scaleY/100;store.updateTransform(d)
    })
  }
  func scalePosition(horizontal: Bool) -> Binding<Double> {
    Binding(get:{ horizontal ? store.transformDraft?.referencePoint.x ?? 0:store.transformDraft?.referencePoint.y ?? 0 },set:{ value in
      guard value.isFinite,var d = store.transformDraft else { return };let p = d.referencePoint;if horizontal { d.centerX += value-p.x } else { d.centerY += value-p.y };store.updateTransform(d)
    })
  }
  var contentAwareScaleOptions: some View {
    Group {
      Text("Content-Aware Scale").fontWeight(.medium)
      Grid(horizontalSpacing:2,verticalSpacing:2) { ForEach(0..<3) { row in GridRow { ForEach(0..<3) { col in
        let anchor = CanvasAnchor.allCases[row*3+col]
        Button { if var d = store.transformDraft { d.referenceAnchor = anchor;store.updateTransform(d) } } label: { Image(systemName:store.transformDraft?.referenceAnchor == anchor ? "square.fill":"square").font(.system(size:6)) }.buttonStyle(.plain).accessibilityLabel("Reference point \(anchor.rawValue)")
      } } } }
      numberField("X",value:scalePosition(horizontal:true),range:-1_000_000...1_000_000,suffix:"px")
      numberField("Y",value:scalePosition(horizontal:false),range:-1_000_000...1_000_000,suffix:"px")
      numberField("W",value:scaleDimension(\.scaleX),range:0.01...10000,suffix:"%")
      Toggle(isOn:scaleOption(\.proportional,default:false)) { Image(systemName:"link") }.toggleStyle(.button).help("Maintain aspect ratio; Shift temporarily toggles while dragging")
      numberField("H",value:scaleDimension(\.scaleY),range:0.01...10000,suffix:"%")
      numberField("Amount",value:scaleOption(\.amount,default:100),range:0...100,suffix:"%")
      Picker("Protect",selection:scaleOption(\.protectChannelID,default:UUID?.none)) {
        Text("None").tag(UUID?.none);ForEach(store.document.alphaChannels ?? []) { Text($0.name).tag(Optional($0.id)) }
      }.frame(width:145).controlSize(.small)
      Toggle(isOn:scaleOption(\.protectSkinTones,default:false)) { Image(systemName:"person.fill") }.toggleStyle(.button).help("Protect Skin Tones")
      if store.contentAwareScaleBusy { ProgressView().controlSize(.small) }
      if let error = store.contentAwareScaleError { Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(.orange).help(error).accessibilityLabel(error) }
      Button("Cancel") { store.cancelTransform() }.controlSize(.small).keyboardShortcut(.cancelAction)
      Button("Apply") { store.commitTransform() }.controlSize(.small).keyboardShortcut(.defaultAction).disabled(store.contentAwareScaleReadyDraft != store.transformDraft || store.contentAwareScalePrepared == nil)
    }
  }
}
