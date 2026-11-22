//
//  StockfishStub.cpp
//  CHESS ENGINE PRO
//
//  Placeholder implementation used when the real Stockfish static library
//  was not built (e.g. a quick simulator run without scripts/build-stockfish.sh).
//  The app then transparently uses the built-in Swift engine.
//

#include "StockfishBridge.h"

extern "C" {

bool sf_available(void) {
    return false;
}

const char *sf_engine_name(void) {
    return "Stockfish (nicht eingebunden)";
}

bool sf_start(void) {
    return false;
}

void sf_write(const char *command) {
    (void)command;
}

int sf_read_line(char *out, int maxLen) {
    if (out && maxLen > 0) out[0] = '\0';
    return -1;
}

void sf_shutdown(void) {
}

}  // extern "C"
