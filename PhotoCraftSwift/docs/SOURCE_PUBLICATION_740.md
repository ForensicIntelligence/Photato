# Source checkpoint 740

Photato now opens both editable planes in an owned PSD saved after Photoshop's Angle control was set to 90°. Build 739 lost the plane family on that file. The new reader recovers the off-centre camera from the three saved vanishing directions and uses it for measurements, scene export and linked selections. The authenticated Photato API replays the same resolved geometry.

The captured edited guide reopens at a focal length of 1,189.243 pixels with the principal point near x198.120, y451.552. Photato's scene export measured a right-to-left surface width ratio of 3.0177489. Photoshop's VPE measured 3.0177395. Native PSD and PSB round trips preserve all 378 bytes of the perspective record and all 3,240,000 merged RGB bytes. Both formats reopened with the same editable geometry.

All 26 Core tests and 14 App and HTTP tests passed in Xcode Debug. Each optimized architecture passed 855 of 857 selected tests, including both additions. The inherited color-profile and layer-effect tests repeated build 739's diagnostics. The fixture PSD, PSB, 3DS, VPE and two textures each match byte for byte in Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both locally signed preview slices opened offscreen on macOS 27.2.1 and target macOS 14. Newly authored PSD angle interchange, exact Marquee donor sampling and other fold angles remain open.

Build inputs **9,429**. Source digest `3b8bbc2f17b94900cef7bc0f126728206140c6959bac25f0f973bbba1a32e6ba`. Local preview SHA-256 `9696d7b4d2716f62fdc3630b4d4bdc6ea6b0e6cb5a28db38f2573c80ba1497fd`.

[Development record](DEVLOG.md#dev-step-740) · [Evidence hashes](SOURCE_PUBLICATION_740.json) · [Photoshop reference observations](VANISHING_POINT_REFERENCES.json).
