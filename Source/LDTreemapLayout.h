#import <Foundation/Foundation.h>
#import "LDExtensionColor.h"
#import "LDFileNode.h"

// A port of WinDirStat's CTreeMap (references/WinDirStat
// windirstat/Controls/TreeMap.cpp): KDirStat and SequoiaView layouts plus
// cushion shading. Pure Foundation; the view only blits the rendered pixels.

typedef enum {
  LDTreemapStyleKDirStat = 0,   // Children laid out in rows (WinDirStat default)
  LDTreemapStyleSequoiaView = 1 // Classic squarification
} LDTreemapStyle;

typedef struct {
  LDTreemapStyle style;
  BOOL grid;
  LDRGBColor gridColor;
  double brightness;   // 0..1
  double height;       // cushion height "H"
  double scaleFactor;  // cushion scale "F", 0..1
  double ambientLight; // "Ia", 0..1
  double lightSourceX; // negative = left
  double lightSourceY; // negative = top
} LDTreemapOptions;

FOUNDATION_EXPORT LDTreemapOptions LDTreemapDefaultOptions(void);
FOUNDATION_EXPORT BOOL LDTreemapOptionsUseCushions(LDTreemapOptions options);

// Half-open integer rectangle, like a Windows RECT: [left, right) x [top, bottom).
typedef struct {
  int left;
  int top;
  int right;
  int bottom;
} LDTreemapRect;

static inline int LDTreemapRectWidth(LDTreemapRect rect) { return rect.right - rect.left; }
static inline int LDTreemapRectHeight(LDTreemapRect rect) { return rect.bottom - rect.top; }
static inline BOOL LDTreemapRectContainsPoint(LDTreemapRect rect, int x, int y)
{
  return x >= rect.left && x < rect.right && y >= rect.top && y < rect.bottom;
}

// One laid-out node: 24 bytes, so a treemap of a million files stays small.
// Cushion surfaces are recomputed while rendering instead of being stored.
typedef struct {
  __unsafe_unretained LDFileNode *node; // LDTreemap keeps the root (and so the tree) alive.
  int16_t left;
  int16_t top;
  int16_t right;
  int16_t bottom;
  int32_t firstChild;   // Index of the first child cell, or -1 if not subdivided.
  uint32_t childCount;
} LDTreemapCell;

// Largest treemap side; cell coordinates are 16-bit.
#define LDTreemapMaxSide 32767

@interface LDTreemap : NSObject
{
  LDFileNode *_rootNode;
  LDSizeMetric _metric;
  LDTreemapOptions _options;
  int _width;
  int _height;
  LDTreemapCell *_cells;
  NSUInteger _cellCount;
  NSUInteger _cellCapacity;
}

// Lays out rootNode (sizes from metric) in a width x height area at (0, 0).
// Children must already be sorted by descending size for the metric.
- (id)initWithRootNode:(LDFileNode *)rootNode
                metric:(LDSizeMetric)metric
                 width:(int)width
                height:(int)height
               options:(LDTreemapOptions)options;

- (LDFileNode *)rootNode;
- (LDSizeMetric)metric;
- (LDTreemapOptions)options;
- (int)width;
- (int)height;
- (NSUInteger)cellCount;
- (const LDTreemapCell *)cells;
- (LDTreemapRect)rectOfCell:(NSUInteger)index;
- (LDFileNode *)nodeOfCell:(NSUInteger)index;
// YES for leaves large enough to be painted.
- (BOOL)isCellRendered:(NSUInteger)index;
// Visits painted leaves depth-first with their depth below the root.
- (void)enumerateRenderedCellsUsingBlock:(void (^)(NSUInteger index, NSUInteger depth))block;

// Port of CTreeMap::FindItemByPoint. Returns -1 outside the area.
- (NSInteger)cellIndexAtX:(int)x y:(int)y;
// The cell for node, or for its deepest laid-out ancestor. -1 if node is not
// in this treemap.
- (NSInteger)cellIndexForNode:(LDFileNode *)node;

// Renders the treemap as width * height * 4 bytes of RGBA, top row first.
// colorIndexes maps extension keys to palette indexes; unknown extensions use
// the final palette entry.
- (NSData *)renderRGBAWithColorIndexes:(NSDictionary *)colorIndexes;

// Color used to paint a leaf node (before shading).
+ (LDRGBColor)colorForNode:(LDFileNode *)node colorIndexes:(NSDictionary *)colorIndexes;

// Port of CTreeMap::DrawColorPreview: a single cushion for legend swatches.
+ (NSData *)renderSwatchRGBAWithColor:(LDRGBColor)color
                                width:(int)width
                               height:(int)height
                              options:(LDTreemapOptions)options;

@end

// Compatibility helpers that return LDTreemapItem objects for painted leaves.
@interface LDTreemapLayout : NSObject

+ (NSArray *)layoutItemsForRootNode:(LDFileNode *)rootNode inRect:(NSRect)rect;
+ (NSArray *)layoutItemsForRootNode:(LDFileNode *)rootNode
                             metric:(LDSizeMetric)metric
                             inRect:(NSRect)rect
                            options:(LDTreemapOptions)options;
+ (id)itemAtPoint:(NSPoint)point inItems:(NSArray *)items;

@end
