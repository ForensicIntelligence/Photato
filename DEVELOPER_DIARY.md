# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **815** · The 10 most recent entries, newest first.

## 2026-11-28 — Step 815 — Apply editable HDR automatic tone and color

Apply Auto Settings in Camera Raw HDR Merge now writes Exposure, Contrast, Highlights, Shadows, Whites, Blacks, Vibrance and Saturation into the output DNG as editable Camera Raw settings. The dialog preview uses the same settings.

Across six owned scenes, mean Exposure error against Adobe fell from 0.73 to 0.26 stops. The other seven sliders averaged 10.5 points from Adobe, down from 31.5. The DNG sensor payload was byte-identical with Auto on and off in all six Photato scenes. Adobe also retained its compressed sensor payload with Auto on and off in the textured scene.

Adobe Camera Raw 18.1.1 wrote recipes for six owned 512 × 384 DNG brackets, including a terrace scene withheld while designing the adjustments. The independently read XMP and encoded sensor hashes are linked below. [Adobe Camera Raw HDR shortcuts](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/default-keyboard-shortcuts.html).

Xcode built the app and all 47 focused application and imaging checks passed, including four added checks. Both optimized architectures passed all 422 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

On the withheld terrace scene, the seven slider values improved on average, and Exposure diverged by 0.77 stops where the previous Exposure was 0.06 stops off. These results measure XMP settings and sensor payload preservation. Adobe-rendered pixels, real-world scenes, larger brackets and deghosting remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-815) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_815.md).

## 2026-11-28 — Step 814 — Fuse scene-linear HDR exposure brackets

Camera Raw merges linear sensor samples using shutter time, aperture and ISO. The middle exposure supplies the reference frame and white balance. Reliable samples recover highlight detail while the deghost mask can restore the reference where subjects move.

On one stationary synthetic bracket, the mean decoded RGB difference from Adobe fell from 0.08634 to 0.04297. On a textured bracket with known translations and motion, it fell from 0.08420 to 0.06289, and the merge corrected both known translations. A separate test confirmed that alignment keeps the stationary bracket stationary.

Adobe Camera Raw 18.1.1 produced the two reference DNGs from owned synthetic input. Decode comparison used the same Apple 8.dng decoder for both outputs. [Adobe Camera Raw HDR shortcuts](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/default-keyboard-shortcuts.html).

Xcode and 43 focused application and imaging tests passed, including the existing HDR Pro cases and three new radiance, alignment and deghost cases. Both optimized architectures passed all 418 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The tested Adobe files and decoded pixels still differ. The shifted fixture tests translation rather than perspective changes. Adobe deghost masks, the full Auto Settings recipe and higher-capacity HDR merges remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-814) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_814.md).

## 2026-11-28 — Step 813 — Merge Camera Raw exposures into editable HDR DNGs

Select two or more RAW brackets and use Merge to HDR. The preview supports alignment, automatic exposure, three deghost strengths and an overlay. The result returns to the filmstrip as an editable DNG.

Option–M opened the preview on three owned brackets, and Option–Shift–M opened the destination picker. The regular merge added a fourth photo and preserved all source bytes. Adobe Camera Raw rendered a Photato-generated linear DNG and allowed exposure edits. Native and authenticated API DNG downloads matched byte for byte with identical inputs and settings.

Adobe Camera Raw 18.1.1 confirmed Align Images and Apply Auto Settings as initial defaults, with Deghost Off. [Adobe Camera Raw shortcuts](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/default-keyboard-shortcuts.html).

Xcode and forty focused application and imaging tests passed, including the ten existing HDR merge workflow cases. Both optimized architectures passed all 415 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The merge kernel reuses Photato’s photographic HDR engine. Automatic settings currently embed a single calculated exposure adjustment. Adobe’s result used JPEG XL and multiple tone adjustments. The tested decoded RGB samples and complete file bytes differ from Adobe’s result. RAW-specific fusion, larger brackets and exact render parity remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-813) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_813.md).

## 2026-11-28 — Step 812 — Hide and reveal photos in Camera Raw sessions

Use the Photo menu or a thumbnail’s contextual menu to hide photos, isolate a selection, or reveal hidden photos. The filmstrip and Grid share visibility. A new Camera Raw session starts with every photo visible.

In the native app, Show Only This Photo isolated one of three test DNGs in both views. Hide Photo emptied Grid, and its empty-state button restored all three. Cancel preserved the source bytes.

Commands follow Adobe’s documented session visibility workflow. [Hide photos in Camera Raw](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/hide-photos-during-a-camera-raw-session.html).

Xcode built the app and all twenty-four focused application tests passed, including returning hidden photos with their filters and saving edits to a hidden DNG. Both optimized architectures passed all 401 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The current installed Adobe Camera Raw predates these commands. Native controls were tested on owned files, with the Adobe documentation as the reference. Stacks and automatic grouping remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-812) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_812.md).

## 2026-11-28 — Step 811 — Save deselected Camera Raw edits when closing with Done

Done saves the changed photos across the Camera Raw session, including photos currently deselected or filtered out. Photato leaves files with unchanged settings and marks untouched.

Adobe Camera Raw 18.1.1 wrote a four-star rating and a red label to an owned DNG after a different photo was selected. The selected, unedited original was byte-identical. A Photato test reproduced those XMP values when a filter left no visible selection and verified the original sensor payload and unedited file bytes.

The live Adobe comparison tested Done and inspected both file hashes and XMP fields after closing the dialog. [Adobe Camera Raw save workflow](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/navigate-open-save-images-camera.html).

Xcode built the app and all twenty-two focused application tests passed. Both optimized architectures passed all 399 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

Open Image and Open as Object have their existing selected-photo behavior. Adobe’s persistence rules for deselected photos when opening images, and the dedicated Hide Photo controls, still need separate qualification.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-811) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_811.md).

## 2026-11-28 — Step 810 — Refresh Camera Raw thumbnails from developed photos

The filmstrip and Grid can show a thumbnail from the developed preview. Selecting a DNG with no usable embedded thumbnail fills both views after preview rendering. Thumbnails for the active draft update after an adjustment.

A synthetic DNG whose red label was written in Adobe Camera Raw previously displayed a placeholder. The native Photato window now showed the image in both the filmstrip and Grid. Cancel left the original bytes intact.

Camera Raw’s thumbnail browsing workflow is documented by Adobe. [Adobe Camera Raw Grid](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/navigate-open-save-images-camera.html).

Xcode built the app and all twenty-one focused application tests passed. The new case checks bounded preview size, pixel change after an exposure edit, fallback after Undo and an exact source file. Both optimized architectures passed all 398 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The current photo’s render refreshes its thumbnail. Other photos use their embedded thumbnail until viewed or edited as the active photo. Automatic refresh of every non-active photo in a batch remains open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-810) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_810.md).

## 2026-11-28 — Step 809 — Browse and edit photos in Camera Raw Grid

Press G to switch the Camera Raw preview to Grid. Double-click a thumbnail to return to Loupe. Both views share selection, ratings, labels, filters and sorting. Grid keeps the adjustments and source information available.

In the native macOS window, three owned DNGs populated Grid. Option–Plus increased the thumbnail size and period hid cell information. Shift-click selected two photos. A 0.75 sensor exposure edit was still present on the second photo after opening it in Loupe.

Grid behavior follows the published Adobe Camera Raw browsing workflow. [Adobe Camera Raw Grid](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/navigate-open-save-images-camera.html).

Xcode built the app and all twenty focused application tests passed. Both optimized architectures passed all 397 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The live comparison covered Photato’s camera-raw window and the documented Adobe workflow. Developed thumbnails, Stacks, virtual copies, and a live comparison against a Grid-capable Adobe build remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-809) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_809.md).

## 2026-11-28 — Step 808 — Inspect and sort Camera Raw photo metadata

Camera Raw can show a photo’s filename, format, size, camera, lens, capture time, caption and copyright. Sort by capture date, file type, camera or lens without changing the selected photos.

The native workspace sorted two owned DNGs by their actual capture instants across different time zones. Their displayed wall times run in the opposite order. Both originals remained byte-identical after inspection and sorting.

The field list follows Adobe’s Photo Info documentation. [Adobe Camera Raw overview](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/introduction-camera-raw.html).

Xcode built the app. All eighteen focused application tests passed. Both optimized architectures passed all 395 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The tests used owned DNGs and the authenticated HTTP endpoint. Photo Info’s layout and sorting were not compared against Adobe’s newer full Grid workspace. Grid, Stacks and Adobe renderer comparisons remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-808) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_808.md).

## 2026-11-28 — Step 807 — Rate and filter Camera Raw photos

The Camera Raw filmstrip can rate, label, sort and filter its photos. Number keys assign stars and color labels. A rating or label can use the existing XMP sidecar or an embedded DNG packet. Rating-only saves preserve Camera Raw adjustments.

Adobe Camera Raw 18.1.1 stored four stars and Red on both selected DNGs. Photato’s native window displayed those marks and filtered out the unmarked photo. A separate embedded DNG round trip wrote the same XMP values and preserved the sensor payload and every developed Photato sample.

The tested XMP values agree with the live Adobe reference. [Adobe Camera Raw keyboard shortcuts](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/default-keyboard-shortcuts.html).

Xcode built the app. All sixteen focused application tests passed. The new cases cover filtering, Undo and Redo, clearing an inherited label, retaining unrelated metadata, and the authenticated source-settings save. Both optimized architectures passed all 393 selected cases. Intel ran under Rosetta. Both signed Universal slices rendered offscreen.

The native test checked reopening and filtering. The embedded save was verified separately through the native RAW engine. Grid, Stacks and the full Adobe renderer and export-byte comparison remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-807) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_807.md).

## 2026-11-28 — Step 806 — Save multiple developed Camera Raw images

Save Images exports selected photos from the Camera Raw filmstrip to TIFF, JPEG, PNG or PSD. It uses each photo’s saved draft, the current Camera Raw output and the native encoding settings.

Command-S opened the native Save Developed Images chooser. The selected owned RAWs produced two 512 × 384 RGB16 TIFFs. The existing TIFF kept its bytes and the new file received a numbered name. The two original DNGs kept their hashes.

The format bytes were compared with separately encoded Photato files. [Adobe Camera Raw processing and export workflow](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/navigate-open-save-images-camera.html).

Xcode built the app. Thirteen focused application checks passed. The new cases verify collision-safe desktop output and byte-for-byte TIFF comparisons between the authenticated download and separately encoded outputs. Both optimized architectures passed all 390 selected cases. Intel ran under Rosetta. Both signed Universal slices rendered offscreen.

RAW filmstrip ratings, Grid, Stacks and Adobe output comparisons remain open. The authenticated ZIP uses the advertised transfer budget. Desktop export stages each file on disk.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-806) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_806.md).
