# Filtering large auxiliary channels

Select an alpha channel, auxiliary spot channel or Quick Mask in the Channels panel, then use the existing Filter menu. Gaussian Blur, Box Blur, Motion Blur, Unsharp Mask, High Pass, Add Noise, Mosaic and Average no longer stop at the former 8-megapixel channel preparation limit. The existing basic filter kernels choose their dense or paged implementation from the input size.

Preview and Cancel leave the source document unchanged. Commit uses one prepared Undo/Redo transaction. Repeat Last Filter uses the current channel and selection. Hidden Quick Masks retain their existing filtering behavior; painting, Fill and Invert still require a visible target. Standalone selection documents can filter their channels without adding image layers.

Channels contain numeric coverage or auxiliary spot density. Float32 proxy storage marks those same numbers linear so filters do not apply an RGB transfer conversion. Display indication, overlay color, opacity and spot Solidity remain presentation properties. The operation retains channel identity, names, options, spot metadata, original spot-gray planes and all other channels/image content. As in the previous implementation, filtered storage is normalized to opaque grayscale across the channel, including unselected samples. Selection controls the filtered change.

Sparse or file-backed mapping replaces full-canvas preparation loops. The logical geometry remains at most 300,000 pixels per side. Existing scratch-plane, file, transfer and actual storage errors remain resource limits; logical admission is not proof that a dense 90-gigapixel job fits a particular Mac. Printing plates retain their separate ink-channel engine.

## API

Use the existing `channel.edit` command:

```json
{
  "action": "filter",
  "target": "<alpha or auxiliary spot channel UUID>",
  "filter": { "kind": "gaussianBlur", "radius": 2 }
}
```

Use `quickMask` as the target for the temporary mask. `channels.filtering` lists the eight paged kinds, geometry, resource limits and retained API-only exceptions. The prior bounded Liquify channel API is preserved with its 8-megapixel limit; it is not newly enabled in the native channel workspace. Other unavailable families reject. Existing stale/busy/sharing/cancellation and prepared-history checks remain. Invalid filter values continue to return the channel API's HTTP422 response.

Native channel storage and current maximum version89 are unchanged. Channel-filter semantic Actions remain unsupported; Actions58 and 265 typed commands are unchanged. No dedicated Adobe HTTP route or unverified desktop action descriptor is introduced.

## Qualification boundary

The baseline contains 288 owned synthetic programs captured from production build468 before this change. They cover three depths, alpha/Quick Mask/spot targets, eight filters, selection and both display indications. All 442,368 captured bytes are compared without normalization or tolerances. A separate 576-byte scalar mean reference checks numeric average and opaque output. These are regression and analytical references, not independent Photoshop filter-output oracles.

Maximum-size tests use sparse constant channels. The separate 8.39-megapixel Noise case executes actual paging and compares its selected row with the frozen earlier output. The final normalized result can compact to a small backed tile; a dense final result is not required. Owned allocation counters are separate from process RSS, mapped residency, disk capacity and interactive frame timing.

[Adobe's alpha-mask guide](https://helpx.adobe.com/photoshop/desktop/create-masks/layer-masks/alpha-channels-and-masks-in-photoshop.html) documents grayscale mask filtering. [The PSB guide](https://helpx.adobe.com/photoshop/desktop/save-and-export/export-files-to-different-formats/image-file-formats-supported-in-photoshop.html) documents the format's 300,000-pixel dimensions. Exact Photoshop kernels, defaults, spot/display/selection policies, wider filter families, dense physical operation, supported platforms, live UI,60fps and full C02 remain open.

All 72 selected Debug methods pass, including 12 new methods. The first implementation run passed 70 and caught two new-test expectation errors: the output compacted to a 64 KB backed tile, and invalid channel-filter values retained the API's existing HTTP422 response. Only those assertions changed; both implementation attempts have identical application hashes. The baseline run intentionally uses unchanged468production code. Every source/log/product is retained. The isolated ARM64 Debug app passes deployment metadata, full entitlements, signature and payload checks and remains unlaunched. Optimized 469 joins a later batch; latest universal is468. [Evidence](CHANNEL_FILTER_CAPACITY_469.json).
