# Source checkpoint 712

Native Swift 0.3.0, build 712, 2026-11-21.

Edit → Generate Image and the canvas controls now generate artwork from a text prompt on eligible Macs. The optional local Core ML model creates one to three alternatives in a single editable Smart Object and preserves the original layers and selection. Properties switches variations and can generate more from the prompt or generate similar results from a saved variation. The Photato API shares the same prepared edit and history. The existing Apple Intelligence route remains available.

The real local model produced identical same-seed rendered pixels through the native editor and authenticated HTTP API. Edited test documents retained their variations in Photato, PSD and PSB at RGB8, RGB16 and RGB32. A 768 × 512 locally generated still life retained both variants and identical rendered bytes across all three formats. An independent reader matched all 3,145,728 merged RGBA bytes in the PSD and PSB previews to the PNG. A 300,000 × 8 PSB reopened with exact edge samples, editable placement and the original square model resolution.

533 of 534 selected regression cases passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The known layer-effect reference test repeated 118 existing assertions in every configuration. Three new format and editing cases passed in all configurations. The additional on-device model test passed in Apple Silicon Debug. The Xcode target built and both signed local preview slices opened offscreen. A signed sandbox harness reproduced both model variants and the selected composite PNG byte for byte. The Generate Image menu binding and Properties controls were checked in an offscreen native workspace.

The on-device model generates at 512 × 512 and offers a centered canvas crop. Adobe’s model picker and hosted Firefly output have separate engines and remain unqualified. The installed Photoshop 27.2.0 document query timed out. Direct Photoshop reopening, live keyboard and assistive technology checks, and Adobe-compatible Generate Image action coverage remain open.

[Adobe Generate Image workflow](https://helpx.adobe.com/photoshop/desktop/create-open-import-images/create-images/generate-image-with-descriptive-text-prompts.html) · [Photoshop API model inventory](https://developer.adobe.com/firefly-services/docs/photoshop/guides/photoshop-v2/v1-to-v2/guides-v2/execute-actions-models) · [Firefly Image5 contract](https://developer.adobe.com/firefly-services/docs/firefly-api/guides/how-tos/cm-generate-image/feature-guide)

[Generate Image guide](GENERATE_IMAGE.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_712.json)
