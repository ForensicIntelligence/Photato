# Source checkpoint 810

The filmstrip and Grid can show a thumbnail from the developed preview. Selecting a DNG with no usable embedded thumbnail fills both views after preview rendering. Thumbnails for the active draft update after an adjustment.

A synthetic DNG whose red label was written in Adobe Camera Raw previously displayed a placeholder. The native Photato window now showed the image in both the filmstrip and Grid. Cancel left the original bytes intact.

Camera Raw’s thumbnail browsing workflow is documented by Adobe. [Adobe Camera Raw Grid](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/navigate-open-save-images-camera.html).

The thumbnail is a desktop preview. The existing RAW development API continues to use the same editing and rendering path.

Xcode built the app and all twenty-one focused application tests passed. The new case checks bounded preview size, pixel change after an exposure edit, fallback after Undo and an exact source file. Both optimized architectures passed all 398 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The current photo’s render refreshes its thumbnail. Other photos use their embedded thumbnail until viewed or edited as the active photo. Automatic refresh of every non-active photo in a batch remains open.

The Universal ZIP targets macOS 14 and later. It contains 79,631,948 bytes with SHA-256 `b4d3c9ab273d5812a1cef2a1abb848728c8a1c651736bbb066220e1274ce3261`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_810.json) · [Development record](DEVLOG.md#dev-step-810).
