# Photato local automation API — v1 preview

Photato can serve a browser client and a versioned HTTP API while its native application is running. The server, document model, renderer and editing commands are Swift. The optional browser client uses HTML/CSS/JavaScript to call that native engine. The macOS editor remains AppKit/SwiftUI.

## Two maintained API interfaces

Maintain both interfaces as supported product APIs: the Photato API for native document automation and Photato-specific capabilities, and the Adobe Photoshop v2-compatible API for clients using the published contract. They share the native Swift engine; do not duplicate editing algorithms. Preserve the existing Photato /v1 routes and clients rather than replace or silently repurpose them. Every new capability must include Photato API coverage, schemas, documentation and tests; when Adobe defines the corresponding operation, include its compatible interface and conformance tests in the same increment. Keep Photato-only operations distinct rather than inventing Adobe routes. Test equivalent underlying operations across both interfaces and the desktop while respecting each contract’s document/job lifecycle. Report each interface’s actual coverage independently; support for one does not imply support for the other.

Current status (step113): seventeen typed document commands, optional resource action jobs, document uploads/downloads, and native Save/Save As with a separate default-off local-write permission. Supported source files retain their file association. Format options, profile/float fidelity, six Adobe endpoints and full Photoshop parity remain open. See [source-save evidence](SOURCE_SAVE_REFERENCES.json) and the [classified backlog](FUNCTION_PHASES_109.json).

## Save and Save As (step113)

**File → Save** (Command-S) writes the associated supported format; **Save As…** (Shift-Command-S) chooses a new name, format and association. Eligible formats are Photato, supported PSD, PNG, JPEG and TIFF. Source associations use the actual image container, including common .jpg/.jpe/.tif aliases and misleading filename extensions. Ordinary Save keeps the associated filename; Save As chooses a canonical extension. The native selector shows only formats capable of preserving the model's supported editable structure; individual codec constraints can still reject the save. Layered documents use Photato or supported PSD; flattened conversions remain Save a Copy. PNG/TIFF persistence requires one full-canvas pixel layer with no mask, transform, path, reduced opacity or non-Normal blending, at8/16-bit depth. JPEG additionally requires opaque RGB8 and uses95% lossy encoding. Recovery autosaves always use Photato archives.

API saving requires **Allow local document saving** in the native API window, an active share and current revision. Save As additionally requires **Choose Save As Folder…**. Both permissions and the selected folder reset when the service stops. Commands accept no arbitrary local path:

```json
{"command":"document.save","revision":"CURRENT_REVISION","parameters":{}}
```

```json
{"command":"document.saveAs","revision":"CURRENT_REVISION","parameters":{"name":"Edited image","format":"photato","replace":false}}
```

Post to `/v1/documents/{id}/commands`. Save As requires all three parameters: a printable nonblank filename of at most200 UTF-8 bytes, format `photato|psd|png|jpeg|tiff`, and boolean `replace`. Names cannot begin with a dot or contain slash, backslash or colon. The canonical extension is appended when absent; supply a bare basename or the matching extension. Only `replace:true` permits replacing an existing destination in the chosen folder. Symbolic-link destinations and files owned by another open document are refused. Ordinary Save requires an associated file whose modification date still matches the last open/save. Source and destination checks run before encoding and again before coordinated writing.

Successful saving returns current document state, clears `isModified`, and keeps Undo/Redo. Save As changes the document name, format and file association. Failed, cancelled, stale or revoked saves do not adopt a new file or clear the modified flag. `documentSaving` exposes format notices and error/availability policies; `documentSavesEnabled` and `saveAsFolderSelected` expose session availability without disclosing paths. State adds:

```json
{
  "persistenceFormat":"psd",
  "saveFormats":["photato","psd"],
  "sourceSaveNeedsReview":false,
  "canSave":true,
  "canSaveAs":true
}
```

`canSave`/`canSaveAs` reflect permission, association/folder and current interaction state; execution still validates representation, revision, disk state and limits. Imported non-sRGB sources and RGB32 PSDs currently require explicit Save As review before ordinary source replacement (`sourceSaveNeedsReview:true`); exact source-profile/float preservation remains unfinished. The format notice identifies conversion limits. Native archive saving retains the current editable model; it does not reconstruct import information already converted by a codec.

Errors: invalid parameters400, disabled saving/missing folder403, missing source/busy/stale/revoked/existing destination/changed file409, output larger than128MiB413, unsupported representation or I/O422. Existing authentication, share, command-body and decoded-document limits apply. Desktop and API use the same native encoder, NSDocument save operation and document history. There is no dedicated desktop Save/Save As endpoint in the pinned Adobe v2 contract; its two partial resource-job endpoints keep using the shared codecs.

## File metadata preservation (step112)

Native Copy/download and both resource-job interfaces share the native metadata encoders. Raster imports retain ImageIO properties and XMP in `.photato` archives. Supported raster outputs preserve camera/descriptive/copyright/IPTC fields and custom XMP while updating orientation, dimensions, resolution and working-color fields. PSD copies retain opaque image-resource blocks, regenerate profile/resolution/path/XMP data and omit stale previews, layer-index/selection, version and recovery records. Opaque retention does not implement the Photoshop workflows those records may describe. Binary PSD EXIF remains opaque; full format metadata synchronization remains open.

`documentTransfers.metadata` exposes the retention policy:

```json
{
  "type": "object",
  "required": ["raster", "psd", "profiles", "metadataLimitBytes"],
  "properties": {
    "raster": {"type": "string"},
    "psd": {"type": "string"},
    "profiles": {"type": "string"},
    "metadataLimitBytes": {"type": "integer", "const": 16777216}
  },
  "additionalProperties": false
}
```

The limit applies to each retained metadata payload (and the complete PSD image-resource section). Invalid or oversized stored metadata rejects encoding through existing error responses; failed output does not modify the shared document/history. Working/output pixels still use sRGB, with linear sRGB for RGB32 PSD. Original non-sRGB profile preservation and full Photoshop pixel/file equivalence remain open. See [metadata evidence and exact limits](SOURCE_METADATA_REFERENCES.json).

## Save a Copy and Revert (step110)

RGB32 storage now preserves supported linear-sRGB PSD raster sample bits through native archive version9, metadata-only edits and PSD layer output. Opaque untransformed Normal raster composition and ordinary groups also retain exact samples in merged output. `documentTransfers.float32Storage` reports the encoding, archive version, shared interfaces and limits. Native downloads/saves and both action-job interfaces use the same codecs. This does not qualify every HDR edit, transformed/adjusted/fractional blend, original non-sRGB profile or complete Photoshop pixel/file equivalence; RGB32 source replacement still requires Save As review.

**File → Save a Copy…** (Option-Command-S) writes a separate Photato, supported PSD, PNG, JPEG or TIFF copy. The API equivalent remains `GET /v1/documents/{id}/file.{format}`: the same snapshot and native encoders produce the output without changing the open document, filename, modified flag or Undo/Redo history. Downloads never choose a local save path. The native sheet explains flattening/depth conversions; format-specific compression, profile and metadata options remain incomplete. A native Save panel replacement confirmation can authorize overwriting an existing original; API downloads have no local overwrite operation; the separately enabled Save commands above can write associated files or files inside the approved folder.

**File → Revert** (F12) reloads the document’s associated local file. The Photato API exposes the same operation:

```json
{"command":"document.revert","revision":"CURRENT_REVISION","parameters":{}}
```

Post this to `/v1/documents/{id}/commands`. Revert requires native **Allow document transfers and Revert** enablement and an existing share. It reads only that document’s existing file association; client-supplied file paths are rejected. Upload-only/unsaved documents have no source until saved through the desktop or the separately enabled Save As command. Revert is one shared history edit, clears `isModified`, and can be undone/redone through either client. State adds `hasRevertSource`, `canRevert`, and `fileOperationBusy`; current interaction/revision checks remain authoritative at execution time. AppKit recovery autosaving preserves the last explicit save separately.

The persistence fields in the returned shared-document state follow this schema (other existing state fields remain present):

```json
{
  "type": "object",
  "required": ["isModified", "hasRevertSource", "canRevert", "fileOperationBusy"],
  "properties": {
    "isModified": {"type": "boolean"},
    "hasRevertSource": {"type": "boolean"},
    "canRevert": {"type": "boolean"},
    "fileOperationBusy": {"type": "boolean"}
  },
  "additionalProperties": true
}
```

Disabled permission returns403; missing saved source, busy/stale requests, concurrent edits or revoked access return409; resource limits413; unreadable/unsupported content422. The read uses the same64MiB input,4MP,64-layer and128MiB decoded-document limits as uploads. Failed/revoked/stale reads leave document content/history unchanged. Current native file lifecycle has no corresponding endpoint in the pinned Adobe v2 contract; existing action jobs remain separate and partially compatible.


**Current format policy:** `.photato` and legacy `.pcswift` downloads use Photato’s own archive; `.psd` uses the separate PSD codec. Full PSD support remains required and incomplete. The proposed PSD-backed `.photato` migration was withdrawn. See [format policy](DOCUMENT_FORMAT_POLICY.json).

## Document uploads and downloads (step109)

Start the API, then enable **Allow document transfers and Revert** in its native window. This is off each session and separate from resource action jobs. Uploads create a new unsaved document, open its native window and share it with the current API session. Downloads copy an explicitly shared document; they do not save to a local path, overwrite its source, mark it clean or change its undo history. Revoking a document share blocks its downloads. Disabling transfers or stopping the service invalidates in-flight results, including if transfers are enabled again before decoding completes. Already-created documents remain open; stopping the service revokes their shares.

| Operation | Request | Result |
| --- | --- | --- |
| Import | `POST /v1/documents/import` with raw file bytes | HTTP201 and new document state with `id` and `revision` |
| Download | `GET /v1/documents/{id}/file.{format}` | HTTP200 with a binary document snapshot |

Import Content-Type values are `application/vnd.photato.document`, `image/vnd.adobe.photoshop`, `image/png`, `image/jpeg`, `image/tiff`, `image/heic`, `image/bmp` and `image/gif`. The native archive type uses the native archive decoder; image types use the shared native image/PSD decoder and content identification. `X-Photato-Name` optionally supplies a nonblank printable ASCII name of at most256 characters; otherwise images use “Imported Image”. Native archives retain their stored name. Desktop file opening also retains its filename-derived name. Supported decoding does not imply complete metadata, profile, animation or format parity; GIF input currently takes the first image.

Download formats are `photato`, `psd`, `png`, `jpeg` and `tiff`. Photato archives preserve supported editable native structure. PSD output uses the existing supported editable-layer writer; unsupported structures can fail explicitly. Raster downloads flatten through the same native image exporter, with its current depth, profile and alpha limits. Supply `X-Photato-Revision` with the latest state revision to reject a stale download request. A document change, share revocation or session change during encoding also rejects the response. This custom header is a Photato revision token, not an HTTP entity tag. The old `file.pcswift` route remains an alias for `file.photato`, returning identical native archive bytes. Capability metadata advertises this under `documentTransfers.download.formatAliases`; the native MIME type and archive encoding are unchanged.

```sh
curl --fail -H "Authorization: Bearer $PHOTATO_TOKEN" \
  -H "Content-Type: image/png" -H "X-Photato-Name: Client image" \
  --data-binary @image.png "$PHOTATO_ENDPOINT/v1/documents/import"

curl --fail -H "Authorization: Bearer $PHOTATO_TOKEN" \
  -H "X-Photato-Revision: $PHOTATO_REVISION" \
  "$PHOTATO_ENDPOINT/v1/documents/$PHOTATO_DOCUMENT_ID/file.photato" \
  --output copy.photato
```

Uploads are limited to64MiB,4,194,304 canvas pixels,64 layers and128MiB of decoded document data. Dimensions are checked before pixel decoding; native archive raster expansion also has an explicit128MiB budget. Downloads are limited to128MiB. Only one transfer runs at a time, and the existing eight-share session limit applies. The upload body limit applies only to the exact POST import route; document-command requests retain64KiB and isolated action submissions retain4MiB. Existing internal codec allocation limits still apply; large-document/scratch/streaming work remains open.

Errors distinguish invalid name400, authentication401, disabled403, missing share/route404, busy/stale/revoked409, resource limits413, unsupported Content-Type415, decode/encode/unsupported content422, and transfer/share capacity429. Complete capability metadata appears under `documentTransfers` and `documentTransfersEnabled`; document state adds `isModified` and `persistenceFormat` (`photato`, `psd`, `png`, `jpeg` or `tiff`). Uploading does not create a document until decoding, limits and session checks succeed. Local source-format save-back is not exposed by these routes.

Adobe v2 has no dedicated interactive desktop Open/Save endpoint. Its existing execute-actions input/output adapter remains a separate, limited action-job workflow using the same native RasterIO/PSDCodec implementation. No new Adobe endpoint or broader Adobe action input contract is claimed here. [Document workflow evidence](DOCUMENT_IO_REFERENCES.json) records tests and live scope.

## Adobe compatibility target

The maintainer requires compatibility with [Adobe Photoshop API v2 GA](https://developer.adobe.com/firefly-services/docs/photoshop/getting-started/v2-ga/) in Firefly Services. The `/v1` document routes below are Photato's own preview. The separate `/v2/execute-actions` and `/v2/status/{jobId}` routes implement a **limited Adobe-shaped subset**, not complete Adobe service compatibility. The existing version label does not refer to Adobe Photoshop API v1.

Add a Swift compatibility adapter alongside the maintained Photato API covering published routes, payloads, asset conventions, job submission/status and error behavior. Adobe's [status guide](https://developer.adobe.com/firefly-services/docs/photoshop/guides/photoshop-v2/v1-to-v2/status-migration) documents the job lifecycle; the [font workflow](https://developer.adobe.com/firefly-services/docs/photoshop/guides/fonts/) demonstrates asynchronous submission. Keep Photato-only extensions separate. New Adobe-covered functionality is incomplete until both its Photato API support and its compatible Adobe API path, documentation and conformance tests ship with it.

[The compatibility plan](ADOBE_API_COMPATIBILITY.json) records work packages and gaps. Step101 pins the authoritative [OpenAPI document](contracts/adobe-photoshop-v2.json) with [immutable provenance and endpoint inventory](contracts/adobe-photoshop-v2.provenance.json); all394 internal references resolve. Repository and service licenses are recorded separately. The contract uses jobId/statusUrl for submission and result/errorDetails for status. No live Adobe jobs or client interoperability are qualified. It has no dedicated desktop channel-view-state endpoint; its general actionJSON/ATN/UXP execution could express channel actions and is partially supported for the native RGB8 select/neutral Fill subset below. The view extensions below do not assert Adobe conformance.

## Native component editing and isolated action jobs (step106)

The Channels panel selects a real editing target; Command-2 selects RGB and Command-3/4/5 select Red/Green/Blue when the document canvas owns keyboard input. RGB8 Normal neutral Fill supports opacity and preserves other components and stored alpha. Geometric selections, shared Undo/Redo and layer metadata remain available. Other component tools, colored foreground conversion, RGB16/32 component writes and alpha/spot channels are still unimplemented; unsupported writers fail before a document/history mutation. Existing view-only API operations retain their meaning and never select an editing target.

Both job interfaces run the same native actionJSON/request/PSD/PNG/resource engine on isolated documents. They accept inline actionJSON resources selecting RGB/Red/Green/Blue and applying RGB8 Normal white/black/50%-gray Fill. RGB16/32 PSD input additionally supports composite RGB selection and PSD output preservation; individual-channel selection/writes still reject. PNG input remains RGB8; RGB32 PNG output rejects rather than converting depth. Composite RGB Fill, other actions, ATN/UXP/JavaScript execution, linked assets, fonts and generative actions are unsupported. Unknown options fail explicitly. Independent Photoshop comparisons cover five original single-layer RGB8 fixtures, not global byte equality, file identity or general imported active-layer semantics.

Start the API, then explicitly enable **Enable resource action jobs** in the native API window. This permits authenticated clients to fetch input URLs and upload results to requested destination URLs from this Mac. It does not grant access to unshared open documents or local filesystem paths. Disable the toggle to cancel/revoke jobs and hosted outputs. Stopping the service also revokes the token, document shares and jobs. Resource jobs are off after every start and launch; completed remote uploads cannot be rolled back by revocation.

Use the native window's loopback base URL and `Authorization: Bearer <session-token>` for both interfaces. Configure Adobe-oriented clients with this base URL and local token; Photato does not implement Adobe OAuth, subscriptions, client credentials or proprietary models. Resource URLs supply their own access (for example presigned URLs); the Photato token is never forwarded to a resource server. No Adobe credentials or external-service interoperability have been qualified.

| Method | Route | Result |
|---|---|---|
| POST | `/v1/action-jobs` | Photato isolated action job, using the typed action resource payload below; HTTP202 with jobId/statusUrl |
| GET | `/v1/action-jobs/{jobId}` | In-memory job status and results |
| GET | `/v1/action-assets/{assetId}` | Authenticated temporary PSD/PNG output |
| POST | `/v2/execute-actions` | Partial Adobe actionJSON adapter; HTTP202 with jobId/statusUrl |
| GET | `/v2/status/{jobId}` | Adobe-shaped not_started/running/succeeded/failed status; result.outputs or errorDetails |
| GET | `/v2/assets/{assetId}` | **Photato local extension**, not a published Adobe endpoint; authenticated temporary output |

POST bodies require Content-Type application/json and Content-Length. These two submission routes allow4MiB; existing document commands retain64KiB. A job accepts1–10 inline resources of at most51,200 Unicode scalars each and1–25 PNG/PSD outputs. Limits include16 retained jobs, one running job,64MiB input,4,194,304 canvas pixels,64 layers,128MiB decoded document and128MiB hosted storage. Hosted outputs require destination.validityPeriod60–86400 seconds; completed jobs expire after24hours. Jobs are in-memory and lost on restart. Dropbox, resource redirects and Creative Cloud resources are unsupported. External HTTPS PUT destinations may specify Azure BlockBlob storage; overwrite prevention depends on destination HTTP preconditions. No real storage-provider upload is qualified.

Example submission payload for either job interface:

```json
{
  "image": {"source": {"url": "https://your-storage.example/input.psd"}},
  "options": {"actions": [{"source": {
    "contentType": "application/json",
    "content": "[{\"_obj\":\"select\",\"_target\":[{\"_ref\":\"channel\",\"_enum\":\"channel\",\"_value\":\"red\"}]},{\"_obj\":\"fill\",\"using\":{\"_enum\":\"fillContents\",\"_value\":\"white\"},\"opacity\":{\"_unit\":\"percentUnit\",\"_value\":50}}]"
  }}]},
  "outputs": [{"mediaType": "image/vnd.adobe.photoshop", "destination": {"validityPeriod": 60}}]
}
```

Poll the returned statusUrl using the same token. When succeeded, fetch result.outputs[].destination.url with that token for a local hosted output. A failed job returns errorDetails and no partial hosted output; earlier external PUTs may already have completed. Adobe routes use error_code/message for immediate errors; Photato routes retain error. The [pinned contract](contracts/adobe-photoshop-v2.json), [compatibility gaps](ADOBE_API_COMPATIBILITY.json) and [integration evidence](COMPONENT_EDITING_INTEGRATION_REFERENCES.json) distinguish the tested subset from complete conformance.

## Start and connect

1. Open **Help → Photato Automation API…** and click **Start API**.
2. Select an open Photato document and click **Share Current Document**. Sharing grants reading and editing access to clients holding this session's token.
3. Click **Copy Session Token**, then **Open Browser Client**. Paste into the browser's password field and click **Connect**.
4. Edit layer names, opacity, visibility, position or pixel fill; create layers and use shared Undo/Redo. The preview is rendered by Photato. Use **Refresh from Photato** after desktop changes.
5. Click **Revoke** for a document, or **Stop API** for the whole session. Closing the control window keeps the API running. Quitting Photato stops it. Every app launch starts with the API off.

The endpoint is an ephemeral `http://127.0.0.1:<port>` address shown in the native control window. No fixed port, DNS, account or external server is required. The browser demonstration is served at `/`. The token has 256 random bits, rotates on each start and is neither placed in a URL nor persisted by the client. Copying it puts it on the macOS clipboard; treat that clipboard content as a password. All authenticated clients have the same access to the session's shared documents. Previously received data cannot be recalled by revoking access.

## HTTP contract

All `/v1/` requests require `Authorization: Bearer <session-token>`. POST requests also require `Content-Type: application/json` and `Content-Length`. Use ordinary HTTP clients that supply the length automatically. The exact `Host` must match the numeric loopback endpoint. Browser requests must come from that same origin; there is no permissive CORS response, cookie authentication, remote listener or token query parameter.

| Method | Route | Result |
|---|---|---|
| GET | `/v1/capabilities` | API version, seventeen executable commands, per-command JSON Schema, channel-view state schema, limits and the separate complete native menu inventory |
| GET | `/v1/documents` | State for explicitly shared open documents |
| GET | `/v1/documents/{id}` | Current document state and opaque revision |
| GET | `/v1/documents/{id}/preview.png` | Flattened native display PNG of the committed document; excludes desktop drafts, selection outlines and channel/mask viewing overlays |
| GET | `/v1/documents/{id}/channel-preview.png` | Committed native composite with current channel visibility; excludes drafts, selection outlines and mask overlays |
| POST | `/v1/documents/{id}/commands` | Execute one command and return updated document state |

Document state includes a session-specific share ID, display name, canvas size, depth, revision, active layer ID, layer IDs/names/opacity/visibility/positions and Undo/Redo availability, plus `channelTarget` (RGB/Red/Green/Blue) and `channelView` with `preview`, ordered `visible` components and `componentEditing` indicating an individual edit target. Preview remains independent of target selection. No filesystem path is returned. Share IDs become invalid after revocation, close, reload or server restart. Layer IDs identify the actual native document layers.

The command request is:

```json
{
  "command": "layer.opacity",
  "revision": "copy the exact revision from the latest document state",
  "parameters": {
    "layerID": "copy the target layer UUID from that state",
    "opacity": 0.75
  }
}
```

The revision is opaque and must not be synthesized or incremented by a client. Desktop edits and API edits use one history. Two changing commands with the same revision cannot both commit. A successful no-op can leave revision and history unchanged. Display updates can conservatively invalidate a revision even if pixels are unchanged. Undo/Redo validate the destination history document against API resource limits before restoring it.

A revision conflict requires refreshing and reviewing the current state, not blindly replaying the old edit. Network disconnection after sending a mutation can leave its outcome unknown; refresh before deciding whether to retry. v1 has no idempotency keys or atomic multi-command batches.

## Executable commands

All listed parameters are required; extra fields are rejected. Names are nonempty, at most 256 Swift characters, and cannot contain control characters. Numeric values must be finite. Selection coordinates are constrained further by the current document size. Capability schemas describe static constraints; document-dependent limits and native edit validation still apply.

| Command | Parameters | Native behavior |
|---|---|---|
| `view.channelPreview` | `channel` (RGB, Red, Green or Blue; exact case) | Select a display preview; exits mask viewing/editing without changing pixels or history |
| `view.channelVisibility` | `channel`, `visible` (boolean) | Change visible components without changing the selected preview; hiding the last component or composite is a no-op |
| `layer.rename` | `layerID`, `name` | Rename the target layer |
| `layer.opacity` | `layerID`, `opacity` (0–1) | Set layer opacity |
| `layer.visibility` | `layerID`, `visible` (boolean) | Set visibility |
| `layer.move` | `layerID`, integer `x`, `y` (±1,000,000) | Absolute position in document pixels, including native group movement semantics |
| `layer.new` | `name` | Transparent pixel layer above the native active layer |
| `layer.fill` | `layerID`, `r`, `g`, `b`, `a` (0–1) | Native pixel-layer RGBA fill, honoring the document selection; masks are not targets |
| `selection.rectangle` | integer `x`, `y`, `width`, `height` | Replace selection with a rectangle contained in the canvas |
| `selection.clear` | none | Deselect |
| `document.revert` | none | Restore the associated saved file as one undoable edit; requires native transfer permission |
| `document.save` | none | Save the associated format/file; requires separate native local-save permission |
| `document.saveAs` | `name`, `format`, `replace` | Save inside the native-selected folder and adopt that file; requires local-save permission |
| `history.undo` | none | Undo the latest document edit from either client |
| `history.redo` | none | Redo the latest undone document edit |

Fill values use the native engine's pixel representation. The browser color picker is a demonstration, not a qualified color-managed web editing workflow. Native layer/group locks apply. API errors do not open desktop alerts. Commands are rejected while desktop numeric/text naming edits, geometry/adjustment dialogs, AI interactions, modal sheets, coalesced edits or pointer interactions in the active shared document window could conflict. Mouse buttons held in another application or unrelated document do not by themselves block automation; document gesture/draft guards still apply after focus changes.

The menu inventory reports paths, node kinds and base key characters; complete modifier bindings remain in the native shortcut reference and are not a web shortcut implementation.

The browser demonstrates eight commands directly. Rectangular selection, deselection and both channel-view operations are available to API clients; their browser controls are future additions. Menu inventory entries are reference/discovery data, including unavailable commands and submenus. Their presence does **not** make them callable. Only `commands` in the capability response identifies executable API commands.

## Error handling and limits

Errors return JSON with an `error` string. Common status codes: 400 malformed request/parameters; 401 missing or expired token; 403 Host/Origin rejected; 404 unshared document/layer/route; 409 stale revision or desktop interaction conflict; 411 missing length; 413 resource limit; 415 unsupported body type; 422 unsupported command or native validation failure; 429 preview/share limit; 503 stopped/cancelled session. Connections over the concurrency limit are closed before request handling.

v1 limits: 16 KiB headers, 64 KiB JSON body, eight connections, 15-second connection lifetime, eight shared documents, one concurrent PNG render, 4,194,304 canvas pixels, 64 layers and 128 MiB estimated document data. Adding a layer uses a conservative worst-case allocation check. HTTP/1.1 only, one request per connection, no chunked bodies or pipelining. Preview generation rechecks the document revision and share/session lifetime before returning data. Core rendering cancellation is bounded by completion of the current native render stage, not guaranteed instantaneous.

## Feature completion requirement

Every new or expanded capability must be reflected in the optional API in the same implementation increment. API coverage is part of feature completion, not deferred follow-up work. Add or update the typed operations, observable state/capabilities, parameter and result schemas, availability/error behavior, usage documentation and relevant API tests. Use the same native Swift implementation and transaction/history path as the desktop, with matching results, validation, undo/redo and document-state effects where applicable. Test desktop/API equivalence and invalid/busy/stale-request behavior as relevant to the feature. For presentation-only changes, explicitly record their API impact and update exposed state or metadata where applicable; do not silently omit the API review. Keep executable capabilities distinct from the reference menu inventory. Existing API coverage gaps remain tracked separately and must not be represented as already implemented.

Channel view state is per open document and is not saved into document archives or history. Selecting RGB restores all components. Selecting a component from RGB, or selecting a hidden component, isolates it; selecting an already-visible component from a component preview preserves the custom visible combination. A single visible component appears grayscale; multiple components keep their colors. Eye visibility never changes the selected preview. `stateSchemas.channelView` in capabilities describes the result object. Mask viewing/editing returns422 for visibility changes; selecting a preview exits it. Ordinary busy/stale requests still return409. Changes invalidate revisions; a no-op does not. Neither operation enables channel-targeted painting. The existing `preview.png` always returns the committed full composite; use `channel-preview.png` to reproduce this view state.

For example, send `view.channelPreview` with `{ "channel": "Red" }`, then use the returned revision to send `view.channelVisibility` with `{ "channel": "Green", "visible": true }`. The resulting state has `preview: "Red"` and `visible: ["Red", "Green"]`; the channel-preview PNG matches the native canvas in the qualified fixture. Authentication and shared-document requirements apply to both PNG routes.

## Next stages

Use the pinned Adobe v2 contract to implement the native adapter, then expand the compatible command coverage alongside tested native features, then add selection/brush gestures, thumbnails and delta updates, asynchronous jobs, explicit import/export permissions, streaming preview updates, client SDKs, action recording and richer machine-readable schemas. A complete web workspace also needs the desktop's panels, tools, keyboard behavior, color management, large-document rendering and accessibility.

LAN/internet hosting is a separate product increment: TLS, user identity, per-client/document permissions, pairing/revocation UI, quotas, deployment and threat testing. This preview must not be exposed by a reverse proxy or tunnel. App Store sandbox distribution will also need the incoming-network entitlement and sandboxed network tests. No server entitlement or public hosting was enabled in this increment. The optional API does not complete Photoshop scripting/UXP compatibility or the Photoshop-parity backlog.

See [current status](STATUS.md), [step091 development record](DEVLOG.md#dev-step-091), and [API qualification evidence](AUTOMATION_API_REFERENCES.json).

Component editing integration (step106): the earlier step102 core foundation is now exposed through native channel targeting/Fill, the Photato channel.target and channel.fill commands, and both isolated job interfaces described above. That step’s executable document registry contained fourteen operations; step110 adds document.revert, and step113 adds document.save/document.saveAs. Existing view.channelPreview and view.channelVisibility operations still affect display only. See [integration evidence](COMPONENT_EDITING_INTEGRATION_REFERENCES.json) for measured scope and remaining gaps.

## Component document commands

`channel.target` requires `{ "channel": "Red" }` (or RGB/Green/Blue). It updates document-local target and preview state without adding document history. A target change invalidates the revision even if its preview already matches. `channel.fill` requires `{ "value": 1, "opacity": 0.5 }`; both numbers must be finite in0–1. It fills the active RGB8 pixel layer's selected component using the shared native transaction. Select an individual target first. Invalid parameters return400; busy or stale requests409; unsupported target/depth/locked/writer contexts422. Undo/Redo uses the existing shared history commands. These operations add to the original twelve document commands; they do not reinterpret layer.fill or the two view-only commands.
