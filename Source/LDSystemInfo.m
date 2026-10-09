#import "LDSystemInfo.h"

#include <stdio.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <mach/mach.h>
#endif

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
#elif defined(__APPLE__)
  mach_task_basic_info_data_t info;
  mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
  if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) {
    return 0;
  }
  return (unsigned long long)info.resident_size;
#else
  return 0;
#endif
}
