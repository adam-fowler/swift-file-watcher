//
// This source file is part of the FileWatcher project
// Copyright (c) the FileWatcher authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

public struct FileWatcherError: Error {
    enum Internal {
        case failedToCreateFileEventStream
    }

    let value: Internal

    public static var failedToCreateFileEventStream: Self { .init(value: .failedToCreateFileEventStream) }
}
