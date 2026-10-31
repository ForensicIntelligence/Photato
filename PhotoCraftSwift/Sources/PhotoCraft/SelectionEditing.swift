import AppKit
import PhotoCraftCore
import SwiftUI

extension EditorStore {
  func selectionMode(modifiers: NSEvent.ModifierFlags) -> SelectionMode {
    if modifiers.contains([.shift, .option]) { return .intersect }
    if modifiers.contains(.shift) { return .add }
    if modifiers.contains(.option) { return .subtract }
    return selectionMode
  }
  func selectShape(_ shape: SelectionShape, mode: SelectionMode) {
    performGeometry(.selectShape(shape, mode, selectionAntiAlias, selectionFeather))
  }
}

// CGPath is not annotated Sendable by the SDK. This wrapper only exposes an immutable
// copy; the worker's CGMutablePath is never shared across actors.
struct SelectionContour: @unchecked Sendable {
  let path: CGPath
  init(_ path: CGPath) { self.path = path.copy()! }
}

enum SelectionOutline {
  /// Half-coverage contour in document coordinates. Merge adjacent unit edges into runs.
  static func path(_ mask: SelectionMask, region:IntRect? = nil, sampleStep:Int = 1) throws -> SelectionContour {
    if mask.isPaged {
      return try boundedPath(mask,region:region ?? IntRect(x:0,y:0,width:mask.width,height:mask.height),sampleStep:max(sampleStep,region == nil ? (max(mask.width,mask.height)+2047)/2048:1))
    }
    let path = CGMutablePath()
    func selected(_ x: Int, _ y: Int) -> Bool { mask.coverage(x: x, y: y) >= 0.5 }
    for y in 0...mask.height {
      try Task.checkCancellation()
      var start: Int?
      for x in 0...mask.width {
        let edge = x < mask.width && selected(x, y - 1) != selected(x, y)
        if edge && start == nil { start = x }
        if !edge, let from = start {
          path.move(to: CGPoint(x: from, y: y))
          path.addLine(to: CGPoint(x: x, y: y))
          start = nil
        }
      }
    }
    for x in 0...mask.width {
      try Task.checkCancellation()
      var start: Int?
      for y in 0...mask.height {
        let edge = y < mask.height && selected(x - 1, y) != selected(x, y)
        if edge && start == nil { start = y }
        if !edge, let from = start {
          path.move(to: CGPoint(x: x, y: from))
          path.addLine(to: CGPoint(x: x, y: y))
          start = nil
        }
      }
    }
    return SelectionContour(path)
  }
  /// Render the visible marching-ants grid at bounded presentation resolution.
  /// Sample neighbors outside the window so clipping cannot create false edges.
  static func boundedPath(_ mask:SelectionMask,region:IntRect,sampleStep:Int)throws->SelectionContour {
    let r=region.clipped(toWidth:mask.width,height:mask.height),path=CGMutablePath()
    guard r.width>0,r.height>0 else {return SelectionContour(path)}
    let step=max(1,sampleStep,(max(r.width,r.height)+2047)/2048)
    let columns=(r.width+step-1)/step,rows=(r.height+step-1)/step
    func xEdge(_ i:Int)->Int {min(r.x+r.width,r.x+i*step)}
    func yEdge(_ i:Int)->Int {min(r.y+r.height,r.y+i*step)}
    func xMiddle(_ i:Int)->Int {i<0 ? r.x-1-(step-1)/2:i>=columns ? r.x+r.width+(step-1)/2:xEdge(i)+(xEdge(i+1)-xEdge(i)-1)/2}
    func yMiddle(_ i:Int)->Int {i<0 ? r.y-1-(step-1)/2:i>=rows ? r.y+r.height+(step-1)/2:yEdge(i)+(yEdge(i+1)-yEdge(i)-1)/2}
    func selected(_ x:Int,_ y:Int)->Bool {mask.coverage(x:x,y:y)>=0.5}
    for row in 0...rows {
      try Task.checkCancellation();let y=yEdge(row);var start:Int?
      for column in 0...columns {
        let x=xEdge(column),middle=column<columns ? x+(xEdge(column+1)-x-1)/2:x
        let edge=column<columns && selected(middle,yMiddle(row-1)) != selected(middle,yMiddle(row))
        if edge && start == nil {start=x}
        if !edge,let from=start {path.move(to:CGPoint(x:from,y:y));path.addLine(to:CGPoint(x:x,y:y));start=nil}
      }
    }
    for column in 0...columns {
      try Task.checkCancellation();let x=xEdge(column);var start:Int?
      for row in 0...rows {
        let y=yEdge(row),middle=row<rows ? y+(yEdge(row+1)-y-1)/2:y
        let edge=row<rows && selected(xMiddle(column-1),middle) != selected(xMiddle(column),middle)
        if edge && start == nil {start=y}
        if !edge,let from=start {path.move(to:CGPoint(x:x,y:from));path.addLine(to:CGPoint(x:x,y:y));start=nil}
      }
    }
    return SelectionContour(path)
  }

}

struct FeatherSelectionSheet: View {
  @Bindable var store: EditorStore
  @State private var radius = 1.0
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Feather Selection").font(.title2.bold())
      HStack {
        Text("Feather Radius:")
        TextField("Pixels", value: $radius, format: .number).frame(width: 85)
        Text("pixels")
      }
      Text("Softens the selection edge. Range: 0–100 pixels.").font(.caption).foregroundStyle(
        .secondary)
      HStack {
        Spacer()
        Button("Cancel") { store.showFeatherSelection = false }.keyboardShortcut(.cancelAction)
        Button("OK") {
          store.showFeatherSelection = false
          store.performGeometry(.featherSelection(radius))
        }.keyboardShortcut(.defaultAction).disabled(!radius.isFinite || !(0...100).contains(radius))
      }
    }.padding(24).frame(width: 380).preferredColorScheme(.dark)
  }
}
