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
    {:pp_net, "~> 0.1.3"}
  ]
end
```

## Transport layer: COBS and Reed-Solomon

Each message is encoded in two stages before being sent on the wire:

1. **Frame**  
   Build the frame: `type` (1 byte) + `body` (variable). There is no separate checksum field; Reed-Solomon provides integrity.

2. **Reed-Solomon**  
   The frame is encoded with **Reed-Solomon** (4 parity bytes), allowing up to 4 corrupted bytes in the block to be corrected. Maximum block size is 255 bytes (typical RS limit in GF(2⁸)).

3. **COBS**  
   The result is encoded with **COBS** (_Consistent Overhead Byte Stuffing_): the byte `0x00` is reserved as the frame delimiter, and the payload is escaped so it never contains `0x00`. Frames can thus be delimited reliably in a stream.

4. **Separator**  
   A single `0x00` byte is appended after each encoded message, marking the end of the frame.

**Decoding:** the receiver splits the stream on `0x00`, decodes each block with COBS, applies Reed-Solomon to correct errors, then parses the frame (type + body).

| Step   | Encode           | Decode          |
| ------ | ---------------- | --------------- |
| Frame  | type + body      | —               |
| RS     | + 4 parity bytes | correction      |
| COBS   | byte stuffing    | unstuff         |
| Stream | …payload…`0x00`  | split by `0x00` |

## Frame structure (after Reed-Solomon)

All messages share the same logical layout before COBS:

| Field | Type   | Bytes    |
| ----- | ------ | -------- |
| type  | uint8  | 1        |
| body  | binary | variable |

The full block (type + body) is protected by 4 Reed-Solomon parity bytes.

---

## Message formats (body)

### Types 1–4: MessagePack body

Hello (1), SingleCounter (2), Ping (3), and Event (4) use **MessagePack** for the body.

---

### Type 1 — Hello

Body: MessagePack array (fields in order).

| Field            | Type    |
| ---------------- | ------- |
| unique_id        | string  |
| board_identifier | string  |
| version          | integer |
| board_version    | integer |
| boot_id          | integer |
| ppnet_version    | integer |

---

### Type 2 — SingleCounter

Body: MessagePack array.

| Field       | Type    |
| ----------- | ------- |
| kind        | string  |
| value       | any     |
| pulses      | integer |
| duration_ms | integer |

---

### Type 3 — Ping

Body: MessagePack array with 10 elements in order:

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
| extra              | map     | —                                 | Optional key/value data                                                                                   |

**Backward compatibility:** A 9-element list without `session_id` is still accepted; `session_id` will be `nil`.

**WiFi encoding:** Each entry is 7 bytes: MAC address as 6 raw bytes (no colon-separated string), then RSSI as one signed byte. This keeps the payload small so the ping stays within a single frame.

---

### Type 4 — Event

Body: MessagePack array `[kind, data]`.

| Field | Type    | Notes                                                                  |
| ----- | ------- | ---------------------------------------------------------------------- |
| kind  | integer | 1 = detection                                                          |
| data  | map     | Example payload: `{"image_id" => <16-byte UUID binary>, "d" => [...]}` |

---

### Type 5 — Image

Body: fixed header + raw image data.

| Field  | Type   | Bytes                     |
| ------ | ------ | ------------------------- |
| id     | binary | 16 (UUIDv4)               |
| format | uint8  | 1 (1=jpeg, 2=webp, 3=png) |
| data   | binary | variable                  |

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

`message_module_code` indicates the original message type (1=Hello, 2=SingleCounter, 3=Ping, 4=Event, 5=Image). Total header body: 11 bytes.

---

### Type 7 — ChunkedMessageBody (fragment)

| Field          | Type   | Bytes      |
| -------------- | ------ | ---------- |
| transaction_id | uint32 | 4          |
| chunk_index    | uint16 | 2          |
| chunk_size     | uint8  | 1          |
| chunk_data     | binary | chunk_size |

`chunk_size` is the length in bytes of `chunk_data`. Fragments are reassembled by `transaction_id` and ordered by `chunk_index`.

---

## Usage

- **Encode** a message: `PPNet.encode_message(message)` returns a single binary, or a list `[header_binary | chunk_binaries]` when the message is chunked (e.g. large image). You can pass `limit: n` to force chunking when the encoded size would exceed `n` bytes (default 254).

- **Parse** a stream: `PPNet.parse(binary)` returns `%{messages: [...], errors: [...]}`. Each element of `messages` is either a decoded message struct (Hello, Ping, etc.) or a `ChunkedMessageHeader` / `ChunkedMessageBody`. Join all frames (e.g. from a stream) and call `parse` on the concatenated binary.

- **Reassemble** chunked payloads: when you have `[%ChunkedMessageHeader{} | chunks]` from `parse`, call `PPNet.chunked_to_message([header | chunks])` to get `{:ok, message}` (or `{:error, reason}`). The result is the original message type (e.g. `%Image{}`, `%Ping{}`).

Example (chunked image):

```elixir
image = %PPNet.Message.Image{data: raw_binary, format: :webp}
[header_bin | chunk_bins] = PPNet.encode_message(image, limit: 200)
payload = [header_bin | chunk_bins] |> Enum.join()
%{messages: [header | body_messages], errors: []} = PPNet.parse(payload)
{:ok, ^image} = PPNet.chunked_to_message([header | body_messages])
```
