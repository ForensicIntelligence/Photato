# Source checkpoint 666

Native Swift 0.3.0, build 666, 20 November 2026.

PSD and PSB preserve the image preview, location and four-corner placement of a linked Smart Object when its original is missing. Free Transform uses the saved artwork frame. Relinking restores source-based perspective editing.

1,511 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional RGB32 test passed on Apple Silicon and reproduced the prior Intel result. Both slices of the signed macOS 14+ universal preview launched offscreen.

Four new tests covered the native Free Transform and Relink workflows, shared instances, masks, Smart Filters, Undo, exact saved corner words and the Photato and Adobe-compatible API views. An independent reader checked eight PSD and PSB outputs and verified that each external-link record omits original image bytes.

Photoshop's live document query timed out. The file and pixel comparisons use Photato and owned fixtures. Live Photoshop interchange, linked PDF perspective and non-identity Warp descriptors remain open.

[Development record](LINKED_PROJECTIVE_SMART_OBJECTS_666.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_666.json)
