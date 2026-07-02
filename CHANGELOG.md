# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.1.6]: https://github.com/monoflow-ayvu/pp_net/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/monoflow-ayvu/pp_net/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/monoflow-ayvu/pp_net/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/monoflow-ayvu/pp_net/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/monoflow-ayvu/pp_net/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/monoflow-ayvu/pp_net/compare/0.1.0...v0.1.1
[0.1.0]: https://github.com/monoflow-ayvu/pp_net/releases/tag/0.1.0
