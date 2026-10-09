#import "AppController.h"
#import "LDListViews.h"

@class LDScanSession;

// Shared between AppController's files.
@interface AppController (Private)
- (NSArray *)selectedNodes;
- (BOOL)isScanning;
// Scanning, refreshing or running a file operation.
- (BOOL)isBusy;
- (void)showStatus:(NSString *)status;
- (NSString *)displayPath:(NSString *)path;
- (void)refreshCommandState;
- (void)startBusyIndicator;
// Stops the busy indicator once nothing is running any more.
- (void)finishBusyWork;
// The tree was edited: rebuild the extension list and treemap.
- (void)didChangeTree;
// node was replaced (or removed when replacement is nil).
- (void)forgetNode:(LDFileNode *)node replacement:(LDFileNode *)replacement;
- (void)configureScanSession:(LDScanSession *)session;
- (void)rescan:(id)sender;
- (NSString *)selectedDirectoryPathFromOpenPanel:(NSOpenPanel *)panel;
@end

@interface AppController (Cleanup)
- (void)openItem:(id)sender;
- (void)revealItem:(id)sender;
- (void)openTerminal:(id)sender;
- (void)showProperties:(id)sender;
- (void)copyPath:(id)sender;
- (void)moveToTrash:(id)sender;
- (void)deletePermanently:(id)sender;
- (void)deleteNodes:(NSArray *)nodes permanently:(BOOL)permanently;
- (void)emptyFolder:(id)sender;
- (void)moveItemsTo:(id)sender;
- (void)emptyTrash:(id)sender;
- (void)runCustomCleanup:(id)sender;
- (NSMenu *)customCleanupMenu;
- (void)refreshSelected:(id)sender;
- (void)refreshNodes:(NSArray *)nodes;
- (LDFileNode *)nodeForPathData:(NSData *)pathData;
@end
