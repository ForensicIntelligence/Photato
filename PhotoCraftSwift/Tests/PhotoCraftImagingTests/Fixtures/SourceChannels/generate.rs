use std::{fs,path::PathBuf};
use photocraft_doc::*;
use photocraft_color::*;
use photocraft_geom::Rect;
use photocraft_raster::Surface;
use photocraft_format::{save_to_bytes,SaveOptions};
use serde_json::json;
fn words(values:&[f32])->Vec<u8>{values.iter().flat_map(|v|v.to_bits().to_le_bytes()).collect()}
fn main(){let out=PathBuf::from(std::env::args().nth(1).unwrap());let(w,h)=(17,11);let mut cases=Vec::new();
for(bits,depth)in[("u8",SampleType::U8),("u16",SampleType::U16),("f32",SampleType::F32)] {
let mut doc=Document::new("Owned channels Ω",Size::new(w,h),ColorMode::Rgb,depth);
let mut image=Surface::new(PixelFormat{mode:ColorMode::Rgb,sample:depth,alpha:true});for y in 0..h{for x in 0..w{image.write_pixel(x as i32,y as i32,&[0.25,0.5,0.75,1.0]);}}
doc.layers.push(Layer::new("Owned background",LayerContent::Raster(image)));
let mut refs=Vec::new();
for index in 0..4 {let mut plane=Surface::new(PixelFormat{mode:ColorMode::Grayscale,sample:depth,alpha:false});for y in 0..h{for x in 0..w{let value=(((x*7+y*11+index*13)%31)as f32)/30.0;plane.write_pixel(x as i32,y as i32,&[value]);}}
let mut channel=AlphaChannel::new(format!("Channel {index} Ω"),plane);channel.color=Color::rgb(0.125,0.625,0.375);channel.opacity=0.375;channel.indicates=ColorIndicates::SelectedAreas;
if index==1{channel.spot=Some((Color::rgb(0.0,0.75,1.0),0.0));}if index==2{channel.spot=Some((Color::rgb(1.0,0.125,0.5),0.625));}
let mut data=Vec::new();for y in 0..h{for x in 0..w{let mut p=[0.0];channel.surface.read_pixel(x as i32,y as i32,&mut p);data.push(p[0]);}}
let file=format!("channels-{bits}-{index}.f32");fs::write(out.join(&file),words(&data)).unwrap();refs.push(file);
if index==3{doc.quick_mask=Some(channel)}else{doc.channels.push(channel)}
}
let project=format!("channels-{bits}.pcraft");fs::write(out.join(&project),save_to_bytes(&doc,&SaveOptions::default()).unwrap()).unwrap();
doc.mode=ColorMode::Multichannel;let printed=photocraft_compose::multichannel::inks(&doc,Rect::new(0,0,w as i32,h as i32));let inkref=format!("channels-{bits}-overprint.rgba32");fs::write(out.join(&inkref),words(&printed.px.iter().flat_map(|p|p.iter().copied()).collect::<Vec<_>>())).unwrap();
cases.push(json!({"depth":bits,"width":w,"height":h,"project":project,"channels":refs,"overprint":inkref}));
}
fs::write(out.join("cases.json"),serde_json::to_vec_pretty(&cases).unwrap()).unwrap();println!("3 original projects; 12 channel planes; 3 two-ink overprint references");}
