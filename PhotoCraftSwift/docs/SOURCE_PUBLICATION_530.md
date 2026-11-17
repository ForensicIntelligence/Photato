# Source checkpoint 530

Native Swift 0.3.0, build 530, 17 November 2026. Photato sends a completed canvas frame directly to its attached AppKit views. Each view schedules an ordinary redraw. SwiftUI still observes geometry and editing controls. A detached view stops receiving notifications and a reused view follows its current document.

The same 59 selected tests pass in Debug, optimized Apple Silicon and translated Intel. The new lifecycle test verifies two views, document replacement and detachment against accepted brush preview revisions. The initial test relied on the value of AppKit's dirty flag after an asynchronous render. AppKit can clear the flag before the test resumes. A visible hosted run already showed a one-to-one publication and invalidation stream in that first candidate. The corrected test observes the notification at delivery. All three app executable hashes agree between the initial and repaired builds. The attempts are retained separately.

The universal package passes its macOS 14 minimum-version, signature, resource and extracted archive checks. These are static package checks. The native window tests ran from the optimized XCTest bundle.

## Hosted AppKit timing

The original fixture generates 240 samples at 120 Hz in a real AppKit window on a 1200 × 800 owned raster at 50% zoom. The table summarizes two runs of each build, in 528, 530, 530, 528 order. Each after-run ready frame has one direct invalidation. The accepted preview pixels agree with the complete native edit for all four tools.

| Tool | Ready to draw median, 528 | Ready to draw median, 530 | Input to draw p95, 528 | Input to draw p95, 530 |
| --- | ---: | ---: | ---: | ---: |
| Blur | 10.80 ms | 4.98 ms | 17.16 ms | 10.82 ms |
| Brush | 6.49 ms | 1.46 ms | 14.36 ms | 9.86 ms |
| Dodge | 10.30 ms | 1.37 ms | 16.25 ms | 9.27 ms |
| Smudge | 10.09 ms | 8.03 ms | 16.86 ms | 15.84 ms |

A separate 24 MP layered fixture at 12.5% zoom preserves all 240 Brush samples and draws 119 distinct preview revisions. The median ready-to-draw delay is 3.53 ms and input-to-draw p95 is 24.97 ms. Its preview pixels also match the complete native command. This fixture has no matched build 528 timing run.

The measurements time AppKit software callbacks. Physical input, monitor presentation and Photoshop sample parity remain unverified for this increment. The earlier Photoshop and history audit failures remain open. Existing document math, archive formats, command settings, keyboard behavior and the two API contracts remain in use. The package is a validation build. App Store release still requires the maintainer's manual approval.

[Development record](DEVLOG.md#dev-step-530) · [Measurements](CANVAS_PUBLICATION_530.json) · [Frozen source](SOURCE_SNAPSHOT_530.json)
