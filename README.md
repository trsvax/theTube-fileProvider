# theTube FileProvider

A macOS/iOS File Provider extension that mounts the tube as a native filesystem.

Browse AWS configs, CloudFront logs, lockers, and routes from Finder (macOS) or Files.app (iOS). Touch ID / Face ID to authenticate.

## How it works

The extension implements Apple's FileProvider framework. The tube appears alongside iCloud Drive in Finder/Files. No localhost server, no `mount` command — the system manages the mount.

```
~/Library/CloudStorage/TubeFS/
  logs/
    2026-05-21/
      00.tsv
      01.tsv
  aws/
    cloudfront/
      general.json
      behaviors/
    lambda/
    s3/
  tube/
    locker/
    routes/
```

## Architecture

```
TubeFS/
  TubeFSApp/                    Container app (status, preferences)
  TubeFileProvider/             File Provider extension
    FileProviderExtension.swift   Root — domain setup, enumerator factory
    FileProviderEnumerator.swift  List items for a path
    FileProviderItem.swift        Metadata for each file/folder
    TubeRequest.swift             URLSession + native Keychain (CryptoKit)
    Providers/
      ContentProvider.swift
      LogsProvider.swift
      CloudFrontProvider.swift
      LambdaProvider.swift
      S3Provider.swift
      TubeProvider.swift
```

## Auth

JWT and secret stored in Keychain. Touch ID (macOS) or Face ID (iOS) on first access. `CryptoKit` computes the time-hash natively. No shell commands, no external processes.

## The tube protocol

Same as the Node WebDAV server and `send-tube`:

```
POST https://thetube.today/tube/{path}
Authorization: Bearer {jwt}
X-Pass: {sha256(secret + timestamp)}
X-Timestamp: {unix seconds}
Content-Type: application/json

{params}
```

200 = sync result. 202 = async (poll result URL). The FileProvider extension handles both transparently.

## Providers

Each provider maps a path prefix to tube requests:

| Path | Tube route | What |
|------|-----------|------|
| `/logs/{date}` | `aws/list-log-hours` | CloudFront log hours |
| `/logs/{date}/{hour}.tsv` | `aws/get-log-content` | Log content |
| `/aws/cloudfront/` | `aws/describe-cloudfront` | Distribution config |
| `/aws/lambda/` | `aws/list-lambdas` | Function list |
| `/tube/locker/` | `aws/list-tube-apps` | Locker contents |
| `/tube/routes/` | `aws/list-tube-files` | Route registry |

## Related

- `trsvax/theTube-mcp` — Node WebDAV server (same providers, same protocol)
- `trsvax/thetube-private` — Lambda source (ticket machine, processor)
- `trsvax/theTube-share` — Share system spec

## Status

Scaffolding. The Node WebDAV server is the working prototype. This is the native version.
