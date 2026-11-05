# Edit live Gradient Fill layers

Checkpoint 410 adds `gradient.fill.patch` to the optional Photato API. It edits an existing live Gradient Fill using the same native command as Properties and canvas controls. All74focused Debug and82normal optimized cases per architecture pass on410Source02, including eight new cases. The isolated universal package passes min14/signature/ZIP checks. Actual live UI remains pending human unlock; full A05/Photoshop qualification is open. [Evidence](GRADIENT_FILL_API_410.json).

POST `/v1/documents/{id}/commands` with the current revision:

```json
{"command":"gradient.fill.patch","revision":"<current revision>","parameters":{"layerID":"<gradient layer UUID>","fill":{"placement":{"angle":45,"scale":0.75,"offsetX":0.125,"reverse":true}}}}
```

The nonempty `fill` object may update `gradient`, `placement`, `aligned` and `dither`. Nested objects retain omitted values; supplied colour or opacity stop arrays replace the whole array. Other layer data, masks and placement transforms are retained. Angles use counterclockwise degrees. Scale and offsets use fractions, unlike the percentages shown in the native UI. The native reference frame accounts for alignment, masks and artboards.

Captured RGB, HSB or gray colours are accepted. Dynamic foreground/background references must be resolved before submission. The gradient definition retains name, interpolation method, smoothness, stops and midpoints. Existing native validation allows up to 1000 colour and 1000 opacity stops. The usual sharing, authentication, request-size, document-size, revision and busy guards remain. Non-gradient targets reject; locked layers/parents and component-editing contexts match native availability. Accepted edits use one Undo/Redo transaction.

`gradientFills.activeLayerID`, `activeFill` and `canEditActive` describe the selected Gradient Fill in document state. A different active layer reports null fill/ID. A patch can target a nonactive gradient layer without changing selection. Capability discovery publishes the command and request/state/result schemas. A normal response is the shared document state.

The typed catalog becomes 244. Native archive 86 is unchanged. A new self-contained Gradient Fill edit requires Actions format 47; older operation payloads retain their earlier minimum versions and files 1–46 remain readable. Earlier unsupported Gradient Fill entries contain no recoverable settings and remain unsupported. No Adobe endpoint or unqualified live-layer descriptor is added. Gradient creation, Classic Gradient painting and preset-library automation remain separate API gaps. Full gradient/noise/GRD/interpolation/dither/default/Photoshop/platform acceptance remains open.
