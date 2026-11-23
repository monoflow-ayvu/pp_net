# PPNet

[![Hex.pm](https://img.shields.io/hexpm/v/pp_net.svg)](https://hex.pm/packages/pp_net)
[![Hex Docs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/pp_net)
[![License](https://img.shields.io/hexpm/l/pp_net.svg)](https://github.com/monoflow-ayvu/pp_net/blob/main/LICENCE)
[![Changelog](https://img.shields.io/badge/changelog-md-blue.svg)](https://github.com/monoflow-ayvu/pp_net/blob/main/CHANGELOG.md)

Message protocol with error correction (Reed-Solomon) and framing (COBS).

## Installation

If [available on Hex](https://hex.pm/docs/publish), add the dependency to your list in `mix.exs`:

```elixir
def deps do
  [
    {:pp_net, "~> 0.3.0"}
  ]
end
```

## Transport layer: COBS and Reed-Solomon

Each message is encoded in two stages before being sent on the wire:

1. **Frame**  
   Build the frame: `type` (1 byte) + `body` (variable). There is no separate checksum field; Reed-Solomon provides integrity.

2. **Reed-Solomon**  
   The frame is encoded with **Reed-Solomon** (8 parity bytes), allowing up to 4 corrupted bytes in the block to be corrected. Maximum block size is 255 bytes (typical RS limit in GF(2⁸)).

3. **COBS**  
   The result is encoded with **COBS** (_Consistent Overhead Byte Stuffing_): the byte `0x00` is reserved as the frame delimiter, and the payload is escaped so it never contains `0x00`. Frames can thus be delimited reliably in a stream.

4. **Separator**  
   A single `0x00` byte is appended after each encoded message, marking the end of the frame.

**Decoding:** the receiver splits the stream on `0x00`, decodes each block with COBS, applies Reed-Solomon to correct errors, then parses the frame (type + body).

| Step   | Encode           | Decode          |
| ------ | ---------------- | --------------- |
| Frame  | type + body      | —               |
| RS     | + 8 parity bytes | correction      |
| COBS   | byte stuffing    | unstuff         |
| Stream | …payload…`0x00`  | split by `0x00` |

## Frame structure (after Reed-Solomon)

All messages share the same logical layout before COBS:

| Field | Type   | Bytes    |
| ----- | ------ | -------- |
| type  | uint8  | 1        |
| body  | binary | variable |

The full block (type + body) is protected by 8 Reed-Solomon parity bytes.

---

## Message formats (body)

### Types 1–4: MessagePack body

Hello (1), SingleCounter (2), Ping (3), and Event (4) use **MessagePack** for the body.

---

### Type 1 — Hello

Body: MessagePack array (fields in order).

| Field            | Type                          |
| ---------------- | ----------------------------- |
| unique_id        | string                        |
| board_identifier | string                        |
| version          | integer                       |
| board_version    | integer                       |
| boot_id          | integer                       |
| ppnet_version    | integer                       |
| datetime         | integer (Unix ts)             |
| capabilities     | integer bitfield (optional)   |

`Hello.capabilities` is a list of atoms in the Elixir API: `:brotli`, `:gzip`, and/or `:heatshrink`. `pack/1` serializes that list as an integer bitfield: Brotli = `0x01` (bit 0), gzip = `0x02` (bit 1), and Heatshrink = `0x04` (bit 2). Receivers ignore unassigned higher bits. An empty list is omitted from the wire, preserving the legacy seven-element body; missing capabilities decode as `[]`.

**Backward compatibility:** A 6-element list without `datetime` is still accepted; `datetime` will be `nil` and `capabilities` will be `[]`. A 7-element list without `capabilities` is also accepted with `capabilities: []`.

---

### Type 2 — SingleCounter

Body: MessagePack array.

| Field       | Type              |
| ----------- | ----------------- |
| kind        | string            |
| value       | any               |
| pulses      | integer           |
| duration_ms | integer           |
| datetime    | integer (Unix ts) |
| hop         | integer (0–255)   |

`hop` is the address of the device that generated the counter on the board's internal bus; `0` is the board itself.

**Backward compatibility:** A 5-element list without `hop` is still accepted; `hop` will be `0`. A 4-element list without `datetime` is still accepted; `datetime` will be `nil` and `hop` will be `0`.

---

### Type 3 — Ping

Body: MessagePack array with 11 elements in order:

| Field              | Type    | Validation                        | Wire format / notes                                                                                       |
| ------------------ | ------- | --------------------------------- | --------------------------------------------------------------------------------------------------------- |
| session_id         | string  | UUID format                       | List of 16 integers (bytes); decoded to UUID string                                                       |
| temperature        | float   | —                                 | —                                                                                                         |
| uptime_ms          | integer | —                                 | —                                                                                                         |
| location           | list    | lat/lon: float, accuracy: integer | `[lat, lon, accuracy]`                                                                                    |
| cpu                | float   | 0.0 <= cpu <= 1.0                 | —                                                                                                         |
| tpu_memory_percent | integer | 0 <= value <= 100                 | % of TPU memory                                                                                           |
| tpu_ping_ms        | integer | —                                 | TPU ping time (ms)                                                                                        |
| wifi               | list    | max 10 entries                    | List of **7-byte binaries**: 6 bytes MAC (raw) + 1 byte RSSI (signed int8, dBm)                          |
| storage            | list    | total/used: integer               | `[total, used]` (2 integers, kilobytes — clients must convert before sending; receivers always assume KB) |
| datetime           | integer | —                                 | Unix timestamp (seconds)                                                                                  |
| extra              | map     | —                                 | Optional key/value data                                                                                   |

**Backward compatibility:** A 9-element list without `session_id` is still accepted; `session_id` will be `nil`. A 10-element list without `datetime` is still accepted; `datetime` will be `nil`.

**WiFi encoding:** Each entry is 7 bytes: MAC address as 6 raw bytes (no colon-separated string), then RSSI as one signed byte. This keeps the payload small so the ping stays within a single frame.

---

### Type 4 — Event

Body: MessagePack array `[kind, data, datetime, hop]`.

| Field    | Type            | Notes                                                                                                         |
| -------- | --------------- | ------------------------------------------------------------------------------------------------------------- |
| kind     | integer         | 1 = detection, 2 = ble_scan                                                                                   |
| data     | map             | Example payload: `{"image_id" => <16-byte UUID binary>, "d" => [...]}`                                       |
| datetime | integer         | Unix timestamp (seconds)                                                                                      |
| hop      | integer (0–255) | Address of the device that generated the event on the board's internal bus; `0` is the board itself          |

**Event kinds:** This table is the source of truth for `kind` codes. A new kind only exists once it has been added here (and to `@event_kind_to_code` in `lib/pp_net/message/event.ex`).

| Code | Name (Elixir atom) | Description        | `data`                                                  |
| ---- | ------------------ | ------------------ | ------------------------------------------------------- |
| 1    | `detection`        | Object detection   | `{"image_id" => <16-byte UUID binary>, "d" => [...]}`   |
| 2    | `ble_scan`         | BLE Scan           | Free map                                                |

**Backward compatibility:** A 3-element list without `hop` is still accepted; `hop` will be `0`. A 2-element list without `datetime` is still accepted; `datetime` will be `nil` and `hop` will be `0`.

---

### Type 5 — Image

Body: fixed header + raw image data.

| Field     | Type          | Bytes                     |
| --------- | ------------- | ------------------------- |
| id        | binary        | 16 (UUIDv4)               |
| format    | uint8         | 1 (1=jpeg, 2=webp, 3=png, 4=h264) |
| hop       | uint8         | 1 (address of the device that captured the image on the board's internal bus; 0 = the board itself) |
| datetime  | uint32 (Unix) | 4                         |
| data_size | uint32        | 4                         |
| data      | binary        | data_size                 |

**H.264 (`4`):** `data` must be an Annex-B byte stream — NAL units prefixed with a `00 00 01` or `00 00 00 01` start code. `pack/1` rejects other framings (e.g. AVCC/length-prefixed) with `%PPNet.PackError{reason: :not_annex_b}`.

**Backward compatibility:** The v0.1.6 format (without `hop`) is still accepted; `hop` will be `0`. The older format (`id` + `format` + `data` without `datetime`/`data_size`) is still accepted too; `datetime` will be `nil` and `hop` will be `0`.

When the encoded image (or any message) exceeds the channel limit, it is sent as chunked messages (types 6 and 7).

---

### Type 6 — ChunkedMessageHeader (chunked message header)

Used when the payload is too large for a single frame (e.g. image). The body is fixed binary.

| Field          | Type          | Bytes |
| -------------- | ------------- | ----- |
| message_module | uint8         | 1     |
| transaction_id | uint32        | 4     |
| datetime       | uint32 (Unix) | 4     |
| total_chunks   | uint16        | 2     |

Total header body: 11 bytes.

`message_module` is the type code of the original message. Only these types can be chunked:

| Code | Message       |
| ---- | ------------- |
| 1    | Hello         |
| 2    | SingleCounter |
| 3    | Ping          |
| 4    | Event         |
| 5    | Image         |
| 9    | ConfigData    |
| 11   | Document      |
| 12   | OTARequest    |

---

### Type 7 — ChunkedMessageBody (fragment)

| Field          | Type          | Bytes      |
| -------------- | ------------- | ---------- |
| transaction_id | uint32        | 4          |
| datetime       | uint32 (Unix) | 4          |
| chunk_index    | uint16        | 2          |
| chunk_size     | uint8         | 1          |
| chunk_data     | binary        | chunk_size |

`chunk_size` is the length in bytes of `chunk_data`. Fragments are reassembled by `transaction_id` and ordered by `chunk_index`.

**Backward compatibility:** The old format without `datetime` is still accepted; `datetime` will be `nil`.

---

### Type 11 — Document

A file of any format. The content type is a [MIME type](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/MIME_types) (for example `text/plain` or `application/pdf`), not a fixed enum. Body: binary fields in this order.

| Field         | Type          | Bytes         | Notes                                                                                     |
| ------------- | ------------- | ------------- | ----------------------------------------------------------------------------------------- |
| id            | binary        | 16 (UUIDv4)   |                                                                                           |
| mime_size     | uint8         | 1             | Length of `mime`, 1–255                                                                   |
| mime          | string        | mime_size     | MIME type of `data`, UTF-8                                                                |
| hop           | uint8         | 1             | Address of the device that created the document on the board's internal bus; 0 = the board itself |
| datetime      | uint32 (Unix) | 4             | Creation date                                                                             |
| data_size     | uint32        | 4             |                                                                                           |
| data          | binary        | data_size     | File content                                                                              |
| metadata_size | uint16        | 2             | Length of `metadata`; `0` when the map is empty                                          |
| metadata      | binary        | metadata_size | MessagePack map with free key/value data (strings, numbers, booleans, nil, lists, maps)   |

`pack/1` returns `%PPNet.PackError{reason: :invalid_mime}` for an empty, non-UTF-8 or longer than 255 bytes `mime`, `reason: :invalid_hop` for an invalid `hop`, and `reason: :invalid_metadata` when `metadata` is not a map, cannot be serialized to MessagePack, or exceeds 65 535 bytes once serialized. Atom keys and values in `metadata` are sent as strings.

**Forward compatibility:** `parse/1` ignores bytes after `metadata`, so new fields can be appended to the end of the body.

A document larger than the frame limit is sent as chunked messages (types 6 and 7).

---

### Type 12 — OTARequest

Sent by the server to the GPS to ask for a firmware update (OTA). The GPS downloads the firmware from `url`, checks it against `sum` and reports with `OTAProgress` (type 13) and `OTAFinish` (type 14), both carrying the same `id`. Body: binary fields in this order.

| Field    | Type          | Bytes       | Notes                                                                                  |
| -------- | ------------- | ----------- | -------------------------------------------------------------------------------------- |
| id       | binary        | 16 (UUIDv4) | Identifies the OTA operation                                                           |
| hop      | uint8         | 1           | Address of the device that must apply the update on the board's internal bus; 0 = the board itself |
| datetime | uint32 (Unix) | 4           | Request date                                                                           |
| sumtype  | uint8         | 1           | Checksum algorithm: `0` = `md5`, `1` = `sha256`, `2` = `sha512`                        |
| sum      | binary        | 16/32/64    | Raw checksum bytes (not the hex string); the size comes from `sumtype`                 |
| url_size | uint16        | 2           | Length of `url`, 1–65 535                                                              |
| url      | string        | url_size    | Firmware download address, UTF-8                                                       |

`sum` has no size field: its size is 16 bytes for `md5`, 32 for `sha256` and 64 for `sha512`.

`pack/1` returns `%PPNet.PackError{reason: :invalid_sumtype}` for a `sumtype` other than `:md5`, `:sha256` or `:sha512`, `reason: :invalid_sum` when `sum` is not a binary with the size of its `sumtype`, `reason: :invalid_url` for an empty, non-UTF-8 or longer than 65 535 bytes `url`, and `reason: :invalid_hop` for an invalid `hop`. `parse/1` returns `%PPNet.ParseError{reason: :unknown_format}` for an unknown `sumtype` code.

**Forward compatibility:** `parse/1` ignores bytes after `url`, so new fields can be appended to the end of the body.

A request with a long `url`, such as a presigned S3 url, is sent as chunked messages (types 6 and 7).

---

### Type 13 — OTAProgress

Sent by the GPS to the server to report how far a firmware update (OTA) has gone. Body: binary fields in this order, 22 bytes in total.

| Field    | Type          | Bytes       | Notes                                                                                   |
| -------- | ------------- | ----------- | --------------------------------------------------------------------------------------- |
| id       | binary        | 16 (UUIDv4) | `id` of the matching `OTARequest`                                                       |
| hop      | uint8         | 1           | Address of the device that reports the progress on the board's internal bus; 0 = the board itself |
| progress | uint8         | 1           | Percentage done, 0–100                                                                  |
| datetime | uint32 (Unix) | 4           | Report date                                                                             |

`pack/1` returns `%PPNet.PackError{reason: :invalid_progress}` when `progress` is not an integer from 0 to 100, and `reason: :invalid_hop` for an invalid `hop`. `parse/1` returns `%PPNet.ParseError{reason: :unknown_format}` for a `progress` above 100.

**Forward compatibility:** `parse/1` ignores bytes after `datetime`, so new fields can be appended to the end of the body.

An OTAProgress always fits in a single frame and is never chunked.

---

### Type 14 — OTAFinish

Sent by the GPS to the server when a firmware update (OTA) ends, with its result. Body: binary fields in this order.

| Field              | Type          | Bytes              | Notes                                                                                 |
| ------------------ | ------------- | ------------------ | ------------------------------------------------------------------------------------- |
| id                 | binary        | 16 (UUIDv4)        | `id` of the matching `OTARequest`                                                     |
| hop                | uint8         | 1                  | Address of the device that reports the result on the board's internal bus; 0 = the board itself |
| success            | uint8         | 1                  | `1` = update applied, `0` = update failed                                             |
| datetime           | uint32 (Unix) | 4                  | End date of the update                                                                |
| error_message_size | uint8         | 1                  | Length of `error_message`; `0` when there is no message                               |
| error_message      | string        | error_message_size | Reason of the failure, UTF-8                                                          |

An OTAFinish always fits in a single frame and is never chunked. The fixed fields take 23 bytes, so `error_message` may use what the frame has left: `limit - 11 (frame overhead) - 23`, which is **220 bytes** with the default limit of 254. `PPNet.encode_message(message, limit: n)` lowers the maximum to match a smaller frame.

A `nil` or empty `error_message` is sent as `error_message_size` 0 and parsed back as `nil`.

`pack/1` and `pack/2` return `%PPNet.PackError{reason: :invalid_error_message}` when `error_message` is not `nil` or a UTF-8 string, or does not fit in the frame, `reason: :invalid_success` when `success` is not a boolean, and `reason: :invalid_hop` for an invalid `hop`. `parse/1` returns `%PPNet.ParseError{reason: :unknown_format}` for a `success` byte other than 0 or 1.

**Forward compatibility:** `parse/1` ignores bytes after `error_message`, so new fields can be appended to the end of the body.

---

## Usage

- **Encode** a message: `PPNet.encode_message(message)` returns `{:ok, binary}`, or `{:ok, [header_binary | chunk_binaries]}` when the message is chunked (e.g. large image). A message that cannot be packed returns `{:error, %PPNet.PackError{}}`. You can pass `limit: n` to force chunking when the encoded size would exceed `n` bytes (default 254).

- **Encode as a stream**: `PPNet.encode_message_stream(message)` returns `{:ok, frames}` with the same frames as a lazy `Enumerable`, so large chunked messages can be sent frame-by-frame (e.g. into a chunked HTTP body) with O(chunk size) peak memory instead of materializing the full frame list. Useful on memory-constrained targets.

- **Parse** a stream: `PPNet.parse(binary)` returns `%{messages: [...], errors: [...]}`. Each element of `messages` is either a decoded message struct (Hello, Ping, etc.) or a `ChunkedMessageHeader` / `ChunkedMessageBody`. Join all frames (e.g. from a stream) and call `parse` on the concatenated binary.

- **Reassemble** chunked payloads: when you have `[%ChunkedMessageHeader{} | chunks]` from `parse`, call `PPNet.chunked_to_message([header | chunks])` to get `{:ok, message}` (or `{:error, reason}`). The result is the original message type (e.g. `%Image{}`, `%Ping{}`).

Example (chunked image):

```elixir
image = %PPNet.Message.Image{data: raw_binary, format: :webp, datetime: DateTime.utc_now()}
{:ok, [header_bin | chunk_bins]} = PPNet.encode_message(image, limit: 200)
payload = [header_bin | chunk_bins] |> Enum.join()
%{messages: [header | body_messages], errors: []} = PPNet.parse(payload)
{:ok, ^image} = PPNet.chunked_to_message([header | body_messages])
```
