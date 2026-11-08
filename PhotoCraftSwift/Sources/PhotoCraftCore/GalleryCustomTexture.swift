import Foundation

extension GalleryMath {
  static func customTexturize(_ input:[V],_ w:Int,_ e:GalleryEffect,_ source:GalleryTextureSource,_ relief:Float?) throws -> [V] {
    let r=relief ?? e.get("relief");guard r>0 else{return input}
    let scale=clamp(e.get("scaling")/100,0.5,2),l=light(e.choice("light")),k=r/50*3,sign:Float=e.flag("invert") ? -1:1
    var out=input
    for i in input.indices {
      try poll(i);let x=Float(i%w),y=Float(i/w)
      let gx=(source.sample(x:x+1,y:y,scale:scale)-source.sample(x:x-1,y:y,scale:scale))*0.5*sign
      let gy=(source.sample(x:x,y:y+1,scale:scale)-source.sample(x:x,y:y-1,scale:scale))*0.5*sign
      out[i]=input[i]*clamp(shade(gx,gy,l,k),0,2)
    };return out
  }
  static func customGlass(_ input:[V],_ w:Int,_ h:Int,_ e:GalleryEffect,_ source:GalleryTextureSource) throws -> [V] {
    let distortion=e.get("distortion"),step=0.5+e.get("smoothness")*0.5,scale=clamp(e.get("scaling")/100,0.5,2),sign:Float=e.flag("invert") ? -1:1,limit=distortion*2
    var out=input
    for i in input.indices {
      try poll(i);let x=Float(i%w),y=Float(i/w)
      let gx=source.sample(x:x+step,y:y,scale:scale)-source.sample(x:x-step,y:y,scale:scale)
      let gy=source.sample(x:x,y:y+step,scale:scale)-source.sample(x:x,y:y-step,scale:scale)
      let dx=clamp(gx*sign*distortion*3,-limit,limit),dy=clamp(gy*sign*distortion*3,-limit,limit)
      out[i]=sample(input,w,h,x+0.5+dx,y+0.5+dy)
    };return out
  }
}
