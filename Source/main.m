#import <AppKit/AppKit.h>
#import "AppController.h"
#import "LDCommandLine.h"
#import "LDPlatformUI.h"
#import "LDPreferences.h"
#import "LDScanOptions.h"

#include <stdio.h>

// --savetocsv and --savedupestocsv run without NSApplication, so they need
// no display (WinDirStat hides its window for them).
static int LDRunHeadless(LDCommandLine *commandLine)
{
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  NSMutableArray *messages = [NSMutableArray array];
  int status = [LDCommandLineExport runCommandLine:commandLine
                                       scanOptions:[LDScanOptions optionsFromPreferences:preferences]
                                      includeOwner:[preferences isColumnShown:LDColumnOwner]
                                          messages:messages];
  for (NSString *message in messages) {
    fprintf(stderr, "LinDirStat: %s\n", [message UTF8String]);
  }
  return status;
}

int main(int argc, char **argv)
{
  (void)argc;
  (void)argv;

  @autoreleasepool {
    LDCommandLine *commandLine = [LDCommandLine processCommandLine];
    if ([commandLine isHeadless]) {
      return LDRunHeadless(commandLine);
    }
    NSApplication *application = [NSApplication sharedApplication];
    [LDPlatformUI prepareApplication:application];
    AppController *controller = [[AppController alloc] init];
    [application setDelegate:controller];
    [application run];
  }
  return 0;
}
