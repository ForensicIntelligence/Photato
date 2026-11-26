import Foundation
import CoreGraphics
import CoreText

extension VanishingScene {
  /// An isolated line reports its orientation from the plane's horizontal axis.
  /// Lines joined at the first endpoint report the angle between the two edges.
  public func measurementAngle(_ line: VanishingMeasurement, settings: VanishingSettings,
    excluding index: Int? = nil) -> Double?
  {
    guard measurementDistance(line) != nil else { return nil }
    let metric = measurementMetric(for: line.plane)
    func heading(to point: PathPoint) -> Double {
      atan2((point.y - line.start.y) * metric.y,(point.x - line.start.x) * metric.x)
    }
    func touches(_ point: PathPoint) -> Bool {
      hypot(point.x - line.start.x,point.y - line.start.y) < 1e-7
    }
    let axis = heading(to:line.end)
    for (offset,other) in (settings.measurements ?? []).enumerated()
        where offset != index && other != line && other.plane == line.plane {
      let endpoint: PathPoint
      if touches(other.start) { endpoint = other.end }
      else if touches(other.end) { endpoint = other.start }
      else { continue }
      let delta = abs((axis - heading(to:endpoint)).truncatingRemainder(dividingBy:2 * .pi))
      return min(delta,2 * .pi - delta) * 180 / .pi
    }
    let angle = axis.truncatingRemainder(dividingBy:.pi)
    return abs(angle) < 1e-12 ? 0 : (angle < 0 ? angle + .pi : angle) * 180 / .pi
  }
}

/// Draw document-space marks into bounded tiles, even when a line crosses
/// almost the full canvas diagonally.
enum VanishingAnnotationRaster {
  private struct Label {
    let text: CTLine
    let box: CGRect
    let baseline: CGPoint

    init(text: String, centeredAt center: CGPoint, font: CTFont, color: CGColor) {
      self.text = CTLineCreateWithAttributedString(NSAttributedString(string:text,attributes:[
        NSAttributedString.Key(rawValue:kCTFontAttributeName as String):font,
        NSAttributedString.Key(rawValue:kCTForegroundColorAttributeName as String):color
      ]))
      var ascent: CGFloat = 0, descent: CGFloat = 0
      let width = CTLineGetTypographicBounds(self.text,&ascent,&descent,nil)
      box = CGRect(x:center.x-width/2-3,y:center.y-(ascent+descent)/2-2,
        width:width+6,height:ascent+descent+4)
      baseline = CGPoint(x:center.x-width/2,y:center.y+(ascent-descent)/2)
    }
  }

  private enum Mark {
    case grid(CGPoint,CGPoint)
    case line(CGPoint,CGPoint)
    case label(Label)
  }

  static func apply(_ program: VanishingProgram, scene: VanishingScene, to output: inout Surface,
    charge: (Int) throws -> Void) throws
  {
    let settings = program.settings
    let lines = program.drawsMeasurements ? settings.measurements ?? [] : []
    let side = Surface.tileSide
    let width = output.width, height = output.height
    let columns = (width + side - 1) / side
    let font = CTFontCreateWithName("Menlo" as CFString,11,nil)
    let black = CGColor(gray:0,alpha:1), white = CGColor(gray:1,alpha:1)
    let blue = CGColor(red:0.18,green:0.52,blue:1,alpha:1)
    var tiles: [Int:[Mark]] = [:]

    func indices(_ minimum: Double,_ maximum: Double, dimension: Int) -> ClosedRange<Int>? {
      guard maximum > 0, minimum < Double(dimension) else { return nil }
      let lower = Int(max(0,floor(minimum))) / side
      let upper = Int(min(Double(dimension-1),ceil(maximum))) / side
      return lower...upper
    }

    func append(_ mark: Mark, toRow row: Int, from left: Double,to right: Double) throws {
      guard let columnsTouched = indices(left,right,dimension:width) else { return }
      for column in columnsTouched {
        let key = row*columns+column
        let area = min(side,width-column*side)*min(side,height-row*side)
        if case .grid = mark {
          // All grid segments share one draw and readback per tile.
          try charge(side+1)
          if tiles[key] == nil { try charge(area) }
        } else {
          try charge(area)
        }
        tiles[key,default:[]].append(mark)
      }
    }

    func enqueue(_ label: Label) throws {
      guard let rows = indices(label.box.minY,label.box.maxY,dimension:height) else { return }
      for row in rows { try append(.label(label),toRow:row,from:label.box.minX,to:label.box.maxX) }
    }

    func enqueueLine(from a: CGPoint, to b: CGPoint, padding: Double, mark: Mark) throws {
      try Task.checkCancellation()
      let dx = b.x-a.x, dy = b.y-a.y
      if let rows = indices(min(a.y,b.y)-padding,max(a.y,b.y)+padding,dimension:height) {
        for row in rows {
          try Task.checkCancellation()
          let start: Double, end: Double
          if dy == 0 {
            start = 0; end = 1
          } else {
            let t0 = (Double(row*side)-padding-a.y)/dy
            let t1 = (Double((row+1)*side)+padding-a.y)/dy
            start = max(0,min(t0,t1))
            end = min(1,max(t0,t1))
          }
          guard start <= end else { continue }
          let x0 = a.x + start*dx, x1 = a.x + end*dx
          try append(mark,toRow:row,from:min(x0,x1)-padding,to:max(x0,x1)+padding)
        }
      }
    }

    if program.drawsGrids {
      func gridLine(_ start: PathPoint, _ end: PathPoint) throws {
        try charge(side)
        let a = CGPoint(x:start.x,y:start.y), b = CGPoint(x:end.x,y:end.y)
        try enqueueLine(from:a,to:b,padding:1,mark:.grid(a,b))
      }
      for (index,frame) in scene.frames.enumerated() {
        for corner in frame.corners.indices {
          try gridLine(frame.corners[corner],frame.corners[(corner+1)%frame.corners.count])
        }
        try scene.forEachInteriorGridLine(for:index,settings:settings,gridLine)
      }
    }

    let format = FloatingPointFormatStyle<Double>.number.locale(Locale(identifier:"en_US_POSIX"))
      .grouping(.never).precision(.fractionLength(0...2))
    for (index,line) in lines.enumerated() {
      let frame = scene.frames[line.plane]
      let p = frame.point(line.start), q = frame.point(line.end)
      let a = CGPoint(x:p.x,y:p.y), b = CGPoint(x:q.x,y:q.y)
      let dx = b.x-a.x, dy = b.y-a.y
      try enqueueLine(from:a,to:b,padding:4,mark:.line(a,b))
      if let length = scene.measurementLength(line,settings:settings) {
        let text = length < 1e10 ? length.formatted(format) : String(format:"%.3g",length)
        try enqueue(Label(text:text,centeredAt:.init(x:(a.x+b.x)/2,y:(a.y+b.y)/2-13),font:font,color:white))
      }
      if let angle = scene.measurementAngle(line,settings:settings,excluding:index) {
        let displacement = min(25/hypot(dx,dy),0.4)
        let anchor = CGPoint(x:a.x+dx*displacement,y:a.y+dy*displacement+12)
        try enqueue(Label(text:angle.formatted(format)+"°",centeredAt:anchor,font:font,color:white))
      }
    }

    guard let space = CGColorSpace(name:output.depth == .f32 ? CGColorSpace.linearSRGB : CGColorSpace.sRGB)
      else { throw CraftError.invalid("Could not prepare the perspective annotation color space.") }
    for key in tiles.keys.sorted() {
      try Task.checkCancellation()
      let x0 = key % columns * side, y0 = key / columns * side
      let tileWidth = min(side,width-x0), tileHeight = min(side,height-y0)
      let layout = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
      guard let context = CGContext(data:nil,width:tileWidth,height:tileHeight,bitsPerComponent:8,
        bytesPerRow:tileWidth*4,space:space,bitmapInfo:layout), let raw = context.data else {
        throw CraftError.invalid("Could not prepare a perspective annotation tile.")
      }
      context.clear(CGRect(x:0,y:0,width:tileWidth,height:tileHeight))
      context.translateBy(x:-CGFloat(x0),y:CGFloat(tileHeight+y0))
      context.scaleBy(x:1,y:-1)
      context.setAllowsFontSmoothing(false)
      context.setLineCap(.round)
      if program.drawsGrids {
        context.setLineCap(.butt)
        context.setStrokeColor(blue)
        context.setLineWidth(1)
        context.beginPath()
        for case .grid(let a,let b) in tiles[key,default:[]] {
          context.move(to:a)
          context.addLine(to:b)
        }
        context.strokePath()
        context.setLineCap(.round)
      }

      for mark in tiles[key,default:[]] {
        switch mark {
        case .grid: break
        case .line(let a,let b):
          for (color,strokeWidth) in [(black,3.0),(white,1.0)] {
            context.setStrokeColor(color)
            context.setLineWidth(strokeWidth)
            context.beginPath()
            context.move(to:a)
            context.addLine(to:b)
            context.strokePath()
          }
          for point in [a,b] {
            let dot = CGRect(x:point.x-2,y:point.y-2,width:4,height:4)
            context.setFillColor(black)
            context.fillEllipse(in:dot.insetBy(dx:-0.5,dy:-0.5))
            context.setFillColor(white)
            context.fillEllipse(in:dot)
          }
        case .label(let label):
          context.setFillColor(black)
          context.fill(label.box)
          context.saveGState()
          context.translateBy(x:label.baseline.x,y:label.baseline.y)
          context.scaleBy(x:1,y:-1)
          context.textMatrix = .identity
          context.textPosition = .zero
          CTLineDraw(label.text,context)
          context.restoreGState()
        }
      }
      let bytes = raw.assumingMemoryBound(to:UInt8.self)
      for y in 0..<tileHeight {
        for x in 0..<tileWidth {
          let offset = (y*tileWidth+x)*4
          let alpha = Float(bytes[offset+3])
          guard alpha > 0 else { continue }
          let ink = Pixel(Float(bytes[offset])/alpha,Float(bytes[offset+1])/alpha,
            Float(bytes[offset+2])/alpha,alpha/255)
          let px = x0+x, py = y0+y
          VanishingEngine.write(&output,px,py,VanishingEngine.over(ink,VanishingEngine.read(output,px,py)))
        }
      }
    }
  }
}
