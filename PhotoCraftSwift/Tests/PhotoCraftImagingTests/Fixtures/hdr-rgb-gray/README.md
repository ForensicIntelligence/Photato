# Linear RGB to Gray32 references

The ICC fixtures are original profiles constructed from published ICC matrix
fields and authored primaries. The test recreates a 128 × 40 RGB32 image with
negative, standard-range and HDR samples. Photoshop 2026 27.2 converted the
owned input to Grayscale with its default linear profile on both Apple Silicon
and Intel under Rosetta. An independent reader decoded the complete PSD gray
planes and confirmed that they match across the two architectures. The fixture
records the input, output and numerical plane hashes. The saved PSDs and vendor
profiles remain outside the repository.
