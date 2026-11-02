use std::{fs,path::PathBuf,sync::Arc};
use photocraft_doc::*;use photocraft_color::*;use photocraft_raster::Surface;use photocraft_format::{save_to_bytes,SaveOptions};use photocraft_engine::Session;use serde_json::json;
fn main(){let out=PathBuf::from(std::env::args().nth(1).unwrap());let mut cases=Vec::new();
for(label,depth)in[("u8",SampleType::U8),("u16",SampleType::U16),("f32",SampleType::F32)] {
 let mut doc=Document::new("Owned File Info",Size::new(5,3),ColorMode::Rgb,depth);
 let mut image=Surface::new(PixelFormat{mode:ColorMode::Rgb,sample:depth,alpha:true});for y in 0..3{for x in 0..5{image.write_pixel(x,y,&[0.25,0.5,0.75,1.0]);}}
 doc.layers.push(Layer::new("Owned pixels",LayerContent::Raster(image)));
 let mut session=Session::new();session.add_document(doc,None);
 session.execute("file.fileInfo",json!({"title":"Night <Sky>","author":"First Author; Second Author","authorTitle":"Artist","description":"Oil & canvas — owned fixture","keywords":["stars","night","café"],"copyright":"Owned test work","copyrightStatus":"publicDomain","copyrightUrl":"https://example.invalid/rights?x=1&y=2"})).unwrap();
 let expected=session.execute("file.fileInfo",json!({})).unwrap();let mut doc=(*session.active().unwrap().doc).clone();
 doc.metadata.exif=Some(Arc::new(vec![0x49,0x49,42,0,8,0,0,0,0,0,0,0,0,0]));
 doc.metadata.psd_resources.push((4000,"owned".into(),Arc::new(vec![1,2,3,4,5])));
 doc.metadata.psd_global_blocks.push((*b"8BIM",*b"zzzz",Arc::new(vec![9,7,5])));
 let name=format!("info-{label}.pcraft");fs::write(out.join(&name),save_to_bytes(&doc,&SaveOptions::default()).unwrap()).unwrap();
 fs::write(out.join(format!("info-{label}.xmp")),doc.metadata.xmp.as_ref().unwrap()).unwrap();
 cases.push(json!({"depth":label,"project":name,"expected":expected}));
}
fs::write(out.join("cases.json"),serde_json::to_vec_pretty(&cases).unwrap()).unwrap();println!("3 source projects; 24 original File Info values; exact source XMP/EXIF/resource/global payloads");}
