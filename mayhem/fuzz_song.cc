// libFuzzer harness: parse an arbitrary module (.fur/.dmf/.mod/.s3m/.xm/.it/.ftm/...) with DivEngine::load.
#include "engine/engine.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size<21 || size>(8U<<20)) return -1;
  // load() takes ownership of the buffer and frees it
  unsigned char* buf=new unsigned char[size];
  memcpy(buf,data,size);
  DivEngine e;
  e.load(buf,size,NULL);
  return 0;
}
