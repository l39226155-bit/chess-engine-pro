//
//  StockfishBridge.h
//  CHESS ENGINE PRO
//
//  Plain C interface to the embedded Stockfish UCI loop. The engine runs
//  inside the app process; stdin/stdout are replaced by thread safe queues.
//

#ifndef STOCKFISH_BRIDGE_H
#define STOCKFISH_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// True when a real Stockfish static library is linked in.
bool sf_available(void);

/// Human readable engine name.
const char *sf_engine_name(void);

/// Starts the engine loop once. Returns false when no engine is linked.
bool sf_start(void);

/// Sends a raw UCI command (a newline is appended).
void sf_write(const char *command);

/// Blocks until a full line is available. Returns the length, or -1 on EOF.
int sf_read_line(char *out, int maxLen);

/// Requests termination of the engine loop.
void sf_shutdown(void);

#ifdef __cplusplus
}
#endif

#endif /* STOCKFISH_BRIDGE_H */
