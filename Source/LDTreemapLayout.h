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

// gridColor's "Auto" (WinDirStat's CLR_DEFAULT): the window colour tinted
// 12% towards the text colour (CTreeMap::GetGridColor).
#define LDTreemapGridColorAuto ((LDRGBColor)0xFF000000)

typedef struct {
  LDTreemapStyle style;
  BOOL grid;
  LDRGBColor gridColor;
  double brightness;   // 0..1
  double height;       // cushion height "H"
  double scaleFactor;  // cushion scale "F", 0..1
  double ambientLight; // "Ia", 0..1
  double saturation;   // 0..1, blends each colour towards its grey (2.9)
  double lightSourceX; // negative = left
  double lightSourceY; // negative = top
  // WinDirStat 2.6-2.8 folder frames (f9ada432, 549d7f20): folders whose
  // shorter side is at least folderFramesDrawThreshold pixels get a frame
  // and, when the name fits, a header; their children go inside.
  BOOL showFolderFrames;
  int folderFramesDrawThreshold;
} LDTreemapOptions;

// What folder frames need from the view: the header height in pixels and
// the window and text colours their branch colours are blended from
// (CFolderColors uses COLOR_WINDOW and COLOR_WINDOWTEXT).
typedef struct {
  int headerHeight;
  LDRGBColor background;
  LDRGBColor text;
} LDTreemapFolderStyle;

// A folder name's width in pixels, as its header would draw it.
typedef double (^LDTreemapTextWidth)(NSString *text);

FOUNDATION_EXPORT LDTreemapOptions LDTreemapDefaultOptions(void);

// WinDirStat 2.9's colour presets (CTreeMap::GetPreset, 181ccb4f). A
// preset sets the appearance: grid, grid colour, brightness, saturation,
// cushion shading, height, scale factor and light source.
typedef enum {
  LDTreemapPresetClassic = 0,
  LDTreemapPresetCalm,
  LDTreemapPresetFlat,
  LDTreemapPresetPastel,
  LDTreemapPresetHighContrast,
  LDTreemapPresetCount
} LDTreemapPreset;

// The default options with preset's appearance.
FOUNDATION_EXPORT LDTreemapOptions LDTreemapPresetOptions(LDTreemapPreset preset);
// options with appearance's appearance (CTreeMap::Options::SetAppearance).
FOUNDATION_EXPORT LDTreemapOptions LDTreemapOptionsWithAppearance(LDTreemapOptions options, LDTreemapOptions appearance);
// The preset whose appearance options has, compared in whole percent as
// CTreeMap::GetMatchingPreset does; NO when none (a custom appearance).
FOUNDATION_EXPORT BOOL LDTreemapMatchingPreset(LDTreemapOptions options, LDTreemapPreset *preset);
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
  LDTreemapFolderStyle _folderStyle;
  LDTreemapTextWidth _textWidth;
  struct LDTreemapFrame *_frames;
  NSUInteger _frameCount;
  NSMapTable *_branchIndexes;
}

// Lays out rootNode (sizes from metric) in a width x height area at (0, 0).
// Children must already be sorted by descending size for the metric.
// Folder frames are drawn without headers; see below for headers.
- (id)initWithRootNode:(LDFileNode *)rootNode
                metric:(LDSizeMetric)metric
                 width:(int)width
                height:(int)height
               options:(LDTreemapOptions)options;
// The same, with folder headers: textWidth measures a folder's name
// (called while laying out, on the caller's thread).
- (id)initWithRootNode:(LDFileNode *)rootNode
                metric:(LDSizeMetric)metric
                 width:(int)width
                height:(int)height
               options:(LDTreemapOptions)options
           folderStyle:(LDTreemapFolderStyle)folderStyle
             textWidth:(LDTreemapTextWidth)textWidth;

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
// the final palette entry. An empty treemap renders fully transparent.
- (NSData *)renderRGBAWithColorIndexes:(NSDictionary *)colorIndexes;

// The folders that got a frame, parents first: the whole frame, and the
// header strip inside it (empty when the name did not fit).
- (void)enumerateFolderFramesUsingBlock:(void (^)(LDFileNode *node, LDTreemapRect frame, LDTreemapRect header))block;
// CFolderColors::GetColor: the scan root a faint text tint of the window
// colour; every other folder the palette colour of its top-level branch
// (chosen by name among its siblings), fading towards the window colour
// with depth. Frames are this dimmed by 10%, headers this.
- (LDRGBColor)folderColorForNode:(LDFileNode *)node;

// YES when the root has no size (0 B, or unreadable): WinDirStat fills such a
// treemap with the window colour rather than drawing cells.
- (BOOL)isEmpty;

// Color used to paint a leaf node (before shading). <Free Space> and
// <Unknown> carry an LDRGBColorFlag, as in WinDirStat.
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
