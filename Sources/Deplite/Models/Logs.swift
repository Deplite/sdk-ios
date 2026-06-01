import Foundation

/// Where a log line originated.
public enum LogStream: String, Codable, Sendable { case raw, system }

/// Severity of a log line.
public enum LogLevel: String, Codable, Sendable { case info, warn, error }

/// A single log line shipped to the backend by an embedded agent.
public struct LogItem: Sendable, Equatable {
    public let seq: Int
    public let stream: LogStream
    public let content: String
    public let stepName: String?
    public let level: LogLevel?

    public init(seq: Int, stream: LogStream, content: String, stepName: String? = nil, level: LogLevel? = nil) {
        self.seq = seq
        self.stream = stream
        self.content = content
        self.stepName = stepName
        self.level = level
    }
}
