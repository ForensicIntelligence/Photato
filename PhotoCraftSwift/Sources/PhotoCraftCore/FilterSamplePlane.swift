import Darwin
import Foundation

/// Private, checked Float64 filter scratch. Only completed planes are mapped,
/// read-only; no mutable mapping or full-image heap array is published.
struct FilterSamplePlane {
  typealias Sample=SIMD4<Double>
  let width:Int,height:Int
  let constant:Sample?
  private let mapped:Mapped?
  init(width:Int,height:Int,constant:Sample) {self.width=width;self.height=height;self.constant=constant;mapped=nil}
  private init(width:Int,height:Int,mapped:Mapped) {self.width=width;self.height=height;constant=nil;self.mapped=mapped}
  @inline(__always) func sample(_ x:Int,_ y:Int)->Sample {
    constant ?? mapped!.sample(y*width+x)
  }
  private final class File {
    let fd:Int32
    init()throws {
      let url=FileManager.default.temporaryDirectory.appendingPathComponent("photato-filter-"+UUID().uuidString)
      let value=url.withUnsafeFileSystemRepresentation {open($0!,O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,S_IRUSR|S_IWUSR)}
      guard value>=0 else {throw RasterScratchFailure.io(operation:"filter creation",code:errno)}
      guard unlink(url.path)==0 else {let code=errno;close(value);throw RasterScratchFailure.io(operation:"filter unlink",code:code)}
      fd=value
    }
    deinit {close(fd)}
  }
  private final class Mapped {
    let file:File,memory:UnsafeMutableRawPointer,bytes:Int
    init(file:File,bytes:Int)throws {
      let p=mmap(nil,bytes,PROT_READ,MAP_SHARED,file.fd,0)
      guard let p,p != MAP_FAILED else {throw RasterScratchFailure.io(operation:"filter mapping",code:errno)}
      self.file=file;self.bytes=bytes;memory=p
    }
    @inline(__always) func sample(_ i:Int)->Sample {memory.load(fromByteOffset:i*32,as:Sample.self)}
    deinit {munmap(memory,bytes)}
  }
  final class Writer {
    let width:Int,height:Int
    private let file:File
    private let bytes:Int,maximumBytes:Int
    private var written=0,finished=false,failed=false
    init(width:Int,height:Int,maximumBytes:Int)throws {
      _ = try Surface(width:width,height:height)
      guard MemoryLayout<Sample>.stride==32,maximumBytes>=0 else {throw CraftError.invalid("Invalid filter scratch layout/budget.")}
      self.width=width;self.height=height;bytes=width*height*32;self.maximumBytes=maximumBytes
      guard bytes<=maximumBytes else {throw RasterScratchFailure.capacity(requiredBytes:bytes,limitBytes:maximumBytes)}
      file=try File()
    }
    func row(_ values:[Sample],x:Int=0,y:Int)throws {
      do {
        try Task.checkCancellation()
        guard !finished,!failed,x>=0,y>=0,y<height,!values.isEmpty,values.count<=width-x,
          values.allSatisfy({p in (0..<4).allSatisfy{p[$0].isFinite}}),
          written<=bytes-values.count*32 else {throw CraftError.invalid("Invalid filter scratch write/lifecycle.")}
        try values.withUnsafeBytes {raw in
          var offset=0
          while offset<raw.count {
            try Task.checkCancellation()
            let count=min(64*1024,raw.count-offset)
            let n=pwrite(file.fd,raw.baseAddress!.advanced(by:offset),count,off_t((y*width+x)*32+offset))
            if n<0 && errno==EINTR {continue}
            guard n>0 else {throw RasterScratchFailure.io(operation:"filter write",code:errno)}
            offset+=n;written+=n
          }
        }
      }catch{failed=true;throw error}
    }
    func finish()throws->FilterSamplePlane {
      do {
        try Task.checkCancellation()
        guard !finished,!failed,written==bytes else {throw CraftError.invalid("Incomplete filter scratch plane.")}
        while fsync(file.fd) != 0 {if errno != EINTR {throw RasterScratchFailure.io(operation:"filter sync",code:errno)};try Task.checkCancellation()}
        var info=stat();guard fstat(file.fd,&info)==0,info.st_size==bytes else {throw CraftError.invalid("Invalid filter scratch extent.")}
        let result=try Mapped(file:file,bytes:bytes);finished=true
        return FilterSamplePlane(width:width,height:height,mapped:result)
      }catch{failed=true;throw error}
    }
  }
}
