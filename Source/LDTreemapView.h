#import <AppKit/AppKit.h>
#import "LDFileNode.h"
#import "LDTreemapLayout.h"

@class LDTreemapView;

@protocol LDTreemapViewDelegate
- (void)treemapView:(LDTreemapView *)view didSelectNode:(LDFileNode *)node;
- (void)treemapView:(LDTreemapView *)view didHoverNode:(LDFileNode *)node;
- (void)treemapViewDidChangeZoom:(LDTreemapView *)view;
@end

// Displays an LDTreemap the way WinDirStat's CTreeMapView does: a cached
// cushion bitmap, a white selection frame or per-extension highlights, and a
// framed zoom state. Theme colors are used only for the view's chrome.
@interface LDTreemapView : NSView
{
  __weak id _delegate;
  LDFileNode *_rootNode;
  LDFileNode *_zoomNode;
  LDFileNode *_selectedNode;
  NSString *_highlightedExtensionKey;
  NSDictionary *_colorIndexes;
  LDSizeMetric _metric;
  LDTreemapOptions _options;
  LDTreemap *_treemap;
  NSBitmapImageRep *_bitmap;
  NSTimer *_renderTimer;
  BOOL _needsRender;
  BOOL _dimmed;
  LDFileNode *_hoverNode;
}

- (id)delegate;
- (void)setDelegate:(id)delegate;

// Sets the scanned tree; resets zoom and selection.
- (void)setRootNode:(LDFileNode *)rootNode metric:(LDSizeMetric)metric colorIndexes:(NSDictionary *)colorIndexes;
- (LDFileNode *)rootNode;
- (LDTreemapOptions)options;
- (void)setOptions:(LDTreemapOptions)options;

- (LDFileNode *)selectedNode;
- (void)setSelectedNode:(LDFileNode *)node;
// When set, every file with this extension is highlighted instead of the
// selection (WinDirStat does this while the extension list has focus).
- (NSString *)highlightedExtensionKey;
- (void)setHighlightedExtensionKey:(NSString *)extensionKey;
// Dims the treemap while a scan is running.
- (BOOL)isDimmed;
- (void)setDimmed:(BOOL)dimmed;

- (LDFileNode *)zoomNode;
- (BOOL)isZoomed;
- (BOOL)canZoomIn;
- (BOOL)canZoomOut;
- (BOOL)canSelectParent;
- (IBAction)zoomIn:(id)sender;
- (IBAction)zoomOut:(id)sender;
- (IBAction)resetZoom:(id)sender;
- (IBAction)selectParent:(id)sender;

- (LDFileNode *)nodeAtPoint:(NSPoint)point;
- (LDTreemap *)treemap;

@end
