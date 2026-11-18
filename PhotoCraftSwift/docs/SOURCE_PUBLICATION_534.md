# Source checkpoint 534

Native Swift 0.3.0, build 534, 17 November 2026. A ready ordinary Brush canvas submits the worker for its first preview during input. The existing renderer computes the pixels and the main actor publishes the accepted frame. A cancellation cancels publication and the early worker. Later frames and other callers continue to submit through their existing tasks. Opt-in canvas timing now includes actual worker enqueue, start and completion for accepted frames. The Brush API metadata describes those fields. The paint command inputs and editing transaction still use the shared brush path.

All 107 selected native methods and seven retained Photoshop-reference methods pass in Debug, optimized Apple Silicon and Intel under Rosetta. The touched tests verify monotonic worker timestamps, synchronous submission, one follow-up frame for all queued samples, exact native output and cancellation without publication or a history entry. The 20 captured Photoshop RGB32 examples exercise the existing compositor. Independent Photoshop freehand stroke comparison remains open. Step 533 records the installed Photoshop control and single-mark Undo behavior.

## AppKit timing

The timed fixture has a 6000 × 4000 canvas, two tone adjustments and 240 independently scheduled Brush samples at 120 Hz. Each comparison uses four runs per build in alternating order. Every run checks exact native preview and committed pixels, one Undo entry and document restoration. The opening comparison is shown below. Start-of-stroke values are the median of four runs. Continuous p95 is the median of the four per-run p95 readings.

| Stage | Build 533 | Build 534 |
| --- | ---: | ---: |
| Initial input to handler return | 0.23 ms | 0.21 ms |
| Initial input to ready preview | 23.66 ms | 17.62 ms |
| Initial input to AppKit draw | 26.86 ms | 20.82 ms |
| Input feed interval, p95 | 9.78 ms | 9.56 ms |
| Continuous enqueue to AppKit draw, p95 | 17.70 ms | 21.46 ms |

The repeat reversed trial order. Its first draw measured 30.44 ms to 20.42 ms, and continuous p95 measured 22.58 ms to 18.21 ms. Across both comparisons, first draw measured 27.52 ms to 20.77 ms, and continuous p95 measured 18.37 ms to 18.48 ms.

Across all eight build 534 trials, the worker begins a median 0.23 ms after accepted input. The worker runs for a median 7.15 ms, and a completed result waits a median 10.04 ms before the main actor accepts it. Build 533 exposed request and ready timestamps, so the worker subdivision is specific to build 534. The measurements are software callbacks. Physical 60 fps, stylus input and arbitrary layered documents remain open.


The ZIP passes macOS 14 deployment metadata, both architectures, signature, entitlement, resource and extracted archive checks. The extracted app ran its built-in offscreen workspace command on Apple Silicon and under Rosetta. Standard interactive packaged launch and editing, actual macOS 14 and physical Intel still require testing.

[Development record](DEVLOG.md#dev-step-534) · [Timing evidence](BRUSH_WORKER_534.json) · [Frozen source](SOURCE_SNAPSHOT_534.json)
