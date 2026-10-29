import AppKit
import CryptoKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

struct PreparedPDFSource: Sendable {
  let data: Data
  let name: String
  static func read(_ url: URL) throws -> Self {
    try RecoverySourceReader.withStableMetadata {
      let reader = try RecoverySourceReader(url)
      let file = try FileHandle(forReadingFrom:url);defer {try? file.close()}
      var data = Data()
      while true {
        try Task.checkCancellation()
        guard let chunk = try file.read(upToCount:min(65536,PDFImport.maximumSourceBytes+1-data.count)),!chunk.isEmpty else {break}
        data.append(chunk)
        guard data.count <= PDFImport.maximumSourceBytes else {throw CraftError.invalid("Choose a PDF no larger than64MiB.")}
      }
      let fingerprint = try reader.finish()
      guard fingerprint.sha256 == SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined() else {throw DocumentPersistenceConflict.changed}
      guard PDFImport.recognizes(data) else {throw CraftError.invalid("Choose a PDF file.")}
      return Self(data:data,name:url.deletingPathExtension().lastPathComponent)
    }
  }
}

enum PDFImportContent: String,CaseIterable {case pages,images}

@MainActor @Observable final class PDFImportWorkspace {
  let source: PreparedPDFSource
  let placement: Bool
  var name: String
  var password = ""
  var settings = PDFImportSettings()
  var imageSettings = PDFImageImportSettings()
  var content = PDFImportContent.pages
  var imageInfo: [PDFImageInfo]?
  var items: [Int] {content == .pages ? (info?.pages.map(\.number) ?? []):(imageInfo?.map(\.number) ?? [])}
  var selected = Set([1])
  var widthText = ""
  var heightText = ""
  var thumbnailSize = 120
  var info: PDFImportInfo?
  var thumbnails: [Int:Data] = [:]
  var error: String?
  var loading = false
  var busy = false
  var finished = false
  @ObservationIgnored var completion: ((Result<[CraftDocument],Error>) -> Void)?
  @ObservationIgnored var placementCompletion: ((Result<PDFSmartObjectOptions,Error>) -> Void)?
  @ObservationIgnored var loadTask: Task<Void,Never>?
  @ObservationIgnored var task: Task<Void,Never>?
  @ObservationIgnored var worker: Task<[CraftDocument],Error>?
  @ObservationIgnored var previewTask: Task<Void,Never>?
  @ObservationIgnored private var previewGeneration = UUID()
  @ObservationIgnored private var pendingPreviews: [Int] = []
  @ObservationIgnored private var visiblePages = Set<Int>()
  @ObservationIgnored private var previewOrder: [Int] = []
  @ObservationIgnored private var selectionAnchor: Int?
  init(source: PreparedPDFSource,placement: Bool = false) {
    self.source = source;self.placement = placement;name = source.name
    if placement {settings.resolution = 72}
  }
  func inspect() {
    guard !finished,!loading,!busy else{return};loading = true;error = nil
    let data = source.data,password = password,content = content
    loadTask = Task { [weak self] in
      guard let self else{return};defer {self.loading = false}
      do {
        let job = Task.detached(priority:.userInitiated) {
          let pages = try PDFImport.inspect(data,password:password)
          let images = content == .images ? try PDFImages.inspect(data,password:password):nil
          return (pages,images)
        }
        let info = try await withTaskCancellationHandler {try await job.value} onCancel:{job.cancel()}
        try Task.checkCancellation();guard !self.finished else{return}
        self.info = info.0;self.imageInfo = info.1;self.selected = self.selected.intersection(self.items)
        if self.selected.isEmpty,let first = self.items.first {self.selected = [first]}
        if self.selectionAnchor == nil {self.selectionAnchor = self.selected.sorted().first}
      } catch is CancellationError {} catch {self.error = error.localizedDescription}
    }
  }
  func changeContent(_ value: PDFImportContent) {
    guard value != content,!loading,!busy,!finished else{return}
    content = value;selected = [1];selectionAnchor = nil
    previewGeneration = UUID();previewTask?.cancel();previewTask = nil
    pendingPreviews = [];visiblePages = [];previewOrder = [];thumbnails = [:]
    inspect()
  }
  func imageOptions() throws -> PDFImageImportSettings {
    var result = imageSettings;result.images = selected.sorted();try result.validate();return result
  }
  func select(_ page: Int,extend: Bool,toggle: Bool) {
    guard !busy,!finished,info != nil,items.contains(page) else{return}
    if placement {selected = [page];selectionAnchor = page}
    else if extend,let anchor = selectionAnchor {selected.formUnion(min(anchor,page)...max(anchor,page))}
    else if toggle {if !selected.insert(page).inserted {selected.remove(page)};selectionAnchor = page}
    else {selected = [page];selectionAnchor = page}
  }
  func options() throws -> PDFImportSettings {
    var result = settings;result.pages = selected.sorted()
    func dimension(_ value: String) throws -> Int? {
      let text = value.trimmingCharacters(in:.whitespacesAndNewlines)
      if text.isEmpty {return nil}
      guard let value = Int(text),value > 0 else {throw CraftError.invalid("Enter positive pixel dimensions, or leave them blank for the chosen resolution.")}
      return value
    }
    result.width = try dimension(widthText);result.height = try dimension(heightText)
    try result.validate();return result
  }
  func showThumbnail(_ page: Int) {
    visiblePages.insert(page)
    guard !finished,info != nil,items.contains(page),thumbnails[page] == nil,!pendingPreviews.contains(page) else{return}
    pendingPreviews.append(page);schedulePreviews()
  }
  func hideThumbnail(_ page: Int) {visiblePages.remove(page);pendingPreviews.removeAll{$0 == page}}
  private func schedulePreviews() {
    guard previewTask == nil,!finished else{return}
    let generation = previewGeneration,content = content
    previewTask = Task { [weak self] in
      guard let self else{return};defer {if self.previewGeneration == generation {self.previewTask = nil}}
      while !self.pendingPreviews.isEmpty,!Task.isCancelled,!self.finished {
        let page = self.pendingPreviews.removeFirst(),data = self.source.data,password = self.password
        let job = Task.detached(priority:.utility) {try content == .pages ? PDFImport.thumbnail(data,page:page,password:password):PDFImages.thumbnail(data,image:page,password:password)}
        if let image = try? await withTaskCancellationHandler(operation:{try await job.value},onCancel:{job.cancel()}),!Task.isCancelled,!self.finished,self.previewGeneration == generation {
          self.thumbnails[page] = image;self.previewOrder.removeAll{$0 == page};self.previewOrder.append(page)
          while self.thumbnails.count > 64,let old = self.previewOrder.first(where:{!self.visiblePages.contains($0)}) {
            self.previewOrder.removeAll{$0 == old};self.thumbnails.removeValue(forKey:old)
          }
        }
      }
    }
  }
  func run() {
    guard !finished,!loading,!busy,info != nil else{return}
    if placement {
      do {
        guard selected.count == 1,let number = selected.first,items.contains(number) else {throw CraftError.invalid("Select one PDF page or image.")}
        guard info?.encrypted == false else {throw CraftError.unsupported("Place an unencrypted PDF source.")}
        var options = PDFSmartObjectOptions()
        options.antialias = settings.antialias
        if content == .pages {options.page = number;options.crop = settings.crop}
        else {options.image = number}
        try options.settings.validate()
        finishPlacement(.success(options))
      } catch {self.error = error.localizedDescription}
      return
    }
    var options = PDFImportSettings(),imageOptions = PDFImageImportSettings()
    do {if content == .pages {options = try self.options()} else {imageOptions = try self.imageOptions()}} catch {self.error = error.localizedDescription;return}
    let data = source.data,name = name,password = password,content = content
    let pageOptions = options,selectedImages = imageOptions
    busy = true;error = nil
    task = Task { [weak self] in
      guard let self else{return};defer {self.busy = false;self.worker = nil}
      do {
        let job = Task.detached(priority:.userInitiated) {try content == .pages ? PDFImport.pages(data,name:name,settings:pageOptions,password:password):PDFImages.documents(data,name:name,settings:selectedImages,password:password)};self.worker = job
        let result = try await withTaskCancellationHandler {try await job.value} onCancel:{job.cancel()}
        try Task.checkCancellation();guard !self.finished else{return};self.finish(.success(result))
      } catch is CancellationError {if !self.finished {self.error = "PDF import cancelled."}} catch {self.error = error.localizedDescription}
    }
  }
  func cancel() {
    if placement {finishPlacement(.failure(CancellationError()))} else {finish(.failure(CancellationError()))}
  }
  private func finishPlacement(_ result: Result<PDFSmartObjectOptions,Error>) {
    guard !finished else{return};finished = true
    loadTask?.cancel();task?.cancel();worker?.cancel();previewTask?.cancel();password = ""
    let callback = placementCompletion;placementCompletion = nil;callback?(result)
  }
  private func finish(_ result: Result<[CraftDocument],Error>) {
    guard !finished else{return};finished = true
    loadTask?.cancel();task?.cancel();worker?.cancel();previewTask?.cancel();password = ""
    let callback = completion;completion = nil;callback?(result)
  }
}

extension DocumentOpening {
  func importPDF(_ url: URL) async throws -> [CraftDocument] {
    let reader = Task.detached(priority:.userInitiated) {try PreparedPDFSource.read(url)}
    let source = try await withTaskCancellationHandler {try await reader.value} onCancel:{reader.cancel()}
    try Task.checkCancellation()
    let model = PDFImportWorkspace(source:source);pdfWorkspace = model
    defer {pdfWindow?.close();pdfWindow = nil;pdfWorkspace = nil}
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {continuation in
        model.completion = {continuation.resume(with:$0)};model.inspect()
        if let pdfPresenter {pdfPresenter(model)} else {
          let window = PDFImportWindow(model:model);pdfWindow = window;window.showWindow(nil)
        }
      }
    } onCancel:{Task {@MainActor in model.cancel()}}
  }
}
