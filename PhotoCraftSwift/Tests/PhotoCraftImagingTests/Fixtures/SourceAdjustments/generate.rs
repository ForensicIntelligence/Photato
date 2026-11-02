use std::{fs,path::PathBuf};
use photocraft_doc::*;
use photocraft_geom::Rect;
use photocraft_format::{save_to_bytes,SaveOptions};
use photocraft_raster::Surface;
use photocraft_compose::{Buffer,adjust::{self,Transfer}};
use serde_json::{json,Value};
fn words(values:&[[f32;4]])->Vec<u8>{values.iter().flat_map(|p|p.iter().flat_map(|v|v.to_bits().to_le_bytes())).collect()}
fn main(){let out=PathBuf::from(std::env::args().nth(1).unwrap());let programs:Vec<Value>=serde_json::from_slice(&fs::read(out.join("programs.json")).unwrap()).unwrap();let mut rows=Vec::new();
for(bits,depth)in[("u8",SampleType::U8),("u16",SampleType::U16),("f32",SampleType::F32)]{for program in &programs{
 let name=program["name"].as_str().unwrap();let adjustment:Adjustment=serde_json::from_value(program["original"].clone()).unwrap();let(w,h)=(19,11);let rect=Rect::new(-2,-3,w-2,h-3);let mut buf=Buffer::transparent(rect);let mut surface=Surface::new(PixelFormat{mode:ColorMode::Rgb,sample:depth,alpha:true});
 for y in 0..h{for x in 0..w{let alpha=if(x+y)%11==0{0.0}else if(x+y)%5==0{0.4}else{1.0};let p=[(x as f32+0.375)/w as f32,(y as f32+0.125)/h as f32,((x*7+y*3)%19)as f32/19.0,alpha];surface.write_pixel(x,y,&p);let mut stored=[0.0;4];surface.read_pixel(x,y,&mut stored);buf.px[(y*w+x)as usize]=stored}}
 let stem=format!("{name}-{bits}");let input=format!("{stem}-input.rgba32");fs::write(out.join(&input),words(&buf.px)).unwrap();adjust::apply_depth(&adjustment,&mut buf,Transfer::for_document(ColorMode::Rgb,depth),Some(depth));let expected=format!("{stem}-expected.rgba32");fs::write(out.join(&expected),words(&buf.px)).unwrap();
 let mut document=Document::new(format!("Owned Adjustment {name}"),Size::new(w as u32,h as u32),ColorMode::Rgb,depth);document.layers.clear();document.layers.push(Layer::new("Owned source pixels",LayerContent::Raster(surface)));let source=format!("{stem}-source.pcraft");fs::write(out.join(&source),save_to_bytes(&document,&SaveOptions::default()).unwrap()).unwrap();document.layers.push(Layer::new("Owned editable adjustment",LayerContent::Adjustment(adjustment)));let project=format!("{stem}.pcraft");fs::write(out.join(&project),save_to_bytes(&document,&SaveOptions::default()).unwrap()).unwrap();let composite=photocraft_compose::flatten(&document);let merged=format!("{stem}-merged.rgba32");fs::write(out.join(&merged),words(&composite.px)).unwrap();let stored=photocraft_compose::flatten_to_surface(&document,PixelFormat{mode:ColorMode::Rgb,sample:depth,alpha:true},None);let mut sampled=Vec::new();for y in 0..h{for x in 0..w{let mut p=[0.0;4];stored.read_pixel(x,y,&mut p);sampled.push(p)}}let merged_stored=format!("{stem}-merged-stored.rgba32");fs::write(out.join(&merged_stored),words(&sampled)).unwrap();rows.push(json!({"name":name,"depth":bits,"width":w,"height":h,"x":-2,"y":-3,"settings":program["native"],"original":program["original"],"input":input,"expected":expected,"source":source,"project":project,"merged":merged,"mergedStored":merged_stored}));
}}
fs::write(out.join("cases.json"),serde_json::to_vec_pretty(&rows).unwrap()).unwrap();println!("{} original adjustment rows",rows.len());}
