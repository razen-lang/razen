#include <stdint.h>
#include <stdbool.h>
#include "razen_core.h"

// Module Network
// #include "std.io.h"

typedef uint32_t Flags;
#define std_io_print(x) printf("print\n")

typedef struct {
	uint8_t tag;
	uint8_t* (*serialize)(void* x); 
} SerDe;

typedef struct {
	uint8_t tag;
	uint8_t* data;
} Packet;

typedef enum {
	State_Open,
	State_Closed
} State;

typedef union {
	int32_t Code;
	const char* Msg;
} NetErr;

typedef enum {
	SystemError_ConnReset,
	SystemError_Timeout
} SystemError;

int32_t bind(int32_t port) {
    return 0;
}

void handle_conn() {
	// [Not fully supported in C] Deferred block:
	std_io_print("Closed!");
	__auto_type s = State_Open;
	// Match s
	if (s == State_Open) {
		std_io_print("open");
	}
	else if (s == State_Closed) {
		std_io_print("closed");
	}
	__auto_type items = (int[]){1, 2, 3};
	// Simplified loop array
	for (size_t _idx = 0; _idx < sizeof(items)/sizeof(items[0]); _idx++) {
		__auto_type i = items[_idx];
		std_io_print(i);
	}
	__auto_type res = RAZEN_TRY(RAZEN_CATCH(bind(8080), { /* block expr */ }));
}

int main() {
    handle_conn();
    return 0;
}
