# Channels footer Save and Load

**Save selection as channel** now saves directly to a new automatically named alpha channel. It keeps the current selection, image pixels, edit target and channel eyes. A successful save adds one Undo. **Option-click Save** opens the existing Save Selection dialog for names, destinations and combination options. The Select-menu dialogs remain available. At the new-alpha limit, ordinary Save reports capacity; it never silently replaces an existing channel. Option Save still permits supported existing-channel/new-document choices.

**Load selected channel as selection** now loads the selected source directly, rather than opening a dialog or taking the first available channel. Supported sources are the selected saved alpha/spot, Quick Mask, single component, composite, pixel mask, Smart Filter mask or single ink target. The source data, current edit target and eyes are retained. Partial multi-component/multi-ink sets with no qualified combination remain unavailable. Modified Load gestures and channel-to-footer drops remain open.

The new Smart Filter mask source reads the stored numeric mask with its document transform and outside value. It reuses the existing projected layer-mask sampler. Display density, feathering and enabled state do not alter that raw numeric source. Independent owned mask arrays check placement and coverage at every supported depth; a small projected mask on the300,000×300,000sparse canvas retains bounded storage. Exact Photoshop source/gesture fidelity remains unqualified.

The optional API keeps the existing `channel.edit` command. Quick save uses:

```json
{"command":"channel.edit","revision":"<current>","parameters":{"action":"saveSelection"}}
```

Direct load uses the advertised source descriptor. For a Smart Filter mask:

```json
{"command":"channel.edit","revision":"<current>","parameters":{"action":"loadSelection","source":{"kind":"smartFilterMask","id":"<owner layer UUID>"}}}
```

Source fields are strict; owner IDs must identify an existing mask. Existing explicit save names/targets, source-document/revision leases and supported load mode/invert options remain available. Native/API operations use the same prepared channel commands. New-channel UUIDs are independent per request; material equality is tested after normalizing only that new UUID. `selectionChannels.footer` exposes `canQuickSave`, `canSaveOptions`, `canLoad` and `loadSource`; `channels.nativeFooter` documents gestures and command mappings. Source lists and schemas include smartFilterMask. Typed250/native archive86/Actions49/settings4/menu identities and shortcuts are unchanged. No unsupported Adobe endpoint/action descriptor is invented.

Checkpoint433 passes58focused Debug tests, including eight new methods. Tests cover known raw mask values/transforms/source retention, maximum sparse coverage and all-depth quick-save/archive/Undo, all16Save modifier policies, options Cancel/capacity, selected-source/target/eye preservation, native/API material equality, strict schema/state/stale/busy and cancellation/session/revocation guards. Source01's new-fixture access-control failure was preserved before a test-only public-API repair; both app binaries are identical. No old fixture or tolerance changed. No live screenshot or physical UI check is claimed. The current build has not received optimized universal/full-suite/Photoshop qualification;432remains the latest optimized/private-source batch.

Full C01 remains open. Layer-mask Save Selection destinations, missing thumbnail/drop workflows, partial multi-target combinations, other paint/filter targets, exact defaults/output/modifiers and full supported-platform/performance checks remain functional or acceptance work. [Evidence](CHANNEL_FOOTER_433.json).
