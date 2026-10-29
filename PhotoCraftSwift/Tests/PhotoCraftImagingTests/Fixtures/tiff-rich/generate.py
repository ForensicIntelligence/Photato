"""Owned numeric fixtures, independent of Photato. No Adobe output claim.

Adobe PSD field layouts plus TIFF structural byte order; psdtags frames and
independently reads containers/channels/LMsk, not the opaque adjustment records.
See provenance.json for pinned dependencies and reference limitations.
"""
import hashlib, importlib.util, json, pathlib, struct, sys
import numpy as np
import tifffile

out = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else pathlib.Path(__file__).resolve().parent
out.mkdir(parents=True, exist_ok=True)
spec = importlib.util.spec_from_file_location("psdtags", sys.argv[1])
p = importlib.util.module_from_spec(spec)
sys.modules["psdtags"] = p
spec.loader.exec_module(p)

def records(order):
    def n(value, size=2):
        return (value % (1 << (size * 8))).to_bytes(size, order)
    def nums(values, size=2):
        return b"".join(n(v, size) for v in values)
    def code(value):
        return value.encode("ascii")[::1 if order == "big" else -1]
    def text(value):
        raw = (value + "\0").encode("utf-16-be" if order == "big" else "utf-16-le")
        return n(len(raw) // 2, 4) + raw
    identity = [0, 255, 0, 255, 100]
    levl = n(2) + nums([17, 231, 9, 244, 125]) + nums(identity * 28)
    curv = b"\0" + n(1) + n(1, 4) + n(3) + nums([9, 0, 115, 127, 244, 255])
    hue = n(2) + bytes([1, 0]) + nums([37, 23, -7, -15, 18, 4])
    for center in [0, 60, 120, 180, 240, 300]:
        hue += nums([(center + x) % 360 for x in [-45, -15, 15, 45]]) + nums([0, 0, 0])
    balance = nums([-31, 17, 4, 12, -9, 27, 44, -18, 5]) + bytes([1, 0])
    gradient = n(3) + bytes([1, 0]) + code("Gcls") + text("Crème 🥔")
    gradient += n(2)
    for location, colors in [(0, [0, 1234, 23456, 56789, 0, 0]), (4096, [0, 65000, 32000, 4000, 0, 0])]:
        gradient += nums([location, 37], 4) + nums(colors)
    gradient += n(2)
    for location, opacity in [(0, 153), (4096, 255)]:
        gradient += nums([location, 61], 4) + n(opacity)
    gradient += nums([2, 4096, 32, 0])
    gradient += n(12345, 4) + nums([0, 1]) + n(2048, 4) + nums([3, 0, 0, 0, 0, 32768, 32768, 32768, 32768, 0])
    gradient += bytes((-len(gradient)) % 4)
    def path_record(selector, data):
        assert len(data) <= 24
        return n(selector) + data + bytes(24 - len(data))
    vector = n(3, 4) + n(0, 4)
    vector += path_record(6, b"") + path_record(8, n(0))
    vector += path_record(0, nums([3, 1, 1]))
    for x, y in [(0.125, 0.25), (0.875, 0.25), (0.5, 0.875)]:
        vector += path_record(2, nums([round(y * 2**24), round(x * 2**24)] * 3, 4))
    return {
        "levl": levl, "curv": curv, "hue2": hue, "blnc": balance,
        "thrs": n(117) + bytes(2), "post": n(7) + bytes(2),
        "grdm": gradient, "vmsk": vector, "vsms": vector,
        "levl-extension": levl + code("Lvls") + nums([3, 30]) + nums(identity),
        "curv-extension": curv + code("Crv ") + n(4) + n(1, 4) + nums([0, 3, 9, 0, 115, 127, 244, 255]),
    }

fixtures = []
for order in ["big", "little"]:
    payloads = records(order)
    for key, value in payloads.items():
        (out / f"{key}-{order}.bin").write_bytes(value)
    for depth, dtype, layerkey in [(8, np.uint8, p.PsdKey.LAYER), (16, np.uint16, p.PsdKey.LAYER_16), (32, np.float32, p.PsdKey.LAYER_32)]:
        fmt = p.PsdFormat.BE32BIT if order == "big" else p.PsdFormat.LE32BIT
        samples = np.arange(4 * 5 * 4).reshape(4, 5, 4)
        samples = (samples / 128 if depth == 32 else samples * (1 if depth == 8 else 257)).astype(dtype)
        def channels():
            return [p.PsdChannel(p.PsdChannelId(i if i < 3 else -1), p.PsdCompressionType.ZIP, samples[..., i]) for i in range(4)]
        def unknown(key, value):
            return p.PsdUnknown(p.PsdKey(key.encode()), fmt, value)
        layers = [p.PsdLayer("Vector base", channels(), p.PsdRectangle(0, 0, 4, 5), info=[unknown("vmsk", payloads["vmsk"])])]
        for key in (["levl", "curv", "hue2", "blnc", "thrs", "post"] + (["grdm"] if depth != 32 else [])):
            layers.append(p.PsdLayer(key, channels(), p.PsdRectangle(0, 0, 4, 5), info=[unknown(key, payloads[key])]))
        mask = p.PsdUserMask(p.PsdColorSpaceType.RGB, (1234, 23456, 56789, 0), 37, 128)
        source = p.TiffImageSourceData(fmt, p.PsdLayers(layerkey, layers, True), mask)
        file = out / f"{depth}-{order}.tiff"
        tifffile.imwrite(file, np.ones((4, 5, 4), dtype=dtype), byteorder=">" if order == "big" else "<",
                         photometric="rgb", extrasamples="unassalpha", metadata=None,
                         extratags=[source.tifftag()])
        parsed = p.TiffImageSourceData.fromtiff(file)
        assert parsed.usermask == mask
        for layer in parsed.layers.layers:
            for index, channel in enumerate(layer.channels):
                np.testing.assert_array_equal(channel.data, samples[..., index])
        fixtures.append(dict(file=file.name, depth=depth, order=order, sha256=hashlib.sha256(file.read_bytes()).hexdigest()))

manifest = dict(
    origin="Owned synthetic numeric fixtures. psdtags independently decodes framing, channels and LMsk; rich records are independently constructed opaque bytes, not independently rendered or Adobe-produced.",
    references=["https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/", "https://www.amyspark.me/blog/posts/2021/11/14/reading-and-writing-tiff-psds.html"],
    psdtags_revision="3b72663b375b60dbadaedfa6eefe5bb4c5cd9e7a",
    psdtags_sha256=hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest(),
    dependencies=dict(numpy=np.__version__, tifffile=tifffile.__version__, imagecodecs="2026.1.14"),
    fixtures=fixtures,
    payloads={f.name: hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(out.glob("*.bin"))},
)
(out / "provenance.json").write_text(json.dumps(manifest, indent=2) + "\n")
print("Generated and independently checked six TIFF containers; 22 literal rich-record payloads.")
