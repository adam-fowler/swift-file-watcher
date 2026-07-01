//
// This source file is part of the FileWatcher project
// Copyright (c) the FileWatcher authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

#if os(macOS)

import CoreServices
import SystemPackage

final class MacOSFileWatcher: PlatformFileWatcher {
    let paths: [FilePath]
    let continuation: AsyncStream<FileWatcher.Event>.Continuation
    let dispatchQueue: DispatchQueue

    init(paths: [FilePath], continuation: AsyncStream<FileWatcher.Event>.Continuation) {
        self.paths = paths
        self.continuation = continuation
        self.dispatchQueue = DispatchQueue.global(qos: .background)
    }

    func watch() async throws {
        let filePaths = paths.map { $0.description }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: retainCallback,
            release: releaseCallback,
            copyDescription: nil
        )
        guard
            let streamRef = FSEventStreamCreate(
                kCFAllocatorDefault,
                eventCallback,
                &context,
                filePaths as! CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0,
                UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
            )
        else {
            throw FileWatcherError.failedToCreateFileEventStream
        }
        FSEventStreamSetDispatchQueue(streamRef, self.dispatchQueue)
        FSEventStreamStart(streamRef)

        let (stream, _) = AsyncStream.makeStream(of: Void.self)
        var iterator = stream.makeAsyncIterator()
        await iterator.next()

        FSEventStreamStop(streamRef)
        FSEventStreamInvalidate(streamRef)
        FSEventStreamRelease(streamRef)
    }

    /**
    * - Parameters:
    *    - streamRef: The stream for which event(s) occurred. clientCallBackInfo: The info field that was supplied in the context when this stream was created.
    *    - contextInfo: Client context info
    *    - numEvents:  The number of events being reported in this callback. Each of the arrays (eventPaths, eventFlags, eventIds) will have this many elements.
    *    - eventPaths: An array of paths to the directories in which event(s) occurred. The type of this parameter depends on the flags
    *    - eventFlags: An array of flag words corresponding to the paths in the eventPaths parameter. If no flags are set, then there was some change in the directory at the specific path supplied in this  event. See FSEventStreamEventFlags.
    *    - eventIds: An array of FSEventStreamEventIds corresponding to the paths in the eventPaths parameter. Each event ID comes from the most recent event being reported in the corresponding directory named in the eventPaths parameter.
    */
    let eventCallback: FSEventStreamCallback = {
        (
            stream: ConstFSEventStreamRef,
            contextInfo: UnsafeMutableRawPointer?,
            numEvents: Int,
            eventPaths: UnsafeMutableRawPointer,
            eventFlags: UnsafePointer<FSEventStreamEventFlags>,
            eventIds: UnsafePointer<FSEventStreamEventId>
        ) in
        let fileSystemWatcher = Unmanaged<MacOSFileWatcher>.fromOpaque(contextInfo!).takeUnretainedValue()
        let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]

        (0..<numEvents).indices.forEach { index in
            fileSystemWatcher.processEvent(paths[index], flags: eventFlags[index], id: eventIds[index])
        }
    }

    let retainCallback: CFAllocatorRetainCallBack = { (info: UnsafeRawPointer?) in
        _ = Unmanaged<MacOSFileWatcher>.fromOpaque(info!).retain()
        return info
    }

    let releaseCallback: CFAllocatorReleaseCallBack = { (info: UnsafeRawPointer?) in
        Unmanaged<MacOSFileWatcher>.fromOpaque(info!).release()
    }

    func processEvent(_ eventPath: String, flags: FSEventStreamEventFlags, id: FSEventStreamEventId) {
        print("\(id): \(eventPath), event: \(String(flags, radix: 16))")
        guard flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) == 0 else { return }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) != 0 {
            self.continuation.yield(.created(.init(eventPath)))
        }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified) != 0 {
            self.continuation.yield(.modified(.init(eventPath)))
        }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) != 0 {
            self.continuation.yield(.deleted(.init(eventPath)))
        }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed) != 0 {
            self.continuation.yield(.moved(.init(eventPath)))
        }
    }
}

#endif
