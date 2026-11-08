# Filtering masks

Select a layer-mask or Smart Filter-mask thumbnail, then choose a supported filter from the existing Filter menu. Gaussian Blur, Box Blur, Motion Blur, High Pass, Unsharp Mask, Add Noise, Average and Mosaic use the existing dialogs and shared filter kernels. Preview works on a document copy; Cancel leaves the document unchanged. OK creates one prepared Undo/Redo transaction. Repeat Last Filter uses the currently selected target and captured settings.

Filtering changes grayscale mask samples. It leaves the owner's color pixels, embedded Smart Object, Smart Filter settings, other masks and mask properties intact. The current selection follows the mask's stored placement. Inversion is interpreted when preparing displayed grayscale and reversed when storing the result. Density, feather, enabled state, linking and outside coverage remain separate properties. Mask alpha does not weight grayscale filtering; its original sample values are retained. Unchanged grayscale samples retain their original stored bits.

The adapter uses the current raster-filter kernels and stored rectangle. It does not add a new document-size limit. Large masks use the same existing paged filter paths and resource checks. Sparse maximum geometry does not establish dense memory, disk or interactive performance qualification. The wider grayscale filter families, vector-mask rasterization, compound-mask conversion and matte-removal commands remain work.

## API

The existing `filter.apply` command accepts an optional `target`:

```json
{
  "layerID": "<owner UUID>",
  "target": "layerMask",
  "filter": { "kind": "gaussianBlur", "radius": 2 }
}
```

Use `smartFilterMask` for the owner's Smart Filter mask. Omitting the parameter keeps the existing `pixels` target, independently of the selected thumbnail. Capabilities list the supported targets and filter kinds; the parameter schema lists all three target values. Both masks share the native engine, prepared transaction, revision, sharing and cancellation checks. `filter.repeat` uses the current native editing target. Missing or locked masks and unavailable filters reject without editing the document.

Native format89 already stores the result. Semantic mask-filter Actions recording remains unsupported and reports that fact explicitly; Actions58 is unchanged. There is no new published Adobe HTTP endpoint or verified desktop action descriptor for this operation. The Adobe-compatible interface retains its previously qualified subset; it does not silently redirect an image filter to a mask.

## Reference boundary

[Adobe's Smart Filter mask guide](https://helpx.adobe.com/photoshop/desktop/effects-filters/smart-filters/mask-smart-filter-effects.html) documents direct filtering of filter masks. It does not establish the exact numerical output of these implementations. Current kernel, border, exterior, affine radius, inversion quantization, noise, profile, default and parameter policies still need independent Photoshop references. Full S06 and Photoshop equivalence remain open.

## Qualification

97 selected Debug methods pass, including all 15 new methods. A planned 98th Debug method crashes with signal 10 on both the current build and retained 467. The same 98 optimized methods pass on ARM and translated Intel, including that method. All 384 bytes of the separate scalar-average reference agree across those runs. The prior neutral Photoshop refinement mask also retains all 3,072 bytes; it is not a filter-output oracle. Existing tests/fixtures, project, assets and entitlements are unchanged.

The first attempt retained three new-test failures and the old Debug crash before repair. The new average expectation had omitted the inverted storage complement, and the HTTP test compared irrelevant settings omitted by the schema. A real API admission defect also prevented an explicit pixel filter while a mask was selected; that is repaired without redirecting the edit to the mask. Both source archives/logs/products and the incorrect reference are retained. The isolated Debug package and optimized universal pass checks for macOS 14 deployment metadata, entitlements, signatures and payloads. The universal ZIP matches its verified extracted content. They are unlaunched; native UI acceptance remains pending after the CUA pipe failure. [Evidence](MASK_FILTER_TARGETS_468.json).
