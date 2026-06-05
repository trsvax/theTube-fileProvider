---
title: TubeFS
date: 2026-06-05
---

# TubeFS

A macOS/iOS app that mounts the tube as a native filesystem via Apple's FileProvider framework, with a Share Extension for capturing content from any app.

## What it does

1. **FileProvider** — the tube appears in Finder (macOS) and Files.app (iOS)
2. **Share Extension** — share sheet → capture to tube from any app, both platforms

One install, two extensions, one shared auth layer.

## Architecture

```
Shared/
  TubeRequest.swift              ← auth + network (Keychain, CryptoKit, URLSession)

TubeFileProvider/
  FileProviderExtension.swift    ← entry point, enumerator factory, fetch
  TubeItem.swift                 ← file/folder metadata
  TubeEnumerator.swift           ← lists items for a container
  ProviderRouter.swift           ← routes paths to providers
  Providers/
    AWSProvider.swift            ← aws/ subtree
    LogsProvider.swift           ← logs/ subtree
    TubeStorageProvider.swift    ← tube/ subtree

TubeShare/
  ShareViewController.swift      ← share sheet → fire capture → dismiss

TubeFS/
  TubeFSApp.swift                ← container app (minimal)
```

## The contract

Every provider implements:
- `list(path:) → [NSFileProviderItem]`
- `fetch(path:) → Data`

Providers call `TubeRequest.shared` which POSTs to `https://thetube.today/tube/{route}`.

## Auth

- JWT + secret in Keychain (shared app group: `group.com.thetube.fs`)
- Touch ID / Face ID on first access (system handles the prompt)
- Time-hash: `SHA256(secret + timestamp)` via CryptoKit
- No shell commands, no external processes

## The tube protocol

```
POST https://thetube.today/tube/{path}
Authorization: Bearer {jwt}
X-Pass: {sha256(secret + timestamp)}
X-Timestamp: {unix seconds}
Content-Type: application/json
```

200 = sync result. 202 = async (poll). 403 = auth failed.

## Namespace

```
/
  logs/
    {date}/
      {hour}.tsv
  aws/
    cloudfront/
    lambda/
    s3/
    cognito/
    iam/
  tube/
    locker/
    routes/
```

## Constraints

- Read-only filesystem (writes go through send-tube / share extension)
- No third-party dependencies (Foundation, CryptoKit, FileProvider, Security)
- Swift 5.9+, async/await, actors
- macOS 13+ / iOS 16+ (minimum for replicated FileProvider)
- No Spotlight indexing

## Build

```bash
./extract.sh        # pulls # src blocks from *.md into out/
open TubeFS.xcodeproj
```

## Related

- `trsvax/theTube-mcp` — Node WebDAV server (same namespace, same protocol)
- `trsvax/thetube-private` — Lambda source (ticket machine, processor)
- `trsvax/theTube` — Platform spec
