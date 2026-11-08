# Content-Aware Fill: Apply and continue

Apply commits the current fill and leaves the native workspace open. Use Selection with Mode New to choose another fill area. Add, Subtract and Intersect are also available; Shift temporarily adds, Option subtracts, and both intersect. The mode is captured at stroke start. Sampling Brush retains its existing Option reversal.

Each applied fill has its own document Undo. Cancel discards the current preview and retains already applied fills. OK commits a pending fill and closes the workspace; immediately after an unchanged Apply it closes without another layer or history entry. Settings and sampling strokes remain; local selection strokes/history reset against the applied selection. New output retains the original sampling layer; Duplicate continues from the new duplicate. Exact Photoshop source and output-layer identity still needs direct comparison.

The existing contentAware.fill API uses the same engine/history for repeated requests. An optional selectionMode on selection strokes accepts New, Add, Subtract and Intersect. Omit it to retain legacy add behavior. A mode on a sampling stroke rejects. Native open-workspace state is available in contentAwareFill, with a discovery schema. Remote commands still reject while a native modal editing workspace is busy.

```json
{"command":"contentAware.fill","revision":"<fresh revision>","parameters":{"layerID":"<source layer UUID>","output":"new","strokes":[{"target":"selection","kind":"lasso","selectionMode":"New","points":[[32,12],[38,12],[38,18],[32,18]]}]}}
```

All 38 focused Debug tests pass, including seven new methods. They cover all three bit depths/output choices, two Applies, Undo/Redo, Cancel, unchanged OK, stale/cancelled work, native archives, literal selection coverage, real HTTP equivalence/state/errors and captured cursor modes. The first run and repairs are retained. Normal458 is deferred; universal457 remains the latest optimized build with its documented strict failures.

The isolated Debug app verifies macOS14 metadata, production sandbox entitlements, signing and exact unsigned payload. Native Open/owned-image/marquee/eligible menu checks succeeded, but the automation native pipe disconnected while opening the fill workspace. Apply, Close and Quit were not observed. The disposable validation app remains open; post-disconnect UI state is unknown. No image save or original-file change occurred. Hosted Light/Dark layout is not full visual or accessibility qualification.

Adobe documents [Apply, new selections, OK and Cancel](https://helpx.adobe.com/photoshop/desktop/repair-retouch/remove-objects-fill-space/apply-or-cancel-fill-changes.html). Its [multi-image workflow](https://helpx.adobe.com/photoshop/desktop/repair-retouch/remove-objects-fill-space/fill-selections-with-multi-image-content-aware-fill.html) is separate missing functional scope. Direct installed-Photoshop Apply/layer/default/pixel qualification remains open. Existing16MP canvas/4MP synthesis/scale dimension and work limits, physical platforms/tablets/60fps, Actions recording, all prior strict failures and full original B06 acceptance remain open. No Adobe route, archive-version change or global shortcut was invented. [Evidence](CONTENT_AWARE_APPLY_458.json).
