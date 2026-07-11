# signer

A headless [NIP-46](https://github.com/nostr-protocol/nips/blob/master/46.md)
remote signer ("bunker") for Nostr, built on the
[zig-nostr/nostr](https://github.com/zig-nostr/nostr) library.

It keeps your `nsec` on a machine you control and signs on behalf of web and
native clients over a relay — the secret key never reaches the client.

> **Status: early / work in progress.** This is Showcase 1 of the zig-nostr
> roadmap. The current build connects to your relays and answers NIP-46
> requests — `get_public_key`, `sign_event`, `ping`, and NIP-44
> encrypt/decrypt — auto-approving each one behind the connection secret.
> Encrypted key storage (NIP-49) and a real approval UX are landing next.

## Build

Requires [Zig](https://ziglang.org) 0.16.0.

```sh
zig build
```

## Usage

Configure the signer with environment variables, then run it:

```sh
SIGNER_SECRET_KEY=<64-char hex secret key> \
SIGNER_RELAYS="wss://relay.example.com,wss://relay.two" \
SIGNER_CONNECT_SECRET=<optional connection secret> \
  zig build run
```

It prints the signer's public key and the `bunker://` token a client uses to
connect, then dials each relay and serves NIP-46 requests until stopped
(reconnecting automatically if a relay drops). Paste the token into a
NIP-46-capable client to sign with a key that never leaves this process.

## Roadmap

- [x] `bunker://` connection token from a key + relays
- [x] Relay listen/sign loop (answer NIP-46 requests over a relay)
- [ ] Encrypted key storage at rest (NIP-49 `ncryptsec`)
- [ ] Per-request approval policy
- [ ] Native macOS app + downloadable build

## License

MIT © Sepehr Safari
