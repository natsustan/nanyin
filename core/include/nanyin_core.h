// C interface of the Rust playback core (core/src/lib.rs).
#pragma once
#include <stdint.h>

typedef void (*nanyin_event_callback)(void *context, uint64_t generation, const char *json);

void nanyin_init(nanyin_event_callback callback, void *context);
uint64_t nanyin_connect(const char *config_json);
int32_t nanyin_command(const char *command_json);
int32_t nanyin_request(const char *request_json);
void nanyin_disconnect(void);
