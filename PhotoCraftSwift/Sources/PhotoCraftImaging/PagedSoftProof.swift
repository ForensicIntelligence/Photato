import Foundation
import PhotoCraftCore

/// Bounded preparation around the existing proof kernel. The proxy carries the
/// original numeric/profile interpretation; its supplied composite is the exact
/// source patch, not a resampled or requantized working image.
enum PagedSoftProof {
  static let patchWidth=2048,patchHeight=64
  static func surface(_ document:CraftDocument,composite:Surface?=nil,settings:ProofSettings)throws->Surface {
    try Task.checkCancellation();try document.validate();try SoftProof.validate(settings,in:document)
    let original=try composite ?? Renderer.composite(document)
    guard original.width==document.width,original.height==document.height else{throw CraftError.invalid("Proof preview dimensions differ from the document.")}
    let native=SoftProof.retainedComponents(document)
    let rgbProfile:Data?
    if native==nil {rgbProfile=try ColorManagement.space(for:document).copyICCData()as Data? ?? NativeModeProfile.standard(.rgb,depth:document.depth)}else{rgbProfile=nil}
    var sources=[original]
    if let native {
      for c in 0..<native.mode.componentCount{sources.append(try native.channel(c))}
      sources.append(try native.opacityChannel())
    }
    func proof(_ composite:Surface,native:NativeModeRaster?)throws->Surface {
      var proxy=try CraftDocument(width:composite.width,height:composite.height,depth:document.depth)
      if let native {
        proxy.modeDescriptor=try .init(mode:native.mode,depth:native.depth,profile:native.profile,intent:native.intent)
        proxy.layers[0].nativeMode=native
      }else{proxy.workingICC=rgbProfile}
      // The valid layer placeholder is not an input: the legacy kernel reads
      // retained components or the explicitly supplied original composite.
      try proxy.validate()
      return try SoftProof.surface(proxy,composite:composite,settings:settings)
    }
    var constant=try Surface(width:1,height:1,depth:original.depth,colorEncoding:original.colorEncoding)
    if original.colorEncoding == .linearRGB {constant.setLinearPixel(x:0,y:0,try original.interpretingSamples(as:.sRGB).defaultPixel)}
    else{constant.setPixel(x:0,y:0,original.defaultPixel)}
    let constantNative:NativeModeRaster?
    if let native {
      var value=try NativeModeRaster(width:1,height:1,mode:native.mode,depth:native.depth,profile:native.profile,intent:native.intent)
      for c in 0...native.mode.componentCount{try value.set(sources[c+1].defaultPixel.r,component:c,index:0)}
      constantNative=value
    }else{constantNative=nil}
    let fill=try proof(constant,native:constantNative).pixel(x:0,y:0)
    let builder=try Surface.PagedBuilder(width:document.width,height:document.height,depth:.f32,fill:fill,colorEncoding:.sRGB)
    let columns=(document.width+63)/64
    var keys=TileKeys(sources).makeIterator(),next=keys.next()
    while let first=next {
      try Task.checkCancellation()
      let row=first/columns;var end=first+1;next=keys.next()
      while let key=next,key==end,key/columns==row,end-first<patchWidth/64{end+=1;next=keys.next()}
      let x=first%columns*64,y=row*64
      let area=IntRect(x:x,y:y,width:min(document.width-x,(end-first)*64),height:min(patchHeight,document.height-y))
      let patch=try proof(original.cropped(to:area),native:native?.cropped(to:area))
      try builder.append(patch,atX:x,atY:y)
    }
    try Task.checkCancellation();return try builder.finish()
  }
  private struct TileKeys:Sequence {
    let sources:[Surface]
    init(_ sources:[Surface]){self.sources=sources}
    func makeIterator()->AnyIterator<Int> {
      var iterators=sources.map{$0.storedTileKeys.makeIterator()}
      var heads=iterators.indices.map{iterators[$0].next()}
      return AnyIterator {
        var first:Int?
        for head in heads{if let head{first=first.map{Swift.min($0,head)} ?? head}}
        guard let key=first else{return nil}
        for i in heads.indices where heads[i]==key{heads[i]=iterators[i].next()}
        return key
      }
    }
  }
}
