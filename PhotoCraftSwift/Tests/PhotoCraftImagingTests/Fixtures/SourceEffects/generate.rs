use std::{fs,path::PathBuf};
use photocraft_doc::*;
use photocraft_color::*;
use photocraft_geom::Rect;
use photocraft_raster::Surface;
use photocraft_compose::{Buffer,effects};
use photocraft_format::{save_to_bytes,SaveOptions};
use serde_json::{json,Value};
fn words(values:&[[f32;4]])->Vec<u8>{values.iter().flat_map(|p|p.iter().flat_map(|v|v.to_bits().to_le_bytes())).collect()}
fn main(){let out=PathBuf::from(std::env::args().nth(1).unwrap());let programs:Vec<Value>=serde_json::from_slice(&fs::read(out.join("programs.json")).unwrap()).unwrap();let mut rows=Vec::new();let(w,h)=(31,23);
let mut tile=Surface::new(PixelFormat::RGBA8);for y in 0..3 {for x in 0..4 {tile.write_pixel(x,y,&[x as f32/4.0,y as f32/3.0,0.625,if(x+y)%3==0{0.375}else{1.0}]);}}
let patterns=vec![Pattern{id:"owned-fx".into(),name:"Owned FX".into(),width:4,height:3,surface:tile}];let mut t=Vec::new();for y in 0..3 {for x in 0..4 {let mut p=[0.0;4];patterns[0].surface.read_pixel(x,y,&mut p);t.push(p)}}fs::write(out.join("pattern.rgba32"),words(&t)).unwrap();
for(bits,depth)in[("u8",SampleType::U8),("u16",SampleType::U16),("f32",SampleType::F32)] {for program in &programs {
let name=program["name"].as_str().unwrap();let mut source=Surface::new(PixelFormat{mode:ColorMode::Rgb,sample:depth,alpha:true});let mut pixels=Vec::new();
for y in 0..h {for x in 0..w {let a=if x>=8&&x<23&&y>=6&&y<18{if(x+y)%7==0{0.375}else{1.0}}else{0.0};source.write_pixel(x,y,&[if a>0.0{(x as f32+0.375)/w as f32}else{0.0},if a>0.0{(y as f32+0.125)/h as f32}else{0.0},if a>0.0{0.625}else{0.0},a]);let mut p=[0.0;4];source.read_pixel(x,y,&mut p);pixels.push(p);}}
let mut layer=Layer::new("Owned source effect",LayerContent::Raster(source));layer.effects.enabled=true;layer.effects.items=serde_json::from_value(program["effects"].clone()).unwrap();layer.fill_opacity=program["fill"].as_f64().unwrap()as f32;layer.opacity=program["opacity"].as_f64().unwrap()as f32;if program["reference"].as_bool().unwrap(){layer.effects.reference=Some((2.375,-1.625));}
let pad=effects::margin(&layer);let rect=Rect::new(-pad,-pad,w+pad,h+pad);let frame=Rect::new(0,0,w,h);let mut content=Buffer::transparent(rect);for y in 0..h{for x in 0..w {content.px[((y+pad)*(rect.width() as i32)+x+pad)as usize]=pixels[(y*w+x)as usize];}}
let shape=content.px.iter().map(|p|p[3]).collect();let light=GlobalLight{angle:113.375,altitude:41.25};let maps=effects::build_maps(&layer,shape,rect,&light,&effects::TextureCtx{rect,patterns:&patterns,anchor:layer.effects.reference.unwrap_or((0.0,0.0))});let mut backdrop=Buffer::transparent(frame);for y in 0..h{for x in 0..w{backdrop.px[(y*w+x)as usize]=[0.0625+x as f32/128.0,0.125+y as f32/128.0,0.3125,if(x+y)%9==0{0.5}else{1.0}];}}
let stem=format!("{name}-{bits}");let input=format!("{stem}-input.rgba32");let base=format!("{stem}-backdrop.rgba32");let expected=format!("{stem}-expected.rgba32");fs::write(out.join(&input),words(&pixels)).unwrap();fs::write(out.join(&base),words(&backdrop.px)).unwrap();effects::composite_with_effects(&layer,&content,&mut backdrop,&maps,frame,&patterns);fs::write(out.join(&expected),words(&backdrop.px)).unwrap();
let mut doc=Document::new(format!("Owned source effect {name}"),Size::new(w as u32,h as u32),ColorMode::Rgb,depth);doc.layers.clear();doc.patterns=patterns.clone();doc.global_light=light;
let mut bg=Surface::new(PixelFormat{mode:ColorMode::Rgb,sample:depth,alpha:true});for y in 0..h{for x in 0..w{bg.write_pixel(x,y,&[0.0625+x as f32/128.0,0.125+y as f32/128.0,0.3125,if(x+y)%9==0{0.5}else{1.0}]);}}
doc.layers.push(Layer::new("Owned backdrop",LayerContent::Raster(bg)));doc.layers.push(layer.clone());let project=format!("{stem}.pcraft");fs::write(out.join(&project),save_to_bytes(&doc,&SaveOptions::default()).unwrap()).unwrap();let merged=photocraft_compose::flatten(&doc);let project_expected=format!("{stem}-project.rgba32");fs::write(out.join(&project_expected),words(&merged.px)).unwrap();
rows.push(json!({"name":name,"depth":bits,"width":w,"height":h,"native":program["native"],"opacity":program["opacity"],"input":input,"backdrop":base,"expected":expected,"project":project,"projectExpected":project_expected}));
}}
fs::write(out.join("cases.json"),serde_json::to_vec_pretty(&rows).unwrap()).unwrap();println!("{} original effect vectors",rows.len());}
