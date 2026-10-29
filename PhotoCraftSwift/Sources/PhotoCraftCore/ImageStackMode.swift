import Foundation

/// Statistical stack operators translated from PhotoCraft algo/stack.rs (MIT OR Apache-2.0).
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
      var bins: [Int:Int] = [:]
      for v in values { bins[Int((min(1,max(0,v))*255).rounded()), default:0] += 1 }
      return -bins.values.reduce(Float(0)) { s,c in let p = Float(c)/n; return s+p*log2(p) } / log2(n)
    case .variance, .standardDeviation, .skewness, .kurtosis:
      let variance = values.reduce(Float(0)) { $0+pow($1-mean,2) }/n
      if self == .variance { return variance }
      let sd = sqrt(variance)
      if self == .standardDeviation { return sd }
      if self == .skewness {
        guard sd >= 1e-6 else { return 0.5 }
        return min(1,max(0,values.reduce(Float(0)) { $0+pow($1-mean,3) }/n/pow(sd,3)/4+0.5))
      }
      guard variance >= 1e-12 else { return 0 }
      return min(1,max(0,values.reduce(Float(0)) { $0+pow($1-mean,4) }/n/(variance*variance)/10))
    }
  }
}
