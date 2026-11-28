# Camera Raw settings references

Photoshop 2026 27.2 with Camera Raw 18.1.1 wrote these XMP files using Save Settings on owned synthetic images. The files contain adjustment settings from the Adobe application and no image data.

- `camera-raw-source-settings.xmp` comes from `synthetic-bayer.dng`. The source used As Shot white balance, Exposure +0.75, Contrast +21, Highlights −17 and Vibrance +9.
- `camera-raw-filter-settings.xmp` comes from a generated RGB16 PSD. The filter used Exposure −0.35, Temperature +31, Tint −24 and Vibrance +12. The temperature and tint are rendered-image offsets.

[Adobe Camera Raw settings](https://helpx.adobe.com/in/camera-raw/desktop/get-started/overview-and-setup/camera-raw-settings.html) · [Adobe XMP settings namespace](https://github.com/adobe/xmp-docs/blob/master/XMPNamespaces/crs.md).

`raw-with-embedded-xmp.dng` is the same owned Bayer source with the Adobe source settings packet appended as TIFF tag 700. The sensor strips and their offsets are untouched. Photoshop Camera Raw opened it at Exposure +0.75, Contrast +21, Highlights −17 and Vibrance +9. Beside `camera-raw-sidecar-override.xmp` under the same stem, Photoshop used Exposure +1.25 and cleared the three embedded values. That partial packet exercises complete precedence of a valid sidecar over the embedded settings.
