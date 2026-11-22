MIX_APP_PATH ?= .

NIF := $(MIX_APP_PATH)/priv/pp_net_heatshrink.so
OBJECT_DIR := $(MIX_APP_PATH)/obj/pp_net_heatshrink
SOURCES := c_src/pp_net_heatshrink.c \
	c_src/heatshrink/heatshrink_encoder.c \
	c_src/heatshrink/heatshrink_decoder.c
OBJECTS := $(patsubst c_src/%.c,$(OBJECT_DIR)/%.o,$(SOURCES))

CFLAGS += -fPIC -shared -std=c99 -O2 -Wall -Wextra
CPPFLAGS += -I$(ERTS_INCLUDE_DIR) -Ic_src/heatshrink
LDFLAGS += -shared

ifeq ($(shell uname -s),Darwin)
LDFLAGS += -undefined dynamic_lookup
endif

.PHONY: all clean

all: $(NIF)

$(NIF): $(OBJECTS)
	mkdir -p $(@D)
	$(CC) $(LDFLAGS) -o $@ $^

$(OBJECT_DIR)/%.o: c_src/%.c
	mkdir -p $(@D)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

clean:
	rm -rf $(OBJECT_DIR) $(NIF)
