import FileWatcher
import Foundation
import SystemPackage
import Testing

@Suite("FileWatcher Tests", .serialized)
struct FileWatcherTests {
    @Test(.disabled()) func testEvents() async throws {
        let watcher = FileWatcher(paths: ["test"])
        try await withDeadline(deadline: .now + .seconds(120)) {
            try await watcher.watch { events in
                for try await event in events {
                    print(event)
                }
            }
        }
    }

    enum DeadlineError: Error {
        case operation(any Error)
        case timeout
    }
    func withDeadline<Value: Sendable>(
        deadline: ContinuousClock.Instant,
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(until: deadline)
                throw DeadlineError.timeout
            }
            let result = try await group.next()
            group.cancelAll()
            return result!
        }
    }

    @Test
    func testCreateFile() async throws {
        let tmpDir = FilePath(FileManager.default.temporaryDirectory.path).appending("testCreateFile")
        let tmpFile = tmpDir.appending("test.txt")
        try FileManager.default.createDirectory(atPath: tmpDir.string, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(atPath: tmpDir.string)
        }
        try await Task.sleep(for: .seconds(0.5))

        let watcher = FileWatcher(paths: [tmpDir])
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withDeadline(deadline: .now + .seconds(5)) {
                    try await watcher.watch { events in
                        try await watcher.watch { events in
                            for try await event in events {
                                if case .created(let file) = event {
                                    #expect(file.lastComponent == tmpFile.lastComponent)
                                    return
                                }
                            }
                        }
                    }
                }
            }
            try await Task.sleep(for: .seconds(1.0))
            // create and close file
            if let fd = fopen(tmpFile.string, "w") {
                fclose(fd)
            }

            try await group.waitForAll()
        }
        try FileManager.default.removeItem(atPath: tmpFile.string)
    }

    @Test
    func testModifyFile() async throws {
        let tmpDir = FilePath(FileManager.default.temporaryDirectory.path).appending("testModifyFile")
        let tmpFile = tmpDir.appending("test.txt")
        try FileManager.default.createDirectory(atPath: tmpDir.string, withIntermediateDirectories: true)
        try "hello".write(to: URL(string: tmpFile.string)!, atomically: false, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(atPath: tmpFile.string)
            try? FileManager.default.removeItem(atPath: tmpDir.string)
        }
        try await Task.sleep(for: .seconds(0.5))

        let watcher = FileWatcher(paths: [tmpDir])
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withDeadline(deadline: .now + .seconds(5)) {
                    try await watcher.watch { events in
                        try await watcher.watch { events in
                            for try await event in events {
                                if case .modified(let file) = event {
                                    #expect(file.lastComponent == tmpFile.lastComponent)
                                    return
                                }
                            }
                        }
                    }
                }
            }
            try await Task.sleep(for: .seconds(1.0))

            let fileHandle = FileHandle(forUpdatingAtPath: tmpFile.string)
            fileHandle?.write(.init("append some text".utf8))
            try fileHandle?.close()

            try await group.waitForAll()
        }
    }

    @Test
    func testDeleteFile() async throws {
        let tmpDir = FilePath(FileManager.default.temporaryDirectory.path).appending("testDeleteFile")
        let tmpFile = tmpDir.appending("test.txt")
        try FileManager.default.createDirectory(atPath: tmpDir.string, withIntermediateDirectories: true)
        try "hello".write(to: URL(string: tmpFile.string)!, atomically: false, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(atPath: tmpDir.string)
        }
        try await Task.sleep(for: .seconds(1))
        let watcher = FileWatcher(paths: [tmpDir])
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withDeadline(deadline: .now + .seconds(5)) {
                    try await watcher.watch { events in
                        for try await event in events {
                            if case .deleted(let file) = event {
                                #expect(file.lastComponent == tmpFile.lastComponent)
                                return
                            }
                        }
                    }
                }
            }
            try await Task.sleep(for: .seconds(1.0))

            try FileManager.default.removeItem(atPath: tmpFile.string)

            try await group.waitForAll()
        }
    }

    @Test
    func testMoveFile() async throws {
        let tmpDir = FilePath(FileManager.default.temporaryDirectory.path).appending("testMoveFile")
        let tmpFile = tmpDir.appending("test.txt")
        let tmpFile2 = tmpDir.appending("test2.txt")
        try FileManager.default.createDirectory(atPath: tmpDir.string, withIntermediateDirectories: true)
        try "hello".write(to: URL(string: tmpFile.string)!, atomically: false, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(atPath: tmpDir.string)
        }
        try await Task.sleep(for: .seconds(0.5))

        let watcher = FileWatcher(paths: [tmpDir])
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withDeadline(deadline: .now + .seconds(5)) {
                    try await watcher.watch { events in
                        for try await event in events {
                            if case .moved(let file) = event {
                                #expect(file.lastComponent == tmpFile.lastComponent || file.lastComponent == tmpFile2.lastComponent)
                                return
                            }
                        }
                    }
                }
            }
            try await Task.sleep(for: .seconds(1.0))
            try FileManager.default.moveItem(
                at: URL(filePath: tmpFile.string, directoryHint: .notDirectory),
                to: URL(filePath: tmpFile2.string, directoryHint: .notDirectory)
            )

            try await group.waitForAll()
        }
    }

    @Test
    func testMultipleFolders() async throws {
        let tmpDir = FilePath(FileManager.default.temporaryDirectory.path).appending("testMultipleFolders")
        let tmpDir2 = FilePath(FileManager.default.temporaryDirectory.path).appending("testMultipleFolders2")
        let tmpFile = tmpDir.appending("test.txt")
        let tmpFile2 = tmpDir2.appending("test2.txt")
        try FileManager.default.createDirectory(atPath: tmpDir.string, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: tmpDir2.string, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(atPath: tmpDir.string)
            try? FileManager.default.removeItem(atPath: tmpDir2.string)
        }
        try await Task.sleep(for: .seconds(0.5))

        let watcher = FileWatcher(paths: [tmpDir, tmpDir2])
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withDeadline(deadline: .now + .seconds(5)) {
                    try await watcher.watch { events in
                        try await watcher.watch { events in
                            var createdFiles = Set<String>()
                            var deletedFiles = Set<String>()
                            loop: for try await event in events {
                                switch event {
                                case .created(let file):
                                    guard let name = file.lastComponent else { continue }
                                    createdFiles.insert(name.string)
                                case .deleted(let file):
                                    guard let name = file.lastComponent else { continue }
                                    deletedFiles.insert(name.string)
                                    if deletedFiles.count == 2 {
                                        break loop
                                    }
                                default:
                                    break
                                }
                            }
                            #expect(createdFiles == ["test.txt", "test2.txt"])
                            #expect(deletedFiles == ["test.txt", "test2.txt"])
                        }
                    }
                }
            }
            try await Task.sleep(for: .seconds(1.0))

            try "hello".write(toFile: tmpFile.string, atomically: false, encoding: .utf8)
            try "hello".write(toFile: tmpFile2.string, atomically: false, encoding: .utf8)
            try FileManager.default.removeItem(atPath: tmpFile.string)
            try FileManager.default.removeItem(atPath: tmpFile2.string)

            try await group.waitForAll()
        }
    }

    @Test
    func testSubFolders() async throws {
        let tmpDir = FilePath(FileManager.default.temporaryDirectory.path).appending("testSubFolder")
        let subDir = tmpDir.appending("subDir")
        let tmpFile = subDir.appending("test.txt")
        try FileManager.default.createDirectory(atPath: subDir.string, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(atPath: subDir.string)
            try? FileManager.default.removeItem(atPath: tmpDir.string)
        }
        try await Task.sleep(for: .seconds(0.5))

        let watcher = FileWatcher(path: tmpDir)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withDeadline(deadline: .now + .seconds(5)) {
                    try await watcher.watch { events in
                        try await watcher.watch { events in
                            var createdFiles = Set<String>()
                            var deletedFiles = Set<String>()
                            loop: for try await event in events {
                                switch event {
                                case .created(let file):
                                    guard let name = file.lastComponent else { continue }
                                    createdFiles.insert(name.string)
                                case .deleted(let file):
                                    guard let name = file.lastComponent else { continue }
                                    deletedFiles.insert(name.string)
                                    if deletedFiles.count == 2 {
                                        break loop
                                    }
                                default:
                                    break
                                }
                            }
                            #expect(createdFiles == ["test.txt", "test2.txt"])
                            #expect(deletedFiles == ["test.txt", "test2.txt"])
                        }
                    }
                }
            }
            try await Task.sleep(for: .seconds(1.0))

            try "hello".write(toFile: tmpFile.string, atomically: false, encoding: .utf8)

            let subSubDir = subDir.appending("subSubDir")
            try FileManager.default.createDirectory(atPath: subSubDir.string, withIntermediateDirectories: true)
            defer {
                try? FileManager.default.removeItem(atPath: subSubDir.string)
            }
            let tmpFile2 = subSubDir.appending("test2.txt")

            try "hello".write(toFile: tmpFile2.string, atomically: false, encoding: .utf8)

            try FileManager.default.removeItem(atPath: tmpFile.string)
            try FileManager.default.removeItem(atPath: tmpFile2.string)

            try await group.waitForAll()
        }
    }
}
