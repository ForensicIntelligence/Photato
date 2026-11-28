# Source checkpoint 812

Use the Photo menu or a thumbnail’s contextual menu to hide photos, isolate a selection, or reveal hidden photos. The filmstrip and Grid share visibility. A new Camera Raw session starts with every photo visible.

In the native app, Show Only This Photo isolated one of three test DNGs in both views. Hide Photo emptied Grid, and its empty-state button restored all three. Cancel preserved the source bytes.

Commands follow Adobe’s documented session visibility workflow. [Hide photos in Camera Raw](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/hide-photos-during-a-camera-raw-session.html).

Visibility is presentation state in the native Camera Raw session. The authenticated RAW inspection and adjustment commands retain their document scope.

Xcode built the app and all twenty-four focused application tests passed, including returning hidden photos with their filters and saving edits to a hidden DNG. Both optimized architectures passed all 401 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The current installed Adobe Camera Raw predates these commands. Native controls were tested on owned files, with the Adobe documentation as the reference. Stacks and automatic grouping remain open.

The Universal ZIP targets macOS 14 and later. It contains 79,644,630 bytes with SHA-256 `d9af7b95a02e00cb0cc6def29853240dc99c45c6b2a74d618270eee47bdb0ba7`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_812.json) · [Development record](DEVLOG.md#dev-step-812).
