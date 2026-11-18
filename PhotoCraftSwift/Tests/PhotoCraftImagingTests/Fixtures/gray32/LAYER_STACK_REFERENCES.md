# Gray32 layer stack references

`gray32-stack-references.json` records five original, procedurally generated
16 × 10 test documents. Photoshop 2026 (27.2) opened each document, the top layer
was hidden and revealed to recompute the merged image, and a separate PSD copy
was saved. Photoshop ran on both Apple Silicon and Intel under Rosetta. An
independent reader decoded all 960 merged Float32 samples per architecture and
confirmed that every original layer sample, alpha sample and tested mask
sample survived the save. The JSON contains the Photoshop output and numerical
plane hashes. The Swift test builds the layers from the same formulas and checks
each sample hash in PSD and PSB under all four compression modes. Photoshop's
saved documents are kept locally.
