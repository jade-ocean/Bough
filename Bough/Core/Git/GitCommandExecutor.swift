import Foundation

/// Per-repository command executor.
///
/// Actor-serialized: all git invocations for one repository queue up, which
/// sidesteps index.lock contention entirely (reads included - acceptable for
/// phase 2; read/write splitting is deferred to the perf phase).
///
/// Captures stdout/stderr via pipes with readabilityHandler accumulation,
/// enforces a timeout, and propagates Task cancellation to the child process.
actor GitCommandExecutor {
    private let gitBinary: String
    private let workingDirectory: URL

    init(gitBinary: String, workingDirectory: URL) {
        self.gitBinary = gitBinary
        self.workingDirectory = workingDirectory
    }

    // MARK: - Output buffer (handler runs on an arbitrary queue)

    private final class PipeBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) {
            lock.lock()
            defer { lock.unlock() }
            data.append(chunk)
        }

        func snapshot() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    // MARK: - Execution

    /// Reentrancy gate: `await` on process exit releases the actor, so two
    /// callers could otherwise run git processes concurrently (index.lock
    /// races). The gate holds the actor busy until the process finishes.
    private var gateIsRunning = false
    private var gateWaiters: [CheckedContinuation<Void, Never>] = []

    private func acquireGate() async {
        if !gateIsRunning {
            gateIsRunning = true
            return
        }
        await withCheckedContinuation { gateWaiters.append($0) }
    }

    private func releaseGate() {
        if gateWaiters.isEmpty {
            gateIsRunning = false
        } else {
            gateWaiters.removeFirst().resume()
        }
    }

    func run(_ command: GitCommand) async throws -> GitResult {
        try Task.checkCancellation()
        await acquireGate()
        defer { releaseGate() }
        let started = DispatchTime.now()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitBinary)
        process.arguments = ["--no-pager", "-c", "core.quotepath=false"] + command.arguments
        process.currentDirectoryURL = workingDirectory
        setupEnvironment(process, extra: command.extraEnvironment)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        if let stdinData = command.stdinData {
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe
            stdinPipe.fileHandleForWriting.write(stdinData)
            stdinPipe.fileHandleForWriting.closeFile()
        } else {
            process.standardInput = FileHandle.nullDevice
        }

        let stdoutBuffer = PipeBuffer()
        let stderrBuffer = PipeBuffer()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handler in
            let chunk = handler.availableData
            if chunk.isEmpty {
                handler.readabilityHandler = nil
            } else {
                stdoutBuffer.append(chunk)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handler in
            let chunk = handler.availableData
            if chunk.isEmpty {
                handler.readabilityHandler = nil
            } else {
                stderrBuffer.append(chunk)
            }
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let box = ResumeBox()
                let commandDescription = command.arguments.joined(separator: " ")
                let handler = ProcessTerminationHandler(process: process, box: box,
                                                        commandDescription: commandDescription,
                                                        started: started,
                                                        stdoutBuffer: stdoutBuffer,
                                                        stderrBuffer: stderrBuffer)
                box.resumeHandler = { result in
                    handler.invalidateTimer()
                    continuation.resume(returning: result)
                }
                box.throwingResumeHandler = { error in
                    handler.invalidateTimer()
                    continuation.resume(throwing: error)
                }
                do {
                    try process.run()
                } catch {
                    box.throw(GitError.executionFailed(
                        command: commandDescription,
                        exitCode: -1,
                        stderr: String(describing: error)))
                }
                handler.scheduleTimeout(seconds: command.timeout)
            }
        } onCancel: {
            process.terminate()
        }
    }

    /// Fires the resume exactly once (spawn failure / termination race).
    private final class ResumeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var resumed = false
        var resumeHandler: ((GitResult) -> Void)?
        var throwingResumeHandler: ((Error) -> Void)?

        func resume(_ result: GitResult) {
            lock.lock()
            defer { lock.unlock() }
            guard !resumed else { return }
            resumed = true
            resumeHandler?(result)
        }

        func `throw`(_ error: Error) {
            lock.lock()
            defer { lock.unlock() }
            guard !resumed else { return }
            resumed = true
            throwingResumeHandler?(error)
        }
    }

    /// Owns the timeout timer for one run; invalidate on completion.
    private final class ProcessTerminationHandler {
        private let process: Process
        private let box: ResumeBox
        private let commandDescription: String
        private let started: DispatchTime
        private let stdoutBuffer: PipeBuffer
        private let stderrBuffer: PipeBuffer
        private let timer: DispatchSourceTimer
        private let lock = NSLock()
        private var finished = false
        private var timedOut = false

        init(process: Process, box: ResumeBox, commandDescription: String, started: DispatchTime,
             stdoutBuffer: PipeBuffer, stderrBuffer: PipeBuffer) {
            self.process = process
            self.box = box
            self.commandDescription = commandDescription
            self.started = started
            self.stdoutBuffer = stdoutBuffer
            self.stderrBuffer = stderrBuffer
            self.timer = DispatchSource.makeTimerSource(queue: .global())
        }

        func scheduleTimeout(seconds: TimeInterval) {
            timer.schedule(deadline: .now() + seconds)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                self.lock.lock()
                self.timedOut = true
                self.lock.unlock()
                self.process.terminate()
            }
            timer.resume()
            process.terminationHandler = { [weak self] process in
                self?.finish(process: process)
            }
        }

        func invalidateTimer() {
            timer.cancel()
        }

        private func finish(process: Process) {
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            finished = true
            lock.unlock()

            timer.cancel()
            process.terminationHandler = nil
            let duration = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000_000
            let result = GitResult(
                exitCode: process.terminationStatus,
                stdout: stdoutBuffer.snapshot(),
                stderr: String(decoding: stderrBuffer.snapshot(), as: UTF8.self),
                duration: duration
            )
            if process.terminationReason == .uncaughtSignal {
                lock.lock()
                let timedOut = self.timedOut
                lock.unlock()
                if timedOut {
                    box.throw(GitError.timedOut(command: commandDescription))
                } else {
                    box.throw(GitError.cancelled(command: commandDescription))
                }
            } else {
                box.resume(result)
            }
        }
    }

    private func setupEnvironment(_ process: Process, extra: [String: String]) {
        var env = ProcessInfo.processInfo.environment
        // Stable, non-localized parsing; avoid opportunistic index.lock side effects.
        env["LC_ALL"] = "en_US.UTF-8"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        for (key, value) in extra { env[key] = value }
        process.environment = env
    }
}
