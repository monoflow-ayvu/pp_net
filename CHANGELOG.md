# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.1.3]: https://github.com/monoflow-ayvu/pp_net/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/monoflow-ayvu/pp_net/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/monoflow-ayvu/pp_net/compare/0.1.0...v0.1.1
[0.1.0]: https://github.com/monoflow-ayvu/pp_net/releases/tag/0.1.0
