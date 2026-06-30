//
// This source file is part of the FileWatcher project
// Copyright (c) the FileWatcher authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//
import SystemPackage

public struct FileWatcher: Sendable {
    public enum Event: Equatable {
        case added(FilePath)
        case deleted(FilePath)
        case changed(FilePath)
    }
    public let paths: [FilePath]

    public init(paths: [FilePath]) {
        self.paths = paths
    }

    public func watch<Value>(_ operation: @Sendable @escaping (AsyncStream<Event>) async throws -> Value) async throws -> Value {
        let (stream, cont) = AsyncStream.makeStream(of: Event.self)

        #if os(macOS)
        let fileWatcher = MacOSFileWatcher(paths: self.paths, continuation: cont)
        #elseif os(Linux)
        let fileWatcher = LinuxFileWatcher(paths: self.paths, continuation: cont)
        #else
        #error("Unsupported platform")
        #endif

        return try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await fileWatcher.watch()
            }
            let value = try await operation(stream)
            group.cancelAll()
            return value
        }
    }

}
