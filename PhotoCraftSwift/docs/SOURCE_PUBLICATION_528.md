# Source checkpoint 528

Native Swift 0.3.0, build 528, 17 November 2026. Includes 527–528 from public source 526.

Save As and document state reuse a single eligibility decision. JPEG and OpenEXR without transparency use the exact surface opacity proof. Cold checks read the visible pixels of each tile through one buffer. Repeated opaque checks can reuse the proof. An alpha edit invalidates it.

File > Open and the optional Photato import API accept JPEG XL stills when ImageIO offers its decoder. The independent fixtures verify all 280 authored RGB8/RGBA16 sample values. Native archive saving preserves the imported image and leaves its source unchanged. Animation is rejected before ImageIO can omit frames.

| Configuration | Selected passed | New tests |
| --- | ---: | ---: |
| Debug | 69/69 | 8/8 |
| Optimized Apple Silicon | 69/69 | 8/8 |
| Optimized translated Intel | 69/69 | 8/8 |

All 7,884 source inputs are frozen. The optimized test IDs match in order. The universal package passes macOS 14 minimum version, signature, entitlement, resource, executable payload and extracted archive checks.

| Optimized configuration | Fixture | Previous two opacity scans | First current JPEG eligibility | 120 subsequent eligibility reads |
| --- | --- | ---: | ---: | ---: |
| Apple Silicon | 24 MP | 74.03 ms | 9.72 ms | 0.12 ms |
| Apple Silicon | 36 MP | 111.06 ms | 15.02 ms | 0.11 ms |
| Intel translated | 24 MP | 144.46 ms | 19.69 ms | 0.26 ms |
| Intel translated | 36 MP | 213.09 ms | 26.77 ms | 0.23 ms |

These are synchronous CPU measurements. The previous predicate runs in the current test binary. JPEG encoding and physical frame rate are separate measurements. Timing varies with allocated tile count and hardware.

The earlier channel-separation HTTP connection failure also occurs on the retained build 526 binary. The version 87 rejection expectation also fails there because that version is supported. The repaired test checks exact version 87 bytes and rejects unsupported version 93. The failed attempts and their changed source inputs are retained at their original hashes.

Desktop automation expired before returning a build 528 launch state. Live editing remains unverified.

Photoshop 27.2 launched and reached its Open dialog. Automation did not open the fixture folder, so the sample comparison in Photoshop remains pending. JPEG XL output, animation import, wider pixel/profile coverage, physical macOS 14 and Intel checks, physical 60 fps, full application testing and prior fidelity/history gates remain open. All 104 scopes, 652 command identities, 81 major memberships and seven passes remain tracked.

[JPEG XL workflow](JPEG_XL_IMPORT.md) · [Evidence](JPEG_XL_AND_SAVE_528.json) · [Source manifest](SOURCE_SNAPSHOT_528.json) · [527 diary](pending-updates/step527.md) · [528 diary](pending-updates/step528.md)
