//
//  RandomGenerator.swift
//  
//
//  Created by Guillermo Cique Fernández on 21/5/23.
//

import CoreML

public protocol RandomGenerator: RandomNumberGenerator {
    func nextNormal(mean: Double, stdev: Double) -> Double
    
    func nextArray(shape: [Int], mean: Double, stdev: Double) -> MLShapedArray<Double>
    
    func nextArray(shape: [Int], mean: [Double], stdev: [Double]) -> MLShapedArray<Double>
}

public extension RandomGenerator {
    func nextNormal() -> Double {
        return nextNormal(mean: 0, stdev: 1)
    }
    
    func nextArray(shape: [Int]) -> MLShapedArray<Double> {
        return nextArray(shape: shape, mean: 0, stdev: 1)
    }
    
    func nextArray(shape: [Int], mean: Double, stdev: Double) -> MLShapedArray<Double> {
        let count = shape.reduce(1, *)
        return .init(unsafeUninitializedShape: shape) { scalars, _ in
            for i in 0..<count {
                scalars.initializeElement(at: i, to: nextNormal(mean: mean, stdev: stdev))
            }
        }
    }
    
    func nextArray(shape: [Int], mean: [Double], stdev: [Double]) -> MLShapedArray<Double> {
        let count = shape.reduce(1, *)
        return .init(unsafeUninitializedShape: shape) { scalars, _ in
            for i in 0..<count {
                scalars.initializeElement(at: i, to: nextNormal(mean: mean[i], stdev: stdev[i]))
            }
        }
    }
}

public extension RandomGenerator {
    func nextNormal(mean: Float32, stdev: Float32) -> Float32 {
        return Float32(nextNormal(mean: Double(mean), stdev: Double(stdev)))
    }
    
    func nextArray(shape: [Int], mean: Float32, stdev: Float32) -> MLShapedArray<Float32> {
        return MLShapedArray<Float32>(converting: nextArray(
            shape: shape,
            mean: Double(mean),
            stdev: Double(stdev)
        ))
    }
    
    func nextArray(shape: [Int], mean: [Float32], stdev: [Float32]) -> MLShapedArray<Float32> {
        return MLShapedArray<Float32>(converting: nextArray(
            shape: shape,
            mean: mean.map { Double($0) },
            stdev: stdev.map { Double($0) }
        ))
    }
}
