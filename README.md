# PpNet

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `pp_net` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:pp_net, "~> 0.1.0"}
  ]
end
```

## Message structure

When encoding, messages may be followed by a newline byte (`\n`, 1 byte). Payloads can contain `\n`; use `PPNet.parse_stream/1` for concatenated messages.

### Common frame (types 1, 2, 3 and 4)

Hello (1), SingleCounter (2), Ping (3) and Event (4) use this frame:

| Field    | Type           | Bytes    |
| -------- | -------------- | -------- |
| type     | uint8          | 1        |
| checksum | uint32 (big)   | 4        |
| body     | msgpack binary | variable |

### Type 1 — Hello

Body: msgpack array. All field sizes variable (msgpack-encoded).

| Field            | Type    | Bytes    |
| ---------------- | ------- | -------- |
| unique_id        | string  | variable |
| board_identifier | string  | variable |
| version          | integer | variable |
| board_version    | integer | variable |
| boot_id          | integer | variable |
| ppnet_version    | integer | variable |

### Type 2 — SingleCounter

Body: msgpack array. All field sizes variable (msgpack-encoded).

| Field       | Type    | Bytes    |
| ----------- | ------- | -------- |
| kind        | string  | variable |
| value       | any     | variable |
| pulses      | integer | variable |
| duration_ms | integer | variable |

### Type 3 — Ping

Body: msgpack array. All field sizes variable (msgpack-encoded).

| Field       | Type   | Bytes    |
| ----------- | ------ | -------- |
| temperature | float  | variable |
| uptime_ms   | integer | variable |
| extra       | map    | variable (optional) |

### Type 4 — Event

Body: msgpack array. All field sizes variable (msgpack-encoded).

| Field | Type  | Bytes    |
| ----- | ----- | -------- |
| kind  | atom  | variable |
| data  | map   | variable |

### Type 5 — ImageHeader

Fixed-size binary: 6 bytes (no checksum on wire).

| Field          | Type   | Bytes |
| -------------- | ------ | ----- |
| type           | uint8  | 1     |
| transaction_id | uint32 | 4     |
| total_chunks   | uint8  | 1     |

### Type 6 — ImageBody

Binary: 8-byte header + `chunk_size` bytes of payload. `chunk_size` is the length of `chunk_data`.

| Field          | Type   | Bytes    |
| -------------- | ------ | -------- |
| type           | uint8  | 1        |
| transaction_id | uint32 | 4        |
| chunk_index    | uint8  | 1        |
| chunk_size     | uint16 | 2        |
| chunk_data     | binary | chunk_size |


