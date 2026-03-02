# PpNet

Message protocol with error correction (Reed-Solomon), framing (COBS), and checksum (Adler32).

## Installation

If [available on Hex](https://hex.pm/docs/publish), add the dependency to your list in `mix.exs`:

```elixir
def deps do
  [
    {:pp_net, "~> 0.1.0"}
  ]
end
```

## Transport layer: COBS and Reed-Solomon

Each message is encoded in two stages before being sent on the wire:

1. **Frame**  
   Build the frame: `type` (1 byte) + `checksum` (4 bytes, Adler32 of body) + `body` (variable).

2. **Reed-Solomon**  
   The frame is encoded with **Reed-Solomon** (4 parity bytes), allowing up to 4 corrupted bytes in the block to be corrected. Maximum block size is 255 bytes (typical RS limit in GF(2⁸)).

3. **COBS**  
   The result is encoded with **COBS** (*Consistent Overhead Byte Stuffing*): the byte `0x00` is reserved as the frame delimiter, and the payload is escaped so it never contains `0x00`. Frames can thus be delimited reliably in a stream.

4. **Separator**  
   A single `0x00` byte is appended after each encoded message, marking the end of the frame.

**Decoding:** the receiver splits the stream on `0x00`, decodes each block with COBS, applies Reed-Solomon to correct errors, then parses the frame (type + checksum + body) and validates the checksum.

| Step    | Encode                     | Decode     |
| ------- | -------------------------- | ---------- |
| Frame   | type + checksum + body     | —          |
| RS      | + 4 parity bytes           | correction |
| COBS    | byte stuffing              | unstuff    |
| Stream  | …payload…`0x00`            | split by `0x00` |

## Frame structure (after Reed-Solomon)

All messages share the same frame header:

| Field    | Type         | Bytes    |
| -------- | ------------ | -------- |
| type     | uint8        | 1        |
| checksum | uint32 (big) | 4        |
| body     | binary       | variable |

The **checksum** is Adler32 of the **body** only (it does not include the type byte). When parsing, the struct field `valid` indicates whether the checksum matches.

---

## Message formats (body)

### Types 1–4: common frame (MessagePack)

Hello (1), SingleCounter (2), Ping (3), and Event (4) use **MessagePack** for the body. The frame is: `type` + `checksum` + MessagePack body.

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

Body: MessagePack array. Minimum format: `[temperature, uptime_ms]`. May include a third element: map `extra`.

| Field       | Type    |
| ----------- | ------- |
| temperature | float   |
| uptime_ms   | integer |
| extra       | map (optional) |

Extended format (8 elements): `[temperature, uptime_ms, cpu, tpu, system_load, storage_available_bytes, wifi, extra]` — CPU, TPU, system load, free storage, and WiFi (MAC address and signal level).

---

### Type 4 — Event

Body: MessagePack array `[kind, data]`.

| Field | Type   |
| ----- | ------ |
| kind  | string |
| data  | map    |

---

### Type 5 — Image

Body: raw binary (image data). Used when the image fits in a single frame (within the channel limit). Otherwise, fragmented messages (types 6 and 7) are used.

---

### Type 6 — ChunckedMessageHeader (fragmented message header)

Used when the payload is large (e.g. image). The body is fixed binary (no MessagePack).

| Field               | Type   | Bytes |
| ------------------- | ------ | ----- |
| message_module_code | uint8  | 1     |
| transaction_id      | uint32 | 4     |
| datetime            | uint32 (Unix) | 4 |
| total_chunks        | uint8  | 1     |

`message_module_code` indicates the original message type (1=Hello, 2=SingleCounter, 3=Ping, 4=Event, 5=Image). The frame checksum covers this entire body (10 bytes).

---

### Type 7 — ChunckedMessageBody (fragment)

Body: binary.

| Field          | Type   | Bytes      |
| -------------- | ------ | ---------- |
| transaction_id | uint32 | 4          |
| chunk_index    | uint8  | 1          |
| chunk_size     | uint16 | 2          |
| chunk_data     | binary | chunk_size |

`chunk_size` is the length in bytes of `chunk_data`. Fragments are reassembled by `transaction_id` and ordered by `chunk_index`.
