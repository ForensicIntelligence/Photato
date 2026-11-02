use std::{fs,path::PathBuf};
use photocraft_doc::*;use photocraft_color::*;use photocraft_raster::Surface;use photocraft_format::{save_to_bytes,SaveOptions};use serde_json::json;
fn main(){let out=PathBuf::from(std::env::args().nth(1).unwrap());let mut cases=Vec::new();
for(label,depth)in[("u8",SampleType::U8),("u16",SampleType::U16),("f32",SampleType::F32)] {
let mut doc=Document::new("Owned guide layout",Size::new(17,11),ColorMode::Rgb,depth);
let mut image=Surface::new(PixelFormat{mode:ColorMode::Rgb,sample:depth,alpha:true});for y in 0..11{for x in 0..17{image.write_pixel(x,y,&[0.25,0.5,0.75,1.0]);}}
doc.layers.push(Layer::new("Owned background",LayerContent::Raster(image)));
doc.guides.horizontal=vec![-0.0,1.0/3.0,5.625,11.0,300000.0];doc.guides.vertical=vec![-7.5,0.03125,8.125,17.0,999999.5];
let mut words=Vec::new();let mut wire=Vec::new();wire.extend_from_slice(&1u32.to_be_bytes());wire.extend_from_slice(&576u32.to_be_bytes());wire.extend_from_slice(&576u32.to_be_bytes());wire.extend_from_slice(&10u32.to_be_bytes());
for(list,axis)in[(&doc.guides.vertical,0u8),(&doc.guides.horizontal,1u8)]{for p in list{words.extend_from_slice(&p.to_bits().to_le_bytes());wire.extend_from_slice(&((p*32.0).round()as i32).to_be_bytes());wire.push(axis);}}
let project=format!("guides-{label}.pcraft");let positions=format!("guides-{label}.f32");let encoded=format!("guides-{label}.resource1032");fs::write(out.join(&project),save_to_bytes(&doc,&SaveOptions::default()).unwrap()).unwrap();fs::write(out.join(&positions),words).unwrap();fs::write(out.join(&encoded),wire).unwrap();cases.push(json!({"depth":label,"width":17,"height":11,"project":project,"positions":positions,"wire":encoded}));}
fs::write(out.join("cases.json"),serde_json::to_vec_pretty(&cases).unwrap()).unwrap();println!("3 original projects; 30 source guide Float words; source-formula1032 records");}
