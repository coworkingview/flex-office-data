import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct HTTPResponse: Sendable {
    var status: Int
    var reason: String
    var headers: [String: String]
    var body: Data

    func value(for header: String) -> String? {
        let name = header.lowercased()
        for (key, value) in headers where key.lowercased() == name {
            return value
        }
        return nil
    }
}

protocol HTTPTransport: Sendable {
    func get(url: URL, headers: [String: String], timeout: TimeInterval) async throws -> HTTPResponse
}

protocol Sleeper: Sendable {
    func sleep(seconds: TimeInterval) async throws
}

struct TaskSleeper: Sleeper {
    func sleep(seconds: TimeInterval) async throws {
        if seconds <= 0 { return }
        let nanoseconds = seconds * 1_000_000_000
        guard nanoseconds <= Double(UInt64.max) else { return }
        try await Task.sleep(nanoseconds: UInt64(nanoseconds))
    }
}

final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession

    init(timeout: TimeInterval) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        session = URLSession(configuration: configuration)
    }

    func get(url: URL, headers: [String: String], timeout: TimeInterval) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let session = self.session
        return try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                var headerMap: [String: String] = [:]
                for (key, value) in http.allHeaderFields {
                    headerMap[String(describing: key)] = String(describing: value)
                }
                continuation.resume(
                    returning: HTTPResponse(
                        status: http.statusCode,
                        reason: HTTPReason.phrase(for: http.statusCode),
                        headers: headerMap,
                        body: data ?? Data()
                    )
                )
            }
            task.resume()
        }
    }
}

enum HTTPReason {
    static func phrase(for status: Int) -> String {
        switch status {
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 409: return "Conflict"
        case 422: return "Unprocessable Entity"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        default: return "HTTP \(status)"
        }
    }
}

enum RetryDelay {
    static let fallback: TimeInterval = 2
    static let maximum: TimeInterval = 10

    static func seconds(headers: [String: String], now: Date = Date()) -> TimeInterval {
        let lookup = HTTPResponse(status: 0, reason: "", headers: headers, body: Data())
        var wait = delay(lookup.value(for: "Retry-After"), now: now)
        if wait == nil {
            wait = delay(lookup.value(for: "RateLimit-Reset"), now: now)
        }
        return min(wait ?? fallback, maximum)
    }

    static func delay(_ value: String?, now: Date) -> TimeInterval? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let number = Double(raw) {
            return max(0, number)
        }
        guard let date = httpDate(raw) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }

    static func httpDate(_ value: String) -> Date? {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEEE, dd-MMM-yy HH:mm:ss zzz",
            "EEE MMM d HH:mm:ss yyyy",
            "EEE, dd MMM yyyy HH:mm:ss",
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }
}

enum HTTPBody {
    static func envelope(response: HTTPResponse, path: String) throws -> JSON.Value {
        do {
            let value = try JSON.parse(response.body)
            if value.object == nil {
                throw APIError(
                    status: response.status,
                    code: "BAD_RESPONSE",
                    title: "The API returned JSON that is not an object",
                    detail: "GET \(path)"
                )
            }
            return value
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError(
                status: response.status,
                code: "BAD_RESPONSE",
                title: "The API returned a body that is not valid JSON",
                detail: detail(response)
            )
        }
    }

    static func problem(_ response: HTTPResponse) -> APIError {
        let body = (try? JSON.parse(response.body))?.object ?? [:]
        let title = JSONRead.string(body["title"]).flatMap { $0.isEmpty ? nil : $0 }
        let detail = JSONRead.string(body["detail"])
        let code = JSONRead.string(body["code"]).flatMap { $0.isEmpty ? nil : $0 }
        var fieldErrors: [FieldError] = []
        if let items = body["errors"]?.array {
            for item in items {
                guard let fields = item.object else { continue }
                fieldErrors.append(
                    FieldError(
                        path: JSONRead.string(fields["path"]),
                        message: JSONRead.string(fields["message"])
                    )
                )
            }
        }
        let reason = response.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return APIError(
            status: response.status,
            code: code ?? "HTTP_\(response.status)",
            title: title ?? (reason.isEmpty ? "HTTP \(response.status)" : reason),
            detail: detail,
            errors: fieldErrors
        )
    }

    static func detail(_ response: HTTPResponse) -> String {
        "HTTP \(response.status) \(response.reason)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isRetryable(_ status: Int) -> Bool {
        status == 429 || (500...599).contains(status)
    }

    static func shape(_ error: ResponseShapeError, status: Int, path: String) -> APIError {
        APIError(status: status, code: "BAD_RESPONSE", title: error.message, detail: "GET \(path)")
    }
}
