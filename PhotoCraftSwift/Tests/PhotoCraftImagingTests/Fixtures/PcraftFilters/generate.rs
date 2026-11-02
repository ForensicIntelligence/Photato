use std::{fs,path::PathBuf,sync::Arc};
use photocraft_doc::*;
use photocraft_geom::Affine;
use photocraft_format::{save_to_bytes,load_from_bytes,SaveOptions};
use photocraft_raster::Surface;
use serde_json::{Value,json};
fn child(depth:SampleType)->Document{
 let mut d=Document::new("Owned editable filter original",Size::new(16,12),ColorMode::Rgb,depth);d.layers.clear();
 let mut p=Surface::new(PixelFormat{mode:ColorMode::Rgb,sample:depth,alpha:true});
 for y in 0..12{for x in 0..16{p.write_pixel(x,y,&[(x*3+y)as f32/64.0,(y*2+x)as f32/48.0,((x+y)%7)as f32/8.0,if(x+y)%5==0{0.5}else{1.0}]);}}
 d.layers.push(Layer::new("Owned original pixels",LayerContent::Raster(p)));d
}
fn main(){
 let out=PathBuf::from(std::env::args().nth(1).unwrap());fs::create_dir_all(&out).unwrap();
 let direct:Vec<String>=serde_json::from_slice(&fs::read(std::env::args().nth(2).unwrap()).unwrap()).unwrap();
 let mut programs:Vec<(String,String,Value,bool)>=direct.iter().map(|c|(c.replace('.',"-"),c.clone(),json!({}),true)).collect();
 for f in photocraft_algo::GalleryFilter::ALL{let id=format!("filter.gallery.{}",f.key());programs.push((id.replace('.',"-"),id,json!({}),true));}
 programs.push(("gallery-stack".into(),"filter.filterGallery".into(),json!({"foreground":"#183858","background":[0.9,0.8,0.7,1.0],"effects":[{"filter":"cutout","params":{"numberOfLevels":5}},{"filter":"crosshatch","params":{},"visible":false}]}),true));
 for(c,p)in[
  ("filter.blur.radialBlur",json!({"amount":13,"method":"zoom","centerX":0.25,"centerY":0.75})),
  ("filter.other.hsbHsl",json!({"inputMode":"hsb","rowOrder":"rgb"})),
  ("filter.other.minimum",json!({"radius":1.5,"preserve":"roundness"})),
  ("filter.pixelate.colorHalftone",json!({"maxRadius":5,"channel1":-45,"channel2":75,"channel3":90,"channel4":180})),
  ("filter.pixelate.pointillize",json!({"cellSize":4,"background":"#204060","seed":-4})),
  ("filter.noise.addNoise",json!({"amount":24.25,"distribution":"gaussian","monochromatic":true,"seed":18446744073709551615u64})),
  ("filter.stylize.tiles",json!({"count":3,"maxOffset":15,"fill":"foreground","foreground":[0.2,0.4,0.6],"seed":-4})),
  ("filter.distort.shear",json!({"points":[[0.0,0.0],[0.5,0.3],[1.0,0.0]],"undefinedAreas":"repeat"})),
  ("filter.blurGallery.fieldBlur",json!({"pins":[{"x":0.2,"y":0.3,"blur":3.0},{"x":0.8,"y":0.7,"blur":7.0}]})),
  ("filter.blurGallery.irisBlur",json!({"pins":[{"x":0.4,"y":0.6,"radius_x":0.3,"radius_y":0.2,"angle":25.0,"roundness":15.0,"feather":0.4,"blur":4.0}]})),
  ("filter.blurGallery.pathBlur",json!({"paths":[{"points":[[0.1,0.2],[0.4,0.8],[0.9,0.4]],"speed":12.0,"taper":30.0}]})),
  ("filter.gallery.glass",json!({"distortion":6,"smoothness":4,"texture":"Canvas","scaling":100,"invert":true})),
 ]{let n=format!("{}-custom",c.replace('.',"-"));programs.push((n,c.into(),p,true));}
 for(c,p)in[
  ("filter.render.relight",json!({})),("filter.render.lightingEffects",json!({})),("filter.distort.displace",json!({})),
  ("filter.blur.lensBlur",json!({"depthMap":"layerMask"})),("filter.distort.wave",json!({"undefinedAreas":"transparent"})),
  ("filter.noise.median",json!({"radius":1.25})),("filter.blur.gaussianBlur",json!({"futureField":true})),
 ]{let n=format!("{}-rejected",c.replace('.',"-"));programs.push((n,c.into(),p,false));}
 let mut cases=Vec::new();
 for(bits,depth)in[("u8",SampleType::U8),("u16",SampleType::U16),("f32",SampleType::F32)]{
  let source=Arc::new(save_to_bytes(&child(depth),&SaveOptions::default()).unwrap());
  for(name,command,params,supported)in &programs{
   let mut doc=Document::new(format!("Owned original filter {name}"),Size::new(16,12),ColorMode::Rgb,depth);doc.layers.clear();
   let mut smart=SmartObject::new(SmartSource::Embedded{file_name:"Owned filter original.pcraft".into(),bytes:source.clone()},Affine::IDENTITY,None);
   smart.smart_filters.push(SmartFilter{command:command.clone(),params:params.clone(),blend:BlendMode::Normal,opacity:0.75,visible:true});
   let expected=photocraft_engine::smart_cmds::render(&doc,&smart).unwrap().unwrap();
   let mut raw=Vec::new();for y in 0..12{for x in 0..16{let mut px=[0.0f32;4];expected.read_pixel(x,y,&mut px);for v in px{raw.extend_from_slice(&v.to_bits().to_le_bytes());}}}
   let word_file=format!("{name}-{bits}.rgba32");fs::write(out.join(&word_file),raw).unwrap();
   let mut files=Vec::new();for cached in [true,false]{let mut object=smart.clone();if cached{object.cache=Some(expected.clone());}doc.layers=vec![Layer::new("Editable original filter",LayerContent::Smart(object))];let data=save_to_bytes(&doc,&SaveOptions::default()).unwrap();assert_eq!(load_from_bytes(&data).unwrap().layers.len(),1);let f=format!("{name}-{bits}-{}.pcraft",if cached{"cached"}else{"uncached"});fs::write(out.join(&f),data).unwrap();files.push(f);}
   cases.push(json!({"name":name,"command":command,"params":params,"depth":bits,"supported":supported,"cached":files[0],"uncached":files[1],"expected":word_file,"width":16,"height":12}));
  }
  println!("{bits}: {} original-engine filter programs, each cached and uncached",programs.len());
 }
 fs::write(out.join("cases.json"),serde_json::to_vec_pretty(&cases).unwrap()).unwrap();
}
