import FileWatcher
import Foundation
import SystemPackage
import Testing

struct FileWatcherTests {
    @Test func testEvents() async throws {
        let watcher = FileWatcher(paths: ["test"])
        try await watcher.watch { events in
            for try await event in events {
                print(event)
            }
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
        let watcher = FileWatcher(paths: [tmpDir])
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await watcher.watch { events in
                    var iterator = events.makeAsyncIterator()
                    let event = await iterator.next()
                    guard case .added(let file) = event else {
                        Issue.record()
                        return
                    }
                    #expect(file.lastComponent == tmpFile.lastComponent)
                }
            }
            try await Task.sleep(for: .seconds(0.5))
            try "hello".write(to: URL(string: tmpFile.string)!, atomically: false, encoding: .utf8)
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
        let watcher = FileWatcher(paths: [tmpDir])
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await watcher.watch { events in
                    var iterator = events.makeAsyncIterator()
                    let event = await iterator.next()
                    guard case .changed(let file) = event else {
                        Issue.record()
                        return
                    }
                    #expect(file.lastComponent == tmpFile.lastComponent)
                }
            }
            try await Task.sleep(for: .seconds(0.5))
            let fileHandle = try FileHandle(forWritingTo: URL(string: tmpFile.string)!)
            try fileHandle.seekToEnd()
            fileHandle.write("append some text".data(using: .utf8)!)
            try fileHandle.close()
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
        let watcher = FileWatcher(paths: [tmpDir])
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await watcher.watch { events in
                    var iterator = events.makeAsyncIterator()
                    let event = await iterator.next()
                    guard case .deleted(let file) = event else {
                        Issue.record()
                        return
                    }
                    #expect(file.lastComponent == tmpFile.lastComponent)
                }
            }
            try await Task.sleep(for: .seconds(0.5))
            try FileManager.default.removeItem(atPath: tmpFile.string)
        }
    }
}
