// SPDX-License-Identifier: GPL-3.0-or-later

#if os(macOS)
import Foundation

internal final class ProcessKataGoTransport: KataGoTransport, @unchecked Sendable {
    private let configuration: KataGoEngineConfiguration
    private let launchArguments: [String]
    private let lock = NSLock()
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var stderrTail = ""
    private var isStarting = false
    private var isProcessLaunched = false
    private var didFinishResponses = false
    private var responseFinishError: Error?

    convenience init(configuration: KataGoEngineConfiguration) {
        self.init(
            configuration: configuration,
            launchArguments: Self.defaultLaunchArguments(for: configuration)
        )
    }

    internal init(configuration: KataGoEngineConfiguration, launchArguments: [String]) {
        self.configuration = configuration
        self.launchArguments = launchArguments
    }

    internal static func defaultLaunchArguments(for configuration: KataGoEngineConfiguration) -> [String] {
        [
            "analysis",
            "-model",
            configuration.modelURL.path,
            "-config",
            configuration.configURL.path,
        ]
    }

    func responses() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            withLock {
                if didFinishResponses {
                    if let responseFinishError {
                        continuation.finish(throwing: responseFinishError)
                    } else {
                        continuation.finish()
                    }
                } else {
                    self.continuation?.finish(
                        throwing: KataGoEngineError.startupFailed(
                            reason: "Response stream was replaced."
                        )
                    )
                    self.continuation = continuation
                }
            }
        }
    }

    func start() async throws {
        let shouldStart = withLock {
            if self.process != nil || isStarting {
                return false
            }
            isStarting = true
            return true
        }
        guard shouldStart else {
            return
        }

        let nextProcess = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        nextProcess.executableURL = configuration.executableURL
        nextProcess.arguments = launchArguments
        nextProcess.standardInput = stdinPipe
        nextProcess.standardOutput = stdoutPipe
        nextProcess.standardError = stderrPipe

        nextProcess.terminationHandler = { [weak self] process in
            self?.finishIfTerminated(process)
        }

        let stdoutTask = makeStdoutTask(stdoutPipe.fileHandleForReading)
        let stderrTask = makeStderrTask(stderrPipe.fileHandleForReading)

        withLock {
            self.process = nextProcess
            self.stdinPipe = stdinPipe
            self.stdoutTask = stdoutTask
            self.stderrTask = stderrTask
            self.stderrTail = ""
            self.isProcessLaunched = false
            self.didFinishResponses = false
            self.responseFinishError = nil
        }

        do {
            try nextProcess.run()
        } catch {
            withLock {
                stdoutTask.cancel()
                stderrTask.cancel()
                self.process = nil
                self.stdinPipe = nil
                self.isProcessLaunched = false
                isStarting = false
            }
            throw KataGoEngineError.startupFailed(reason: error.localizedDescription)
        }

        let shouldTerminateAfterLaunch = withLock {
            self.isProcessLaunched = true
            self.isStarting = false
            return self.process == nil || self.didFinishResponses
        }
        if shouldTerminateAfterLaunch, nextProcess.isRunning {
            nextProcess.terminate()
        }
    }

    func send(_ line: Data) async throws {
        guard let handle = withLock({ stdinPipe?.fileHandleForWriting }) else {
            throw KataGoEngineError.startupFailed(reason: "Process stdin is unavailable.")
        }

        do {
            try handle.write(contentsOf: line)
        } catch {
            throw KataGoEngineError.startupFailed(reason: error.localizedDescription)
        }
    }

    func stop() async {
        let process = withLock {
            isProcessLaunched ? self.process : nil
        }
        if process?.isRunning == true {
            process?.terminate()
        }
        withLock {
            stdoutTask?.cancel()
            stderrTask?.cancel()
            finishResponsesLocked(throwing: nil)
            self.stdinPipe = nil
            self.isStarting = false
            if self.process?.isRunning == false {
                self.process = nil
                self.isProcessLaunched = false
            }
        }
    }

    private func makeStdoutTask(_ handle: FileHandle) -> Task<Void, Never> {
        Task { [weak self] in
            do {
                for try await line in handle.bytes.lines {
                    guard let self else {
                        return
                    }
                    _ = withLock {
                        continuation?.yield(Data(line.utf8))
                    }
                }
            } catch {
                self?.withLock {
                    self?.finishResponsesLocked(throwing: error)
                }
            }
        }
    }

    private func makeStderrTask(_ handle: FileHandle) -> Task<Void, Never> {
        Task { [weak self] in
            do {
                for try await line in handle.bytes.lines {
                    self?.appendStderr(line)
                }
            } catch {
                self?.appendStderr(error.localizedDescription)
            }
        }
    }

    private func appendStderr(_ line: String) {
        withLock {
            stderrTail.append(line)
            stderrTail.append("\n")
            if stderrTail.count > 4096 {
                stderrTail.removeFirst(stderrTail.count - 4096)
            }
        }
    }

    private func finishIfTerminated(_ process: Process) {
        let exitCode = process.terminationStatus
        let stdoutTask = withLock { self.stdoutTask }
        let stderrTask = withLock { self.stderrTask }

        Task { [weak self] in
            if exitCode == 0 {
                await stdoutTask?.value
                self?.withLock {
                    self?.finishResponsesLocked(throwing: nil)
                    self?.process = nil
                    self?.stdinPipe = nil
                    self?.isStarting = false
                    self?.isProcessLaunched = false
                }
                return
            }

            await stderrTask?.value
            let tail = self?.withLock { self?.stderrTail } ?? ""
            self?.withLock {
                self?.finishResponsesLocked(
                    throwing: KataGoEngineError.engineTerminated(
                        exitCode: exitCode,
                        stderrTail: tail
                    )
                )
                self?.process = nil
                self?.stdinPipe = nil
                self?.isStarting = false
                self?.isProcessLaunched = false
            }
        }
    }

    private func finishResponsesLocked(throwing error: Error?) {
        guard didFinishResponses == false else {
            return
        }

        didFinishResponses = true
        responseFinishError = error
        if let error {
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }
        continuation = nil
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
#endif
