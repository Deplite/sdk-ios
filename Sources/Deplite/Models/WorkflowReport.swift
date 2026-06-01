import Foundation

public enum WorkflowParamType: String, Codable, Sendable {
    case string, number, boolean, `enum`
}

public enum WorkflowOutputType: String, Codable, Sendable {
    case string, number, boolean
}

public enum WorkflowBackoff: String, Codable, Sendable {
    case fixed, linear, exponential
}

public struct WorkflowParam: Codable, Sendable, Equatable {
    public let name: String
    public let type: WorkflowParamType
    public let required: Bool?
    public let description: String?
    public let `default`: JSONValue?
    public let pattern: String?
    public let options: [String]?
    public let min: Double?
    public let max: Double?

    public init(
        name: String,
        type: WorkflowParamType,
        required: Bool? = nil,
        description: String? = nil,
        `default`: JSONValue? = nil,
        pattern: String? = nil,
        options: [String]? = nil,
        min: Double? = nil,
        max: Double? = nil
    ) {
        self.name = name
        self.type = type
        self.required = required
        self.description = description
        self.default = `default`
        self.pattern = pattern
        self.options = options
        self.min = min
        self.max = max
    }
}

public struct WorkflowOutput: Codable, Sendable, Equatable {
    public let name: String
    public let type: WorkflowOutputType
    public let description: String?

    public init(name: String, type: WorkflowOutputType, description: String? = nil) {
        self.name = name
        self.type = type
        self.description = description
    }
}

public struct WorkflowSecret: Codable, Sendable, Equatable {
    public let name: String
    public let required: Bool?
    public let description: String?

    public init(name: String, required: Bool? = nil, description: String? = nil) {
        self.name = name
        self.required = required
        self.description = description
    }
}

public struct WorkflowRetry: Codable, Sendable, Equatable {
    public let maxAttempts: Int
    public let backoff: WorkflowBackoff?
    public let initialDelaySeconds: Int?
    public let maxDelaySeconds: Int?

    public init(
        maxAttempts: Int,
        backoff: WorkflowBackoff? = nil,
        initialDelaySeconds: Int? = nil,
        maxDelaySeconds: Int? = nil
    ) {
        self.maxAttempts = maxAttempts
        self.backoff = backoff
        self.initialDelaySeconds = initialDelaySeconds
        self.maxDelaySeconds = maxDelaySeconds
    }
}

/// Catalog projection of a single step. Execution body stays on the agent.
public struct WorkflowStepReport: Codable, Sendable, Equatable {
    public let id: String?
    public let name: String
    public let timeoutMinutes: Int?
    public let verbose: Bool?
    public let continueOnError: Bool?
    public let retry: WorkflowRetry?

    public init(
        name: String,
        id: String? = nil,
        timeoutMinutes: Int? = nil,
        verbose: Bool? = nil,
        continueOnError: Bool? = nil,
        retry: WorkflowRetry? = nil
    ) {
        self.id = id
        self.name = name
        self.timeoutMinutes = timeoutMinutes
        self.verbose = verbose
        self.continueOnError = continueOnError
        self.retry = retry
    }
}

/// Workflow definition reported by an embedded agent. Execution body and
/// secret values are not present.
public struct WorkflowReport: Codable, Sendable, Equatable {
    public let name: String
    public let description: String?
    public let version: String?
    public let schemaVersion: Int?
    public let verboseSteps: [String]
    public let secretsKeys: [String]
    public let secrets: [WorkflowSecret]
    public let params: [WorkflowParam]
    public let outputs: [WorkflowOutput]
    public let retry: WorkflowRetry?
    public let steps: [WorkflowStepReport]

    public init(
        name: String,
        description: String? = nil,
        version: String? = nil,
        schemaVersion: Int? = nil,
        verboseSteps: [String] = [],
        secretsKeys: [String] = [],
        secrets: [WorkflowSecret] = [],
        params: [WorkflowParam] = [],
        outputs: [WorkflowOutput] = [],
        retry: WorkflowRetry? = nil,
        steps: [WorkflowStepReport] = []
    ) {
        self.name = name
        self.description = description
        self.version = version
        self.schemaVersion = schemaVersion
        self.verboseSteps = verboseSteps
        self.secretsKeys = secretsKeys
        self.secrets = secrets
        self.params = params
        self.outputs = outputs
        self.retry = retry
        self.steps = steps
    }
}
