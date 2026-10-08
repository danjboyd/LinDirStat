#import <AppKit/AppKit.h>
#import "AppController.h"

int main(int argc, char **argv)
{
  (void)argc;
  (void)argv;

  @autoreleasepool {
    NSApplication *application = [NSApplication sharedApplication];
    AppController *controller = [[AppController alloc] init];
    [application setDelegate:controller];
    [application run];
  }
  return 0;
}
