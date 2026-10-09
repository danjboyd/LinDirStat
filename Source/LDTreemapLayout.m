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
  // stale; these are the values WinDirStat actually uses.
  LDTreemapOptions options;
  options.style = LDTreemapStyleKDirStat;
  options.grid = NO;
  options.gridColor = LDRGB(0, 0, 0);
  options.brightness = 0.88;
  options.height = 0.38;
  options.scaleFactor = 0.91;
  options.ambientLight = 0.13;
  options.lightSourceX = -1.0;
  options.lightSourceY = -1.0;
  return options;
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
  self = [super init];
  if (self) {
    _rootNode = rootNode;
    _metric = metric;
    _options = options;
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
      NSArray *children = [node children];
      NSUInteger count = [self sizedChildren:children sizes:&sizes capacity:&sizesCapacity];
      if (count == 0) {
        continue;
      }
      int32_t firstChild = (int32_t)_cellCount;
      if (_options.style == LDTreemapStyleSequoiaView) {
        [self layoutSequoiaChildren:children sizes:sizes count:count ofCell:(NSInteger)index];
      } else {
        [self layoutKDirStatChildren:children sizes:sizes count:count ofCell:(NSInteger)index];
      }
      _cells[index].firstChild = firstChild;
      _cells[index].childCount = (uint32_t)(_cellCount - (NSUInteger)firstChild);
    }
  }
  free(sizes);
}

// Port of CTreeMap::KDirStat_CalculateNextRow.
static double LDKDirStatCalculateNextRow(const double *sizes, NSUInteger count, double parentSize,
                                         NSUInteger nextChild, double width,
                                         NSUInteger *childrenUsed, double *childWidth)
{
  double sizeUsed = 0.0;
  double rowHeight = 0.0;
  NSUInteger i = nextChild;
  for (; i < count; i++) {
    double childSize = sizes[i];
    sizeUsed += childSize;
    double virtualRowHeight = sizeUsed / parentSize;
    double proposedWidth = childSize / parentSize * width / virtualRowHeight;
    if (proposedWidth / virtualRowHeight < LDKDirStatMinProportion && i > nextChild) {
      break;
    }
    rowHeight = virtualRowHeight;
  }

  *childrenUsed = i - nextChild;
  double rowSize = parentSize * rowHeight;
  NSUInteger j = 0;
  for (j = 0; j < *childrenUsed; j++) {
    childWidth[nextChild + j] = sizes[nextChild + j] / rowSize;
  }
  return rowHeight;
}

// Port of the KDirStat branch of CTreeMap::DrawTreeMap.
- (void)layoutKDirStatChildren:(NSArray *)children sizes:(const double *)sizes count:(NSUInteger)count ofCell:(NSInteger)index
{
  LDTreemapRect parentRect = [self rectOfCell:(NSUInteger)index];
  double parentSize = (double)[self sizeOfNode:_cells[index].node];

  double *childWidth = malloc(count * sizeof(double));
  double *rows = malloc(count * sizeof(double));
  NSUInteger *childrenPerRow = malloc(count * sizeof(NSUInteger));
  NSUInteger rowCount = 0;

  int parentWidth = LDTreemapRectWidth(parentRect);
  int parentHeight = LDTreemapRectHeight(parentRect);
  BOOL horizontalRows = parentWidth >= parentHeight;
  double width = 1.0;
  if (horizontalRows) {
    if (parentHeight > 0) {
      width = (double)parentWidth / parentHeight;
    }
  } else if (parentWidth > 0) {
    width = (double)parentHeight / parentWidth;
  }

  NSUInteger nextChild = 0;
  while (nextChild < count) {
    NSUInteger used = 0;
    rows[rowCount] = LDKDirStatCalculateNextRow(sizes, count, parentSize, nextChild, width, &used, childWidth);
    childrenPerRow[rowCount] = used;
    rowCount++;
    nextChild += used;
  }

  int rowExtent = horizontalRows ? parentHeight : parentWidth;
  int childExtent = horizontalRows ? parentWidth : parentHeight;
  double top = horizontalRows ? parentRect.top : parentRect.left;
  NSUInteger c = 0;
  NSUInteger row = 0;
  for (row = 0; row < rowCount; row++) {
    double fBottom = top + rows[row] * rowExtent;
    int bottom = (int)fBottom;
    if (row == rowCount - 1) {
      bottom = horizontalRows ? parentRect.bottom : parentRect.right;
    }
    double left = horizontalRows ? parentRect.left : parentRect.top;
    NSUInteger k = 0;
    for (k = 0; k < childrenPerRow[row]; k++, c++) {
      double fRight = left + childWidth[c] * childExtent;
      int right = (int)fRight;
      if (k == childrenPerRow[row] - 1) {
        right = horizontalRows ? parentRect.right : parentRect.bottom;
      }

      LDTreemapRect childRect;
      if (horizontalRows) {
        childRect.left = (int)left;
        childRect.right = right;
        childRect.top = (int)top;
        childRect.bottom = bottom;
      } else {
        childRect.left = (int)top;
        childRect.right = bottom;
        childRect.top = (int)left;
        childRect.bottom = right;
      }
      [self appendCellForNode:[children objectAtIndex:c] rect:childRect];
      left = fRight;
    }
    top = fBottom;
  }

  free(childWidth);
  free(rows);
  free(childrenPerRow);
}

// Port of the SequoiaView branch of CTreeMap::DrawTreeMap.
- (void)layoutSequoiaChildren:(NSArray *)children sizes:(const double *)sizes count:(NSUInteger)count ofCell:(NSInteger)index
{
  LDTreemapRect remaining = [self rectOfCell:(NSUInteger)index];
  double remainingSize = (double)[self sizeOfNode:_cells[index].node];
  double sizePerSquarePixel = remainingSize / LDTreemapRectWidth(remaining) / LDTreemapRectHeight(remaining);
  NSUInteger head = 0;

  while (head < count) {
    BOOL horizontal = LDTreemapRectWidth(remaining) >= LDTreemapRectHeight(remaining);
    int height = horizontal ? LDTreemapRectHeight(remaining) : LDTreemapRectWidth(remaining);
    double hh = (double)height * height * sizePerSquarePixel;

    NSUInteger rowBegin = head;
    NSUInteger rowEnd = head;
    double worst = DBL_MAX;
    double rmax = sizes[rowBegin];
    double sum = 0.0;
    while (rowEnd < count) {
      double rmin = sizes[rowEnd];
      double ss = (sum + rmin) * (sum + rmin);
      double nextWorst = MAX(hh * rmax / ss, ss / hh / rmin);
      if (nextWorst > worst) {
        break;
      }
      sum += rmin;
      rowEnd++;
      worst = nextWorst;
    }

    int width = horizontal ? LDTreemapRectWidth(remaining) : LDTreemapRectHeight(remaining);
    if (sum < remainingSize) {
      width = (int)(sum / remainingSize * width);
    }

    LDTreemapRect rowRect = remaining;
    if (horizontal) {
      rowRect.right = rowRect.left + width;
    } else {
      rowRect.bottom = rowRect.top + width;
    }

    double fBegin = horizontal ? rowRect.top : rowRect.left;
    NSUInteger i = 0;
    for (i = rowBegin; i < rowEnd; i++) {
      double childSize = sizes[i];
      double fraction = childSize / sum;
      double fEnd = fBegin + fraction * (horizontal ? LDTreemapRectHeight(rowRect) : LDTreemapRectWidth(rowRect));
      int end = (int)fEnd;
      if (i == rowEnd - 1) {
        end = horizontal ? rowRect.bottom : rowRect.right;
      }

      LDTreemapRect childRect;
      if (horizontal) {
        childRect.left = rowRect.left;
        childRect.right = rowRect.right;
        childRect.top = (int)fBegin;
        childRect.bottom = end;
      } else {
        childRect.left = (int)fBegin;
        childRect.right = end;
        childRect.top = rowRect.top;
        childRect.bottom = rowRect.bottom;
      }
      [self appendCellForNode:[children objectAtIndex:i] rect:childRect];
      fBegin = fEnd;
    }

    if (horizontal) {
      remaining.left += width;
    } else {
      remaining.top += width;
    }
    remainingSize -= sum;
    head += rowEnd - rowBegin;

    if (LDTreemapRectWidth(remaining) <= 0 || LDTreemapRectHeight(remaining) <= 0) {
      break;
    }
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

  if (_cellCount == 0 || [self sizeOfNode:_rootNode] == 0) {
    LDDrawSolidRect(bitmap, _width, area, LDRGB(0, 0, 0), LDPaletteBrightness);
    return data;
  }

  LDDrawSolidRect(bitmap, _width, area, _options.gridColor, LDPaletteBrightness);
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
  return data;
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
