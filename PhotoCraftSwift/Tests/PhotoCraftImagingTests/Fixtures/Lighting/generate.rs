use std::{fs,path::PathBuf,sync::Arc};
use photocraft_doc::*;
use photocraft_geom::{Affine,Rect};
use photocraft_format::{save_to_bytes,SaveOptions};
use photocraft_raster::Surface;
use photocraft_algo::{FilterParams,Light,LightKind,TextureChannel};
use serde_json::{json,Value};
fn words(surface:&Surface,w:i32,h:i32)->Vec<u8>{let mut raw=Vec::new();for y in 0..h{for x in 0..w{let mut p=[0.0f32;4];surface.read_pixel(x,y,&mut p);for v in p{raw.extend_from_slice(&v.to_bits().to_le_bytes());}}}raw}
struct Config {name:&'static str,lights:Vec<Light>,gloss:f32,metallic:f32,exposure:f32,ambience:f32,texture:TextureChannel,height:f32,white:bool,root:bool,translated:bool}
fn configurations()->Vec<Config>{let mut rows=Vec::new();for name in ["default","point","infinite","three","negative","texture-red","texture-green","texture-blue","texture-alpha","texture-luminance","white-low","matte","metal","exposure","ambient-only","transparent","off-canvas","sixteen","root-fallback","ignored-fallback","translated","tile-boundary"]{
 let mut c=Config{name,lights:vec![Light::default()],gloss:0.0,metallic:0.0,exposure:0.0,ambience:8.0,texture:TextureChannel::None,height:50.0,white:true,root:false,translated:false};
 match name {
  "point"=>{c.lights[0].kind=LightKind::Point;c.lights[0].x=0.7;c.lights[0].y=0.6;c.lights[0].radius=1.3;},
  "infinite"=>{c.lights[0].kind=LightKind::Infinite;c.lights[0].angle = -35.0;c.lights[0].elevation=60.0;},
  "three"=>{let mut b=Light::default();b.kind=LightKind::Point;b.x=0.8;b.y=0.6;b.color=[0.3,0.5,1.0];b.intensity=40.0;let mut d=Light::default();d.kind=LightKind::Infinite;d.angle = -40.0;d.color=[1.0,0.3,0.1];d.intensity=20.0;c.lights.extend([b,d]);},
  "negative"=>{c.lights[0].kind=LightKind::Infinite;c.lights[0].intensity = -50.0;c.ambience=100.0;},
  "texture-red"=>c.texture=TextureChannel::Red,
  "texture-green"=>c.texture=TextureChannel::Green,
  "texture-blue"=>c.texture=TextureChannel::Blue,
  "texture-alpha"=>c.texture=TextureChannel::Alpha,
  "texture-luminance"=>c.texture=TextureChannel::Luminance,
  "white-low"=>{c.texture=TextureChannel::Luminance;c.white=false;c.height=90.0;},
  "matte"=>{c.gloss = -100.0;c.lights[0].kind=LightKind::Infinite;},
  "metal"=>{c.metallic=100.0;c.gloss=80.0;c.texture=TextureChannel::Red;},
  "exposure"=>{c.exposure=75.0;c.ambience=60.0;c.lights[0].kind=LightKind::Infinite;},
  "ambient-only"=>{c.lights.clear();c.ambience=100.0;},
  "transparent"=>{c.texture=TextureChannel::Alpha;c.lights[0].color=[0.2,0.6,1.0];},
  "off-canvas"=>{c.lights[0].kind=LightKind::Point;c.lights[0].x = -0.25;c.lights[0].y=1.2;c.lights[0].z=12.0;c.lights[0].radius=20.0;},
  "sixteen"=>{c.lights=(0..16).map(|i|{let mut l=Light::default();l.kind=match i%3{0=>LightKind::Spot,1=>LightKind::Point,_=>LightKind::Infinite};l.x=(i%4)as f32/3.0;l.y=(i/4)as f32/3.0;l.angle=i as f32*22.5;l.color=[(i%3+1)as f32/3.0,0.5,1.0];l.intensity=10.0;l}).collect();},
  "root-fallback"=>{c.root=true;c.lights[0].kind=LightKind::Point;c.lights[0].x=0.7;c.lights[0].y=0.65;c.lights[0].color=[102.0/255.0,51.0/255.0,1.0];},
  "translated"=>c.translated=true,
  "tile-boundary"=>{c.texture=TextureChannel::Luminance;c.lights[0].kind=LightKind::Point;c.lights[0].radius=1.2;},
  _=>{}
 };rows.push(c)
};rows}
fn main(){let out=PathBuf::from(std::env::args().nth(1).unwrap());fs::create_dir_all(&out).unwrap();let mut rows=Vec::new();
 for(bits,depth)in[("u8",SampleType::U8),("u16",SampleType::U16),("f32",SampleType::F32)]{for cfg in configurations(){if cfg.name=="tile-boundary" && bits!="f32"{continue};let(w,h)=if cfg.name=="tile-boundary"{(257,129)}else{(23,19)};
  let mut pixels=Surface::new(PixelFormat{mode:ColorMode::Rgb,sample:depth,alpha:true});for y in 0..h{for x in 0..w{let alpha=if cfg.name=="transparent" &&(x+y)%4==0{0.0}else if(x+y)%5==0{0.4}else{1.0};let scale=if bits=="f32"{2.5}else{1.0};pixels.write_pixel(x,y,&[(0.05+x as f32/w as f32*0.7)*scale,(0.1+y as f32/h as f32*0.6)*scale,(0.08+((x+y)%9)as f32/12.0)*scale,alpha]);}}
  let bounds=Rect::new(0,0,w,h);let spec=FilterParams::LightingEffects{lights:cfg.lights.clone(),gloss:cfg.gloss,metallic:cfg.metallic,exposure:cfg.exposure,ambience:cfg.ambience,texture:cfg.texture,height:cfg.height,white_is_high:cfg.white};let expected=photocraft_algo::apply_in(&pixels,&spec,bounds,bounds,None,bounds);
  let common=json!({"gloss":cfg.gloss,"metallic":cfg.metallic,"exposure":cfg.exposure,"ambience":cfg.ambience,"texture":cfg.texture,"height":cfg.height,"whiteIsHigh":cfg.white});let mut params=common.clone();
  if cfg.root{let l=&cfg.lights[0];params["lightType"]=json!(l.kind);params["lightX"]=json!(l.x);params["lightY"]=json!(l.y);params["lightZ"]=json!(l.z);params["targetX"]=json!(l.target_x);params["targetY"]=json!(l.target_y);params["angle"]=json!(l.angle);params["elevation"]=json!(l.elevation);params["color"]=json!("#6633FF");params["intensity"]=json!(l.intensity);params["cone"]=json!(l.cone);params["hotspot"]=json!(l.hotspot);params["radius"]=json!(l.radius);}else{params["lights"]=json!(cfg.lights);}
  if cfg.name=="ignored-fallback"{params["lightX"]=json!("unused fallback");params["color"]=json!(false);}
  let mut native=common;let mut lights=serde_json::to_value(&cfg.lights).unwrap();for l in lights.as_array_mut().unwrap(){l["enabled"]=json!(true)};native["lights"]=lights;
  let mut original=Document::new(format!("Owned Lighting {}",cfg.name),Size::new(w as u32,h as u32),ColorMode::Rgb,depth);original.layers.clear();original.layers.push(Layer::new("Owned source pixels",LayerContent::Raster(pixels.clone())));
  let base=format!("{}-{bits}",cfg.name);let source_file=format!("{base}-source.pcraft");let input_file=format!("{base}-input.rgba32");let expected_file=format!("{base}-expected.rgba32");let bytes=save_to_bytes(&original,&SaveOptions::default()).unwrap();fs::write(out.join(&source_file),&bytes).unwrap();fs::write(out.join(&input_file),words(&pixels,w,h)).unwrap();fs::write(out.join(&expected_file),words(&expected,w,h)).unwrap();
  let placement=if cfg.translated{Affine::translate(3.0,2.0)}else{Affine::IDENTITY};let mut smart=SmartObject::new(SmartSource::Embedded{file_name:"Owned Lighting source.pcraft".into(),bytes:Arc::new(bytes)},placement,None);smart.smart_filters.push(SmartFilter{command:"filter.render.lightingEffects".into(),params:params.clone(),blend:BlendMode::Normal,opacity:1.0,visible:true});let projected=photocraft_engine::smart_cmds::render(&original,&smart).unwrap().unwrap();let smart_expected=format!("{base}-smart.rgba32");fs::write(out.join(&smart_expected),words(&projected,w,h)).unwrap();
  let mut files=Vec::new();for cached in [true,false]{let mut object=smart.clone();if cached{object.cache=Some(projected.clone())};let mut d=original.clone();d.layers=vec![Layer::new("Owned editable Lighting Effects",LayerContent::Smart(object))];let file=format!("{base}-{}.pcraft",if cached{"cached"}else{"uncached"});fs::write(out.join(&file),save_to_bytes(&d,&SaveOptions::default()).unwrap()).unwrap();files.push(file)}
  rows.push(json!({"name":cfg.name,"depth":bits,"width":w,"height":h,"params":native,"sourceParams":params,"source":source_file,"input":input_file,"expected":expected_file,"smartExpected":smart_expected,"cached":files[0],"uncached":files[1],"translated":cfg.translated}));
 }}
 fs::write(out.join("cases.json"),serde_json::to_vec_pretty(&rows).unwrap()).unwrap();println!("{} owned Lighting Effects vectors",rows.len());}
