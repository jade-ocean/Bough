import Foundation

/// Parser for "bough://open?path=<file-path>" (pure, unit-testable).
///
/// Example:
///   bough://open?path=%2FUsers%2Fme%2Fcode%2Fproj
///     -> OpenRequest(path: "/Users/me/code/proj")
enum BoughURLScheme {
    enum SchemeError: LocalizedError, Equatable {
        case unsupportedAction(String?)
        case missingPathParameter
        case emptyPathParameter

        var errorDescription: String? {
            switch self {
            case .unsupportedAction(let host):
                return "不支持的 bough:// 动作：\(host ?? "nil")"
            case .missingPathParameter:
                return "URL 缺少 path 参数"
            case .emptyPathParameter:
                return "URL 的 path 参数为空"
            }
        }
    }

    struct OpenRequest: Equatable {
        /// Expanded (~) and standardized; existence is checked at open time.
        let path: String
    }

    static func parse(_ url: URL) throws -> OpenRequest {
        guard url.scheme?.lowercased() == "bough" else {
            throw SchemeError.unsupportedAction(url.host)
        }
        guard url.host?.lowercased() == "open" else {
            throw SchemeError.unsupportedAction(url.host)
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SchemeError.missingPathParameter
        }
        guard let raw = components.queryItems?.first(where: { $0.name == "path" })?.value else {
            throw SchemeError.missingPathParameter
        }
        guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw SchemeError.emptyPathParameter
        }
        let expanded = (raw as NSString).expandingTildeInPath
        return OpenRequest(path: expanded)
    }
}
