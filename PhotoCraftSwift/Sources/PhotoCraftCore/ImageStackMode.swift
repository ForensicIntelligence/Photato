import Foundation

/// Stack operators inspired by PhotoCraft algo/stack.rs (MIT OR Apache-2.0).
/// Moments and entropy follow Adobe's published definitions; see STACK_STATISTICS_417.json.
public enum ImageStackMode: String, CaseIterable, Codable, Sendable {
  case entropy, kurtosis, maximum, mean, median, minimum, range, skewness, standardDeviation, summation, variance
  public var title: String { switch self {
    case .entropy: "Entropy"; case .kurtosis: "Kurtosis"; case .maximum: "Maximum"
    case .mean: "Mean"; case .median: "Median"; case .minimum: "Minimum"; case .range: "Range"
    case .skewness: "Skewness"; case .standardDeviation: "Standard Deviation"; case .summation: "Summation"; case .variance: "Variance"
  } }
  public func statistic(_ values: [Float]) -> Float {
    guard !values.isEmpty else { return 0 }
    let n = Float(values.count), sum = values.reduce(0,+), mean = sum/n
    switch self {
    case .mean: return mean
    case .maximum: return values.max()!
    case .minimum: return values.min()!
    case .range: return values.max()!-values.min()!
    case .summation: return sum
    case .median:
      let sorted = values.sorted(), mid = sorted.count/2
      return sorted.count % 2 == 0 ? (sorted[mid-1]+sorted[mid])/2 : sorted[mid]
    case .entropy:
      guard values.count > 1 else { return 0 }
      var bins: [UInt32:Int] = [:]
      for value in values { bins[value == 0 ? 0 : value.bitPattern, default:0] += 1 }
      // Sort counts so dictionary iteration cannot change the floating-point sum.
      let entropy = -bins.values.sorted().reduce(0.0) { sum,count in
        let probability = Double(count)/Double(values.count)
        return sum + probability*log2(probability)
      }
      return entropy == 0 ? 0 : Float(entropy)
    case .variance, .standardDeviation, .skewness, .kurtosis:
      guard values.count > 1 else { return 0 }
      let samples = values.map(Double.init), denominator = Double(values.count - 1)
      let center = samples.reduce(0,+)/Double(values.count)
      let variance = samples.reduce(0.0) { sum,value in let delta = value-center; return sum+delta*delta }/denominator
      if self == .variance { return Float(variance) }
      let sd = sqrt(variance)
      if self == .standardDeviation { return Float(sd) }
      // Degenerate estimates have no defined standardized moment; keep native pixels finite.
      guard variance > 0 else { return 0 }
      if self == .skewness {
        let third = samples.reduce(0.0) { sum,value in let delta = value-center; return sum+delta*delta*delta }
        return Float(third/(denominator*sd*sd*sd))
      }
      let fourth = samples.reduce(0.0) { sum,value in let delta = value-center; let square = delta*delta; return sum+square*square }
      return Float(fourth/(denominator*variance*variance))
    }
  }
}
