#import <AppKit/AppKit.h>

@interface AppController : NSObject <NSApplicationDelegate>
{
  NSWindow *_window;
  NSTextField *_titleField;
  NSButton *_openButton;
  NSButton *_rescanButton;
  NSButton *_stopButton;
  NSTextField *_directoryLabel;
  NSTextField *_extensionLabel;
  NSTextField *_treemapLabel;
  NSScrollView *_directoryScroll;
  NSScrollView *_extensionScroll;
  NSTableView *_directoryTable;
  NSTableView *_extensionTable;
  NSTextField *_statusField;
  NSTextField *_pathField;
  id _treemapView;
  NSArray *_directoryRows;
  NSArray *_extensionRows;
  id _scanSession;
  NSTimer *_scanTimer;
  id _rootNode;
  NSString *_currentScanPath;
  unsigned long long _totalBytes;
  NSUInteger _scanAnimationFrame;
}
@end
