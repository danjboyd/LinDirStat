#import <AppKit/AppKit.h>

// Window-wide keys that are not menu commands, like WinDirStat's
// accelerators and its Tab handling between panes.
@protocol LDMainWindowKeyHandler
// Returns YES if the key was handled.
- (BOOL)mainWindowHandleKeyDown:(NSEvent *)event;
@end

// The main window: offers key-down events to its key handler before the
// first responder sees them.
@interface LDMainWindow : NSWindow
{
  __weak id<LDMainWindowKeyHandler> _keyHandler;
}

- (void)setKeyHandler:(id<LDMainWindowKeyHandler>)handler;

@end
