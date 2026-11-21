import Accelerate
import CoreGraphics
import CoreML
import Foundation
import RandomGenerator
import Schedulers

/// Native inference for the exemplar-conditioned diffusion model. Shares the
/// compiled VAE, noise model wrapper, and PNDM scheduler with Stable Diffusion.
public final class PaintByExamplePipeline {
    private static let contract = "photato-paint-by-example-1"
    private static let side = 512
    public static let referenceSide = 224
    private let sourceEncoder: Encoder
    private let decoder: Decoder
    private let imageEncoder: ManagedMLModel
    private let unet: Unet
    private let reduceMemory: Bool

    public init(resources: URL, reduceMemory: Bool = false) throws {
        self.reduceMemory = reduceMemory
        let configurations: [(String, [String: [Int]])] = [
            ("ImageEncoder", ["reference": [1, 3, Self.referenceSide, Self.referenceSide]]),
            ("VAEEncoder", ["z": [1, 3, Self.side, Self.side]]),
            ("VAEDecoder", ["z": [1, 4, 64, 64]]),
            ("Unet", ["sample": [2, 9, 64, 64], "timestep": [2], "encoder_hidden_states": [2, 768, 1, 1]]),
        ]
        let models = try configurations.map { name, inputs in
            let folder = resources.appending(path: "\(name).mlmodelc", directoryHint: .isDirectory)
            let metadata = folder.appending(path: "metadata.json")
            guard let bytes = try? metadata.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                (1...262_144).contains(bytes) else {
                throw StableDiffusionError.missingInputs
            }
            let metadataBytes = try Data(contentsOf: metadata)
            let descriptions = try JSONDecoder().decode([CoreMLMetadata].self, from: metadataBytes)
            guard descriptions.count == 1, let info = descriptions.first,
                info.userDefinedMetadata?["reference_contract"] == Self.contract,
                info.inputSchema.count == inputs.count,
                info.inputSchema.allSatisfy({ inputs[$0.name] == $0.shape }) else {
                throw StableDiffusionError.missingInputs
            }
            return (folder, info)
        }
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU
        // The exemplar is encoded once. Running CLIP on CPU leaves the GPU
        // command queue and memory available for repeated denoising.
        let referenceConfig = MLModelConfiguration()
        referenceConfig.computeUnits = .cpuOnly
        imageEncoder = ManagedMLModel(modelAt: models[0].0, configuration: referenceConfig)
        sourceEncoder = try Encoder(modelAt: models[1].0, metadata: models[1].1, configuration: config)
        decoder = try Decoder(modelAt: models[2].0, metadata: models[2].1, configuration: config)
        unet = Unet(chunksAt: [models[3].0], metadata: models[3].1, configuration: config)
    }

    public func unloadResources() {
        sourceEncoder.unloadResources(clearCache: true)
        decoder.unloadResources()
        imageEncoder.unloadResources()
        unet.unloadResources()
    }

    public func referenceEmbedding(_ samples: [Float]) throws -> MLShapedArray<Float32> {
        let shape = [1, 3, Self.referenceSide, Self.referenceSide]
        guard samples.count == shape.reduce(1, *), samples.allSatisfy(\.isFinite) else {
            throw StableDiffusionError.missingInputs
        }
        defer { imageEncoder.unloadResources() }
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "reference": MLMultiArray(MLShapedArray(scalars: samples, shape: shape))
        ])
        return try imageEncoder.perform { model in
            let output = try model.prediction(from: input)
            guard let array = output.featureValue(for: "embeddings")?.multiArrayValue else {
                throw StableDiffusionError.missingInputs
            }
            let result = MLShapedArray<Float32>(converting: array)
            guard result.shape == [2, 768, 1, 1], result.scalars.allSatisfy(\.isFinite) else {
                throw StableDiffusionError.missingInputs
            }
            return result
        }
    }

    public func generate(image: [Float], mask: [Float], embedding: MLShapedArray<Float32>, seed: UInt32,
        stepCount: Int = 30) throws -> CGImage {
        try Task.checkCancellation()
        let side = Self.side
        let area = side * side
        guard image.count == area * 3, mask.count == area, embedding.shape == [2, 768, 1, 1],
            image.allSatisfy(\.isFinite), mask.allSatisfy({ $0 == 0 || $0 == 1 }),
            (2...100).contains(stepCount) else {
            throw StableDiffusionError.missingInputs
        }
        let generator = TorchRandomGenerator(seed: seed)
        let scheduler = PNDMScheduler(stepCount: stepCount, setAlphaToOne: false, stepsOffset: 1)
        var latent: MLShapedArray<Float32> = generator.nextArray(shape: [1, 4, 64, 64], mean: 0, stdev: scheduler.initNoiseSigma)
        let masked = image.enumerated().map { index, value in mask[index % area] == 1 ? 0 : 2 * value - 1 }
        let posterior = MLShapedArray<Float32>(scalars: masked, shape: [1, 3, side, side])
        let maskedLatent = try sourceEncoder.encode(posterior, generator: generator)
        if reduceMemory { sourceEncoder.unloadResources() }
        let maskedBatch = MLShapedArray<Float32>(concatenating: [maskedLatent, maskedLatent], alongAxis: 0)
        // The exemplar model receives keep coverage, the inverse of the
        // editor's selection and the mask used by text-conditioned inpainting.
        let smallMask = (0..<(64 * 64)).map { 1 - mask[($0 / 64 * 8) * side + ($0 % 64 * 8)] }
        let maskBatch = MLShapedArray<Float32>(scalars: smallMask + smallMask, shape: [2, 1, 64, 64])
        for timestep in scheduler.timeSteps {
            try Task.checkCancellation()
            let input = MLShapedArray<Float32>(concatenating: [latent, latent], alongAxis: 0)
            let scaled = scheduler.scaleModelInput(timeStep: timestep, sample: input)
            // The released exemplar model takes source latents before the mask.
            let sample = MLShapedArray<Float32>(concatenating: [scaled, maskedBatch, maskBatch], alongAxis: 1)
            let output = try unet.predictNoise(latents: [sample], timeStep: timestep, hiddenStates: embedding)
            guard let noise = output.first, noise.shape == [2, 4, 64, 64] else {
                throw StableDiffusionError.missingInputs
            }
            let guided = MLShapedArray<Float32>(unsafeUninitializedShape: [1, 4, 64, 64]) { result, _ in
                vDSP.linearInterpolate(noise[0].scalars, noise[1].scalars, using: 5.0, result: &result)
            }
            latent = scheduler.step(output: guided, timeStep: timestep, sample: latent, generator: generator)
        }
        if reduceMemory { unet.unloadResources() }
        try Task.checkCancellation()
        guard latent.scalars.allSatisfy(\.isFinite) else { throw StableDiffusionError.missingInputs }
        let result = try decoder.decode(latent)
        if reduceMemory { decoder.unloadResources() }
        return result
    }
}
