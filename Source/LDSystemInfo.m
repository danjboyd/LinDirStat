#import "LDSystemInfo.h"

#include <stdio.h>
#include <unistd.h>

unsigned long long LDResidentMemoryBytes(void)
{
#if defined(__linux__)
  FILE *file = fopen("/proc/self/statm", "r");
  if (!file) {
    return 0;
  }
  unsigned long long totalPages = 0;
  unsigned long long residentPages = 0;
  int fields = fscanf(file, "%llu %llu", &totalPages, &residentPages);
  fclose(file);
  if (fields != 2) {
    return 0;
  }
  return residentPages * (unsigned long long)sysconf(_SC_PAGESIZE);
#else
  return 0;
#endif
}
