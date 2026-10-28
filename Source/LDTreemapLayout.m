#import "LDTreemapLayout.h"
#import "LDExtensionStats.h"
#import "LDTreemapItem.h"
#import "LDHardLinks.h"

#include <float.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

// WinDirStat equalizes palette colors to this brightness and scales by
// brightness / PALETTE_BRIGHTNESS when shading.
static const double LDPaletteBrightness = 0.6;
// KDirStat rows accept children while childWidth / rowHeight >= this.
static const double LDKDirStatMinProportion = 0.4;

LDTreemapOptions LDTreemapDefaultOptions(void)
{
  // TreeMap.h DefaultOptions. The header comments (0.84/0.40/0.90/0.15) are
  // stale; these are the values WinDirStat actually uses. Zeroed first, so
  // options compare equal with memcmp.
  LDTreemapOptions options;
  memset(&options, 0, sizeof(options));
  options.style = LDTreemapStyleKDirStat;
  options.grid = NO;
  options.gridColor = LDRGB(0, 0, 0);
  options.brightness = 0.88;
  options.height = 0.38;
  options.scaleFactor = 0.91;
  options.ambientLight = 0.13;
  options.lightSourceX = -1.0;
  options.lightSourceY = -1.0;
  options.saturation = 1.0;
  options.showFolderFrames = NO;
  options.folderFramesDrawThreshold = 5;
  return options;
}

LDTreemapOptions LDTreemapPresetOptions(LDTreemapPreset preset)
{
  LDTreemapOptions options = LDTreemapDefaultOptions();
  if (preset == LDTreemapPresetClassic) {
    return options;
  }
  options.grid = YES;
  options.gridColor = LDTreemapGridColorAuto;
  options.brightness = 0.72;
  options.saturation = 0.65;
  options.height = 0.15;
  options.scaleFactor = 0.80;
  options.ambientLight = 0.70;
  switch (preset) {
    case LDTreemapPresetFlat:
      options.saturation = 0.85;
      options.height = 0.0;
      options.ambientLight = 1.0;
      break;
    case LDTreemapPresetPastel:
      options.brightness = 0.82;
      options.saturation = 0.40;
      options.height = 0.10;
      options.ambientLight = 0.85;
      break;
    case LDTreemapPresetHighContrast:
      options.gridColor = LDRGB(0, 0, 0);
      options.brightness = 0.62;
      options.saturation = 1.0;
      options.height = 0.0;
      options.ambientLight = 1.0;
      break;
    default:
      break;
  }
  return options;
}

LDTreemapOptions LDTreemapOptionsWithAppearance(LDTreemapOptions options, LDTreemapOptions appearance)
{
  options.grid = appearance.grid;
  options.gridColor = appearance.gridColor;
  options.brightness = appearance.brightness;
  options.saturation = appearance.saturation;
  options.ambientLight = appearance.ambientLight;
  options.height = appearance.height;
  options.scaleFactor = appearance.scaleFactor;
  options.lightSourceX = appearance.lightSourceX;
  options.lightSourceY = appearance.lightSourceY;
  return options;
}

// CTreeMap::Options::RoundDouble.
static int LDPercent(double value)
{
  double scaled = value * 100.0;
  return (int)(scaled + (scaled < 0.0 ? -0.5 : 0.5));
}

static BOOL LDSameAppearance(LDTreemapOptions a, LDTreemapOptions b)
{
  return a.grid == b.grid && (!a.grid || a.gridColor == b.gridColor)
         && LDPercent(a.brightness) == LDPercent(b.brightness) && LDPercent(a.saturation) == LDPercent(b.saturation)
         && LDPercent(a.ambientLight) == LDPercent(b.ambientLight) && LDPercent(a.height) == LDPercent(b.height)
         && LDPercent(a.scaleFactor) == LDPercent(b.scaleFactor)
         && LDPercent(a.lightSourceX) == LDPercent(b.lightSourceX) && LDPercent(a.lightSourceY) == LDPercent(b.lightSourceY);
}

BOOL LDTreemapMatchingPreset(LDTreemapOptions options, LDTreemapPreset *preset)
{
  int candidate = 0;
  for (candidate = 0; candidate < LDTreemapPresetCount; candidate++) {
    if (LDSameAppearance(options, LDTreemapPresetOptions((LDTreemapPreset)candidate))) {
      if (preset) {
        *preset = (LDTreemapPreset)candidate;
      }
      return YES;
    }
  }
  return NO;
}

// A folder that got a frame (CTreeMap's FolderDrawInfo).
struct LDTreemapFrame {
  uint32_t cell;
  BOOL header;
};

// CItem::IsScanRoot: the tree's root, or a root of a multi-root scan.
static BOOL LDIsScanRoot(LDFileNode *node)
{
  return ![node parent] || [[node parent] isComputer];
}

// CColorSpace::BlendColor.
static LDRGBColor LDBlendColor(LDRGBColor color, LDRGBColor background, double amount)
{
  return LDRGB((int)(LDRGBRed(color) * (1.0 - amount) + LDRGBRed(background) * amount),
               (int)(LDRGBGreen(color) * (1.0 - amount) + LDRGBGreen(background) * amount),
               (int)(LDRGBBlue(color) * (1.0 - amount) + LDRGBBlue(background) * amount));
}

// CColorSpace::DimColor with its default factor.
static LDRGBColor LDDimColor(LDRGBColor color)
{
  return LDRGB((int)(LDRGBRed(color) * 0.9f), (int)(LDRGBGreen(color) * 0.9f), (int)(LDRGBBlue(color) * 0.9f));
}

BOOL LDTreemapOptionsUseCushions(LDTreemapOptions options)
{
  return options.ambientLight < 1.0 && options.height > 0.0 && options.scaleFactor > 0.0;
}

static void LDAddRidge(LDTreemapRect rect, double *surface, double h)
{
  int width = LDTreemapRectWidth(rect);
  int height = LDTreemapRectHeight(rect);
  if (width <= 0 || height <= 0) {
    return;
  }

  double h4 = 4.0 * h;
  double wf = h4 / width;
  surface[2] += wf * (rect.right + rect.left);
  surface[0] -= wf;

  double hf = h4 / height;
  surface[3] += hf * (rect.bottom + rect.top);
  surface[1] -= hf;
}

static void LDStorePixel(uint8_t *pixel, int red, int green, int blue)
{
  pixel[0] = (uint8_t)red;
  pixel[1] = (uint8_t)green;
  pixel[2] = (uint8_t)blue;
  pixel[3] = 255;
}

static void LDDrawSolidRect(uint8_t *bitmap, int stride, LDTreemapRect rect, LDRGBColor color, double brightness)
{
  double factor = brightness / LDPaletteBrightness;
  int red = (int)(LDRGBRed(color) * factor);
  int green = (int)(LDRGBGreen(color) * factor);
  int blue = (int)(LDRGBBlue(color) * factor);
  [LDExtensionColor normalizeRed:&red green:&green blue:&blue];

  int y = 0;
  int x = 0;
  for (y = rect.top; y < rect.bottom; y++) {
    uint8_t *row = bitmap + ((size_t)y * stride + rect.left) * 4;
    for (x = rect.left; x < rect.right; x++) {
      LDStorePixel(row, red, green, blue);
      row += 4;
    }
  }
}

static void LDDrawCushion(uint8_t *bitmap, int stride, LDTreemapRect rect, const double *surface,
                          LDRGBColor color, double brightness, LDTreemapOptions options)
{
  double lx = options.lightSourceX;
  double ly = options.lightSourceY;
  double lz = 10.0;
  double length = sqrt(lx * lx + ly * ly + lz * lz);
  lx /= length;
  ly /= length;
  lz /= length;

  double ia = options.ambientLight;
  double is = 1.0 - ia;
  double colR = LDRGBRed(color);
  double colG = LDRGBGreen(color);
  double colB = LDRGBBlue(color);
  double scale = brightness / LDPaletteBrightness;

  int y = 0;
  int x = 0;
  for (y = rect.top; y < rect.bottom; y++) {
    uint8_t *row = bitmap + ((size_t)y * stride + rect.left) * 4;
    double ny = -(2.0 * surface[1] * (y + 0.5) + surface[3]);
    for (x = rect.left; x < rect.right; x++) {
      double nx = -(2.0 * surface[0] * (x + 0.5) + surface[2]);
      double cosa = (nx * lx + ny * ly + lz) / sqrt(nx * nx + ny * ny + 1.0);
      if (cosa > 1.0) {
        cosa = 1.0;
      }

      double pixel = is * cosa;
      if (pixel < 0.0) {
        pixel = 0.0;
      }
      pixel += ia;
      pixel *= scale;

      int red = (int)(colR * pixel);
      int green = (int)(colG * pixel);
      int blue = (int)(colB * pixel);
      [LDExtensionColor normalizeRed:&red green:&green blue:&blue];
      LDStorePixel(row, red, green, blue);
      row += 4;
    }
  }
}

@implementation LDTreemap

- (id)initWithRootNode:(LDFileNode *)rootNode
                metric:(LDSizeMetric)metric
                 width:(int)width
                height:(int)height
               options:(LDTreemapOptions)options
{
  LDTreemapFolderStyle style = {0, LDRGB(255, 255, 255), LDRGB(0, 0, 0)};
  return [self initWithRootNode:rootNode metric:metric width:width height:height options:options
                    folderStyle:style textWidth:nil];
}

- (id)initWithRootNode:(LDFileNode *)rootNode
                metric:(LDSizeMetric)metric
                 width:(int)width
                height:(int)height
               options:(LDTreemapOptions)options
           folderStyle:(LDTreemapFolderStyle)folderStyle
             textWidth:(LDTreemapTextWidth)textWidth
{
  self = [super init];
  if (self) {
    _rootNode = rootNode;
    _metric = metric;
    _options = options;
    _folderStyle = folderStyle;
    _textWidth = [textWidth copy];
    _width = MIN(MAX(width, 0), LDTreemapMaxSide);
    _height = MIN(MAX(height, 0), LDTreemapMaxSide);
    [self layout];
  }
  return self;
}

- (LDFileNode *)rootNode { return _rootNode; }
- (LDSizeMetric)metric { return _metric; }
- (LDTreemapOptions)options { return _options; }
- (int)width { return _width; }
- (int)height { return _height; }
- (NSUInteger)cellCount { return _cellCount; }
- (const LDTreemapCell *)cells { return _cells; }

- (NSInteger)appendCellForNode:(LDFileNode *)node rect:(LDTreemapRect)rect
{
  if (_cellCount == _cellCapacity) {
    _cellCapacity = MAX((NSUInteger)64, _cellCapacity * 2);
    _cells = realloc(_cells, _cellCapacity * sizeof(LDTreemapCell));
  }
  LDTreemapCell *cell = &_cells[_cellCount];
  cell->node = node;
  cell->left = (int16_t)rect.left;
  cell->top = (int16_t)rect.top;
  cell->right = (int16_t)rect.right;
  cell->bottom = (int16_t)rect.bottom;
  cell->firstChild = -1;
  cell->childCount = 0;
  return (NSInteger)_cellCount++;
}

- (LDTreemapRect)rectOfCell:(NSUInteger)index
{
  LDTreemapCell *cell = &_cells[index];
  LDTreemapRect rect = {cell->left, cell->top, cell->right, cell->bottom};
  return rect;
}

- (LDFileNode *)nodeOfCell:(NSUInteger)index
{
  return _cells[index].node;
}

- (BOOL)cellIsLargeEnough:(NSUInteger)index
{
  int gridWidth = _options.grid ? 1 : 0;
  LDTreemapCell *cell = &_cells[index];
  return cell->right - cell->left > gridWidth && cell->bottom - cell->top > gridWidth;
}

- (BOOL)isCellRendered:(NSUInteger)index
{
  return [self cellIsLargeEnough:index] && [_cells[index].node isLeaf];
}

- (unsigned long long)sizeOfNode:(LDFileNode *)node
{
  return [node aggregateSizeForMetric:_metric];
}

// The leading children with a size (children are sorted by descending
// size), their sizes stored in *sizes, which is grown as needed.
- (NSUInteger)sizedChildren:(NSArray *)children sizes:(double **)sizes capacity:(NSUInteger *)capacity
{
  NSUInteger count = [children count];
  if (count > *capacity) {
    *capacity = MAX(count, *capacity * 2);
    *sizes = realloc(*sizes, *capacity * sizeof(double));
  }
  NSUInteger i = 0;
  for (LDFileNode *child in children) {
    unsigned long long size = [child aggregateSizeForMetric:_metric];
    if (size == 0) {
      break;
    }
    (*sizes)[i++] = (double)size;
  }
  return i;
}

// Port of the layout half of CTreeMap::DrawTreeMap. Cells are visited in
// creation order, which is breadth-first, so no explicit stack is needed.
- (void)layout
{
  free(_cells);
  _cells = NULL;
  _cellCount = 0;
  _cellCapacity = 0;
  free(_frames);
  _frames = NULL;
  _frameCount = 0;
  NSUInteger frameCapacity = 0;

  if (!_rootNode || _width <= 0 || _height <= 0) {
    return;
  }

  LDTreemapRect area = {0, 0, _width, _height};
  [self appendCellForNode:_rootNode rect:area];
  if ([self sizeOfNode:_rootNode] == 0) {
    return;
  }

  double *sizes = NULL;
  NSUInteger sizesCapacity = 0;
  NSUInteger index = 0;
  for (index = 0; index < _cellCount; index++) {
    LDFileNode *node = _cells[index].node;
    if (![self cellIsLargeEnough:index] || [node isLeaf]) {
      continue;
    }
    @autoreleasepool {
      LDTreemapRect area = [self rectOfCell:index];
      int width = LDTreemapRectWidth(area);
      int height = LDTreemapRectHeight(area);
      if (_options.showFolderFrames && index != 0 && MIN(width, height) >= _options.folderFramesDrawThreshold) {
        // A 1-pixel frame, and a header when the name fits; the children
        // go inside.
        int headerHeight = _folderStyle.headerHeight;
        BOOL header = headerHeight > 0 && _textWidth && height > headerHeight + 2
                      && _textWidth([node displayName]) <= width - 2 - 6;
        if (_frameCount == frameCapacity) {
          NSUInteger grown = MAX((NSUInteger)32, frameCapacity * 2);
          struct LDTreemapFrame *frames = realloc(_frames, grown * sizeof(struct LDTreemapFrame));
          if (frames) {
            _frames = frames;
            frameCapacity = grown;
          }
        }
        // Out of memory, the folder is laid out unframed.
        if (_frameCount < frameCapacity) {
          _frames[_frameCount].cell = (uint32_t)index;
          _frames[_frameCount].header = header;
          _frameCount++;
          area.left++;
          area.top++;
          area.right--;
          area.bottom--;
          if (header) {
            area.top += headerHeight;
          }
          int gridWidth = _options.grid ? 1 : 0;
          if (LDTreemapRectWidth(area) <= gridWidth || LDTreemapRectHeight(area) <= gridWidth) {
            continue;
          }
        }
      }
      NSArray *children = [node children];
      NSUInteger count = [self sizedChildren:children sizes:&sizes capacity:&sizesCapacity];
      if (count == 0) {
        continue;
      }
      int32_t firstChild = (int32_t)_cellCount;
      if (_options.style == LDTreemapStyleSequoiaView) {
        [self layoutSequoiaChildren:children sizes:sizes count:count ofCell:(NSInteger)index inRect:area];
      } else {
        [self layoutKDirStatChildren:children sizes:sizes count:count ofCell:(NSInteger)index inRect:area];
      }
      _cells[index].firstChild = firstChild;
      _cells[index].childCount = (uint32_t)(_cellCount - (NSUInteger)firstChild);
    }
  }
  free(sizes);
}

// Port of TreeMapLayout.cpp's ArrangeRows (v2.9.3; KDirStat style). sizes
// hold the children's integer sizes (exact as doubles), largest first and
// none zero, so its zero-weight cases do not arise.
- (void)layoutKDirStatChildren:(NSArray *)children sizes:(const double *)sizes count:(NSUInteger)count
                        ofCell:(NSInteger)index inRect:(LDTreemapRect)bounds
{
  double parentWeight = (double)[self sizeOfNode:_cells[index].node];
  int boundsWidth = LDTreemapRectWidth(bounds);
  int boundsHeight = LDTreemapRectHeight(bounds);
  BOOL horizontalRows = boundsWidth >= boundsHeight;
  double normalizedWidth = horizontalRows ? (double)boundsWidth / boundsHeight : (double)boundsHeight / boundsWidth;
  int rowExtent = horizontalRows ? boundsHeight : boundsWidth;
  int columnExtent = horizontalRows ? boundsWidth : boundsHeight;

  double top = horizontalRows ? bounds.top : bounds.left;
  NSUInteger rowBegin = 0;
  while (rowBegin < count) {
    double rowWeight = 0.0;
    double rowFraction = 0.0;
    NSUInteger rowEnd = rowBegin;
    for (; rowEnd < count; rowEnd++) {
      double childWeight = sizes[rowEnd];
      rowWeight += childWeight;
      double candidateFraction = rowWeight / parentWeight;
      double childWidth = childWeight / parentWeight * normalizedWidth / candidateFraction;
      if (childWidth / candidateFraction < LDKDirStatMinProportion) {
        rowWeight -= childWeight;
        break;
      }
      rowFraction = candidateFraction;
    }
    if (rowEnd == rowBegin) {
      return;
    }

    double nextTop = top + rowFraction * rowExtent;
    int bottom = rowEnd == count ? (horizontalRows ? bounds.bottom : bounds.right) : (int)nextTop;
    double left = horizontalRows ? bounds.left : bounds.top;
    NSUInteger i = 0;
    for (i = rowBegin; i < rowEnd; i++) {
      double nextLeft = left + sizes[i] / rowWeight * columnExtent;
      int right = i + 1 == rowEnd ? (horizontalRows ? bounds.right : bounds.bottom) : (int)nextLeft;
      LDTreemapRect childRect;
      if (horizontalRows) {
        childRect = (LDTreemapRect){(int)left, (int)top, right, bottom};
      } else {
        childRect = (LDTreemapRect){(int)top, (int)left, bottom, right};
      }
      [self appendCellForNode:[children objectAtIndex:i] rect:childRect];
      left = nextLeft;
    }
    top = nextTop;
    rowBegin = rowEnd;
  }
}

// Port of TreeMapLayout.cpp's ArrangeSquarified (v2.9.3; SequoiaView style).
- (void)layoutSequoiaChildren:(NSArray *)children sizes:(const double *)sizes count:(NSUInteger)count
                       ofCell:(NSInteger)index inRect:(LDTreemapRect)remaining
{
  double remainingWeight = (double)[self sizeOfNode:_cells[index].node];
  double weightPerPixel = remainingWeight / LDTreemapRectWidth(remaining) / LDTreemapRectHeight(remaining);
  NSUInteger head = 0;

  while (head < count && LDTreemapRectWidth(remaining) > 0 && LDTreemapRectHeight(remaining) > 0) {
    BOOL horizontal = LDTreemapRectWidth(remaining) >= LDTreemapRectHeight(remaining);
    int rowThickness = horizontal ? LDTreemapRectHeight(remaining) : LDTreemapRectWidth(remaining);
    double squaredRowWeight = (double)rowThickness * rowThickness * weightPerPixel;

    NSUInteger rowBegin = head;
    NSUInteger rowEnd = head;
    double worst = DBL_MAX;
    double largest = sizes[rowBegin];
    double rowWeight = 0.0;
    while (rowEnd < count) {
      double childWeight = sizes[rowEnd];
      double nextWeight = rowWeight + childWeight;
      double squaredWeight = nextWeight * nextWeight;
      double nextWorst = MAX(squaredRowWeight * largest / squaredWeight, squaredWeight / squaredRowWeight / childWeight);
      if (nextWorst > worst) {
        break;
      }
      rowWeight += childWeight;
      rowEnd++;
      worst = nextWorst;
    }
    if (rowWeight == 0.0) {
      break;
    }

    int remainingExtent = horizontal ? LDTreemapRectWidth(remaining) : LDTreemapRectHeight(remaining);
    int rowWidth = remainingExtent;
    if (rowWeight < remainingWeight) {
      rowWidth = MIN(MAX((int)(rowWeight / remainingWeight * remainingExtent), 1), remainingExtent);
    }
    LDTreemapRect rowBounds = remaining;
    if (horizontal) {
      rowBounds.right = rowBounds.left + rowWidth;
    } else {
      rowBounds.bottom = rowBounds.top + rowWidth;
    }

    double begin = horizontal ? rowBounds.top : rowBounds.left;
    NSUInteger i = 0;
    for (i = rowBegin; i < rowEnd; i++) {
      double next = begin + sizes[i] / rowWeight * (horizontal ? LDTreemapRectHeight(rowBounds) : LDTreemapRectWidth(rowBounds));
      int end = i + 1 == rowEnd ? (horizontal ? rowBounds.bottom : rowBounds.right) : (int)next;
      LDTreemapRect childRect;
      if (horizontal) {
        childRect = (LDTreemapRect){rowBounds.left, (int)begin, rowBounds.right, end};
      } else {
        childRect = (LDTreemapRect){(int)begin, rowBounds.top, end, rowBounds.bottom};
      }
      [self appendCellForNode:[children objectAtIndex:i] rect:childRect];
      begin = next;
    }

    if (horizontal) {
      remaining.left += rowWidth;
    } else {
      remaining.top += rowWidth;
    }
    remainingWeight -= rowWeight;
    head += rowEnd - rowBegin;
  }
}

- (NSInteger)cellIndexAtX:(int)x y:(int)y
{
  if (_cellCount == 0 || !LDTreemapRectContainsPoint([self rectOfCell:0], x, y)) {
    return -1;
  }

  NSUInteger index = 0;
  while (YES) {
    LDTreemapCell *cell = &_cells[index];
    if (![self cellIsLargeEnough:index] || cell->firstChild < 0) {
      return (NSInteger)index;
    }
    NSInteger next = -1;
    uint32_t i = 0;
    for (i = 0; i < cell->childCount; i++) {
      NSUInteger childIndex = (NSUInteger)cell->firstChild + i;
      if (LDTreemapRectContainsPoint([self rectOfCell:childIndex], x, y)) {
        next = (NSInteger)childIndex;
        break;
      }
    }
    if (next < 0) {
      return (NSInteger)index;
    }
    index = (NSUInteger)next;
  }
}

- (void)enumerateRenderedCellsUsingBlock:(void (^)(NSUInteger index, NSUInteger depth))block
{
  if (_cellCount == 0) {
    return;
  }
  // Parents precede their children, so depths fill in one pass.
  uint16_t *depths = calloc(_cellCount, sizeof(uint16_t));
  NSUInteger index = 0;
  for (index = 0; index < _cellCount; index++) {
    LDTreemapCell *cell = &_cells[index];
    uint32_t i = 0;
    for (i = 0; cell->firstChild >= 0 && i < cell->childCount; i++) {
      depths[(NSUInteger)cell->firstChild + i] = depths[index] + 1;
    }
    if ([self isCellRendered:index]) {
      block(index, depths[index]);
    }
  }
  free(depths);
}

- (NSInteger)cellIndexForNode:(LDFileNode *)node
{
  if (_cellCount == 0 || !node || ![_rootNode isAncestorOf:node]) {
    return -1;
  }

  NSMutableArray *ancestry = [NSMutableArray array];
  LDFileNode *cursor = node;
  while (cursor && cursor != _rootNode) {
    [ancestry insertObject:cursor atIndex:0];
    cursor = [cursor parent];
  }

  NSInteger index = 0;
  NSEnumerator *enumerator = [ancestry objectEnumerator];
  LDFileNode *step = nil;
  while ((step = [enumerator nextObject])) {
    LDTreemapCell *cell = &_cells[index];
    NSInteger next = -1;
    NSUInteger i = 0;
    for (i = 0; cell->firstChild >= 0 && i < cell->childCount; i++) {
      if (_cells[cell->firstChild + (NSInteger)i].node == step) {
        next = cell->firstChild + (NSInteger)i;
        break;
      }
    }
    if (next < 0) {
      break;
    }
    index = next;
  }
  return index;
}

+ (LDRGBColor)colorForNode:(LDFileNode *)node colorIndexes:(NSDictionary *)colorIndexes
{
  if (LDIsHardLinkItem(node)) {
    return [LDHardLinks treemapColor];
  }
  LDFileNodeKind kind = [node kind];
  // CItem::GetGraphColor.
  if (kind == LDFileNodeKindUnknown) {
    return LDRGB(255, 255, 0) | LDRGBColorFlagLighter;
  }
  if (kind == LDFileNodeKindFreeSpace) {
    return LDRGB(100, 100, 100) | LDRGBColorFlagDarker;
  }
  if (kind != LDFileNodeKindFile && kind != LDFileNodeKindSymlink) {
    return LDRGB(0, 0, 0);
  }
  NSString *key = [node extensionKey];
  NSNumber *index = [colorIndexes objectForKey:key];
  NSUInteger paletteIndex = index ? [index unsignedIntegerValue] : [LDExtensionColor paletteCount] - 1;
  return [LDExtensionColor paletteColorAtIndex:paletteIndex];
}

// The flag handling of CTreeMap::RenderRectangle: returns the brightness to
// draw with and strips the flags from color.
// The saturation step of PrepareRenderColor (v2.9.3): the colour blended
// towards its grey by 1 - saturation.
static LDRGBColor LDDesaturate(LDRGBColor color, double saturation)
{
  if (saturation >= 1.0) {
    return color;
  }
  double amount = 1.0 - MAX(saturation, 0.0);
  int gray = (int)((LDRGBRed(color) + LDRGBGreen(color) + LDRGBBlue(color)) / 3);
  return LDRGB((int)(LDRGBRed(color) * (1.0 - amount) + gray * amount),
               (int)(LDRGBGreen(color) * (1.0 - amount) + gray * amount),
               (int)(LDRGBBlue(color) * (1.0 - amount) + gray * amount));
}

static double LDResolveColorFlags(LDRGBColor *color, double brightness)
{
  LDRGBColor flags = *color & LDRGBColorFlagMask;
  if (flags == 0) {
    return brightness;
  }
  *color = [LDExtensionColor makeBrightColor:*color & ~LDRGBColorFlagMask brightness:LDPaletteBrightness];
  if (flags & LDRGBColorFlagDarker) {
    return brightness * 0.66;
  }
  return MIN(brightness * 1.2, 1.0);
}

typedef struct {
  NSUInteger index;
  double surface[4];
  double height;
} LDRenderFrame;

- (BOOL)isEmpty
{
  return _cellCount == 0 || [self sizeOfNode:_rootNode] == 0;
}

// Port of the drawing half of CTreeMap::DrawTreeMap: walks the cells
// depth-first, adding each cell's ridge to its parent's cushion surface.
- (NSData *)renderRGBAWithColorIndexes:(NSDictionary *)colorIndexes
{
  NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)_width * (NSUInteger)_height * 4];
  if (_width <= 0 || _height <= 0) {
    return data;
  }
  uint8_t *bitmap = [data mutableBytes];
  LDTreemapRect area = {0, 0, _width, _height};

  // Left transparent, so the view's background shows through.
  if ([self isEmpty]) {
    return data;
  }

  LDDrawSolidRect(bitmap, _width, area, [self gridColor], LDPaletteBrightness);
  BOOL cushions = LDTreemapOptionsUseCushions(_options);
  NSMutableDictionary *colorCache = [NSMutableDictionary dictionary];

  NSUInteger capacity = 256;
  NSUInteger depth = 0;
  LDRenderFrame *stack = malloc(capacity * sizeof(LDRenderFrame));
  stack[0].index = 0;
  memset(stack[0].surface, 0, sizeof(stack[0].surface));
  stack[0].height = _options.height;
  depth = 1;

  while (depth > 0) {
    LDRenderFrame frame = stack[--depth];
    LDTreemapCell *cell = &_cells[frame.index];
    if (![self cellIsLargeEnough:frame.index]) {
      continue;
    }
    LDTreemapRect rect = [self rectOfCell:frame.index];
    if (cushions && frame.index != 0) {
      LDAddRidge(rect, frame.surface, frame.height);
    }

    if ([cell->node isLeaf]) {
      if (_options.grid) {
        rect.top++;
        rect.left++;
        if (LDTreemapRectWidth(rect) <= 0 || LDTreemapRectHeight(rect) <= 0) {
          continue;
        }
      }
      LDRGBColor color = LDRGB(0, 0, 0);
      LDFileNodeKind kind = [cell->node kind];
      if ([cell->node isSpaceItem]) {
        color = [LDTreemap colorForNode:cell->node colorIndexes:colorIndexes];
      } else if (kind == LDFileNodeKindFile || kind == LDFileNodeKindSymlink) {
        NSString *key = [cell->node extensionKey];
        NSNumber *cached = [colorCache objectForKey:key];
        if (!cached) {
          cached = [NSNumber numberWithUnsignedInt:[LDTreemap colorForNode:cell->node colorIndexes:colorIndexes]];
          [colorCache setObject:cached forKey:key];
        }
        color = [cached unsignedIntValue];
      } else if (LDIsHardLinkItem(cell->node)) {
        color = [LDHardLinks treemapColor];
      }
      double brightness = LDResolveColorFlags(&color, _options.brightness);
      color = LDDesaturate(color, _options.saturation);
      if (cushions) {
        LDDrawCushion(bitmap, _width, rect, frame.surface, color, brightness, _options);
      } else {
        LDDrawSolidRect(bitmap, _width, rect, color, brightness);
      }
      continue;
    }

    if (cell->firstChild < 0) {
      continue;
    }
    if (depth + cell->childCount > capacity) {
      capacity = MAX(capacity * 2, depth + cell->childCount);
      stack = realloc(stack, capacity * sizeof(LDRenderFrame));
    }
    uint32_t i = 0;
    for (i = 0; i < cell->childCount; i++) {
      LDRenderFrame *child = &stack[depth++];
      child->index = (NSUInteger)cell->firstChild + i;
      memcpy(child->surface, frame.surface, sizeof(child->surface));
      child->height = frame.height * _options.scaleFactor;
    }
  }
  free(stack);

  // Folder frames and headers over the cells (CTreeMap::DrawTreemap draws
  // them after blitting); the view draws the names.
  NSUInteger f = 0;
  for (f = 0; f < _frameCount; f++) {
    LDTreemapRect frame = [self rectOfCell:_frames[f].cell];
    if (LDTreemapRectWidth(frame) <= 2 || LDTreemapRectHeight(frame) <= 2) {
      continue;
    }
    LDRGBColor color = [self folderColorForNode:_cells[_frames[f].cell].node];
    LDRGBColor border = LDDimColor(color);
    LDTreemapRect edge = frame;
    edge.bottom = edge.top + 1;
    LDDrawSolidRect(bitmap, _width, edge, border, LDPaletteBrightness);
    edge.top = frame.bottom - 1;
    edge.bottom = frame.bottom;
    LDDrawSolidRect(bitmap, _width, edge, border, LDPaletteBrightness);
    edge = frame;
    edge.right = edge.left + 1;
    LDDrawSolidRect(bitmap, _width, edge, border, LDPaletteBrightness);
    edge.left = frame.right - 1;
    edge.right = frame.right;
    LDDrawSolidRect(bitmap, _width, edge, border, LDPaletteBrightness);
    if (_frames[f].header) {
      LDTreemapRect header = {frame.left + 1, frame.top + 1, frame.right - 1, frame.top + 1 + _folderStyle.headerHeight};
      LDDrawSolidRect(bitmap, _width, header, color, LDPaletteBrightness);
    }
  }
  return data;
}

// CTreeMap::GetGridColor.
- (LDRGBColor)gridColor
{
  if (_options.gridColor == LDTreemapGridColorAuto) {
    return LDBlendColor(_folderStyle.background, _folderStyle.text, 0.12);
  }
  return _options.gridColor;
}

- (void)enumerateFolderFramesUsingBlock:(void (^)(LDFileNode *node, LDTreemapRect frame, LDTreemapRect header))block
{
  NSUInteger f = 0;
  for (f = 0; f < _frameCount; f++) {
    LDTreemapRect frame = [self rectOfCell:_frames[f].cell];
    LDTreemapRect header = {frame.left + 1, frame.top + 1, frame.left + 1, frame.top + 1};
    if (_frames[f].header) {
      header.right = frame.right - 1;
      header.bottom = frame.top + 1 + _folderStyle.headerHeight;
    }
    block(_cells[_frames[f].cell].node, frame, header);
  }
}

// CFolderColors::GetColor.
- (LDRGBColor)folderColorForNode:(LDFileNode *)node
{
  LDRGBColor background = _folderStyle.background;
  if (!node || LDIsScanRoot(node)) {
    return LDBlendColor(background, _folderStyle.text, 0.12);
  }
  static const LDRGBColor palette[8] = {
    LDRGB(79, 157, 232), LDRGB(71, 173, 128), LDRGB(230, 159, 0), LDRGB(213, 94, 0),
    LDRGB(168, 135, 224), LDRGB(86, 180, 233), LDRGB(204, 121, 167), LDRGB(230, 205, 70)
  };
  // The branch: the ancestor just below a scan root.
  NSUInteger depth = 0;
  LDFileNode *ancestor = node;
  while ([ancestor parent] && !LDIsScanRoot([ancestor parent])) {
    ancestor = [ancestor parent];
    depth++;
  }
  if (!_branchIndexes) {
    _branchIndexes = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsOpaqueMemory | NSPointerFunctionsOpaquePersonality
                                           valueOptions:NSPointerFunctionsStrongMemory];
  }
  NSNumber *branch = [_branchIndexes objectForKey:ancestor];
  if (!branch) {
    // Each sibling folder, largest (physical) first, takes the palette
    // entry its name hashes to, or the next one free.
    NSMutableArray *siblings = [NSMutableArray array];
    for (LDFileNode *sibling in [[ancestor parent] children]) {
      if (![sibling isLeaf]) {
        [siblings addObject:sibling];
      }
    }
    [siblings sortUsingComparator:^NSComparisonResult(LDFileNode *left, LDFileNode *right) {
      unsigned long long a = [left aggregateAllocatedSize];
      unsigned long long b = [right aggregateAllocatedSize];
      if (a != b) {
        return a > b ? NSOrderedAscending : NSOrderedDescending;
      }
      return [[left displayName] compare:[right displayName] options:NSLiteralSearch];
    }];
    unsigned int used = 0;
    for (LDFileNode *sibling in siblings) {
      if (used == (1u << 8) - 1) {
        used = 0;
      }
      NSString *name = [sibling displayName];
      uint32_t hash = 2166136261u;
      NSUInteger i = 0;
      for (i = 0; i < [name length]; i++) {
        hash = (hash ^ [name characterAtIndex:i]) * 16777619u;
      }
      NSUInteger index = hash % 8;
      while (used & (1u << index)) {
        index = (index + 1) % 8;
      }
      used |= 1u << index;
      [_branchIndexes setObject:[NSNumber numberWithUnsignedInteger:index] forKey:sibling];
    }
    branch = [_branchIndexes objectForKey:ancestor];
  }
  return LDBlendColor(palette[[branch unsignedIntegerValue]], background, 0.22 + MIN(depth, (NSUInteger)6) * 0.06);
}

+ (NSData *)renderSwatchRGBAWithColor:(LDRGBColor)color
                                width:(int)width
                               height:(int)height
                              options:(LDTreemapOptions)options
{
  NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)MAX(width, 0) * (NSUInteger)MAX(height, 0) * 4];
  if (width <= 0 || height <= 0) {
    return data;
  }
  LDTreemapRect rect = {0, 0, width, height};
  double surface[4] = {0.0, 0.0, 0.0, 0.0};
  color = LDDesaturate(color, options.saturation);
  LDAddRidge(rect, surface, options.height * options.scaleFactor);
  if (LDTreemapOptionsUseCushions(options)) {
    LDDrawCushion([data mutableBytes], width, rect, surface, color, options.brightness, options);
  } else {
    LDDrawSolidRect([data mutableBytes], width, rect, color, options.brightness);
  }
  return data;
}

- (void)dealloc
{
  free(_cells);
  free(_frames);
}

@end

@implementation LDTreemapLayout

+ (NSArray *)layoutItemsForRootNode:(LDFileNode *)rootNode inRect:(NSRect)rect
{
  return [self layoutItemsForRootNode:rootNode
                               metric:LDSizeMetricLogical
                               inRect:rect
                              options:LDTreemapDefaultOptions()];
}

+ (NSArray *)layoutItemsForRootNode:(LDFileNode *)rootNode
                             metric:(LDSizeMetric)metric
                             inRect:(NSRect)rect
                            options:(LDTreemapOptions)options
{
  NSMutableArray *items = [NSMutableArray array];
  if (!rootNode) {
    return items;
  }
  [rootNode sortChildrenByMetric:metric];
  LDTreemap *treemap = [[LDTreemap alloc] initWithRootNode:rootNode
                                                    metric:metric
                                                     width:(int)floor(rect.size.width)
                                                    height:(int)floor(rect.size.height)
                                                   options:options];
  [treemap enumerateRenderedCellsUsingBlock:^(NSUInteger index, NSUInteger depth) {
    LDTreemapRect r = [treemap rectOfCell:index];
    LDFileNode *node = [treemap nodeOfCell:index];
    NSRect itemRect = NSMakeRect(rect.origin.x + r.left,
                                 rect.origin.y + r.top,
                                 LDTreemapRectWidth(r),
                                 LDTreemapRectHeight(r));
    [items addObject:[LDTreemapItem itemWithNode:node
                                            rect:itemRect
                                    extensionKey:[node extensionKey]
                                           depth:depth]];
  }];
  return items;
}

+ (id)itemAtPoint:(NSPoint)point inItems:(NSArray *)items
{
  LDTreemapItem *best = nil;
  NSEnumerator *enumerator = [items objectEnumerator];
  LDTreemapItem *item = nil;
  while ((item = [enumerator nextObject])) {
    if (NSPointInRect(point, [item rect]) && (!best || [item depth] >= [best depth])) {
      best = item;
    }
  }
  return best;
}

@end
