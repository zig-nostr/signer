**Signet** — a native NIP-46 remote signer for Nostr. macOS, **ad-hoc signed (not notarized)**.

### Install

Download the `Signet-*-macos.zip` asset below, unzip it, and move `Signet.app` to `/Applications`.

Because Signet isn't notarized, macOS quarantines the download and shows *"Signet.app is damaged and can't be opened"* on first launch — that's Gatekeeper, not actual damage. Clear the quarantine flag once, then open normally:

```sh
xattr -dr com.apple.quarantine /Applications/Signet.app
open /Applications/Signet.app
```

Removing `com.apple.quarantine` only drops the "downloaded from the internet" marker; the app stays ad-hoc signed. The trust anchor is a reproducible build — this artifact was built by CI from the tagged commit, and you can rebuild it yourself (see the [README](https://github.com/zig-nostr/signet#build)). **Your key never leaves the daemon.**
