# PpNet


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

All multi-field messages are followed by a newline byte (`\n`, 1 byte) on the wire.

### Common frame (types 1, 2 and 5)

Messages of type Hello (1), SingleCounter (2) and Ping (5) use this frame:

| Field     | Type           | Bytes    |
| --------- | -------------- | -------- |
| type      | uint8          | 1        |
| checksum  | uint32 (big)   | 4        |
| body      | msgpack binary | variable |

### Type 1 — Hello

Body is a msgpack array. Field sizes are variable (msgpack-encoded).

| Field            | Type    | Bytes    |
| ---------------- | ------- | -------- |
| unique_id        | string  | variable |
| board_identifier | string  | variable |
| version          | integer | variable |
| board_version    | integer | variable |
| boot_id          | integer | variable |
| ppnet_version    | integer | variable |

### Type 2 — SingleCounter

Body is a msgpack array. Field sizes are variable (msgpack-encoded).

| Field       | Type    | Bytes    |
| ----------- | ------- | -------- |
| kind        | string  | variable |
| value       | any     | variable |
| pulses      | integer | variable |
| duration_ms | integer | variable |

### Type 5 — Ping

Body is a msgpack array. Field sizes are variable (msgpack-encoded).

| Field       | Type   | Bytes    |
| ----------- | ------ | -------- |
| temperature | float  | variable |
| uptime_ms   | integer | variable |

### Type 3 — ImageHeader

Fixed-size binary (7 bytes total including type and newline).

| Field          | Type  | Bytes |
| -------------- | ----- | ----- |
| type           | uint8 | 1     |
| transaction_id | uint32 | 4     |
| total_chunks   | uint8 | 1     |
| newline        | byte  | 1     |

### Type 4 — ImageBody

Binary; payload size is variable.

| Field          | Type   | Bytes    |
| -------------- | ------ | -------- |
| type           | uint8  | 1        |
| transaction_id | uint32 | 4        |
| chunk_index    | uint8  | 1        |
| chunk_data     | binary | variable |
| newline        | byte   | 1        |


