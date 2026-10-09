#import <AppKit/AppKit.h>
#import "AppController.h"
#import "LDPlatformUI.h"

int main(int argc, char **argv)
{
  (void)argc;
  (void)argv;

  @autoreleasepool {
    NSApplication *application = [NSApplication sharedApplication];
    [LDPlatformUI prepareApplication:application];
    AppController *controller = [[AppController alloc] init];
    [application setDelegate:controller];
    [application run];
  }
  return 0;
}
