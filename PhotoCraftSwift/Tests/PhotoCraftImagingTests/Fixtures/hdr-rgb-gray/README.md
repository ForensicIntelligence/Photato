# Linear RGB to Gray32 references

The ICC fixtures are original profiles constructed from published ICC matrix
fields and authored primaries. The test recreates a 128 × 40 RGB32 image with
negative, standard-range and HDR samples. Photoshop 2026 27.2 converted the
owned input to Grayscale with its default linear profile on both Apple Silicon
and Intel under Rosetta. An independent reader decoded the complete PSD gray
planes and confirmed that they match across the two architectures. The fixture
records the input, output and numerical plane hashes. The saved PSDs and vendor
profiles remain outside the repository.

`merged-p3-mask.psd` is a Photato-authored procedural test input with a masked
Display P3 overlay. Photoshop 2026 27.2.0 opened this file, merged the layers,
converted to its default linear gray profile, and saved 5,120 reference words
on each architecture. The test pins the original input and the two saved plane
hashes. The fixture is available under MIT OR Apache-2.0.
