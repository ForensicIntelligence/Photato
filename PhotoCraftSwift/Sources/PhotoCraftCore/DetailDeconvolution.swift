import Accelerate
import Foundation

/// Wiener-style inverse of a sampled disk or line PSF. Fixed tile interiors bound
/// memory; an edge-replicated halo separates output pixels from FFT wraparound.
enum DetailDeconvolution {
  static func restore(_ planes:[[Float]],_ w:Int,_ h:Int,_ settings:SmartSharpenSettings)throws->[[Float]] {
    let tile=256,halo=max(16,Int(ceil(settings.radius*4))+8)
    var side=1,log=0
    while side<tile+2*halo { side *= 2;log += 1 }
    let count=side*side
    guard let setup=vDSP_create_fftsetup(vDSP_Length(log),FFTRadix(kFFTRadix2)) else { throw CraftError.invalid("Unable to allocate sharpening transform.") }
    defer { vDSP_destroy_fftsetup(setup) }
    func fft(_ real:inout [Float],_ imaginary:inout [Float],_ direction:FFTDirection) {
      real.withUnsafeMutableBufferPointer { r in imaginary.withUnsafeMutableBufferPointer { i in
        var split=DSPSplitComplex(realp:r.baseAddress!,imagp:i.baseAddress!)
        vDSP_fft2d_zip(setup,&split,1,vDSP_Stride(side),vDSP_Length(log),vDSP_Length(log),direction)
      } }
    }
    var kernel=[Float](repeating:0,count:count),imaginary=kernel
    func add(_ x:Int,_ y:Int,_ value:Float) { kernel[((y%side+side)%side)*side+(x%side+side)%side] += value }
    if settings.remove == .lens {
      let r=Int(ceil(settings.radius+0.5))
      for y in -r...r { for x in -r...r { add(x,y,Float(max(0,min(1,settings.radius+0.5-hypot(Double(x),Double(y)))))) } }
    } else {
      let a=settings.angle * .pi/180,samples=max(2,Int(ceil(settings.radius*8)))
      for i in 0...samples { let t=(Double(i)/Double(samples)*2-1)*settings.radius,x=t*cos(a),y = -t*sin(a),ix=Int(floor(x)),iy=Int(floor(y)),fx=Float(x-Double(ix)),fy=Float(y-Double(iy));add(ix,iy,(1-fx)*(1-fy));add(ix+1,iy,fx*(1-fy));add(ix,iy+1,(1-fx)*fy);add(ix+1,iy+1,fx*fy) }
    }
    let total=kernel.reduce(0,+);guard total>0 else { return planes };kernel=kernel.map{$0/total}
    fft(&kernel,&imaginary,FFTDirection(FFT_FORWARD))
    let regularization=Float(0.006+0.12*settings.reduceNoise/100)
    for i in 0..<count { let denominator=kernel[i]*kernel[i]+imaginary[i]*imaginary[i]+regularization,k=(1+regularization)/denominator;kernel[i] *= k;imaginary[i] *= -k }
    var output=planes
    for y0 in stride(from:0,to:h,by:tile) { for x0 in stride(from:0,to:w,by:tile) {
      for c in planes.indices {
        try Task.checkCancellation();var real=[Float](repeating:0,count:count),imag=[Float](repeating:0,count:count)
        for y in 0..<side { let sy=min(h-1,max(0,y0+y-halo));for x in 0..<side { let sx=min(w-1,max(0,x0+x-halo));real[y*side+x]=planes[c][sy*w+sx] } }
        fft(&real,&imag,FFTDirection(FFT_FORWARD))
        for i in 0..<count { let a=real[i],b=imag[i];real[i]=a*kernel[i]-b*imaginary[i];imag[i]=a*imaginary[i]+b*kernel[i] }
        fft(&real,&imag,FFTDirection(FFT_INVERSE))
        // vDSP's complex FFT inverse is unnormalized. The independent DC fixture
        // checks this scale as well as preserving constant colours at tile edges.
        let scale=1/Float(count)
        for y in 0..<min(tile,h-y0) { for x in 0..<min(tile,w-x0) { output[c][(y0+y)*w+x0+x]=real[(y+halo)*side+x+halo]*scale } }
      }
    } }
    return output
  }
}
