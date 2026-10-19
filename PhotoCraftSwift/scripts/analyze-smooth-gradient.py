#!/usr/bin/env python3
"""Measure Smooth references and exploratory interpolation candidates; no fitted app code."""
import argparse
import importlib.util
import json
import math
import struct
from pathlib import Path

spec = importlib.util.spec_from_file_location('reference', Path(__file__).with_name('inspect-gradient-method-reference.py'))
reference = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reference)


def lightness(value):
    linear = value / 12.92 if value <= .04045 else ((value + .055) / 1.055) ** 2.4
    return linear ** (1 / 3)


def curve(path):
    w, h, d, raw = reference.merged(path)
    values = struct.unpack('>' + str(len(raw) // 2) + 'H', raw) if d == 16 else raw
    scale = 65535 if d == 16 else 255
    low, high = lightness(values[0] / scale), lightness(values[w - 1] / scale)
    return [(x / (w - 1), (lightness(values[x] / scale) - low) / (high - low)) for x in range(w)]


def bezier(t, points):
    x1, y1, x2, y2 = points
    def coord(u, a, b):
        return 3 * (1 - u) ** 2 * u * a + 3 * (1 - u) * u * u * b + u ** 3
    low, high = 0, 1
    for _ in range(25):
        mid = (low + high) / 2
        if coord(mid, x1, x2) < t:
            low = mid
        else:
            high = mid
    return coord((low + high) / 2, y1, y2)


def fit(pairs):
    def cost(p):
        if not all(0 <= v <= 1 for v in p) or p[0] > p[2]:
            return 1e3
        return sum((bezier(x, p) - y) ** 2 for x, y in pairs) / len(pairs)
    initial = [.5, 1 / 3, 2 / 3, 2 / 3]
    simplex = [initial] + [[v + (.04 if i == j else 0) for j, v in enumerate(initial)] for i in range(4)]
    for _ in range(450):
        simplex.sort(key=cost)
        centroid = [sum(p[i] for p in simplex[:-1]) / 4 for i in range(4)]
        worst = simplex[-1]
        reflected = [2 * a - b for a, b in zip(centroid, worst)]
        if cost(reflected) < cost(simplex[0]):
            expanded = [a + 2 * (b - a) for a, b in zip(centroid, reflected)]
            simplex[-1] = expanded if cost(expanded) < cost(reflected) else reflected
        elif cost(reflected) < cost(simplex[-2]):
            simplex[-1] = reflected
        else:
            contracted = [(a + b) / 2 for a, b in zip(centroid, worst)]
            if cost(contracted) < cost(worst):
                simplex[-1] = contracted
            else:
                simplex = [simplex[0]] + [[(a + b) / 2 for a, b in zip(simplex[0], p)] for p in simplex[1:]]
    p = min(simplex, key=cost)
    return dict(control_points=p, rms=math.sqrt(cost(p)),
                maximum=max(abs(bezier(x, p) - y) for x, y in pairs),
                warning='Exploratory fit only; does not identify an algorithm or qualify production behavior')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    assert not args.output.exists(), 'Use a distinct analysis output for each attempt'
    gray = curve(args.run / 'inputs-03/photoshop-smooth-gray-range-rgb16.psd')
    neutral = curve(args.run / 'inputs-02/photoshop-smooth-neutral-rgb16.psd')
    differences = [abs(a[1] - b[1]) for a, b in zip(gray, neutral)]
    fit_pairs = [(x * 2, y * 2) for x, y in gray[64:2048:32]]
    report = dict(gray_curve_samples=gray[::128], neutral_curve_samples=neutral[::128],
                  maximum_normalized_gray_neutral_difference=max(differences),
                  half_curve_bezier=fit(fit_pairs), sources='Original saved Photoshop references',
                  production_implementation=False)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
