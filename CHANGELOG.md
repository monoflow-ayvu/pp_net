# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Optional open `Hello.extra` MessagePack map at wire index 8 for arbitrary data such as cellular
  identifiers. Non-empty maps always include the capabilities slot at index 7; empty maps preserve
  the existing seven- and eight-element wire bodies

## [0.4.1] - 2026-11-23

### Fixed

- The Hex release workflow runs `mix hex.publish` with `MIX_ENV=dev`, where `ex_doc` is
  available. In 0.4.0 the publish step ran with `MIX_ENV=prod`, could not build the docs and did
  not publish the package, so 0.4.0 is not on Hex. 0.4.1 has the same code as 0.4.0

## [0.4.0] - 2026-11-23

### Added

- Optional `Hello.capabilities` list advertising `:brotli`, `:gzip`, and `:heatshrink`, serialized as
  a compact wire bitfield. The empty default is omitted, preserving the legacy seven-element wire
  body; older six- and seven-element bodies decode with no capabilities
- `ConfigData` compression with gzip (code `2`) and raw upstream Heatshrink streams (code `3`,
  fixed `window_sz2=8`, `lookahead_sz2=4`), backed by the vendored Heatshrink 0.4.1 native binding
- Precompiled Heatshrink NIFs for Linux x86_64/aarch64 GNU, macOS x86_64/arm64, and Windows
  x86_64 MSVC, with SHA-256 verification, automatic source-build fallback on other targets, and
  `PP_NET_FORCE_BUILD=1` for deterministic local source builds

## [0.3.0] - 2026-11-19

### Added

- `PPNet.Message.Document` (type 11): a file of any format, identified by a MIME type string
  instead of a fixed enum. Binary body `id | mime_size | mime | hop | datetime | data_size | data |
  metadata_size | metadata`, where `metadata` is an optional MessagePack map (`%{}` by default,
  sent as `metadata_size` 0). `parse/1` ignores bytes after `metadata`, so fields can be appended
  later. `pack/1` rejects an empty or invalid `mime` (`:invalid_mime`), an invalid `hop`
  (`:invalid_hop`) and a non-serializable or larger than 65 535 bytes `metadata`
  (`:invalid_metadata`). Large documents are chunked like `Image`
- `PPNet.Message.OTARequest` (type 12): the server asks the GPS for a firmware update (OTA).
  Binary body `id | hop | datetime | sumtype | sum | url_size | url`, where `sumtype` is `:md5`,
  `:sha256` or `:sha512` (codes 0, 1, 2) and sets the size of the raw `sum` (16, 32 or 64 bytes).
  `parse/1` ignores bytes after `url`, so fields can be appended later. `pack/1` rejects a
  `sumtype` outside the enum (`:invalid_sumtype`), a `sum` whose size does not match the `sumtype`
  (`:invalid_sum`), an empty, non-UTF-8 or longer than 65 535 bytes `url` (`:invalid_url`) and an
  invalid `hop` (`:invalid_hop`). A request with a long `url`, such as a presigned S3 url, is chunked
  like `Image`
- `PPNet.Message.OTAProgress` (type 13): the GPS reports how far a firmware update (OTA) has gone.
  Binary body `id | hop | progress | datetime` (22 bytes), where `id` is the `id` of the matching
  OTA request and `progress` is a percentage from 0 to 100. `parse/1` ignores bytes after
  `datetime`, so fields can be appended later. `pack/1` rejects a `progress` outside 0–100
  (`:invalid_progress`) and an invalid `hop` (`:invalid_hop`). Always fits in a single frame
- `PPNet.Message.OTAFinish` (type 14): the GPS reports the result of a firmware update (OTA).
  Binary body `id | hop | success | datetime | error_message_size | error_message`, where `id` is
  the `id` of the matching OTA request. Always fits in a single frame and is never chunked:
  `error_message` may use what the frame has left after the 23 bytes of fixed fields (220 bytes with
  the default limit of 254, less with a smaller `limit`). A `nil` or empty `error_message` is sent
  as size 0 and parsed back as `nil`. `parse/1` ignores bytes after `error_message`, so fields can
  be appended later. `pack/1` rejects an `error_message` that is not a UTF-8 string or does not fit
  (`:invalid_error_message`), a non-boolean `success` (`:invalid_success`) and an invalid `hop`
  (`:invalid_hop`)
- `ble_scan` kind in `PPNet.Message.Event` (code 2), for BLE scan results. `data` is a free map.
  The wire format does not change, but a receiver on an earlier version rejects code 2 with
  `:unknown_format`, so update the receiver before the senders

## [0.2.0] - 2026-10-28

### Added

- `hop` field in `PPNet.Message.SingleCounter`: an unsigned 8-bit address (0–255) of the device on
  the board's internal bus; `0` (the default) is the board itself. Wire format is now
  `[kind, value, pulses, duration_ms, datetime, hop]`; lists of 5 and 4 elements are still read, with
  `hop: 0`. `pack/1` returns `{:error, %PPNet.PackError{reason: :invalid_hop}}` for an invalid `hop`
- `hop` field in `PPNet.Message.Event`, same meaning and validation as in `SingleCounter`. Wire
  format is now `[kind_code, data, datetime, hop]`; lists of 3 and 2 elements are still read, with
  `hop: 0`
- `hop` field in `PPNet.Message.Image`, same meaning and validation as in `SingleCounter`. The
  binary body now carries `hop` (1 byte) right after `format`; the v0.1.6 body and the older one
  without `datetime` are still read, with `hop: 0`
- `hop` field in `PPNet.Message.ConfigData`: the origin in the board → server kinds and the
  destination in the server → board kinds. The binary header is now 15 bytes, with `hop` right
  after `kind`. There is no legacy clause for the previous 14-byte header, because `ConfigData` was
  not part of any release and no firmware sends it

## [0.1.6] - 2026-07-02

### Added

- `PPNet.encode_message_stream/2` — returns the encoded frames as a lazy `Enumerable`, so
  a large chunked message can be fed to a transport one frame at a time with O(chunk size)
  peak memory instead of materializing the full `[header_binary | chunk_binaries]` list

### Changed

- Chunked encoding splits payloads with binary pattern matching (zero-copy sub-binaries)
  instead of `:binary.bin_to_list/1` + `Enum.chunk_every/2`. Peak transient allocation drops
  from ~32× the payload size to O(payload); a 1.6 MB `Image` no longer OOMs 256 MB targets.
  Wire output is unchanged
- COBS framing on encode uses a one-pass zero-splitting encoder (byte-identical output)
  instead of the byte-at-a-time `Cobs.encode!/1`; `Cobs` is still used for decoding

### Fixed

- `encode_message/2` with a `limit` that leaves no room for chunk data (22 bytes, the clamp
  minimum) now raises a descriptive `ArgumentError` instead of a `FunctionClauseError`

## [0.1.5] - 2026-06-30

### Added

- `:h264` image format (format code `4`) to `PPNet.Message.Image`
- `Image.pack/1` requires `:h264` data to be Annex-B framed (NAL start code `00 00 01` or `00 00 00 01`) and rejects other framings with `%PPNet.PackError{reason: :not_annex_b}`

## [0.1.4] - 2026-03-31

### Added

- `datetime` field to all message types: Hello, SingleCounter, Ping, Event, Image, ChunkedMessageHeader, and ChunkedMessageBody
- Backward compatibility for all old formats — messages without `datetime` are still accepted; `datetime` will be `nil`
- UTF-8 validation in `Event` data before packing
- `is_valid_pack_input` guard in `Ping`

### Changed

- Minimum chunk size increased from 17 to 22 bytes to account for the `datetime` field in `ChunkedMessageHeader`
- Corrected Reed-Solomon parity byte count in documentation (8, not 4)

## [0.1.3] - 2026-03-19

### Added

- `session_id` field to `Ping` message
- `is_valid_ping_list` guard and its use in `parse`

## [0.1.2] - 2026-03-11

### Added

- Default `pack/1` to all message modules
- `defguard`s to simplify validation across message types
- Doctests and enhanced protocol documentation

### Changed

- Replaced long guard clauses with `defguard`s in Ping and chunked messages
- Enforced `chunk_size <= 254` via guard
- Enforced non-negative integers in `is_valid_types` guard
- Added guards and validations to message packers

## [0.1.1] - 2026-03-11

### Changed

- Updated organization name

## [0.1.0] - 2026-03-11

### Added

- Initial release with Ping, Event, and Image message types
- Reed-Solomon error correction and COBS framing
- Chunked message support
- Protocol encoding and parsing

[Unreleased]: https://github.com/monoflow-ayvu/pp_net/compare/v0.4.1...HEAD
[0.4.1]: https://github.com/monoflow-ayvu/pp_net/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/monoflow-ayvu/pp_net/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/monoflow-ayvu/pp_net/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/monoflow-ayvu/pp_net/compare/v0.1.6...v0.2.0
[0.1.6]: https://github.com/monoflow-ayvu/pp_net/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/monoflow-ayvu/pp_net/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/monoflow-ayvu/pp_net/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/monoflow-ayvu/pp_net/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/monoflow-ayvu/pp_net/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/monoflow-ayvu/pp_net/compare/0.1.0...v0.1.1
[0.1.0]: https://github.com/monoflow-ayvu/pp_net/releases/tag/0.1.0
