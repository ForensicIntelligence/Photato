import Foundation

/// Catalogue and defaults translated from PhotoCraft artistic.rs (MIT OR Apache-2.0).
public enum GalleryFilter:String,Codable,CaseIterable,Sendable {
  case coloredPencil, cutout, dryBrush, filmGrain, fresco, neonGlow, paintDaubs, paletteKnife, plasticWrap, posterEdges, roughPastels, smudgeStick, sponge, underpainting, watercolor, accentedEdges, angledStrokes, crosshatch, darkStrokes, inkOutlines, spatter, sprayedStrokes, sumiE, diffuseGlow, glass, oceanRipple, basRelief, chalkCharcoal, charcoal, chrome, conteCrayon, graphicPen, halftonePattern, notePaper, photocopy, plaster, reticulation, stamp, tornEdges, waterPaper, glowingEdges, craquelure, grain, mosaicTiles, patchwork, stainedGlass, texturizer
  public static let categories=["Artistic","Brush Strokes","Distort","Sketch","Stylize","Texture"]
  public var title:String{switch self{
    case .coloredPencil: "Colored Pencil"
    case .cutout: "Cutout"
    case .dryBrush: "Dry Brush"
    case .filmGrain: "Film Grain"
    case .fresco: "Fresco"
    case .neonGlow: "Neon Glow"
    case .paintDaubs: "Paint Daubs"
    case .paletteKnife: "Palette Knife"
    case .plasticWrap: "Plastic Wrap"
    case .posterEdges: "Poster Edges"
    case .roughPastels: "Rough Pastels"
    case .smudgeStick: "Smudge Stick"
    case .sponge: "Sponge"
    case .underpainting: "Underpainting"
    case .watercolor: "Watercolor"
    case .accentedEdges: "Accented Edges"
    case .angledStrokes: "Angled Strokes"
    case .crosshatch: "Crosshatch"
    case .darkStrokes: "Dark Strokes"
    case .inkOutlines: "Ink Outlines"
    case .spatter: "Spatter"
    case .sprayedStrokes: "Sprayed Strokes"
    case .sumiE: "Sumi-e"
    case .diffuseGlow: "Diffuse Glow"
    case .glass: "Glass"
    case .oceanRipple: "Ocean Ripple"
    case .basRelief: "Bas Relief"
    case .chalkCharcoal: "Chalk & Charcoal"
    case .charcoal: "Charcoal"
    case .chrome: "Chrome"
    case .conteCrayon: "Conté Crayon"
    case .graphicPen: "Graphic Pen"
    case .halftonePattern: "Halftone Pattern"
    case .notePaper: "Note Paper"
    case .photocopy: "Photocopy"
    case .plaster: "Plaster"
    case .reticulation: "Reticulation"
    case .stamp: "Stamp"
    case .tornEdges: "Torn Edges"
    case .waterPaper: "Water Paper"
    case .glowingEdges: "Glowing Edges"
    case .craquelure: "Craquelure"
    case .grain: "Grain"
    case .mosaicTiles: "Mosaic Tiles"
    case .patchwork: "Patchwork"
    case .stainedGlass: "Stained Glass"
    case .texturizer: "Texturizer"
  }}
  public var category:String{switch self{
    case .coloredPencil: "Artistic"
    case .cutout: "Artistic"
    case .dryBrush: "Artistic"
    case .filmGrain: "Artistic"
    case .fresco: "Artistic"
    case .neonGlow: "Artistic"
    case .paintDaubs: "Artistic"
    case .paletteKnife: "Artistic"
    case .plasticWrap: "Artistic"
    case .posterEdges: "Artistic"
    case .roughPastels: "Artistic"
    case .smudgeStick: "Artistic"
    case .sponge: "Artistic"
    case .underpainting: "Artistic"
    case .watercolor: "Artistic"
    case .accentedEdges: "Brush Strokes"
    case .angledStrokes: "Brush Strokes"
    case .crosshatch: "Brush Strokes"
    case .darkStrokes: "Brush Strokes"
    case .inkOutlines: "Brush Strokes"
    case .spatter: "Brush Strokes"
    case .sprayedStrokes: "Brush Strokes"
    case .sumiE: "Brush Strokes"
    case .diffuseGlow: "Distort"
    case .glass: "Distort"
    case .oceanRipple: "Distort"
    case .basRelief: "Sketch"
    case .chalkCharcoal: "Sketch"
    case .charcoal: "Sketch"
    case .chrome: "Sketch"
    case .conteCrayon: "Sketch"
    case .graphicPen: "Sketch"
    case .halftonePattern: "Sketch"
    case .notePaper: "Sketch"
    case .photocopy: "Sketch"
    case .plaster: "Sketch"
    case .reticulation: "Sketch"
    case .stamp: "Sketch"
    case .tornEdges: "Sketch"
    case .waterPaper: "Sketch"
    case .glowingEdges: "Stylize"
    case .craquelure: "Texture"
    case .grain: "Texture"
    case .mosaicTiles: "Texture"
    case .patchwork: "Texture"
    case .stainedGlass: "Texture"
    case .texturizer: "Texture"
  }}
  public var parameters:[GalleryParameter]{switch self{
    case .coloredPencil: [.init("pencilWidth",1.0,24.0,4.0),.init("strokePressure",0.0,15.0,8.0),.init("paperBrightness",0.0,50.0,25.0)]
    case .cutout: [.init("numberOfLevels",2.0,8.0,4.0),.init("edgeSimplicity",0.0,10.0,4.0),.init("edgeFidelity",1.0,3.0,2.0)]
    case .dryBrush: [.init("brushSize",0.0,10.0,2.0),.init("brushDetail",0.0,10.0,8.0),.init("texture",1.0,3.0,1.0)]
    case .filmGrain: [.init("grain",0.0,20.0,4.0),.init("highlightArea",0.0,20.0,0.0),.init("intensity",0.0,10.0,10.0)]
    case .fresco: [.init("brushSize",0.0,10.0,2.0),.init("brushDetail",0.0,10.0,8.0),.init("texture",1.0,3.0,1.0)]
    case .neonGlow: [.init("glowSize",-24.0,24.0,5.0),.init("glowBrightness",0.0,50.0,15.0)]
    case .paintDaubs: [.init("brushSize",1.0,50.0,8.0),.init("sharpness",0.0,40.0,7.0),.init("brushType",choices:["simple", "lightRough", "darkRough", "wideSharp", "wideBlurry", "sparkle"])]
    case .paletteKnife: [.init("strokeSize",1.0,50.0,25.0),.init("strokeDetail",1.0,3.0,3.0),.init("softness",0.0,10.0,0.0)]
    case .plasticWrap: [.init("highlightStrength",0.0,20.0,15.0),.init("detail",1.0,15.0,9.0),.init("smoothness",1.0,15.0,7.0)]
    case .posterEdges: [.init("edgeThickness",0.0,10.0,2.0),.init("edgeIntensity",0.0,10.0,1.0),.init("posterization",0.0,6.0,2.0)]
    case .roughPastels: [.init("strokeLength",0.0,40.0,6.0),.init("strokeDetail",1.0,20.0,4.0),.init("texture",choices:["canvas", "brick", "burlap", "sandstone"]),.init("scaling",50.0,200.0,100.0),.init("relief",0.0,50.0,20.0),.init("light",choices:["bottom", "bottomLeft", "left", "topLeft", "top", "topRight", "right", "bottomRight"]),.init("invert",boolean:true)]
    case .smudgeStick: [.init("strokeLength",0.0,10.0,2.0),.init("highlightArea",0.0,20.0,0.0),.init("intensity",0.0,10.0,10.0)]
    case .sponge: [.init("brushSize",0.0,10.0,2.0),.init("definition",0.0,25.0,12.0),.init("smoothness",1.0,15.0,5.0)]
    case .underpainting: [.init("brushSize",0.0,40.0,6.0),.init("textureCoverage",0.0,40.0,16.0),.init("texture",choices:["canvas", "brick", "burlap", "sandstone"]),.init("scaling",50.0,200.0,100.0),.init("relief",0.0,50.0,4.0),.init("light",choices:["top", "topRight", "right", "bottomRight", "bottom", "bottomLeft", "left", "topLeft"]),.init("invert",boolean:true)]
    case .watercolor: [.init("brushDetail",1.0,14.0,9.0),.init("shadowIntensity",0.0,10.0,1.0),.init("texture",1.0,3.0,1.0)]
    case .accentedEdges: [.init("edgeWidth",1.0,14.0,2.0),.init("edgeBrightness",0.0,50.0,38.0),.init("smoothness",1.0,15.0,5.0)]
    case .angledStrokes: [.init("directionBalance",0.0,100.0,50.0),.init("strokeLength",3.0,50.0,15.0),.init("sharpness",0.0,10.0,3.0)]
    case .crosshatch: [.init("strokeLength",3.0,50.0,9.0),.init("sharpness",0.0,20.0,6.0),.init("strength",1.0,3.0,1.0)]
    case .darkStrokes: [.init("balance",0.0,10.0,5.0),.init("blackIntensity",0.0,10.0,6.0),.init("whiteIntensity",0.0,10.0,2.0)]
    case .inkOutlines: [.init("strokeLength",1.0,50.0,4.0),.init("darkIntensity",0.0,50.0,20.0),.init("lightIntensity",0.0,50.0,10.0)]
    case .spatter: [.init("sprayRadius",0.0,25.0,10.0),.init("smoothness",1.0,15.0,5.0)]
    case .sprayedStrokes: [.init("strokeLength",0.0,20.0,12.0),.init("sprayRadius",0.0,25.0,7.0),.init("strokeDirection",choices:["rightDiagonal", "horizontal", "leftDiagonal", "vertical"])]
    case .sumiE: [.init("strokeWidth",3.0,15.0,10.0),.init("strokePressure",0.0,15.0,2.0),.init("contrast",0.0,40.0,16.0)]
    case .diffuseGlow: [.init("graininess",0.0,10.0,6.0),.init("glowAmount",0.0,20.0,10.0),.init("clearAmount",0.0,20.0,15.0)]
    case .glass: [.init("distortion",0.0,20.0,5.0),.init("smoothness",1.0,15.0,3.0),.init("texture",choices:["frosted", "blocks", "canvas", "tinyLens"]),.init("scaling",50.0,200.0,100.0),.init("invert",boolean:true)]
    case .oceanRipple: [.init("rippleSize",1.0,15.0,9.0),.init("rippleMagnitude",0.0,20.0,9.0)]
    case .basRelief: [.init("detail",1.0,15.0,13.0),.init("smoothness",1.0,15.0,3.0),.init("light",choices:["bottom", "bottomLeft", "left", "topLeft", "top", "topRight", "right", "bottomRight"])]
    case .chalkCharcoal: [.init("charcoalArea",0.0,20.0,6.0),.init("chalkArea",0.0,20.0,6.0),.init("strokePressure",0.0,5.0,1.0)]
    case .charcoal: [.init("charcoalThickness",1.0,7.0,1.0),.init("detail",0.0,5.0,5.0),.init("lightDarkBalance",0.0,100.0,50.0)]
    case .chrome: [.init("detail",0.0,10.0,4.0),.init("smoothness",0.0,10.0,7.0)]
    case .conteCrayon: [.init("foregroundLevel",1.0,15.0,11.0),.init("backgroundLevel",1.0,15.0,7.0),.init("texture",choices:["canvas", "brick", "burlap", "sandstone"]),.init("scaling",50.0,200.0,100.0),.init("relief",0.0,50.0,4.0),.init("light",choices:["top", "topRight", "right", "bottomRight", "bottom", "bottomLeft", "left", "topLeft"]),.init("invert",boolean:true)]
    case .graphicPen: [.init("strokeLength",1.0,15.0,15.0),.init("lightDarkBalance",0.0,100.0,50.0),.init("strokeDirection",choices:["rightDiagonal", "horizontal", "leftDiagonal", "vertical"])]
    case .halftonePattern: [.init("size",1.0,12.0,1.0),.init("contrast",0.0,50.0,5.0),.init("patternType",choices:["dot", "circle", "line"])]
    case .notePaper: [.init("imageBalance",0.0,50.0,25.0),.init("graininess",0.0,20.0,10.0),.init("relief",0.0,25.0,11.0)]
    case .photocopy: [.init("detail",1.0,24.0,7.0),.init("darkness",1.0,50.0,8.0)]
    case .plaster: [.init("imageBalance",0.0,50.0,20.0),.init("smoothness",1.0,15.0,2.0),.init("light",choices:["top", "topRight", "right", "bottomRight", "bottom", "bottomLeft", "left", "topLeft"])]
    case .reticulation: [.init("density",0.0,50.0,12.0),.init("foregroundLevel",0.0,50.0,40.0),.init("backgroundLevel",0.0,50.0,5.0)]
    case .stamp: [.init("lightDarkBalance",0.0,50.0,25.0),.init("smoothness",1.0,50.0,5.0)]
    case .tornEdges: [.init("imageBalance",0.0,50.0,25.0),.init("smoothness",1.0,15.0,11.0),.init("contrast",1.0,25.0,17.0)]
    case .waterPaper: [.init("fiberLength",3.0,50.0,15.0),.init("brightness",0.0,100.0,60.0),.init("contrast",0.0,100.0,80.0)]
    case .glowingEdges: [.init("edgeWidth",1.0,14.0,2.0),.init("edgeBrightness",0.0,20.0,6.0),.init("smoothness",1.0,15.0,5.0)]
    case .craquelure: [.init("crackSpacing",2.0,100.0,15.0),.init("crackDepth",0.0,10.0,6.0),.init("crackBrightness",0.0,10.0,9.0)]
    case .grain: [.init("intensity",0.0,100.0,40.0),.init("contrast",0.0,100.0,50.0),.init("grainType",choices:["regular", "soft", "sprinkles", "clumped", "contrasty", "enlarged", "stippled", "horizontal", "vertical", "speckle"])]
    case .mosaicTiles: [.init("tileSize",2.0,100.0,12.0),.init("groutWidth",1.0,15.0,3.0),.init("lightenGrout",0.0,10.0,9.0)]
    case .patchwork: [.init("squareSize",0.0,10.0,4.0),.init("relief",0.0,25.0,8.0)]
    case .stainedGlass: [.init("cellSize",2.0,50.0,10.0),.init("borderThickness",1.0,20.0,4.0),.init("lightIntensity",0.0,10.0,3.0)]
    case .texturizer: [.init("texture",choices:["canvas", "brick", "burlap", "sandstone"]),.init("scaling",50.0,200.0,100.0),.init("relief",0.0,50.0,4.0),.init("light",choices:["top", "topRight", "right", "bottomRight", "bottom", "bottomLeft", "left", "topLeft"]),.init("invert",boolean:true)]
  }}
}
