//
//  NumPyRandomGenerator.swift
//  
//
//  Created by Guillermo Cique Fernández on 21/5/23.
//

import CoreML

/// A random source consistent with NumPy
///
///  This implementation matches:
///  [NumPy's older randomkit.c](https://github.com/numpy/numpy/blob/v1.0/numpy/random/mtrand/randomkit.c)
///
public class NumPyRandomGenerator: RandomGenerator {
    struct State {
        var key = [UInt32](repeating: 0, count: 624)
        var pos: Int = 0
        var nextGauss: Double? = nil
    }

    var state: State

    /// Initialize with a random seed
    ///
    /// - Parameters
    ///     - seed: Seed for underlying Mersenne Twister 19937 generator
    /// - Returns random source
    public init(seed: UInt32) {
        state = .init()
        var s = seed & 0xffffffff
        for i in 0..<state.key.count {
            state.key[i] = s
            s = UInt32((UInt64(1812433253) * UInt64(s ^ (s >> 30)) + UInt64(i) + 1) & 0xffffffff)
        }
        state.pos = state.key.count
        state.nextGauss = nil
    }

    /// Generate next UInt32 using fast 32bit Mersenne Twister
    public func nextUInt32() -> UInt32 {
        let n = 624
        let m = 397
        let matrixA: UInt64    = 0x9908b0df
        let upperMask: UInt32  = 0x80000000
        let lowerMask: UInt32  = 0x7fffffff

        var y: UInt32
        if state.pos == state.key.count {
            for i in 0..<(n - m) {
                y = (state.key[i] & upperMask) | (state.key[i + 1] & lowerMask)
                state.key[i] = state.key[i + m] ^ (y >> 1) ^ UInt32((UInt64(~(y & 1)) + 1) & matrixA)
            }
            for i in (n - m)..<(n - 1) {
                y = (state.key[i] & upperMask) | (state.key[i + 1] & lowerMask)
                state.key[i] = state.key[i + (m - n)] ^ (y >> 1) ^ UInt32((UInt64(~(y & 1)) + 1) & matrixA)
            }
            y = (state.key[n - 1] & upperMask) | (state.key[0] & lowerMask)
            state.key[n - 1] = state.key[m - 1] ^ (y >> 1) ^ UInt32((UInt64(~(y & 1)) + 1) & matrixA)
            state.pos = 0
        }
        y = state.key[state.pos]
        state.pos += 1

        y ^= (y >> 11)
        y ^= (y << 7) & 0x9d2c5680
        y ^= (y << 15) & 0xefc60000
        y ^= (y >> 18)

        return y
    }

    public func next() -> UInt64 {
        let low = nextUInt32()
        let high = nextUInt32()
        return (UInt64(high) << 32) | UInt64(low)
    }

    /// Generate next random double value
    public func nextDouble() -> Double {
        let a = Double(nextUInt32() >> 5)
        let b = Double(nextUInt32() >> 6)
        return (a * 67108864.0 + b) / 9007199254740992.0
    }

    /// Generate next random value from a standard normal
    public func nextGauss() -> Double {
        if let nextGauss = state.nextGauss {
            state.nextGauss = nil
            return nextGauss
        }
        var x1, x2, r2: Double
        repeat {
            x1 = 2.0 * nextDouble() - 1.0
            x2 = 2.0 * nextDouble() - 1.0
            r2 = x1 * x1 + x2 * x2
        } while r2 >= 1.0 || r2 == 0.0

        // Box-Muller transform
        let f = sqrt(-2.0 * log(r2) / r2)
        state.nextGauss = f * x1
        return f * x2
    }

    /// Generates a random value from a normal distribution with given mean and standard deviation.
    public func nextNormal(mean: Double, stdev: Double) -> Double {
        nextGauss() * stdev + mean
    }
}
