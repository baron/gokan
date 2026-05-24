// SPDX-License-Identifier: GPL-3.0-or-later

#if os(macOS)
import Foundation

internal final class ProcessKataGoTransport: KataGoTransport, @unchecked Sendable {
    private let configuration: KataGoEngineConfiguration
    private let lock = NSLock()
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var stderrTail = ""
    private var isStarting = false

    init(configuration: KataGoEngineConfiguration) {
        self.configuration = configuration
    }

    func responses() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            withLock {
                self.continuation = continuation
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
        nextProcess.arguments = [
            "analysis",
            "-model",
            configuration.modelURL.path,
            "-config",
            configuration.configURL.path,
        ]
        nextProcess.standardInput = stdinPipe
        nextProcess.standardOutput = stdoutPipe
        nextProcess.standardError = stderrPipe

        nextProcess.terminationHandler = { [weak self] process in
            self?.finishIfTerminated(process)
        }

        do {
            try nextProcess.run()
        } catch {
            withLock {
                isStarting = false
            }
            throw KataGoEngineError.startupFailed(reason: error.localizedDescription)
        }

        withLock {
            self.process = nextProcess
            self.stdinPipe = stdinPipe
            self.stdoutTask = makeStdoutTask(stdoutPipe.fileHandleForReading)
            self.stderrTask = makeStderrTask(stderrPipe.fileHandleForReading)
            self.isStarting = false
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
        let process = withLock { self.process }
        process?.terminate()
        withLock {
            stdoutTask?.cancel()
            stderrTask?.cancel()
            continuation?.finish()
            self.process = nil
            self.stdinPipe = nil
            self.isStarting = false
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
                self?.withLock {
                    self?.continuation?.finish()
                }
            } catch {
                self?.withLock {
                    self?.continuation?.finish(throwing: error)
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
        guard process.terminationStatus != 0 else {
            withLock {
                continuation?.finish()
            }
            return
        }

        let tail = withLock { stderrTail }
        withLock {
            continuation?.finish(
                throwing: KataGoEngineError.engineTerminated(
                    exitCode: process.terminationStatus,
                    stderrTail: tail
                )
            )
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
#endif
