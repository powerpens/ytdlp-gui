import Foundation

enum ProcessRunnerError: Error {
    case executableNotFound(String)
}

struct ProcessRunnerResult {
    let output: String
    let terminationStatus: Int32
}

enum ProcessRunner {
    static func run(_ executable: String, arguments: [String]) throws -> String {
        try runResult(executable, arguments: arguments).output
    }

    static func runResult(_ executable: String, arguments: [String]) throws -> ProcessRunnerResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return ProcessRunnerResult(
            output: String(decoding: data, as: UTF8.self),
            terminationStatus: process.terminationStatus
        )
    }

    static func which(_ command: String) -> String? {
        guard let output = try? run("/usr/bin/which", arguments: [command]) else {
            return nil
        }

        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}
