# AGENTS.md

Guidance for automated agents working in this repository.

## Don't make assumptions. If you don't know something, say so.

---

## Project Overview

`theTube-fileProvider` is a macOS/iOS File Provider extension that exposes the tube as a native filesystem. It appears in Finder (macOS) and Files.app (iOS) alongside iCloud Drive.

This is the native Swift equivalent of the Node WebDAV server in `trsvax/theTube-mcp/webdav/`.

---

## Architecture

```
TubeFS/
  TubeFSApp/                    Container app
  TubeFileProvider/             File Provider extension
    FileProviderExtension.swift
    FileProviderEnumerator.swift
    FileProviderItem.swift
    TubeRequest.swift
    Providers/
```

## The contract

Every provider implements:
- `list(path) → [FileProviderItem]` — enumerate children
- `read(path) → Data` — fetch file contents

Providers call `TubeRequest` which POSTs to `https://thetube.today/tube/{route}` with P-256 signature from device key.

## Auth

- P-256 private key in Keychain (shared app group), protected by access control
- Touch ID / Face ID triggered by Keychain access control on the private key
- Signs: `method + path + timestamp + body_hash` → `X-Signature` header
- `X-Device-Id` + `X-Timestamp` headers identify and timestamp the request
- No shared secrets, no tokens, no shell commands

## Related repos

- `trsvax/theTube-mcp` — Node WebDAV server (same providers, same protocol)
- `trsvax/thetube-private` — Lambda source (ticket machine, processor)
- `trsvax/theTube` — Platform spec, AGENTS.md

## Build

Open `TubeFS.xcodeproj` in Xcode. Build the container app target — the extension builds automatically.

## Code conventions

- Swift 5.9+, async/await throughout
- No third-party dependencies (Foundation, CryptoKit, FileProvider framework only)
- Structured concurrency (actors for shared state)
- Each provider is a standalone struct conforming to `TubeProvider` protocol

_Last updated: 2026-06-19_
