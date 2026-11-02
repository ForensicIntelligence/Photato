# Source Displace maps and rebinding

**Checkpoint322, Source05:** All13 new Core/Imaging/App workflow cases pass. All43 cached, unresolved and bound references match206,028 original words per set exactly. The affected run passes315/322 cases; seven prior strict cases retain220 assertions, zero unexpected errors/crashes. Source05 changes one test opt-in; production and binary are identical to Source04. No complete inventory or live visual acceptance is claimed. See `WORKING_CHECKPOINT_322.json` and the retained attempts.

Photato distinguishes its existing 8-bit Displace maps from original PhotoCraft filter programs. Existing native maps retain their byte samples, neutral128, whole-number scales and native39/Actions11 contracts. Original programs retain Float32 scales and inert file/session hints, and can bind one or two Float32 map channels without 8-bit quantization.

The original Smart Filter record stores parameters rather than the resolved map. Its renderer leaves an unresolved Displace stage unchanged. Photato preserves that behavior and any separately saved original appearance. A warning in the Smart Filter row and editor identifies missing maps. Changing an active unresolved stack that would discard that appearance requires explicit binding; unchanged requests remain no-ops. Destructive native application always requires a map.

Open the imported Displace Smart Filter and choose a map file. The explicit selection supplies its decoded numerical channels; original path/document/layer hints remain recorded and are never opened automatically. The editor displays missing/bound status, map name, dimensions and channel precision. Map replacement participates in local Undo/Redo; Cancel leaves the document unchanged, and OK commits through normal document history. Native73 preserves source contexts and transparent edges, including retained animation/video filter payloads. Actions28 preserves the corresponding operations. Earlier native/Actions versions remain the required versions for earlier features.

The existing Photato `filter.apply` and `smartFilter.set` commands use the same settings, validation, renderer and history. A filter payload can supply this Float32 context:

```json
{
  "kind": "displace",
  "distortion": {
    "horizontalScale": 12.75,
    "verticalScale": -8.125,
    "fit": "stretchToFit",
    "edge": "repeatEdge",
    "source": {
      "reference": { "path": "Original map.psd" },
      "map": {
        "width": 1,
        "height": 1,
        "channels": 2,
        "samples": "AAAAPwAAAD8=",
        "name": "Neutral float map"
      }
    }
  }
}
```

`map.samples` contains little-endian finite Float32 values, row-major, first horizontal/red then vertical/green; one channel supplies both. Alpha is excluded. Neutral0.5 gives no displacement. Values outside0…1 are retained. The legacy `distortion.map` and new `distortion.source` are mutually exclusive. Source reference fields are `path`, `documentName` or `documentIndex`, and optional `layerID`; these are original hints, not native document UUIDs or access permissions.

Native downloads retaining these settings require `X-Photato-Archive-Version: 73`. Capability discovery advertises the feature, versions and schema through the existing APIs. Adobe actionJSON/PSD distortion descriptors remain explicitly unqualified; no new Adobe route or proprietary descriptor is invented. Photato resource jobs can process supported native documents carrying bound settings, while Adobe input-format restrictions remain in force.

Map preparation retains a1,048,576-pixel limit, one/two channels and an8MiB numerical payload limit. Source rendering retains its existing8,388,608-source-pixel preparation limit. Unsupported document contexts and extreme/nonfinite numeric results reject atomically. These are processing limits, not large-document parity claims. Complete source contexts, independent Photoshop output/UI/menu behavior, full capacity, universal/Intel/macOS14+ runtime, physical60fps and native visual acceptance remain open.

The owned reference generator uses unchanged MIT OR Apache-2.0 Rust only to produce procedural test files. Its43 vectors separately record original unresolved Smart output, explicitly bound kernel output and cached appearance across8/16/32 bits. The production implementation remains native Swift. Strict word differences, if any, remain failures rather than adjusted tolerances.
