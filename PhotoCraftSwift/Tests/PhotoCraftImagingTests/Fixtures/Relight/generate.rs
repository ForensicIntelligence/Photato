use std::{fs,path::PathBuf,sync::Arc};
use photocraft_doc::*;
use photocraft_geom::{Affine,Rect};
use photocraft_format::{save_to_bytes,SaveOptions};
use photocraft_raster::Surface;
use photocraft_algo::FilterParams;
use serde_json::json;
fn words(surface:&Surface,w:i32,h:i32)->Vec<u8>{let mut raw=Vec::new();for y in 0..h{for x in 0..w{let mut p=[0.0f32;4];surface.read_pixel(x,y,&mut p);for v in p{raw.extend_from_slice(&v.to_bits().to_le_bytes());}}}raw}
fn main(){let out=PathBuf::from(std::env::args().nth(1).unwrap());fs::create_dir_all(&out).unwrap();let mut rows=Vec::new();
 for(bits,depth)in[("u8",SampleType::U8),("u16",SampleType::U16),("f32",SampleType::F32)]{
  for(name,a,e,i,amb,warm,soft)in[("default",45.0,40.0,40.0,55.0,0.0,25.0),("identity",45.0,40.0,0.0,55.0,0.0,25.0),("cool-left",-135.0,25.0,65.0,30.0,-60.0,90.0),("warm-overhead",90.0,85.0,80.0,10.0,75.0,55.0),("ambient",0.0,0.0,50.0,100.0,0.0,1.0),("transparent",180.0,45.0,75.0,45.0,20.0,100.0),("tile-boundary",-45.0,55.0,55.0,40.0,-25.0,100.0)]{
   if name=="tile-boundary" && bits!="f32"{continue}
   let(w,h)=if name=="tile-boundary"{(257,129)}else{(23,19)};
   let mut pixels=Surface::new(PixelFormat{mode:ColorMode::Rgb,sample:depth,alpha:true});
   for y in 0..h{for x in 0..w{let alpha=if name=="transparent" &&(x+y)%4==0{0.0}else if(x+y)%5==0{0.4}else{1.0};let scale=if bits=="f32"{2.5}else{1.0};pixels.write_pixel(x,y,&[(0.05+x as f32/w as f32*0.7)*scale,(0.1+y as f32/h as f32*0.6)*scale,(0.08+((x+y)%9)as f32/12.0)*scale,alpha]);}}
   let params=FilterParams::Relight{angle:a,elevation:e,intensity:i,ambient:amb,warmth:warm,softness:soft};let bounds=Rect::new(0,0,w,h);
   let expected=photocraft_algo::apply_in(&pixels,&params,bounds,bounds,None,bounds);
   let mut original=Document::new(format!("Owned Relight {name}"),Size::new(w as u32,h as u32),ColorMode::Rgb,depth);original.layers.clear();original.layers.push(Layer::new("Owned source pixels",LayerContent::Raster(pixels.clone())));
   let base=format!("{name}-{bits}");let source_file=format!("{base}-source.pcraft");let input_file=format!("{base}-input.rgba32");let expected_file=format!("{base}-expected.rgba32");
   let bytes=save_to_bytes(&original,&SaveOptions::default()).unwrap();fs::write(out.join(&source_file),&bytes).unwrap();fs::write(out.join(&input_file),words(&pixels,w,h)).unwrap();fs::write(out.join(&expected_file),words(&expected,w,h)).unwrap();
   let p=json!({"angle":a,"elevation":e,"intensity":i,"ambient":amb,"warmth":warm,"softness":soft});let mut smart=SmartObject::new(SmartSource::Embedded{file_name:"Owned relight source.pcraft".into(),bytes:Arc::new(bytes)},Affine::IDENTITY,None);smart.smart_filters.push(SmartFilter{command:"filter.render.relight".into(),params:p.clone(),blend:BlendMode::Normal,opacity:1.0,visible:true});
   let projected=photocraft_engine::smart_cmds::render(&original,&smart).unwrap().unwrap();let smart_expected=format!("{base}-smart.rgba32");fs::write(out.join(&smart_expected),words(&projected,w,h)).unwrap();
   let mut files=Vec::new();for cached in [true,false]{let mut object=smart.clone();if cached{object.cache=Some(projected.clone());}let mut d=original.clone();d.layers=vec![Layer::new("Owned editable Relight",LayerContent::Smart(object))];let f=format!("{base}-{}.pcraft",if cached{"cached"}else{"uncached"});fs::write(out.join(&f),save_to_bytes(&d,&SaveOptions::default()).unwrap()).unwrap();files.push(f);}
   rows.push(json!({"name":name,"depth":bits,"width":w,"height":h,"params":p,"source":source_file,"input":input_file,"expected":expected_file,"smartExpected":smart_expected,"cached":files[0],"uncached":files[1]}));
  }
 }
 fs::write(out.join("cases.json"),serde_json::to_vec_pretty(&rows).unwrap()).unwrap();println!("{} owned direct/source Relight vectors",rows.len());}
