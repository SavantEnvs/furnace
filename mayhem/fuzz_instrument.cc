// libFuzzer harness: parse an arbitrary instrument file (.fui, .dmp, .tfi, .vgi, .opli, ...) via DivEngine::instrumentFromFile.
#include "engine/engine.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static char path[4096];

extern "C" int LLVMFuzzerInitialize(int*, char***) {
  const char* tmp=getenv("TMPDIR");
  snprintf(path,sizeof(path),"%s/fuzz_instrument_XXXXXX",(tmp && *tmp)?tmp:"/tmp");
  int fd=mkstemp(path);
  if (fd<0) { perror("mkstemp"); abort(); }
  close(fd);
  return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size==0 || size>(4U<<20)) return -1;
  FILE* f=fopen(path,"wb");
  if (f==NULL) abort();
  fwrite(data,1,size,f);
  fclose(f);
  DivEngine e;
  std::vector<DivInstrument*> ins=e.instrumentFromFile(path,true,true);
  for (DivInstrument* i: ins) delete i;
  return 0;
}
