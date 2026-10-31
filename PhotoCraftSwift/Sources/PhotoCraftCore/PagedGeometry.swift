import Foundation

/// Integer inverse mapping for an exact axis-aligned lattice permutation.
/// Eligibility requires the complete transformed source rectangle, not a crop.
struct RasterGridMap {
  let a:Int,b:Int,c:Int,d:Int,x0:Int,y0:Int
  init?(_ t:Transform2D,inverse:Transform2D,width:Int,height:Int,bounds:IntRect) {
    let coefficients=[t.a,t.b,t.c,t.d]
    guard coefficients.allSatisfy({[-1.0,0,1].contains($0)}),
      abs(t.a)+abs(t.c)==1,abs(t.b)+abs(t.d)==1,
      abs(t.a)+abs(t.b)==1,abs(t.c)+abs(t.d)==1,
      t.tx == t.tx.rounded(),t.ty == t.ty.rounded(),
      let complete=try? t.bounds(width:width,height:height),complete==bounds else {return nil}
    a=Int(inverse.a);b=Int(inverse.b);c=Int(inverse.c);d=Int(inverse.d)
    let p=inverse.point(Double(bounds.x)+0.5,Double(bounds.y)+0.5)
    x0=Int(floor(p.x));y0=Int(floor(p.y))
  }
  func source(_ x:Int,_ y:Int)->(Int,Int) {(a*x+c*y+x0,b*x+d*y+y0)}
  func destination(_ x:Int,_ y:Int)->(Int,Int) {
    let x=x-x0,y=y-y0;return(a*x+b*y,c*x+d*y)
  }
}

/// At most one row of bounded support intervals is resident. Sparse projected
/// rectangles never become a canvas-sized Set/bitmap, even when enlarged.
struct GeometryPatchRegions:Sequence {
  let width:Int,height:Int,rectangles:[IntRect]
  func makeIterator()->AnyIterator<IntRect> {
    var row=0,intervals:[Range<Int>]=[],intervalIndex=0,column=0
    return AnyIterator {
      while true {
        if intervalIndex < intervals.count {
          let range=intervals[intervalIndex]
          if column < range.upperBound {
            let first=column;column=Swift.min(range.upperBound,column+32)
            let x=first*64,y=(row-1)*64
            return IntRect(x:x,y:y,width:Swift.min(self.width-x,(column-first)*64),height:Swift.min(64,self.height-y))
          }
          intervalIndex += 1
          if intervalIndex < intervals.count {column=intervals[intervalIndex].lowerBound}
          continue
        }
        guard row < (self.height+63)/64 else {return nil}
        var ranges:[Range<Int>]=[]
        for r in self.rectangles where r.width>0 && r.height>0 && row*64<r.y+r.height && row*64+64>r.y {
          ranges.append((r.x/64)..<((r.x+r.width+63)/64))
        }
        intervals=[]
        for range in ranges.sorted(by:{$0.lowerBound<$1.lowerBound}) {
          if let last=intervals.last,range.lowerBound<=last.upperBound {
            intervals[intervals.count-1]=last.lowerBound..<Swift.max(last.upperBound,range.upperBound)
          } else {intervals.append(range)}
        }
        row += 1;intervalIndex=0;column=intervals.first?.lowerBound ?? 0
      }
    }
  }
}
