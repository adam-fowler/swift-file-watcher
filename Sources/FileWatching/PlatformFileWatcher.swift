//
// This source file is part of the FileWatcher project
// Copyright (c) the FileWatcher authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//
import SystemPackage

protocol PlatformFileWatcher: Sendable {
    init(paths: [FilePath], continuation: AsyncStream<FileWatcher.Event>.Continuation)
    func watch() async throws
}
