import Foundation
import Darwin
import XCTest
@testable import PhotoCraftCore

final class StrictAtomicFileWriterTests:XCTestCase {
  func folder()throws->URL {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    let physical=root.withUnsafeFileSystemRepresentation{path in path.flatMap{Darwin.realpath($0,nil)}}
    guard let physical else{throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
    defer{Darwin.free(physical)}
    return URL(fileURLWithFileSystemRepresentation:physical,isDirectory:true,relativeTo:nil)
  }
  func testStrictWriterPublishesRegularFileAndRejectsFinalOrAncestorSymlinks()throws {
    let root=try folder();defer{try? FileManager.default.removeItem(at:root)}
    let original=root.appendingPathComponent("source"),link=root.appendingPathComponent("alias")
    try Data([1,2]).write(to:original)
    let transaction=try AtomicFileWriter(to:original,maximumBytes:10,followSymbolicLinks:false)
    try transaction.append(Data([3,4,5]));try transaction.commit();XCTAssertEqual(try Data(contentsOf:original),Data([3,4,5]))
    try FileManager.default.createSymbolicLink(at:link,withDestinationURL:original)
    XCTAssertThrowsError(try AtomicFileWriter(to:link,followSymbolicLinks:false))
    let directory=root.appendingPathComponent("directory"),alias=root.appendingPathComponent("directory-alias")
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
    try FileManager.default.createSymbolicLink(at:alias,withDestinationURL:directory)
    XCTAssertThrowsError(try AtomicFileWriter(to:alias.appendingPathComponent("new"),followSymbolicLinks:false))
    XCTAssertFalse(FileManager.default.fileExists(atPath:directory.appendingPathComponent("new").path))
    XCTAssertEqual(try Data(contentsOf:original),Data([3,4,5]))
  }
  func testStrictWriterRejectsChangedParentAndKeepsUnrelatedData()throws {
    let root=try folder();defer{try? FileManager.default.removeItem(at:root)}
    let parent=root.appendingPathComponent("folder"),moved=root.appendingPathComponent("moved")
    try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:false)
    let original=parent.appendingPathComponent("source");try Data([1]).write(to:original)
    let transaction=try AtomicFileWriter(to:original,followSymbolicLinks:false);try transaction.append(Data([2]))
    try FileManager.default.moveItem(at:parent,to:moved);try FileManager.default.createSymbolicLink(at:parent,withDestinationURL:moved)
    XCTAssertThrowsError(try transaction.commit());transaction.discard()
    XCTAssertEqual(try Data(contentsOf:moved.appendingPathComponent("source")),Data([1]))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:moved.path),["source"])
  }
}
