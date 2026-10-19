#!/usr/bin/env python3
"""Independently decode the one-layer RGB16 matrix and measure candidate matte rules."""
import argparse
import hashlib
import importlib.util
import json
import struct
import zlib
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    'gradient_reference', Path(__file__).with_name('inspect-gradient-method-reference.py'))
gradient_reference = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gradient_reference)


def layer_planes(path):
    data = path.read_bytes()
    assert data[:6] == b'8BPS\0\1' and data[22:26] == b'\0\x10\0\x03'
    at = 26
    for _ in range(2):
        at += 4 + int.from_bytes(data[at:at + 4], 'big')
    block = data[at + 4:at + 4 + int.from_bytes(data[at:at + 4], 'big')]
    at = 4 + int.from_bytes(block[:4], 'big')
    at += 4 + int.from_bytes(block[at:at + 4], 'big')
    while at < len(block):
        signature, key, size = struct.unpack('>4s4sI', block[at:at + 12])
        assert signature == b'8BIM'
        at += 12
        if key == b'Lr16':
            info = block[at:at + size]
            break
        at += (size + 3) // 4 * 4
    else:
        raise AssertionError('Missing RGB16 layer records')
    count, top, left, bottom, right, channels = struct.unpack('>hiiiiH', info[:20])
    assert abs(count) == 1 and top == left == 0 and channels == 4
    assert count < 0 or b'8BIMMt16\0\0\0\0' in block
    width, height = right - left, bottom - top
    ids = [struct.unpack('>hI', info[20 + c * 6:26 + c * 6]) for c in range(channels)]
    at = 20 + channels * 6
    assert info[at:at + 8] == b'8BIMnorm' and info[at + 8] == 255
    at += 12
    at += 4 + int.from_bytes(info[at:at + 4], 'big')
    planes = {}
    for cid, size in ids:
        payload = info[at:at + size]
        at += size
        compression = int.from_bytes(payload[:2], 'big')
        if compression == 0:
            raw = payload[2:]
        elif compression in (2, 3):
            raw = zlib.decompress(payload[2:])
        elif compression == 1:
            lengths = struct.unpack('>' + str(height) + 'H', payload[2:2 + height * 2])
            cursor = 2 + height * 2
            raw = bytearray()
            for length in lengths:
                row = payload[cursor:cursor + length]
                cursor += length
                q = 0
                decoded = bytearray()
                while q < len(row):
                    n = row[q]
                    q += 1
                    if n < 128:
                        decoded += row[q:q + n + 1]
                        q += n + 1
                    elif n > 128:
                        decoded += row[q:q + 1] * (257 - n)
                        q += 1
                assert len(decoded) == width * 2
                raw += decoded
        else:
            raise AssertionError(f'Unsupported compression {compression}')
        assert len(raw) == width * height * 2
        values = list(struct.unpack('>' + str(width * height) + 'H', raw))
        if compression == 3:
            for y in range(height):
                for x in range(1, width):
                    i = y * width + x
                    values[i] = (values[i] + values[i - 1]) & 65535
        planes[cid] = values
    return width, height, [planes[k] for k in (0, 1, 2, -1)]


def rounded_ratio(n, d):
    return (n + d // 2) // d


def expand(n):
    return rounded_ratio(n * 65535, 32768)


def working(n):
    return rounded_ratio(n * 32768, 65535)


def inspect():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('reference', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    assert not args.output.exists(), 'Use a new output path for each analysis attempt'
    width, height, original = layer_planes(args.input)
    w, h, planes = layer_planes(args.reference)
    assert (width, height) == (w, h)
    mw, mh, depth, raw = gradient_reference.merged(args.reference)
    assert (mw, mh, depth) == (width, height, 16)
    n = width * height
    stored = list(struct.unpack('>' + str(n * 4) + 'H', raw))
    merged = [stored[c * n:(c + 1) * n] for c in range(4)]
    candidates = {
        'full_range_round': lambda c, a: rounded_ratio(c * a + 65535 * (65535 - a), 65535),
        'working_grid_round': lambda c, a: expand(rounded_ratio(working(c) * working(a) + 32768 * (32768 - working(a)), 32768)),
        'working_grid_subtract_rounded_distance': lambda c, a: expand(32768 - rounded_ratio((32768 - working(c)) * working(a), 32768)),
        'working_grid_floor': lambda c, a: expand((working(c) * working(a) + 32768 * (32768 - working(a))) // 32768),
        'working_inputs_continuous_matte': lambda c, a: rounded_ratio((working(c) * working(a) + 32768 * (32768 - working(a))) * 65535, 32768 ** 2),
    }
    results = {}
    for name, operation in candidates.items():
        diffs, examples, maximum, changed_pixels = 0, [], 0, set()
        for c in range(3):
            for i, (value, alpha, expected) in enumerate(zip(planes[c], planes[3], merged[c])):
                actual = operation(value, alpha)
                if actual != expected:
                    diffs += 1
                    changed_pixels.add(i)
                    maximum = max(maximum, abs(actual - expected))
                    if len(examples) < 12:
                        examples.append(dict(index=i, channel=c, color=value, alpha=alpha,
                                             actual=actual, expected=expected))
        results[name] = dict(differing_channels=diffs, differing_pixels=len(changed_pixels),
                             maximum_stored_error=maximum, first_differences=examples)
    report = dict(input=str(args.input), reference=str(args.reference),
                  input_sha256=hashlib.sha256(args.input.read_bytes()).hexdigest(),
                  reference_sha256=hashlib.sha256(args.reference.read_bytes()).hexdigest(),
                  width=width, height=height, depth=depth,
                  input_to_saved_layer_changed_samples=[sum(a != b for a, b in zip(x, y))
                                                       for x, y in zip(original, planes)],
                  saved_layer_vs_working_grid_expansion=[sum(expand(working(a)) != b for a, b in zip(x, y))
                                                        for x, y in zip(original, planes)],
                  merged_alpha_vs_saved_layer_differences=sum(a != b for a, b in zip(merged[3], planes[3])),
                  candidates=results)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: v for k, v in report.items() if k != 'candidates'}, indent=2))
    print(json.dumps({k: {a: b for a, b in v.items() if a != 'first_differences'}
                      for k, v in results.items()}, indent=2))


if __name__ == '__main__':
    inspect()
