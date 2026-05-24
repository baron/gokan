// SPDX-License-Identifier: GPL-3.0-or-later

#if os(macOS)
import Dispatch
import Foundation

internal enum StartupReadinessPolicy: Sendable {
    case disabled
    case stderrBanner(String, timeoutSeconds: TimeInterval)

    static let kataGoDefault: StartupReadinessPolicy = .stderrBanner(
        "Started, ready to begin handling requests",
        timeoutSeconds: 30
    )
}

internal final class ProcessKataGoTransport: KataGoTransport, @unchecked Sendable {
    private struct StartupWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private let configuration: KataGoEngineConfiguration
    private let launchArguments: [String]
    private let readinessPolicy: StartupReadinessPolicy
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
    private var isReadyForSends = false
    private var startupResolution: Result<Void, Error>?
    private var startupWaiters: [StartupWaiter] = []
    private var readinessTimeoutTask: Task<Void, Never>?

    convenience init(configuration: KataGoEngineConfiguration) {
        self.init(
            configuration: configuration,
            launchArguments: Self.defaultLaunchArguments(for: configuration),
            readinessPolicy: .kataGoDefault
        )
    }

    internal init(
        configuration: KataGoEngineConfiguration,
        launchArguments: [String],
        readinessPolicy: StartupReadinessPolicy = .disabled
    ) {
        self.configuration = configuration
        self.launchArguments = launchArguments
        self.readinessPolicy = readinessPolicy
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
            isReadyForSends = false
            startupResolution = nil
            startupWaiters.removeAll()
            readinessTimeoutTask?.cancel()
            readinessTimeoutTask = nil
            return true
        }
        guard shouldStart else {
            try await awaitStartupReadiness()
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
            let startupError = KataGoEngineError.startupFailed(reason: error.localizedDescription)
            withLock {
                stdoutTask.cancel()
                stderrTask.cancel()
                finishResponsesLocked(throwing: startupError)
                self.process = nil
                self.stdinPipe = nil
                self.isReadyForSends = false
                self.isProcessLaunched = false
                isStarting = false
            }
            resolveStartup(.failure(startupError))
            throw startupError
        }

        let shouldTerminateAfterLaunch = withLock {
            self.isProcessLaunched = true
            self.isStarting = false
            return self.process == nil || self.didFinishResponses
        }
        if shouldTerminateAfterLaunch, nextProcess.isRunning {
            nextProcess.terminate()
        }

        switch readinessPolicy {
        case .disabled:
            resolveStartup(.success(()))
        case .stderrBanner:
            beginReadinessTimeoutIfNeeded()
            try await awaitStartupReadiness()
        }
    }

    func send(_ line: Data) async throws {
        let state = withLock {
            (
                startupResolution: startupResolution,
                isReadyForSends: isReadyForSends,
                handle: stdinPipe?.fileHandleForWriting
            )
        }

        guard let handle = state.handle else {
            throw KataGoEngineError.startupFailed(reason: "Process stdin is unavailable.")
        }

        if case .failure(let error) = state.startupResolution {
            throw error
        }

        guard state.isReadyForSends else {
            throw KataGoEngineError.startupFailed(
                reason: "KataGo process is not ready to receive requests."
            )
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
        let waiters = withLock {
            readinessTimeoutTask?.cancel()
            readinessTimeoutTask = nil
            let waiters: [StartupWaiter]
            if startupResolution == nil {
                startupResolution = .failure(CancellationError())
                waiters = startupWaiters
                startupWaiters.removeAll()
            } else {
                waiters = []
            }
            return waiters
        }
        resume(waiters, with: .failure(CancellationError()))
        withLock {
            stdoutTask?.cancel()
            stderrTask?.cancel()
            finishResponsesLocked(throwing: nil)
            self.stdinPipe = nil
            self.isReadyForSends = false
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
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    var pending = Data()

                    while true {
                        let data = handle.availableData
                        if data.isEmpty {
                            break
                        }

                        for byte in data {
                            if byte == 0x0A {
                                self?.appendStderr(String(decoding: pending, as: UTF8.self))
                                pending.removeAll(keepingCapacity: true)
                                continue
                            }

                            pending.append(byte)
                            if pending.count > 4096 {
                                pending.removeFirst(pending.count - 4096)
                            }
                            self?.observeStderrFragment(String(decoding: pending, as: UTF8.self))
                        }
                    }

                    if pending.isEmpty == false {
                        self?.appendStderr(String(decoding: pending, as: UTF8.self))
                    }

                    continuation.resume()
                }
            }
        }
    }

    private func observeStderrFragment(_ fragment: String) {
        guard case .stderrBanner(let banner, _) = readinessPolicy, fragment.contains(banner) else {
            return
        }
        resolveStartup(.success(()))
    }

    private func appendStderr(_ line: String) {
        let didObserveReadiness = withLock {
            stderrTail.append(line)
            stderrTail.append("\n")
            if stderrTail.count > 4096 {
                stderrTail.removeFirst(stderrTail.count - 4096)
            }

            guard case .stderrBanner(let banner, _) = readinessPolicy else {
                return false
            }
            return line.contains(banner)
        }

        if didObserveReadiness {
            resolveStartup(.success(()))
        }
    }

    private func finishIfTerminated(_ process: Process) {
        let exitCode = process.terminationStatus
        let stdoutTask = withLock { self.stdoutTask }
        let stderrTask = withLock { self.stderrTask }

        Task { [weak self] in
            if exitCode == 0 {
                await stdoutTask?.value
                guard let self else {
                    return
                }
                let startupError = KataGoEngineError.startupFailed(
                    reason: "KataGo exited before emitting readiness banner."
                )
                let shouldFailStartup = withLock {
                    startupResolution == nil && readinessPolicy.requiresReadinessBanner
                }
                if shouldFailStartup {
                    failStartup(startupError, terminateProcess: false)
                }
                withLock {
                    finishResponsesLocked(throwing: shouldFailStartup ? startupError : nil)
                    self.process = nil
                    stdinPipe = nil
                    isReadyForSends = false
                    isStarting = false
                    isProcessLaunched = false
                }
                return
            }

            await stderrTask?.value
            guard let self else {
                return
            }
            let tail = withLock { stderrTail }
            let terminationError = KataGoEngineError.engineTerminated(
                exitCode: exitCode,
                stderrTail: tail
            )
            if withLock({ startupResolution == nil }) {
                failStartup(terminationError, terminateProcess: false)
            }
            withLock {
                finishResponsesLocked(throwing: terminationError)
                self.process = nil
                stdinPipe = nil
                isReadyForSends = false
                isStarting = false
                isProcessLaunched = false
            }
        }
    }

    private func beginReadinessTimeoutIfNeeded() {
        guard case .stderrBanner(let banner, let timeoutSeconds) = readinessPolicy else {
            return
        }

        let task = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            } catch {
                return
            }
            guard Task.isCancelled == false else {
                return
            }
            self?.failStartup(
                KataGoEngineError.startupFailed(
                    reason: "Timed out waiting for KataGo readiness banner: \(banner)"
                ),
                terminateProcess: true
            )
        }

        let shouldCancel = withLock {
            guard startupResolution == nil else {
                return true
            }
            readinessTimeoutTask = task
            return false
        }
        if shouldCancel {
            task.cancel()
        }
    }

    private func awaitStartupReadiness() async throws {
        let currentResolution = withLock { startupResolution }
        if let currentResolution {
            try currentResolution.get()
            return
        }

        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var shouldFailForCancellation = false
                let resolution: Result<Void, Error>? = withLock {
                    if let startupResolution {
                        return startupResolution
                    }
                    if Task.isCancelled {
                        shouldFailForCancellation = true
                        return .failure(CancellationError())
                    }
                    startupWaiters.append(
                        StartupWaiter(id: waiterID, continuation: continuation)
                    )
                    return nil
                }

                if shouldFailForCancellation {
                    failStartup(CancellationError(), terminateProcess: true)
                }

                if let resolution {
                    continuation.resume(with: resolution)
                }
            }
        } onCancel: {
            cancelStartup(id: waiterID)
        }
    }

    private func failStartup(_ error: Error, terminateProcess: Bool) {
        let state = withLock {
            guard startupResolution == nil else {
                return (
                    waiters: [StartupWaiter](),
                    process: Optional<Process>.none
                )
            }

            readinessTimeoutTask?.cancel()
            readinessTimeoutTask = nil
            startupResolution = .failure(error)
            isReadyForSends = false
            let waiters = startupWaiters
            startupWaiters.removeAll()
            finishResponsesLocked(throwing: error)
            return (
                waiters: waiters,
                process: terminateProcess && isProcessLaunched ? process : nil
            )
        }

        resume(state.waiters, with: .failure(error))

        if state.process?.isRunning == true {
            state.process?.terminate()
        }
    }

    private func resolveStartup(_ result: Result<Void, Error>) {
        let waiters = withLock {
            guard startupResolution == nil else {
                return [StartupWaiter]()
            }

            readinessTimeoutTask?.cancel()
            readinessTimeoutTask = nil
            startupResolution = result
            if case .success = result {
                isReadyForSends = true
            } else {
                isReadyForSends = false
            }
            let waiters = startupWaiters
            startupWaiters.removeAll()
            return waiters
        }

        resume(waiters, with: result)
    }

    private func cancelStartup(id: UUID) {
        let shouldCancelStartup = withLock {
            startupResolution == nil && startupWaiters.contains { $0.id == id }
        }

        if shouldCancelStartup {
            failStartup(CancellationError(), terminateProcess: true)
        }
    }

    private func resume(
        _ waiters: [StartupWaiter],
        with result: Result<Void, Error>
    ) {
        for waiter in waiters {
            waiter.continuation.resume(with: result)
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

private extension StartupReadinessPolicy {
    var requiresReadinessBanner: Bool {
        switch self {
        case .disabled:
            false
        case .stderrBanner:
            true
        }
    }
}
#endif
