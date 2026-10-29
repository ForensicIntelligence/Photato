import Foundation

// Native port of PhotoCraft crates/algo/src/segment/{mod,quick,grabcut}.rs.
// Original project: MIT OR Apache-2.0. Numerical Photoshop equivalence is unqualified.
struct SelectionImage:Sendable {
  var width:Int,height:Int,pixels:[SelectionRGB]
  init(width:Int,height:Int,pixels:[SelectionRGB]) {self.width=width;self.height=height;self.pixels=pixels}
  init(_ surface:Surface,rect:IntRect,step:Int=1)throws {
    width=(rect.width+step-1)/step;height=(rect.height+step-1)/step
    pixels=Array(repeating:.zero,count:width*height)
    for y in 0..<height {
      try Task.checkCancellation()
      for x in 0..<width {
        var sum=SelectionRGB.zero,n:Float=0
        for yy in y*step..<min((y+1)*step,rect.height) {for xx in x*step..<min((x+1)*step,rect.width) {
          let p=surface.pixel(x:rect.x+xx,y:rect.y+yy)
          guard p.r.isFinite,p.g.isFinite,p.b.isFinite,p.a.isFinite else{throw CraftError.invalid("Selection source contains a nonfinite sample.")}
          let a=min(1,max(0,p.a))
          sum+=SelectionRGB(min(1,max(0,p.r))*a+0.5*(1-a),min(1,max(0,p.g))*a+0.5*(1-a),min(1,max(0,p.b))*a+0.5*(1-a));n+=1
        }}
        pixels[y*width+x]=sum/n
      }
    }
  }
  func at(_ x:Int,_ y:Int)->SelectionRGB {pixels[y*width+x]}
}
public enum SelectionSegmentation {
  public static let maximumPixels=16_777_216
  static let workingPixels=160_000
  static let neighbors:[(Int,Int,Float)]=[(1,0,1),(0,1,1),(1,1,Float(2).squareRoot()),(-1,1,Float(2).squareRoot())]
  static func check(_ image:Surface)throws {
    guard image.width<=maximumPixels/max(1,image.height) else{throw CraftError.unsupported("Selection analysis supports at most16MP canvas pixels.")}
    try Task.checkCancellation()
  }
  static func clampRect(_ r:IntRect,_ width:Int,_ height:Int)->IntRect {
    let x=max(0,min(width,r.x)),y=max(0,min(height,r.y)),right=max(x,min(width,r.x+r.width)),bottom=max(y,min(height,r.y+r.height))
    return .init(x:x,y:y,width:right-x,height:bottom-y)
  }
  static func inflate(_ r:IntRect,_ amount:Int,_ width:Int,_ height:Int)->IntRect {clampRect(.init(x:r.x-amount,y:r.y-amount,width:r.width+2*amount,height:r.height+2*amount),width,height)}
  static func subsample<T>(_ values:[T],_ maximum:Int)->[T] {
    guard values.count>maximum else{return values};let step=(values.count+maximum-1)/maximum
    return stride(from:0,to:values.count,by:step).map{values[$0]}
  }
  static func beta(_ image:SelectionImage)throws->Float {
    var sum=0.0,count=0;let w=image.width,h=image.height
    for y in 0..<h {try Task.checkCancellation();for x in 0..<w {
      let a=image.at(x,y)
      for (dx,dy,_) in neighbors {let nx=x+dx,ny=y+dy;if nx>=0 && nx<w && ny<h {sum+=Double(selectionDistance(a,image.at(nx,ny)));count+=1}}
    }}
    return count==0 || sum<=1e-12 ? 0:Float(Double(count)/(2*sum))
  }
  static func gridCut(_ image:SelectionImage,foreground:[Float],background:[Float],fixed:[UInt8],gamma:Float=50,beta:Float)throws->[Bool] {
    let w=image.width,h=image.height,n=w*h;var index=[Int](repeating:-1,count:n),count=0
    for i in 0..<n where fixed[i]==0 {index[i]=count;count+=1}
    var output=fixed.map{$0==1};if count==0{return output}
    let graph=SelectionGraph(nodes:count,edges:count*4)
    for i in 0..<n where index[i]>=0 {graph.addTerminal(index[i],source:background[i],sink:foreground[i])}
    func fixedLink(_ node:Int,_ label:UInt8,_ weight:Float){graph.addTerminal(node,source:label==1 ? weight:0,sink:label==1 ? 0:weight)}
    for y in 0..<h {try Task.checkCancellation();for x in 0..<w {
      let i=y*w+x,a=image.pixels[i]
      for (dx,dy,length) in neighbors {
        let nx=x+dx,ny=y+dy;guard nx>=0,nx<w,ny<h else{continue};let j=ny*w+nx
        let weight=gamma*exp(-beta*selectionDistance(a,image.pixels[j]))/length
        if index[i]>=0 && index[j]>=0 {graph.addEdge(index[i],index[j],capacity:weight,reverse:weight)}
        else if index[i]>=0 {fixedLink(index[i],fixed[j],weight)}else if index[j]>=0 {fixedLink(index[j],fixed[i],weight)}
      }
    }}
    try graph.maxflow();for i in 0..<n where index[i]>=0 {output[i]=graph.inSource(index[i])};return output
  }
  static func components(_ mask:[Bool],_ w:Int,_ h:Int,four:Bool=false)throws->([Int],[Int]) {
    var labels=[Int](repeating:0,count:w*h),sizes=[0],stack:[Int]=[],ticks=0
    for s in mask.indices where mask[s] && labels[s]==0 {
      let label=sizes.count;sizes.append(0);labels[s]=label;stack.append(s)
      while let i=stack.popLast() {
        ticks+=1;if ticks%4096==0{try Task.checkCancellation()};sizes[label]+=1;let x=i%w,y=i/w
        for dy in -1...1 {for dx in -1...1 {
          if four && abs(dx)+abs(dy) != 1 {continue};let nx=x+dx,ny=y+dy
          if nx>=0 && ny>=0 && nx<w && ny<h {let j=ny*w+nx;if mask[j] && labels[j]==0 {labels[j]=label;stack.append(j)}}
        }}
      }
    }
    return (labels,sizes)
  }
  static func keepSeeded(_ mask:[Bool],seeds:[Bool],_ w:Int,_ h:Int)throws->[Bool] {
    let (labels,sizes)=try components(mask,w,h);var keep=[Bool](repeating:false,count:sizes.count)
    for i in seeds.indices where seeds[i] && labels[i] != 0 {keep[labels[i]]=true}
    return labels.map{$0 != 0 && keep[$0]}
  }
  static func clean(_ mask:[Bool],_ w:Int,_ h:Int)throws->[Bool] {
    let (labels,sizes)=try components(mask,w,h),largest=sizes.dropFirst().max() ?? 0
    guard largest>0 else{return mask};let minimum=Int(ceil(Float(largest)*0.1))
    var output=labels.map{$0 != 0 && sizes[$0]>=minimum};let holeLimit=Int(Float(output.filter{$0}.count)*0.002)
    let (holes,holeSizes)=try components(output.map{!$0},w,h,four:true);var touches=[Bool](repeating:false,count:holeSizes.count)
    for x in 0..<w {touches[holes[x]]=true;touches[holes[(h-1)*w+x]]=true}
    for y in 0..<h {touches[holes[y*w]]=true;touches[holes[y*w+w-1]]=true}
    for i in output.indices {let l=holes[i];if l != 0 && !touches[l] && holeSizes[l]<=holeLimit {output[i]=true}}
    return output
  }
  static func antialias(_ bytes:inout [UInt8],_ w:Int,_ h:Int)throws {
    let source=bytes
    for y in 0..<h {try Task.checkCancellation();for x in 0..<w {
      let value=source[y*w+x];var sum=0,edge=false
      for dy in -1...1 {for dx in -1...1 {
        let nx=x+dx,ny=y+dy,v=nx<0 || ny<0 || nx>=w || ny>=h ? value:source[ny*w+nx]
        edge = edge || v != value;sum+=Int(v)
      }}
      if edge {let average=Float(sum)/(9*255),v=value>127 ? 0.5+0.5*average:0.5*average;bytes[y*w+x]=UInt8((v*255).rounded())}
    }}
  }
  static func finish(_ source:Surface,window:IntRect,step:Int,low:[Bool],width lw:Int,height lh:Int,foreground:SelectionColorModel,background:SelectionColorModel)throws->SelectionMask {
    let w=window.width,h=window.height
    var mask=[UInt8](repeating:0,count:w*h),band=[Bool](repeating:false,count:lw*lh)
    for y in 0..<h {for x in 0..<w {mask[y*w+x]=low[min(lh-1,y/step)*lw+min(lw-1,x/step)] ? 255:0}}
    if step>1 {
      for y in 0..<lh {for x in 0..<lw {
        for dy in -1...1 {for dx in -1...1 {let nx=x+dx,ny=y+dy
          if nx>=0 && ny>=0 && nx<lw && ny<lh && low[ny*lw+nx] != low[y*lw+x] {band[y*lw+x]=true}
        }}
      }}
      func block(_ x:Int,_ y:Int)->Int {min(lh-1,(y-window.y)/step)*lw+min(lw-1,(x-window.x)/step)}
      for ty in stride(from:window.y,to:window.y+h,by:192) {for tx in stride(from:window.x,to:window.x+w,by:192) {
        try Task.checkCancellation()
        let tile=IntRect(x:tx,y:ty,width:min(192,window.x+w-tx),height:min(192,window.y+h-ty))
        var intersects=false
        for by in (ty-window.y)/step...(ty+tile.height-1-window.y)/step {
          for bx in (tx-window.x)/step...(tx+tile.width-1-window.x)/step where band[by*lw+bx] {intersects=true}
        }
        guard intersects else{continue}
        let rx=max(window.x,tx-12),ry=max(window.y,ty-12),right=min(window.x+w,tx+tile.width+12),bottom=min(window.y+h,ty+tile.height+12)
        let rect=IntRect(x:rx,y:ry,width:right-rx,height:bottom-ry),image=try SelectionImage(source,rect:rect),rw=rect.width,rh=rect.height
        var fixed=[UInt8](repeating:0,count:rw*rh),cf=[Float](repeating:0,count:rw*rh),cb=cf
        for y in 0..<rh {for x in 0..<rw {
          let i=y*rw+x,b=block(rx+x,ry+y),label=low[b]
          if !band[b] {fixed[i]=label ? 1:2;continue}
          cf[i]=foreground.cost(image.pixels[i])+(label ? 0:0.4);cb[i]=background.cost(image.pixels[i])+(label ? 0.4:0)
        }}
        let cut=try gridCut(image,foreground:cf,background:cb,fixed:fixed,beta:beta(image))
        for y in 0..<tile.height {for x in 0..<tile.width {mask[(ty-window.y+y)*w+tx-window.x+x]=cut[(ty-ry+y)*rw+tx-rx+x] ? 255:0}}
      }}
    }
    try antialias(&mask,w,h)
    var full=[UInt8](repeating:0,count:source.width*source.height)
    for y in 0..<h {full.replaceSubrange((window.y+y)*source.width+window.x..<(window.y+y)*source.width+window.x+w,with:mask[y*w..<(y+1)*w])}
    return try .init(width:source.width,height:source.height,bytes:full)
  }
}
