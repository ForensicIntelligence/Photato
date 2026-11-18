# SDR to HDR precision references

The test ICC profiles are original project fixtures. Each uses a minimal matrix or
grayscale header, public color-space coefficients and authored tone curves. The
test reconstructs the matching opaque raw PSD inputs and checks their SHA-256.

The installed Adobe Photoshop 2026 version 27.2 set each owned input to 32 Bits/Channel
using its scripting interface, saved a raw PSD copy with a profile, and closed the
temporary document. An independent reader checked the header, skipped the declared
sections and hashed the complete big-endian Float32 merged plane. `references.json`
records the source, profile, output and plane hashes. The Photoshop files and Adobe
profiles are held outside the repository.

The 16-bit inputs cover all 32,769 working values. The 8-bit ramps contain every
possible component level. For RGB, the green and blue ramps are rotated relative
to red. The reference capture ran Photoshop on Apple Silicon and ran its Intel
slice under Rosetta. Each test checks the exact sample hash from Photoshop on
the matching architecture.
