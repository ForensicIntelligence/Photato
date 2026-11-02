# Trim and Reveal All

Image > Trim… offers Transparent Pixels, Top Left Pixel Color and Bottom Right Pixel Color, plus independent Top, Bottom, Left and Right checkboxes. The documented default is top-left with all four edges enabled. Cancel and changed-source checks preserve the document. A changed Trim result is a single Undo. The native UI and API share preparation and commit.

Trim analyzes the full visible RGB composite, regardless of the current selection. It excludes invisible layers from that composite. A flat aligned native component image compares its numerical channels directly, preserving distinctions that a display RGB cache could clip. Indexed/Bitmap use their palette/bit representation and existing exact grid crop. Empty results fail atomically. No selected edges and already-trimmed bounds produce no change. On a changed result, ordinary raster pixels outside the new canvas are cropped and current selection is cleared. Rich objects retain their editable source. Saved paths, guides and channels follow the geometry; captured comp positions follow each layer's actual new storage origin.

Image > Reveal All expands the current canvas to include retained nontransparent leaf content. It retains the existing canvas, includes hidden and zero-opacity leaves, and ignores transparent storage padding. Layer content remains editable and unresampled. The coordinate frame, saved paths, guides, selection/channels, masks, fill geometry and comp positions move together. Background extension uses the captured background color. Native Background components are copied as bytes; retained values do not pass through RGB conversion. Advanced mask/effect bounds and exact Photoshop handling of those contexts remain unqualified.

Exact RGB framing chooses a uniform default from the larger original/padding region and streams bounded patches to pages. A thin border can be represented without materializing a large uniform interior. Raw floating words, both floating sample encodings and intentionally unquantized implicit values are retained. RGB logical dimensions remain300000per side. Native component/palette/ink storage still has its separate existing budgets; dense maximum-size editing and speed are not qualified.

## Automation

Photato document.trim accepts optional basis (topLeft default, bottomRight, transparent) and Boolean top/left/bottom/right (true defaults). document.revealAll accepts optional backgroundColor as three RGB values. Both require the composite document target and the source revision. Responses use the existing updated shared-document state schema, including canvasEdges availability/dialog/reason fields. Malformed values, unavailable context, busy/stale/cancelled/revoked requests retain the shared API error and transaction policy. No partial commit occurs. There are239typed commands, native84andsemanticActions44. Older action minima remain, including Flatten43, Pattern42andpixelFill/Stroke41.

Semantic recording retains the operation, Trim edges/basis and captured extension color. Replay uses the same compositor and exact geometry. Downgraded action files reject the new operations. The existing native history/API authorization/lifecycle checks remain in force.

The pinned Firefly contract has no dedicated Trim or Reveal All endpoint. Public desktop UXP Document.trim and revealAll describe reference behavior but are not Firefly HTTP routes. Generic actionJSON support remains an explicit gap until authoritative descriptor provenance and conformance are available. No route or proprietary model equivalence is invented.

## Evidence and remaining work

All 24 new cases pass. Of 304 affected optimized cases, 302 pass; 2 fail with 2 assertions and 1 unexpected errors. There are 0 crashes. Independent analytical/PNG readers verify336RGBAbytes; 12 PSD/PSB headers are checked separately.

Temporal and ink-mode canvas rebasing, layered native component Trim, advanced mask/effect bounds, authoritative Adobe actionJSON descriptors, exact Photoshop defaults/output/live UI, supported Macs, full current suite, dense maximum capacity and physical60fps remain open. All104complete package scopes remain open.

Photoshop's Home window and menu tree were readable, but input commands timed out. No reference document was opened, and no live Trim/Reveal All result was qualified. Ordinary installed AppleScript terminology confirms the named operations/defaults; it is not proof of Action Manager descriptors. Owned analytical vectors, native AppKit controls, loopback HTTP, numerical-plane comparisons and native format round trips provide separate evidence. Any affected failures remain in the current run; their case identities are compared with359for investigation, without claiming that matching a failed case name proves identical output.

Installed283, private source backup298 and store archive332 are unchanged. No install, push, archive, upload or release.

[Adobe desktop help](https://helpx.adobe.com/sk/photoshop/desktop/crop-resize-transform/resize-adjust-resolution/crop-and-straighten-images.html) · [Adobe UXP Document](https://developer.adobe.com/photoshop/uxp/2022/ps-reference/classes/document) · [Evidence](CANVAS_EDGES_REFERENCES.json)
