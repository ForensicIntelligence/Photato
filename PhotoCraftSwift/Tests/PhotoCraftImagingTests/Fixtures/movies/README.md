# Owned movie fixtures

These are original Photato fixtures, licensed MIT OR Apache-2.0. `generate.py` uses Pillow to create three16×12 RGBA frames, then FFmpeg's uncompressed ARGB QuickTime encoder and an original440Hz tone. Variable frame timestamps are0,0.12,0.32,0.40seconds; the final frame ends at0.44seconds. The513-frame limit fixture verifies rejection without truncation. The rotated copy carries a90-degree display matrix. `reference.json` retains independent ffprobe timestamps/track metadata and SHA-256 hashes. FFmpeg and Pillow are fixture/oracle tools only and are not application dependencies. No Adobe artwork or implementation is used.

`owned-h264.mp4` scales the same original artwork to128×96 and uses ordinary lossy H.264/YUV420 with BT.709 tags and AAC audio. It verifies codec/PTS/source retention, not byte equality to the original RGB artwork. The16×12 H.264 probe failed on the current host and is preserved in step233 artifacts.
