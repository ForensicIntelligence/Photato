import Foundation

extension AutomationService {
  /// Both interfaces share one isolated native job engine. The Adobe route keeps
  /// its published envelope; Photato's explicit routes do not replace document commands.
  func handleActionJobRequest(_ request: AutomationRequest) throws -> AutomationResponse? {
    let adobe = request.path.hasPrefix("/v2/")
    let photato =
      request.path == "/v1/action-jobs"
      || request.path.hasPrefix("/v1/action-jobs/")
      || request.path.hasPrefix("/v1/action-assets/")
    guard adobe || photato else { return nil }
    guard resourceJobsEnabled, let endpoint, let base = URL(string: endpoint) else {
      throw AdobeAPIError(
        status: 403, code: "unauthorized_forbidden",
        message: "Enable resource action jobs in Photato's native API window first.")
    }
    let submitPath = adobe ? "/v2/execute-actions" : "/v1/action-jobs"
    if request.path == submitPath {
      guard request.method == "POST" else {
        throw AdobeAPIError(
          status: 405, code: "unsupported_method", message: "Use POST to submit actions.")
      }
      guard
        request.headers["content-type"]?.lowercased().split(separator: ";").first
          == "application/json"
      else {
        throw AdobeAPIError(
          status: 415, code: "invalid_content_type",
          message: "Content-Type must be application/json.")
      }
      let actions = try AdobeActionsRequest(data: request.body)
      let job = try actionJobs.submit(
        actions, baseURL: base,
        assetPath: adobe ? "v2/assets" : "v1/action-assets")
      let statusPath = adobe ? "v2/status" : "v1/action-jobs"
      return .json(
        [
          "jobId": job.id.uuidString,
          "statusUrl": base.appendingPathComponent("\(statusPath)/\(job.id.uuidString)")
            .absoluteString,
        ], status: 202)
    }
    let parts = request.path.split(separator: "/", omittingEmptySubsequences: false)
    let statusRoute = adobe ? "status" : "action-jobs"
    let assetRoute = adobe ? "assets" : "action-assets"
    guard parts.count == 4, parts[0].isEmpty,
      parts[2] == statusRoute || parts[2] == assetRoute
    else {
      throw AdobeAPIError(
        status: 404, code: "validation_error", message: "Route is not implemented.")
    }
    guard request.method == "GET" else {
      throw AdobeAPIError(
        status: 405, code: "unsupported_method", message: "Use GET for jobs and outputs.")
    }
    guard let id = UUID(uuidString: String(parts[3])) else {
      throw AdobeAPIError.invalid("Invalid job or output ID.")
    }
    if parts[2] == statusRoute {
      guard let job = actionJobs.snapshot(id) else {
        throw AdobeAPIError(status: 404, code: "unknown_job_id", message: "Job not found.")
      }
      return job.response
    }
    // Hosted output delivery is an authenticated local extension, not an Adobe endpoint.
    guard let asset = actionJobs.asset(id) else {
      throw AdobeAPIError(
        status: 404, code: "unknown_output_id", message: "Output expired or not found.")
    }
    return .init(status: 200, contentType: asset.mediaType.rawValue, body: asset.data)
  }
}
