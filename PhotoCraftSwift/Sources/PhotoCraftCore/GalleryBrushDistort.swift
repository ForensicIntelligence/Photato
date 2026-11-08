import Foundation

extension GalleryMath {
  static func brushDistort(_ e:GalleryEffect,_ input:[V],_ w:Int,_ h:Int)throws->[V]{
    var c=input;let g=e.get,bg=e.background.rgb
    switch e.filter {
    case .accentedEdges:
      let l=try blur(c.map(lum),w,h,1,0.4+g("smoothness")*0.3),edge=try blur(gradient(l,w,h),w,h,1,g("edgeWidth")*0.5),brightness=g("edgeBrightness")/50
      for i in c.indices{try poll(i);let k=clamp(edge[i]*6);c[i]=map(c[i]){brightness>=0.5 ? $0+(1-$0)*k*(brightness-0.5)*2:$0*(1-k*(0.5-brightness)*2)}}
    case .angledStrokes,.crosshatch:
      let radius=Int(g("strokeLength")/3)
      if e.filter == .crosshatch{let strength=g("strength");for i in c.indices{try poll(i);let n=(hash(i%w,i/w,0,81)-0.5)*0.12*strength;c[i]=map(c[i]){$0+n}}}
      let l=c.map(lum),a=try line3(c,w,h,(1,1),radius);c=try line3(c,w,h,(1,-1),radius)
      if e.filter == .angledStrokes{let balance=g("directionBalance")/100;for i in c.indices{try poll(i);c[i]=mix(a[i],c[i],smooth(1-balance-0.15,1-balance+0.15,l[i]))};c=try unsharp(c,w,h,1,g("sharpness")/10*1.5)}
      else{for i in c.indices{try poll(i);c[i]=mix(a[i],c[i],0.5)};c=try unsharp(c,w,h,1,g("sharpness")/20*3)}
    case .darkStrokes:
      let balance=g("balance")/10,black=g("blackIntensity")/10,white=g("whiteIntensity")/10,l=c.map(lum),a=try line3(c,w,h,(1,1),3),t:Float=0.25+balance*0.5;c=try line3(c,w,h,(1,-1),8)
      for i in c.indices{try poll(i);let dark=a[i]*(1-black*0.85),light=map(c[i]){$0+(1-$0)*white*0.5};c[i]=mix(dark,light,smooth(t-0.1,t+0.1,l[i]))}
    case .inkOutlines:
      let dark=g("darkIntensity")/50,light=g("lightIntensity")/50,l=c.map(lum),edge=try gradient(l,w,h);c=try line3(c,w,h,(1,1),Int(g("strokeLength")/2))
      for i in c.indices{try poll(i);let ink=clamp(edge[i]*5)*dark*1.5,lt=smooth(0.5,1,l[i])*light,dk=smooth(0.5,0,l[i])*dark*0.8;c[i]=map(c[i]){($0+(1-$0)*lt)*(1-dk)*(1-clamp(ink))}}
    case .spatter,.sprayedStrokes:
      let radius=g("sprayRadius"),scale:Float=e.filter == .spatter ? 0.6+g("smoothness")*0.25:1.2
      for i in c.indices{try poll(i);let x=Float(i%w),y=Float(i/w),dx=(noise(x/scale,y/scale,91)-0.5)*2*radius,dy=(noise(x/scale,y/scale,92)-0.5)*2*radius;c[i]=sample(input,w,h,x+0.5+dx,y+0.5+dy)}
      if e.filter == .sprayedStrokes{c=try line3(c,w,h,direction(e.choice("strokeDirection")),Int(g("strokeLength")/2))}
    case .sumiE:
      let width=g("strokeWidth"),pressure=g("strokePressure")/15,contrast=g("contrast")/40;c=try blur3(c,w,h,width*0.2);c=try line3(c,w,h,(1,1),Int(width/2))
      for i in c.indices{try poll(i);let ink=pow(smooth(0.65,0.15,lum(c[i])),1-pressure*0.5);c[i]=map(c[i]){clamp(($0-0.5)*(1+contrast)+0.5)*(1-ink*0.9*(0.5+contrast))}}
    case .diffuseGlow:
      let grain=g("graininess")/10,glow=g("glowAmount")/20,threshold=0.2+g("clearAmount")/20*0.7
      for i in c.indices{try poll(i);var m=smooth(threshold-0.3,threshold+0.1,lum(c[i]))*glow*1.4;if hash(i%w,i/w,0,101)<grain*0.3*(m+0.15){m += 0.5};c[i]=mix(c[i],bg,clamp(m))}
    case .glass:
      if let texture=e.texture {return try customGlass(input,w,h,e,texture)}
      let distortion=g("distortion"),step=0.5+g("smoothness")*0.5,kind=e.choice("texture"),scale=clamp(g("scaling")/100,0.5,2),sign:Float=e.flag("invert") ? -1:1,limit=distortion*2
      for i in c.indices{try poll(i);let x=Float(i%w),y=Float(i/w),gx=texture(kind,x+step,y,scale)-texture(kind,x-step,y,scale),gy=texture(kind,x,y+step,scale)-texture(kind,x,y-step,scale),dx=clamp(gx*sign*distortion*3,-limit,limit),dy=clamp(gy*sign*distortion*3,-limit,limit);c[i]=sample(input,w,h,x+0.5+dx,y+0.5+dy)}
    case .oceanRipple:
      let scale=2+g("rippleSize")*1.2,magnitude=g("rippleMagnitude")*0.9
      for i in c.indices{try poll(i);let x=Float(i%w),y=Float(i/w),dx=(noise(x/scale,y/scale,111)-0.5)*2*magnitude,dy=(noise(x/scale,y/scale,112)-0.5)*2*magnitude;c[i]=sample(input,w,h,x+0.5+dx,y+0.5+dy)}
    case .glowingEdges:
      c=try blur3(c,w,h,0.3+g("smoothness")*0.25);var edges=[V](repeating:.zero,count:c.count)
      for channel in 0..<3{let plane=try gradient(c.map{$0[channel]},w,h);for i in c.indices{try poll(i);edges[i][channel]=plane[i]}}
      edges=try blur3(edges,w,h,g("edgeWidth")*0.4);let k=2+g("edgeBrightness")*1.2
      for i in c.indices{try poll(i);c[i]=map(edges[i]){clamp($0*k)}}
    default:throw CraftError.invalid("Not a Brush Strokes/Distort/Stylize gallery effect.")
    };return c
  }
}
