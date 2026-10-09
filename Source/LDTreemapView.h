#import <AppKit/AppKit.h>
#import "LDFileNode.h"
#import "LDTreemapLayout.h"

@class LDTreemapView;

// The largest rect with whole-number edges inside rect.
FOUNDATION_EXPORT NSRect LDWholePixelRectInside(NSRect rect);

@protocol LDTreemapViewDelegate
- (void)treemapView:(LDTreemapView *)view didSelectNode:(LDFileNode *)node;
- (void)treemapView:(LDTreemapView *)view didHoverNode:(LDFileNode *)node;
- (void)treemapViewDidChangeZoom:(LDTreemapView *)view;
@end

// Displays an LDTreemap the way WinDirStat's CTreeMapView does: a cached
// cushion bitmap, a selection frame or per-extension highlights in the
// highlight colour (white by default), and a framed zoom state. Theme colors
// are used only for the view's chrome.
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
  NSMutableArray *_reselectStack;
  LDRGBColor _highlightColor;
}

- (id)delegate;
- (void)setDelegate:(id)delegate;

// Sets the scanned tree; resets zoom and selection.
- (void)setRootNode:(LDFileNode *)rootNode metric:(LDSizeMetric)metric colorIndexes:(NSDictionary *)colorIndexes;
- (LDFileNode *)rootNode;
- (LDTreemapOptions)options;
- (void)setOptions:(LDTreemapOptions)options;
// WinDirStat's TreeMapHighlightColor, for the selection frame.
- (LDRGBColor)highlightColor;
- (void)setHighlightColor:(LDRGBColor)color;

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
// Zooms to node (nil or the root resets the zoom).
- (void)setZoomNode:(LDFileNode *)node;
- (BOOL)isZoomed;
- (BOOL)canZoomIn;
- (BOOL)canZoomOut;
- (BOOL)canSelectParent;
- (IBAction)zoomIn:(id)sender;
- (IBAction)zoomOut:(id)sender;
- (IBAction)resetZoom:(id)sender;
- (IBAction)selectParent:(id)sender;
// WinDirStat's Reselect Child: undoes Select Parent steps.
- (BOOL)canReselectChild;
- (IBAction)reselectChild:(id)sender;

- (LDFileNode *)nodeAtPoint:(NSPoint)point;
// Where the treemap's cells are drawn, in view coordinates (flipped).
- (NSRect)treemapArea;
- (LDTreemap *)treemap;

@end
