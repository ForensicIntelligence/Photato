# Source checkpoint 533

Native Swift 0.3.0, build 533, 17 November 2026. A ready ordinary Brush canvas captures the first preview immediately. The background renderer remains responsible for preparing pixels. Later frames use the existing rate and collect every stroke sample. The ordinary Brush, Pencil, Mixer Brush, Eraser, mask and Adjustment Brush tests exercise preparation and commit through their normal entry points. Brush capability metadata describes the desktop behavior. Command inputs, shortcuts and native document structures retain their existing contracts.

All 93 focused and seven retained Photoshop-reference methods pass in Debug, optimized Apple Silicon and Intel under Rosetta. The deterministic new test verifies synchronous first preparation, a single follow-up frame for a burst of ten samples, exact final composite equality and empty pre-release history. The Photoshop fixture methods exercise 20 captured RGB32 examples through the existing compositor; a new freehand Photoshop byte comparison remains open. Photoshop's installed Brush displayed 10% smoothing, and Undo cleared the mark in a disposable document. The automated drag registered one mark, so that reference covers the initial action only.

## AppKit timing

The same native AppKit workspace hosts both builds with an independently scheduled 120 Hz input feed, 240 Brush samples, a 6000 × 4000 canvas and two tone adjustments. Four optimized runs per build use alternating order. Every run compares the final preview and committed document to the complete command, checks one history entry, and checks that Undo restores the document. First-frame columns report the median of four first frames. Continuous rows report the median of each run's p95.

| Stage | Build 532 | Build 533 |
| --- | ---: | ---: |
| Initial input to preparation | 18.12 ms | 0.20 ms |
| Initial input to handler return | 0.17 ms | 0.22 ms |
| Initial input to ready preview | 25.90 ms | 25.43 ms |
| Initial input to AppKit draw | 29.45 ms | 29.14 ms |
| Initial enqueue to AppKit draw | 29.59 ms | 29.26 ms |
| Input feed interval, p95 | 10.26 ms | 10.28 ms |
| Continuous enqueue to AppKit draw, p95 | 24.61 ms | 24.72 ms |

The first frame captures one sample inside input delivery in every candidate run. The first AppKit draw changed by less than a millisecond and the continuous p95 stayed near 25 ms in both builds. EditorStore.render still creates its background worker inside a main-actor task. Measuring actual worker start would distinguish that remaining delay from the work performed by the renderer. Physical input and monitor presentation remain unmeasured. Exact Photoshop Brush kernels and the broader parity work remain open.

The universal validation archive passes architecture, macOS 14 deployment metadata, signature, bundled model, and extracted archive checks. The live packaged-app check ended when the computer-use connection expired, so runtime launch of the package remains unverified. Actual macOS 14 and physical Intel still require runtime verification.

[Development record](DEVLOG.md#dev-step-533) · [Timing evidence](BRUSH_FIRST_FRAME_533.json) · [Frozen source](SOURCE_SNAPSHOT_533.json)
