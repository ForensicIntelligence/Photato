# Custom Filter Gallery textures

Rough Pastels, Underpainting, Glass, Conté Crayon and Texturizer can now load a custom Photoshop PSD or PSB texture. In **Filter > Filter Gallery**, choose one of those effects and click **Load Texture…**. The Texture control shows the loaded filename and dimensions. Choosing a built-in texture removes the custom override. Scaling and Invert apply to all five effects; relief/light or Glass distortion/smoothness use the existing effect controls.

Loading changes the filter draft, with local Undo/Redo. It does not edit document pixels until OK. Cancel discards the draft. A failed or cancelled load retains the previous settings and usable preview. Changing the effect, editing settings or closing the workspace prevents a late load from replacing newer work. File reading, decoding and conversion run in a cancellable worker. The native picker grants access to the selected file; the app does not ask for broader folder access.

Textures are embedded height samples, not references to external files or library entries. New effect copies and reordered effects retain their own settings. Smart Filters remain editable, and Actions carry the same samples into later documents. Documents containing texture-bearing Smart Filters require **native archive 88**; Actions containing these settings require **version 54**. Ordinary Gallery settings retain their earlier minimum versions, 36 and 8. Older requested archive versions reject the new feature rather than silently lose it. Editable Adobe PSD/PSB Gallery descriptors remain unsupported; save the editable document as Photato.

## API

The optional native API adds **`filter.gallery.texture`**. Send the current shared document revision and a canonical base64 PSD/PSB file:

```json
{
  "command": "filter.gallery.texture",
  "revision": "<current revision>",
  "parameters": {
    "name": "My texture.psd",
    "data": "<base64 Photoshop file>"
  }
}
```

The result contains `revision` and `texture`. Conversion has no document, preference or history side effects. It uses the same loader as the desktop. Authentication, sharing, busy state, request cancellation and current revision are checked; generation, sharing, revision and desktop preflight are rechecked after the worker completes.

Pass the returned object to the existing **`filter.apply`** command:

```json
{
  "layerID": "<target layer UUID>",
  "filter": {
    "kind": "filterGallery",
    "artistic": {
      "effects": [{"filter": "texturizer", "texture": {"name": "Example height", "width": 2, "height": 2, "samples": "AFWq/w=="}}]
    }
  }
}
```

The example uses a small literal height plane. Replace it with the returned `texture` object when loading a PSD/PSB. Omission or `null` uses the built-in texture choice in `values.texture`. Unsupported effect kinds reject custom textures, including hidden effects. A texture has `name`, `width`, `height` and canonical base64 `samples`: one row-major unsigned 8-bit height per pixel. No path, URL or bookmark is stored. State under `filterGallery.workspace` adds `textureLoading` and `textureError`; discovery includes the new command, texture/result schemas, workspace schema extension and current limits. There are 260 typed commands.

There is no dedicated Photoshop v2 texture-import operation in the pinned Adobe contract. Gallery `actionJSON` remains explicitly unsupported. No Adobe endpoint or descriptor is invented.

## Current processing and limits

The loader reads the file's merged image through ImageIO, converts it into encoded sRGB8 and computes rounded `0.299R + 0.587G + 0.114B` height samples. Custom sampling repeats bilinearly at integer pixel centers, using the existing Gallery shading/distortion controls. These are current Photato processing semantics; Photoshop's precise conversion, alpha/profile interpretation, orientation, tiling, scaling, light and numerical behavior have not been qualified independently. Built-in texture algorithms and original fixtures are unchanged.

Inputs are bounded to 64 MiB and textures to 8,388,608 pixels, with dimensions up to 300,000 per axis subject to that pixel budget. Existing Gallery limits of 8 MP per layer and 64 million effect-pixels per stack remain. Actions retain their existing 16 MiB file limit. The native command request limit is raised to 89,544,024 bytes to accommodate the largest supported PSD/PSB input and the returned texture payload. Other HTTP route limits are unchanged. Aggregate request, document, archive and memory limits still apply; this does not establish Photoshop-scale Gallery capacity or 60fps performance.

## Validation

All 34 focused Debug methods pass, including 16 new tests. They cover gray/color PSD and PSB decoding, row orientation, strict malformed inputs, analytic height sampling, all five effects at three depths, retained alpha, local/document history, cancellation/errors/stale loads, Smart Filters, Actions, real HTTP conversion/application/guards, an 8 MP API payload and archive negotiation. Existing Gallery effect, drag, modifier and catalogue tests are included. Native sandbox testing verifies PSD/PSB picker loads, local Undo/Redo, a committed Smart Filter, document Undo/Redo, native Save As 88, retained settings on re-edit, Cancel and normal Quit.

Optimized architecture and fresh-file reopening checks are complete for the selected workflow; the strict Float32 byte comparison remains failed. [Checkpoint evidence](GALLERY_TEXTURES_453.json) records the final results, source/binary hashes, signing metadata exception, failed attempts and remaining gates. Offscreen snapshots are not live UI evidence. No full F06 or Photoshop parity claim is made.

The same 34 selected tests pass in optimized Apple Silicon and Intel builds, with Intel run under Rosetta. Ten of fifteen raw effect/depth buffers match byte-for-byte across those builds. Five Float32 buffers retain 55 color-word differences of one ULP; alpha is exact. The strict byte gate remains failed. Native testing confirms PSD/PSB loading, local and document history, Save and a fresh optimized reopen of the embedded Smart Filter. The universal package verifies both macOS 14 targets, full sandbox entitlements, signing and exact ZIP extraction. These are focused checks; no independent Photoshop texture pixel oracle was obtained. [Checkpoint evidence](GALLERY_TEXTURES_453.json).
