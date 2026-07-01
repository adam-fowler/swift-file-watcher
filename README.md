# FileWatcher

Watch for filesystem changes.

## Overview

Watching for changes in a file system folder is a OS specific operation. FileWatcher provides a standard API for doing this on both Linux and macOS.

## Usage

To watch for changes in a folder you create a `FileWatcher` referencing that folder and then call the `watch` function. The closure you provide to `watch` will receive all the file system change events that occur in that folder.

```swift
let fileWatcher = FileWatcher(path: "test")
try await fileWatcher.watch { events in
    for try await event in events {
        switch event {
        case .created(let file):
            print("Created \(file)")
        case .modified(let file):
            print("Modified \(file)")
        case .deleted(let file):
            print("Deleted \(file)")
        case .moved(let file):
            print("Moved \(file)")
        }
        print(event)
    }
}
```

You can watch for changes in multiple folders by initializing your `FileWatcher` with multiple paths

```
let fileWatcher = FileWatcher(paths: ["test", "test2"])
```

### Considerations

FileWatcher provides you with the raw stream of file system events. It does not attempt to massage the data. So operations like delete on a macOS in many cases will be reported as a move (delete moves the file to waste basket). File operations on macOS that modify a file can sometimes also report a created event.
