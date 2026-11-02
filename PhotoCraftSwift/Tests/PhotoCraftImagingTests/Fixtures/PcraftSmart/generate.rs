use std::{fs,path::PathBuf,sync::Arc};
use photocraft_doc::*;
use photocraft_geom::{Affine,warp::{Warp,WarpStyle}};
use photocraft_format::{save_to_bytes,load_from_bytes,SaveOptions};
use photocraft_raster::Surface;
fn child(depth:SampleType)->Document{
 let mut doc=Document::new("Owned original contents",Size::new(16,12),ColorMode::Rgb,depth);doc.layers.clear();
 let fmt=PixelFormat{mode:ColorMode::Rgb,sample:depth,alpha:true};
 for i in 0..2{let mut pixels=Surface::new(fmt);for y in 0..12{for x in 0..16{pixels.write_pixel(x,y,&[x as f32/20.0,(y+i*2)as f32/18.0,if i==0{0.25}else{0.75},1.0]);}}doc.layers.push(Layer::new(format!("Editable source {}",i+1),LayerContent::Raster(pixels)));}
 doc
}
fn main(){
 let out=PathBuf::from(std::env::args().nth(1).unwrap());fs::create_dir_all(&out).unwrap();let mut manifest=Vec::new();
 for(bits,depth)in[("u8",SampleType::U8),("u16",SampleType::U16),("f32",SampleType::F32)]{
  let base=child(depth);let original=Arc::new(save_to_bytes(&base,&SaveOptions::default()).unwrap());
  let mut names:Vec<String>=["affine-cached","affine-uncached","projective-cached","projective-uncached","warp-cached","warp-uncached","filter-cached","filter-uncached","filtermask-cached","mask-cached","shared","linked-cached","unsupported-cached","nested-cached"].iter().map(|x|x.to_string()).collect();
  for mode in StackMode::ALL{names.push(format!("stack-{}",mode.id()));}
  for name in names{
   let mut doc=Document::new(format!("Owned Smart {name}"),Size::new(80,64),ColorMode::Rgb,depth);doc.layers.clear();
   let mut smart=SmartObject::new(SmartSource::Embedded{file_name:"Owned source.pcraft".into(),bytes:original.clone()},Affine::translate(7.0,9.0),None);
   smart.psd_raw=Some(Arc::new(b"OWNED-PHOTATO-PLACED-RECORD".to_vec()));
   if name.starts_with("projective"){smart.perspective=Some([1.25,0.1,7.0,0.05,1.1,9.0,0.008,0.004,1.0]);}
   if name.starts_with("warp"){let mut warp=Warp::preset(WarpStyle::Arch,25.0,[0.0,0.0,16.0,12.0]);warp.h_distort=3.0;smart.warp=Some(warp);}
   if name.starts_with("filter"){smart.smart_filters.push(SmartFilter{command:"filter.blur.gaussianBlur".into(),params:serde_json::json!({"radius":1.5}),blend:BlendMode::Normal,opacity:0.65,visible:true});}
   if name=="filtermask-cached"{let mut mask=LayerMask::reveal_all();mask.linked=false;mask.density=0.75;for y in 9..21{for x in 7..23{mask.surface.write_pixel(x,y,&[if x<14{0.25}else{0.8}]);}}smart.filter_mask=Some(mask);}
   if let Some(suffix)=name.strip_prefix("stack-"){smart.stack_mode=StackMode::ALL.into_iter().find(|x|x.id()==suffix);}
   if name=="unsupported-cached"{smart.smart_filters.push(SmartFilter{command:"psd.unsupportedFilter".into(),params:serde_json::json!({"descriptor":"OWNED"}),blend:BlendMode::Normal,opacity:1.0,visible:true});}
   if name=="nested-cached"{let mut nested=Document::new("Owned nested original",Size::new(32,24),ColorMode::Rgb,depth);nested.layers.clear();let mut inner=SmartObject::new(smart.source.clone(),Affine::translate(3.0,4.0),None);inner.cache=photocraft_engine::smart_cmds::render(&nested,&inner).unwrap();nested.layers.push(Layer::new("Nested editable Smart",LayerContent::Smart(inner)));smart.source=SmartSource::Embedded{file_name:"Nested original.pcraft".into(),bytes:Arc::new(save_to_bytes(&nested,&SaveOptions::default()).unwrap())};}
   let expected=photocraft_engine::smart_cmds::render(&doc,&smart).unwrap().unwrap();let mut words=Vec::new();for y in 0..64{for x in 0..80{let mut pixel=[0.0f32;4];expected.read_pixel(x,y,&mut pixel);for v in pixel{words.extend_from_slice(&v.to_bits().to_le_bytes());}}}
   let cached=!name.ends_with("uncached");if cached{smart.cache=Some(expected);}
   if name=="linked-cached"{smart.source=SmartSource::Linked{path:"/__photato_owned_missing__/original.pcraft".into()};}
   let mut layer=Layer::new(format!("Smart {name}"),LayerContent::Smart(smart.clone()));
   if name=="mask-cached"{let mut mask=LayerMask::reveal_all();mask.linked=false;mask.density=0.8;for y in 9..21{for x in 7..23{mask.surface.write_pixel(x,y,&[0.25]);}}layer.mask=Some(mask);}
   doc.layers.push(layer);if name=="shared"{doc.layers.push(Layer::new("Shared second instance",LayerContent::Smart(smart)));}
   let bytes=save_to_bytes(&doc,&SaveOptions::default()).unwrap();assert_eq!(load_from_bytes(&bytes).unwrap().layers.len(),doc.layers.len());let file=format!("{name}-{bits}.pcraft");let raw=format!("{name}-{bits}.rgba32");fs::write(out.join(&file),bytes).unwrap();fs::write(out.join(&raw),words).unwrap();manifest.push(serde_json::json!({"name":name,"depth":bits,"file":file,"expected":raw,"cached":cached,"width":80,"height":64,"expected_source":"Original smart_cmds::render before optional cache removal; linked fixture cache rendered while embedded, then locator becomes declarative."}));
  }
  println!("{bits}:25 owned Smart Object variants; original engine source, warp, filter, stack and cache samples");
 }
 fs::write(out.join("cases.json"),serde_json::to_vec_pretty(&manifest).unwrap()).unwrap();
}
