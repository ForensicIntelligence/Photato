import AppKit
import PhotoCraftCore

@MainActor extension EditorStore{
  var nativePixelPaintTarget:PixelPaintTarget?{
    guard !smartFilterMaskEditing,pathTarget==nil else{return nil}
    if let channel=editingChannel{return .channel(channel)}
    guard !editingComponent,document.inkMode==nil,let id=document.activeLayerID else{return nil}
    return editingMask ? .mask(id):.layer(id)
  }
  var canUsePixelPaint:Bool{guard canSelectComponentTarget,let target=nativePixelPaintTarget else{return false};return PixelFillStroke.available(document,target:target)}
  var canUsePixelStroke:Bool { canUsePixelPaint && !hasHiddenQuickMaskEditingTarget }
  var pixelFillPatterns:[RasterPattern]{var seen=Set<String>();return ((document.patterns ?? [])+patterns.items).filter{seen.insert($0.id).inserted}}
  var canFillWithPattern:Bool{canUsePixelPaint && !patterns.busy && !pixelFillPatterns.isEmpty}
  func applyPixelPaint(_ kind:PixelPaintKind,settings:PixelPaintSettings,pattern:RasterPattern?=nil,placement:PatternPlacement?=nil){
    guard canUsePixelPaint,let target=nativePixelPaintTarget else{return}
    do{try settings.validate(kind)}catch{self.error=error.localizedDescription;return}
    let request=PixelPaintRequest(kind,target:target,settings:settings,pattern:pattern,placement:placement),prepare=pixelPaintPreparation,isChannel:Bool;if case .channel=target{isChannel=true}else{isChannel=false}
    do { try validateQuickMaskVisibility(.pixelPaint(request)) } catch { self.error=error.localizedDescription; return }
    if kind == .stroke{lastPixelStroke=settings}else{lastPixelFill=settings;if let pattern{lastPixelFillContents="Pattern";lastPixelFillPatternID=pattern.id}}
    performPreparedGeometry(label:kind.title,allowAuxiliary:isChannel,prepare:{source in try PreparedEdit(command:prepare(source,request),document:source)},validateCommit:{[weak self] in guard self?.nativePixelPaintTarget==target else{throw CraftError.invalid("The Fill/Stroke target changed. Try again.")}})
  }
}
@MainActor final class PixelPaintAccessory:NSObject{
  let view:NSView
  let color:NSColorWell,width=NSTextField(string:"1"),location=NSPopUpButton(),mode=NSPopUpButton(),opacity=NSTextField(string:"100"),opacitySlider=NSSlider(value:100,minValue:0,maxValue:100,target:nil,action:nil),preserve=NSButton(checkboxWithTitle:"Preserve Transparency",target:nil,action:nil)
  let kind:PixelPaintKind
  let contents=NSPopUpButton(),customPattern=NSPopUpButton(),sourceLabel=NSTextField(labelWithString:"Color:"),foreground:Pixel,background:Pixel
  let patternItems:[RasterPattern]
  var chosenPattern:RasterPattern?{patternItems.indices.contains(customPattern.indexOfSelectedItem) ? patternItems[customPattern.indexOfSelectedItem]:nil}
  init(kind:PixelPaintKind,settings:PixelPaintSettings,scalar:Bool,background:Pixel = .white,allowContentAware:Bool=false,patterns:[RasterPattern]=[],selectedPatternID:String?=nil,patternBusy:Bool=false){
    self.kind=kind;patternItems=patterns;foreground=settings.color;self.background=background;view=NSView(frame:.init(x:0,y:0,width:340,height:kind == .stroke ? 230:200));color=NSColorWell(frame:.init(x:110,y:0,width:70,height:26));super.init()
    let ink=settings.color;color.color=NSColor(srgbRed:CGFloat(ink.r),green:CGFloat(ink.g),blue:CGFloat(ink.b),alpha:CGFloat(ink.a));width.stringValue=String(settings.width);opacity.stringValue=String(Double(settings.opacity)*100);opacitySlider.doubleValue=Double(settings.opacity)*100
    location.addItems(withTitles:PixelStrokeLocation.allCases.map(\.rawValue));location.selectItem(withTitle:settings.location.rawValue);mode.addItems(withTitles:BlendMode.allCases.map(\.rawValue));mode.selectItem(withTitle:settings.mode.rawValue);preserve.state=settings.preserveTransparency ? .on:.off;preserve.isEnabled = !scalar
    opacitySlider.target=self;opacitySlider.action=#selector(sliderChanged);opacity.target=self;opacity.action=#selector(fieldChanged)
    func row(_ label:String,_ control:NSView,_ y:Double){let text=NSTextField(labelWithString:label);text.frame = .init(x:0,y:y+3,width:100,height:20);control.frame = .init(x:110,y:y,width:220,height:26);view.addSubview(text);view.addSubview(control);control.setAccessibilityLabel(label)}
    if kind == .fill{contents.addItems(withTitles:["Foreground Color","Background Color","Color…","Black","50% Gray","White","Pattern"]);contents.item(withTitle:"Pattern")?.isEnabled = !patterns.isEmpty && !patternBusy;if allowContentAware{contents.addItem(withTitle:"Content-Aware…")};contents.target=self;contents.action=#selector(contentsChanged)}
    customPattern.addItems(withTitles:patterns.map(\.displayName));if let id=selectedPatternID,let index=patterns.firstIndex(where:{$0.id==id}){customPattern.selectItem(at:index)};customPattern.isEnabled = !patterns.isEmpty && !patternBusy;customPattern.isHidden=true
    var y=Double(view.frame.height)-28
    if kind == .fill{row("Contents:",contents,y);y-=32}
    if kind == .stroke{row("Width (px):",width,y);y-=32;row("Location:",location,y);y-=32}
    sourceLabel.frame = .init(x:0,y:y+3,width:106,height:20);view.addSubview(sourceLabel);color.frame = .init(x:110,y:y,width:220,height:26);customPattern.frame=color.frame;view.addSubview(color);view.addSubview(customPattern);color.setAccessibilityLabel("Color");customPattern.setAccessibilityLabel("Custom Pattern");y-=32;row("Mode:",mode,y);y-=32
    let label=NSTextField(labelWithString:"Opacity:");label.frame = .init(x:0,y:y+3,width:100,height:20);view.addSubview(label);opacity.frame = .init(x:110,y:y,width:60,height:24);view.addSubview(opacity);opacity.setAccessibilityLabel("Opacity (%)");opacitySlider.frame = .init(x:178,y:y,width:150,height:24);view.addSubview(opacitySlider);opacitySlider.setAccessibilityLabel("Opacity slider");y-=32
    preserve.frame = .init(x:110,y:y,width:220,height:24);view.addSubview(preserve)
  }
  @objc func contentsChanged(){let isPattern=contents.titleOfSelectedItem=="Pattern";color.isHidden=isPattern;customPattern.isHidden = !isPattern;sourceLabel.stringValue=isPattern ? "Custom Pattern:":"Color:";let colors:[Pixel?]=[foreground,background,nil,.black,Pixel(0.5,0.5,0.5),.white];if colors.indices.contains(contents.indexOfSelectedItem),let ink=colors[contents.indexOfSelectedItem]{color.color=NSColor(srgbRed:CGFloat(ink.r),green:CGFloat(ink.g),blue:CGFloat(ink.b),alpha:CGFloat(ink.a))}}
  @objc func sliderChanged(){opacity.stringValue=String(format:"%.0f",opacitySlider.doubleValue)}
  @objc func fieldChanged(){if let value=Double(opacity.stringValue),value.isFinite,(0...100).contains(value){opacitySlider.doubleValue=value}}
  func settings()throws->PixelPaintSettings{
    guard let ink=color.color.usingColorSpace(.sRGB),let percent=Float(opacity.stringValue),percent.isFinite,(0...100).contains(percent),let blend=mode.titleOfSelectedItem.flatMap(BlendMode.init(rawValue:)),let alignment=location.titleOfSelectedItem.flatMap(PixelStrokeLocation.init(rawValue:)),kind != .stroke || Int(width.stringValue) != nil else{throw CraftError.invalid("Enter a valid color, opacity, mode and whole-pixel width.")}
    var result=PixelPaintSettings(color:Pixel(Float(ink.redComponent),Float(ink.greenComponent),Float(ink.blueComponent),Float(ink.alphaComponent)));result.opacity=percent/100;result.mode=blend;result.width=Int(width.stringValue) ?? 1;result.location=alignment;result.preserveTransparency=preserve.isEnabled && preserve.state == .on;try result.validate(kind);return result
  }
}
extension AppDelegate{
  @objc func strokeSelectionDialog(){presentPixelPaint(.stroke)}
  func presentPixelPaint(_ kind:PixelPaintKind){
    guard let store else{return};store.finishNumericField();store.finishLayerName();guard store.canUsePixelPaint else{return};let source=store.document,target=store.nativePixelPaintTarget
    var settings=kind == .stroke ? store.lastPixelStroke:store.lastPixelFill;settings.color=store.brush.color
    let scalar:Bool;if let target{switch target{case .mask,.channel:scalar=true;default:scalar=false}}else{scalar=false}
    let accessory=PixelPaintAccessory(kind:kind,settings:settings,scalar:scalar,background:store.backgroundColor,allowContentAware:store.canBeginContentAwareFill,patterns:store.pixelFillPatterns,selectedPatternID:store.lastPixelFillPatternID ?? store.patterns.selected?.id,patternBusy:store.patterns.busy),alert=NSAlert();alert.messageText=kind.title;alert.addButton(withTitle:"OK");alert.addButton(withTitle:"Cancel");alert.accessoryView=accessory.view
    if kind == .fill{let wanted=store.lastPixelFillContents;if wanted != "Pattern" || store.canFillWithPattern{accessory.contents.selectItem(withTitle:wanted)};accessory.contentsChanged()}
    guard alert.runModal() == .alertFirstButtonReturn else{return}
    guard store.document==source,store.nativePixelPaintTarget==target,store.canUsePixelPaint else{store.error="The Fill/Stroke target changed while the dialog was open.";return}
    if kind == .fill{store.lastPixelFillContents=accessory.contents.titleOfSelectedItem ?? "Foreground Color"}
    if kind == .fill,accessory.contents.titleOfSelectedItem=="Content-Aware…"{store.beginContentAwareFill();return}
    do{if kind == .fill,accessory.contents.titleOfSelectedItem=="Pattern"{guard let pattern=accessory.chosenPattern else{throw CraftError.invalid("Choose a saved pattern first.")};store.lastPixelFillPatternID=pattern.id;store.applyPixelPaint(kind,settings:try accessory.settings(),pattern:pattern)}else{store.applyPixelPaint(kind,settings:try accessory.settings())}}catch{store.error=error.localizedDescription}
  }
}
