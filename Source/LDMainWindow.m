#import "LDMainWindow.h"

@implementation LDMainWindow

- (void)setKeyHandler:(id<LDMainWindowKeyHandler>)handler
{
  _keyHandler = handler;
}

- (void)sendEvent:(NSEvent *)event
{
  if ([event type] == NSKeyDown && [_keyHandler mainWindowHandleKeyDown:event]) {
    return;
  }
  [super sendEvent:event];
}

@end
