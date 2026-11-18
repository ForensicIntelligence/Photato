# Source checkpoint 570

Native Swift 0.3.0, build 570, 18 November 2026. Eligible flat Normal RGB stacks use their original working profile when merged before Image Mode conversion. A single unchanged full-canvas native layer preserves its original color and alpha samples. Unmasked integer RGB stacks inside the existing merge memory budget share the measured Normal blend used by the Layer menu.

The corrected build matched all 35,840 stored 32-bit words across three Photoshop 2026 references on each optimized architecture. The controls cover a Gray16 document with one visible layer, an opaque RGB16 overlay, and a translucent RGB16 overlay. The new Swift tests include three targeted RGB16 rounding positions on each architecture and a Display P3 HDR merge compared with independently prepared working-profile samples.

All 678 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ local validation archive passed offscreen checks. Physical Intel hardware, macOS 14 runtime, and live editing remain unqualified for this build.

The two external HDR references from ZIP-encoded PSD layers contain non-finite colors. They are excluded from the result. The 16-bit RGB-to-Grayscale curve, masked and large integer merge rounding, complex component stacks, and external HDR merge byte equality remain open.

[Development record](DEVLOG.md#dev-step-570) · [Validation data and source fingerprints](MERGE_MODE_REFERENCES_570.json)
