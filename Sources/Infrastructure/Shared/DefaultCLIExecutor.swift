import Foundation

/// Default CLIExecutor that uses BinaryLocator and InteractiveRunner.
/// This is an adapter that wraps system APIs for CLI execution.
public struct DefaultCLIExecutor: CLIExecutor {
    /// Environment variable keys to exclude from the subprocess environment.
    /// When set, these keys are removed before the subprocess launches,
    /// preventing tokens like `CLAUDE_CODE_OAUTH_TOKEN` from being inherited.
    private let environmentExclusions: [String]
    /// Environment variable keys and values to inject into the subprocess environment.
    /// Use this to set per-invocation context such as `CLAUDE_CONFIG_DIR`.
    private let environmentAdditions: [String: String]

    public init(
        environmentExclusions: [String] = [],
        environmentAdditions: [String: String] = [:]
    ) {
        self.environmentExclusions = environmentExclusions
        self.environmentAdditions = environmentAdditions
    }

    public func locate(_ binary: String) -> String? {
        BinaryLocator.which(binary)
    }

    public func execute(
        binary: String,
        args: [String],
        input: String?,
        timeout: TimeInterval,
        workingDirectory: URL?,
        autoResponses: [String: String]
    ) throws -> CLIResult {
        let runner = InteractiveRunner()
        let options = InteractiveRunner.Options(
            timeout: timeout,
            workingDirectory: workingDirectory,
            arguments: args,
            autoResponses: autoResponses,
            environmentExclusions: environmentExclusions,
            environmentAdditions: environmentAdditions
        )

        let result = try runner.run(binary: binary, input: input ?? "", options: options)
        return CLIResult(output: result.output, exitCode: result.exitCode)
    }
}
