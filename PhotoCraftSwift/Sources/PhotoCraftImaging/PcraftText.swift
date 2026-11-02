import Foundation
import PhotoCraftCore

/// Typed translation of PhotoCraft's licensed TextLayer. Source style runs are
/// normalized as byte ranges first, then merged as native UTF-16 ranges.
enum PcraftText {
  static func layer(_ node:PcraftNode,name:String,project:PcraftProject,depth:PixelDepth,dpi:Double,budget:inout Int)throws->Layer {
    var text=try content(node)
    if depth == .f32{text.typography?.defaultStyle.characterFormatting?.linearColor=true;if let count=text.typography?.runs.count{for i in 0..<count{text.typography?.runs[i].style.characterFormatting?.linearColor=true}}}
    let transform=try node.field("transform");try transform.keys("m");let values=try transform.field("m").array().map{try $0.double()};guard values.count==6 else{throw transform.invalid}
    let matrix=Transform2D(a:values[0],b:values[1],c:values[2],d:values[3],tx:values[4],ty:values[5]);try matrix.validated()
    if text.typography?.geometry != nil {
      var plain=text;plain.typography?.geometry=nil;let metrics=try NativeTextLayout.metrics(plain,dpi:dpi)
      text.typography?.geometry?.width=Double(metrics.width);text.typography?.geometry?.height=Double(metrics.height)
    }
    var appearance=ImportedTextAppearance(content:text,textTransform:matrix)
    if let cache=node.optional("cache") {
      try PcraftSamples.validateSchema(cache)
      guard let source=project.surfaces[cache.path],try PcraftSamples.depth(source.sample)==depth else{throw cache.invalid}
      let placed=try PcraftSamples.placed(source,mask:false,budget:&budget);appearance.pixels=placed.surface;appearance.x=placed.x;appearance.y=placed.y
    }
    if let raw=node.optional("psd_raw"){guard let bytes=project.blobs[try raw.string()],bytes.count<=16*1024*1024 else{throw raw.invalid};appearance.typeRecord=bytes}
    if appearance.pixels != nil || appearance.typeRecord != nil{text.importedAppearance=appearance}
    let full:Transform2D
    if appearance.pixels != nil{full = .translation(Double(appearance.x),Double(appearance.y))}
    else{let origin=try NativeTextLayout.metrics(text,dpi:dpi).origin;full=matrix * .translation(origin.x,origin.y)}
    var layer=Layer(name:name,content:.text(text));layer.x=Int(floor(full.tx));layer.y=Int(floor(full.ty));layer.affine = .translation(-Double(layer.x),-Double(layer.y))*full
    if layer.affine == .identity{layer.affine=nil};return layer
  }
  static func character(_ node:PcraftNode,default base:TypeStyle)throws->TypeStyle {
    try node.keys("font_family font_style postscript_name weight italic size_pt color tracking leading_pt baseline_shift_pt horizontal_scale vertical_scale underline strikethrough faux_bold faux_italic kerning kern caps ligatures discretionary_ligatures features variations language style_sheet")
    var style=base,formatting=TypeCharacterFormatting(),options=TypeFontOptions()
    let family=try node.optional("font_family")?.string() ?? base.font
    style.font=family.isEmpty ? "HelveticaNeue":family
    formatting.sourceFontReference=style.font;formatting.sourceFace=try node.optional("font_style")?.string()
    formatting.sourcePostScriptName=try node.optional("postscript_name")?.string();if formatting.sourcePostScriptName==""{formatting.sourcePostScriptName=nil}
    formatting.weight=try node.optional("weight")?.integer() ?? 400;formatting.italic=try node.optional("italic")?.boolean() ?? false;formatting.sourceWeight=formatting.weight;formatting.sourceItalic=formatting.italic
    formatting.fauxBold=try node.optional("faux_bold")?.boolean() ?? false;formatting.fauxItalic=try node.optional("faux_italic")?.boolean() ?? false
    if let value=node.optional("kerning"){guard let v=TypeCharacterFormatting.Kerning(rawValue:try value.string().lowercased()) else{throw value.invalid};formatting.kerning=v}
    if let value=node.optional("caps"){let raw=try value.string();guard let v=TypeCharacterFormatting.Caps(rawValue:raw.prefix(1).lowercased()+raw.dropFirst())else{throw value.invalid};formatting.caps=v}
    formatting.manualKerning=Double(try node.optional("kern")?.float() ?? 0)
    formatting.ligatures=try node.optional("ligatures")?.boolean() ?? true;formatting.discretionaryLigatures=try node.optional("discretionary_ligatures")?.boolean() ?? false
    if let id=node.optional("style_sheet"){let value=try id.unsigned();guard value>0,value<=UInt32.max else{throw id.invalid};formatting.styleSheet=UInt32(value)}
    if let size=node.optional("size_pt"){style.size=Double(try size.float())}
    if let color=node.optional("color"){style.color=try PcraftFills.color(color)}
    for (field,key) in [("tracking",\TypeStyle.tracking),("baseline_shift_pt",\.baseline),("horizontal_scale",\.horizontalScale),("vertical_scale",\.verticalScale)]{if let value=node.optional(field){style[keyPath:key]=Double(try value.float())}}
    style.leading=Double(try node.optional("leading_pt")?.float() ?? 0)
    style.underline=try node.optional("underline")?.boolean() ?? false;style.strikethrough=try node.optional("strikethrough")?.boolean() ?? false
    for feature in try node.optional("features")?.array() ?? []{try feature.keys("tag value");options.features.append(.init(try feature.field("tag").string(),try feature.field("value").integer()))}
    for variation in try node.optional("variations")?.array() ?? [] {
      try variation.keys("axis value");let axis=try variation.field("axis").string(),bytes=Array(axis.utf8);guard bytes.count==4,bytes.allSatisfy({(32...126).contains($0)})else{throw variation.invalid}
      let id=bytes.reduce(UInt32(0)){$0<<8|UInt32($1)};options.variations.append(.init(id,Double(try variation.field("value").float())))
    }
    options.language=try node.optional("language")?.string();style.fontOptions=options.isEmpty ? nil:options;style.characterFormatting=formatting;try style.validate();return style
  }
  static func paragraph(_ node:PcraftNode)throws->TypeParagraph {
    try node.keys("align first_line_indent_pt start_indent_pt end_indent_pt space_before_pt space_after_pt auto_leading direction hyphenate style_sheet")
    var p=TypeParagraph(),extra=TypeParagraphFormatting()
    switch try node.optional("align")?.string() ?? "Left" {
    case "Left":p.alignment = .left
    case "Center":p.alignment = .center
    case "Right":p.alignment = .right
    case "JustifyLeft":p.alignment = .justified;extra.lastLine = .left
    case "JustifyCenter":p.alignment = .justified;extra.lastLine = .center
    case "JustifyRight":p.alignment = .justified;extra.lastLine = .right
    case "JustifyAll":p.alignment = .justified;extra.lastLine = .justified
    default:throw node.unsupported("Unknown paragraph alignment.")
    }
    for (field,key)in [("first_line_indent_pt",\TypeParagraph.firstIndent),("start_indent_pt",\.startIndent),("end_indent_pt",\.endIndent),("space_before_pt",\.spaceBefore),("space_after_pt",\.spaceAfter)]{p[keyPath:key]=Double(try node.optional(field)?.float() ?? 0)}
    extra.autoLeading=Double(try node.optional("auto_leading")?.float() ?? 1.2)
    if let id=node.optional("style_sheet"){let value=try id.unsigned();guard value<=UInt32.max else{throw id.invalid};extra.styleSheet=UInt32(value)}
    switch try node.optional("direction")?.string() ?? "Auto"{case "Auto":p.direction = .natural;case "Ltr":p.direction = .leftToRight;case "Rtl":p.direction = .rightToLeft;default:throw node.invalid}
    p.hyphenation=try node.optional("hyphenate")?.boolean() ?? false;p.formatting=extra;try p.validate();return p
  }
  static func content(_ node:PcraftNode)throws->TextContent {
    try node.keys("kind text font_family size_pt color transform cache psd_raw runs paragraphs shape orientation antialias warp")
    let string=try node.field("text").string(),family=try node.field("font_family").string(),size=Double(try node.field("size_pt").float()),color=try PcraftFills.color(node.field("color"))
    var style=TypeStyle();style.font=family.isEmpty ? "HelveticaNeue":family;style.size=size;style.color=color;style.characterFormatting = .init();style.characterFormatting?.sourceFontReference=style.font
    var characters:[TypeSourceRuns.Span<TypeStyle>]=[],paragraphs:[TypeSourceRuns.Span<TypeParagraph>]=[]
    for run in try node.optional("runs")?.array() ?? [] {try run.keys("len style");characters.append(.init(try run.field("len").integer(),try character(run.field("style"),default:style)))}
    var defaultParagraph=TypeParagraph();defaultParagraph.formatting = .init()
    for run in try node.optional("paragraphs")?.array() ?? []{try run.keys("len style");paragraphs.append(.init(try run.field("len").integer(),try paragraph(run.field("style"))))}
    let cr=try TypeSourceRuns.normalize(characters,text:string,default:style),pr=try TypeSourceRuns.normalize(paragraphs,text:string,default:defaultParagraph)
    var type=TextTypography();type.defaultStyle=cr.first?.value ?? style;type.defaultParagraph=pr.first?.value ?? defaultParagraph;type.runs=try TypeSourceRuns.merge(characters:cr,paragraphs:pr,text:string)
    var text=TextContent(text:string,fontName:type.defaultStyle.font,size:type.defaultStyle.size,color:type.defaultStyle.color),frame=TypeSourceFrame()
    if let shape=node.optional("shape") {
      if shape.value.string=="Point"{frame.kind = .point}
      else {try shape.keys("Box");let box=try shape.field("Box");try box.keys("x y width height");frame.kind = .box;frame.x=Double(try box.field("x").float());frame.y=Double(try box.field("y").float());frame.width=Double(try box.field("width").float());frame.height=Double(try box.field("height").float());try frame.validate();type.kind = .paragraph;text.layoutWidth=Int(ceil(frame.width));text.layoutHeight=Int(ceil(frame.height))}
    }
    type.sourceFrame=frame
    switch try node.optional("orientation")?.string() ?? "Horizontal"{case "Horizontal":break;case "Vertical":type.orientation = .vertical;default:throw node.invalid}
    let aa=try node.optional("antialias")?.string() ?? "Smooth",raw=aa=="WindowsLcd" ? "windowsLCD":aa.prefix(1).lowercased()+aa.dropFirst()
    guard let mode=TypeAntialias(rawValue:raw)else{throw node.invalid};type.antialiasMode=mode;type.antialias=mode != .none
    if let warp=node.optional("warp") {
      try warp.keys("style value horizontal_distortion vertical_distortion horizontal");let name=try warp.field("style").string();let styleName=name.hasPrefix("warp") ? String(name.dropFirst(4)):name;let lower=styleName.isEmpty ? "none":styleName.prefix(1).lowercased()+styleName.dropFirst()
      guard let kind=WarpStyle(rawValue:lower),kind != .custom else{throw warp.unsupported("Unsupported text warp style.")}
      var geometry=TextGeometry();geometry.warp.style=kind;geometry.warp.bend=Double(try warp.field("value").float())/100;geometry.warp.horizontalDistortion=Double(try warp.field("horizontal_distortion").float())/100;geometry.warp.verticalDistortion=Double(try warp.field("vertical_distortion").float())/100;geometry.warp.vertical = !(try warp.field("horizontal").boolean());type.geometry=geometry
    }
    text.typography=type;try text.validate();return text
  }
}
