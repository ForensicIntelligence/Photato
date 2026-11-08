# Classic RGB16 gradient boundaries

Photato now evaluates the second product and addition together when interpolating Classic RGB16 Gradient Map stops. This removes the retained linear-ramp rounding mismatch without special cases for a preset or position. The shared native/API adjustment and history paths use the same kernel. No Gradient Fill, gradient painting, RGB8 or float transfer math changed.

The change was selected against 21 retained Photoshop ramps before three fresh owned references were generated and independently recalculated in Photoshop. A rational-interpolation alternative was rejected because it increased mismatches. The fresh references include linear, partial-smoothness and curved controls plus partial alpha. A separate public-format reader finds all 786,624 merged sample bytes exact per Debug/optimized ARM/translated Intel variant, 2,359,872 bytes in total. This is sample equality for the checked merged images, not whole-file or complete Photoshop parity.

All 61 selected Debug tests pass. The optimized batch passes 61/61 on Apple Silicon and 60/61 on translated Intel; all three new tests pass on both. The remaining Legacy float-transfer vector170 failure reproduces unchanged on build485. That failure remains open; its assertion and fixture were retained.

The universal candidate imports an owned reference with two editable RGB16 layers. Reverse, Command-Z, Command-Shift-Z, restoration, 100% viewport containment, closing unchanged and normal Quit pass. Minimum macOS14 metadata, signatures, entitlements, payload and extracted ZIP also pass. Full A06, Smooth interpolation, one older curved-ramp residual, RGB32 fills, dither/profiles/defaults, physical platforms and performance remain open. Build480 remains the latest fully qualified selected universal.

[Evidence](CLASSIC_RGB16_BOUNDARIES_486.json).
