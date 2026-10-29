"""Original Photato test assets, MIT OR Apache-2.0. FFmpeg/Pillow are test-only."""
from pathlib import Path
from PIL import Image
import subprocess, tempfile, json, hashlib
root=Path(__file__).resolve().parent
with tempfile.TemporaryDirectory() as work:
 d=Path(work)
 for i,color in enumerate([(255,0,0,255),(0,255,0,255),(0,0,255,255)]):
  im=Image.new('RGBA',(16,12),color)
  im.putpixel((0,0),(255,255,255,255));im.putpixel((15,11),(255,255,0,128));im.save(d/f'{i}.png')
 (d/'list.txt').write_text("file '0.png'\nduration 0.12\nfile '1.png'\nduration 0.20\nfile '2.png'\nduration 0.08\nfile '2.png'\n")
 commands=[['ffmpeg','-y','-v','error','-f','concat','-safe','0','-i',str(d/'list.txt'),'-f','lavfi','-i','sine=frequency=440:sample_rate=8000:duration=0.44','-fps_mode','vfr','-c:v','rawvideo','-pix_fmt','argb','-c:a','pcm_s16le','-movflags','+faststart',str(root/'owned-vfr-audio.mov')],['ffmpeg','-y','-v','error','-display_rotation','90','-i',str(root/'owned-vfr-audio.mov'),'-c','copy',str(root/'owned-rotated.mov')]]
 commands.append(['ffmpeg','-y','-v','error','-loop','1','-i',str(d/'0.png'),'-frames:v','513','-c:v','rawvideo','-pix_fmt','argb',str(root/'owned-too-many.mov')])
 commands.append(['ffmpeg','-y','-v','error','-i',str(root/'owned-vfr-audio.mov'),'-fps_mode','passthrough','-vf','scale=128:96:flags=neighbor:in_range=full:out_range=tv:out_color_matrix=bt709','-c:v','libx264','-pix_fmt','yuv420p','-crf','18','-colorspace','bt709','-color_primaries','bt709','-color_trc','bt709','-c:a','aac','-b:a','32k','-movflags','+faststart',str(root/'owned-h264.mp4')])
 for c in commands:subprocess.run(c,check=True)
 report={}
 for p in sorted([*root.glob('*.mov'),*root.glob('*.mp4')]):
  report[p.name]={'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'probe':json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_frames','-of','json',str(p)]))}
 (root/'reference.json').write_text(json.dumps(report,indent=2))
