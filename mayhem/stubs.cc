// reportError() lives in src/main.cpp (the CLI entry point, not linked into the harnesses).
#include "ta-utils.h"
#include "ta-log.h"

void reportError(String what) {
  logE("%s",what);
}
