#!/usr/bin/env python3
"""Independent rational/80-digit Decimal reference; imports no Photato implementation."""
import argparse
from collections import Counter
from decimal import Decimal, localcontext
from fractions import Fraction
import json
from pathlib import Path
import struct

MODES = ('variance', 'standardDeviation', 'skewness', 'kurtosis', 'entropy')

def f32(value):
    return struct.unpack('!f', struct.pack('!f', float(value)))[0]

def word(value):
    return struct.unpack('!I', struct.pack('!f', float(value)))[0]

def reference(values):
    samples = [Fraction.from_float(f32(v)) for v in values]
    n = len(samples)
    with localcontext() as context:
        context.prec = 80
        decimal = lambda v: Decimal(v.numerator) / Decimal(v.denominator)
        zero = Decimal(0)
        if n < 2:
            return {mode: 0 for mode in MODES}
        mean = sum(samples) / n
        differences = [v - mean for v in samples]
        variance = sum(v*v for v in differences) / (n-1)
        deviation = decimal(variance).sqrt()
        third = decimal(sum(v**3 for v in differences))
        fourth = sum(v**4 for v in differences)
        counts = Counter(samples)
        entropy = -sum((Decimal(count)/n) * ((Decimal(count)/n).ln()/Decimal(2).ln())
                       for count in sorted(counts.values()))
        result = {
            'variance': decimal(variance), 'standardDeviation': deviation,
            'skewness': third / ((n-1)*deviation**3) if variance else zero,
            'kurtosis': decimal(fourth / ((n-1)*variance**2)) if variance else zero,
            'entropy': entropy if entropy else zero,
        }
        return {mode: word(value) for mode, value in result.items()}

def fixture():
    vectors = {
        'empty': [], 'single': [0.25], 'constant': [0.5]*3,
        'symmetric': [0, 0.5, 1], 'positive': [0, 0, 0.25, 1],
        'negative': [0, 0.75, 1, 1], 'balanced': [0, 0, 1, 1],
        'hdr': [-2, 0, 4, 8], 'signedZero': [-0.0, 0.0, 1],
        'closeFloatValues': [0.5, f32(0.5+2**-24), f32(0.5+2**-23)],
        'sixteen': [i/16 for i in range(16)],
        'channelRed': [0, 0.5, 1], 'channelGreen': [0, 0, 1],
        'channelBlue': [0, 0.75, 1],
    }
    return {
        'version': 1, 'license': 'MIT OR Apache-2.0; independently generated numerical data',
        'reference': 'https://helpx.adobe.com/photoshop/desktop/create-manage-layers/create-layer-compositions/image-stack-rendering-modes.html',
        'method': 'Exact rational moments and 80-digit Decimal sqrt/log, rounded to Float32 words.',
        'limits': 'Empty/single/constant standardized moments return0 as an explicit Photato finite policy. Not Photoshop pixel/display/rounding/edge-case proof.',
        'cases': [{'name': name, 'inputs': [f32(v) for v in values], 'expectedWords': reference(values)}
                  for name, values in vectors.items()],
    }

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--generate', type=Path)
    parser.add_argument('--fixture', type=Path)
    parser.add_argument('--capture', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.generate:
        args.generate.parent.mkdir(parents=True, exist_ok=True)
        with args.generate.open('x') as out:
            json.dump(fixture(), out, indent=2); out.write('\n')
        return
    if not args.fixture or not args.capture:
        parser.error('--fixture and --capture are required for verification')
    data = json.loads(args.fixture.read_text())
    capture = json.loads(args.capture.read_text())
    expected = {row['name']: reference(row['inputs']) for row in data['cases']}
    assert {row['name']: row['expectedWords'] for row in data['cases']} == expected
    assert capture['cases'] == expected, 'Captured scalar Float32 words differ from independent reference'
    result = {'passed': True, 'cases': len(expected), 'exactFloat32Words': len(expected)*len(MODES),
              'method': data['method'], 'Photoshop_pixel_equivalence': False}
    if args.output:
        with args.output.open('x') as out:
            json.dump(result, out, indent=2); out.write('\n')
    print(json.dumps(result))

if __name__ == '__main__':
    main()
