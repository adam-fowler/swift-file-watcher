//
// This source file is part of the FileWatcher project
// Copyright (c) the FileWatcher authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

#if os(Linux)

import CInotify
import Dispatch
import FoundationEssentials
import Synchronization
import SystemPackage

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#else
#error("Unsupported platform")
#endif

final class LinuxFileWatcher: PlatformFileWatcher {
    let paths: [FilePath]
    let continuation: AsyncStream<FileWatcher.Event>.Continuation
    let dispatchQueue: DispatchQueue
    let shouldStopWatching: Atomic<Bool>

    init(paths: [FilePath], continuation: AsyncStream<FileWatcher.Event>.Continuation) {
        self.paths = paths
        self.continuation = continuation
        self.dispatchQueue = DispatchQueue.global(qos: .background)
        self.shouldStopWatching = .init(false)
    }

    func watch() async throws {
        dispatchQueue.async {
            var process = FileWatcherProcess(parent: self)
            process.watch()
        }

        let (stream, _) = AsyncStream.makeStream(of: Void.self)
        var iterator = stream.makeAsyncIterator()
        await iterator.next()

        self.shouldStopWatching.store(true, ordering: .relaxed)
    }

    struct FileWatcherProcess {
        var pathToDescriptor: [FilePath: Int32]
        var descriptorToPath: [Int32: FilePath]
        let fileDescriptor: Int32
        let parent: LinuxFileWatcher

        init(parent: LinuxFileWatcher) {
            self.descriptorToPath = [:]
            self.pathToDescriptor = [:]
            self.fileDescriptor = inotify_init()
            self.parent = parent
        }

        mutating func watch() {
            let eventMask: InotifyEventMask = [.inCreate, .inMovedTo, .inDelete, .inDeleteSelf, .inMovedFrom, .inModify, .inMoveSelf]
            for path in parent.paths {
                watchPathRecursive(path: path, for: eventMask)
            }

            let bufferLength: Int = MemoryLayout<inotify_event>.size + Int(NAME_MAX) + 1
            let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferLength)

            while !self.parent.shouldStopWatching.load(ordering: .relaxed) {
                var currentIndex: Int = 0
                let readLength = read(fileDescriptor, buffer, bufferLength)

                while currentIndex < readLength {
                    let event = withUnsafePointer(to: &buffer[currentIndex]) {
                        $0.withMemoryRebound(to: inotify_event.self, capacity: 1) {
                            $0.pointee
                        }
                    }

                    if event.len > 0 {
                        let filename = String(cString: buffer + currentIndex + MemoryLayout<inotify_event>.size)

                        if let folderName = self.descriptorToPath[event.wd] {
                            let iNotifyEventMask = InotifyEventMask(rawValue: event.mask)
                            if iNotifyEventMask.contains(.inIsDir) {
                                // Add path to watch if directory is created, or moved into a watched folder.
                                if !iNotifyEventMask.intersection([.inCreate, .inMovedTo]).isEmpty {
                                    self.watchPath(path: folderName.appending(filename), for: eventMask)
                                    // Remove watched path if directory is deleted or moved out of watched directory
                                } else if !iNotifyEventMask.intersection([.inDelete, .inDeleteSelf, .inMovedFrom]).isEmpty {
                                    self.unwatchPath(path: folderName.appending(filename))
                                }
                            } else {
                                if !iNotifyEventMask.intersection([.inModify]).isEmpty {
                                    parent.continuation.yield(.changed(folderName.appending(filename)))
                                } else if !iNotifyEventMask.intersection([.inCreate]).isEmpty {
                                    parent.continuation.yield(.added(folderName.appending(filename)))
                                } else if !iNotifyEventMask.intersection([.inDelete, .inDeleteSelf]).isEmpty {
                                    parent.continuation.yield(.deleted(folderName.appending(filename)))
                                } else if !iNotifyEventMask.intersection([.inMovedTo, .inMovedFrom]).isEmpty {
                                    parent.continuation.yield(.moved(folderName.appending(filename)))
                                }
                            }
                        }
                    }

                    currentIndex += MemoryLayout<inotify_event>.stride + Int(event.len)
                }
            }

            for watchDescriptor in self.pathToDescriptor.values {
                inotify_rm_watch(fileDescriptor, watchDescriptor)
            }
            self.descriptorToPath = [:]
            self.pathToDescriptor = [:]

            close(fileDescriptor)
        }

        mutating func watchPathRecursive(path: FilePath, for mask: InotifyEventMask) {
            watchPath(path: path, for: mask)
            // check for sub-directories
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: path.string) else { return }
            for file in files {
                var isDir: Bool = false
                let fullPath = path.appending(file)
                if FileManager.default.fileExists(atPath: "\(path)/\(file)", isDirectory: &isDir) && isDir {
                    watchPathRecursive(path: fullPath, for: mask)
                }
            }
        }

        mutating func watchPath(path: FilePath, for mask: InotifyEventMask) {
            guard self.pathToDescriptor[path] == nil else { return }
            print("Watch: \(path)")
            let wd = inotify_add_watch(fileDescriptor, path.string, mask.rawValue)
            self.pathToDescriptor[path] = wd
            self.descriptorToPath[wd] = path
        }

        mutating func unwatchPath(path: FilePath) {
            guard let wd = self.pathToDescriptor[path] else { return }
            _ = inotify_rm_watch(fileDescriptor, wd)
            self.pathToDescriptor.removeValue(forKey: path)
            self.descriptorToPath.removeValue(forKey: wd)
        }
    }
}

struct InotifyEventMask: OptionSet {
    let rawValue: UInt32

    static var inAccess: Self { .init(rawValue: 0x0000_0001) }  // File was accessed
    static var inModify: Self { .init(rawValue: 0x0000_0002) }  // File was modified
    static var inAttrib: Self { .init(rawValue: 0x0000_0004) }  // Metadata changed

    static var inCloseWrite: Self { .init(rawValue: 0x0000_0008) }  // Closed after opened for writing
    static var inCloseNoWrite: Self { .init(rawValue: 0x0000_0010) }  // Closed after opening for reading
    static var inClose: Self { .init(rawValue: 0x0000_0018) }  // Closed (independent of mode)

    static var inOpen: Self { .init(rawValue: 0x0000_0020) }  // File opened
    static var inMovedFrom: Self { .init(rawValue: 0x0000_0040) }  // Old file before move
    static var inMovedTo: Self { .init(rawValue: 0x0000_0080) }  // New file after move
    static var inMove: Self { .init(rawValue: 0x0000_00C0) }  // On any move event

    static var inCreate: Self { .init(rawValue: 0x0000_0100) }  // New file created
    static var inDelete: Self { .init(rawValue: 0x0000_0200) }  // File deleted
    static var inDeleteSelf: Self { .init(rawValue: 0x0000_0400) }  // File itself was deleted
    static var inMoveSelf: Self { .init(rawValue: 0x0000_0800) }  // File itself was moved

    static var inUnmount: Self { .init(rawValue: 0x0000_2000) }  // FS was unmounted
    static var inQueueOverflow: Self { .init(rawValue: 0x0000_4000) }  // Queue overflowed
    static var inIgnored: Self { .init(rawValue: 0x0000_8000) }  // Watch for file removed

    static var inOnlyDir: Self { .init(rawValue: 0x0100_0000) }  // Set to only watch if is a dir
    static var inDontFollow: Self { .init(rawValue: 0x0200_0000) }  // Dont watch if is symlink
    static var inExcludeUnlink: Self { .init(rawValue: 0x0400_0000) }  // Ignore events for children if not applicable

    static var inMaskAdd: Self { .init(rawValue: 0x2000_0000) }  // Dont overwrite watch masks

    static var inIsDir: Self { .init(rawValue: 0x4000_0000) }  // File is a directory
    static var inOneShot: Self { .init(rawValue: 0x8000_0000) }  // Only watch for changes once

    static var inAllEvents: Self { .init(rawValue: 0x0000_0FFF) }  // Meta value to watch all events
}
#endif
