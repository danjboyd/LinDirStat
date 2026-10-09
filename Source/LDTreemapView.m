#import "LDTreemapView.h"
#import "LDExtensionStats.h"
#import "LDHardLinks.h"
#import "LDPlatformUI.h"

// WinDirStat's CTreeMapView::ZoomFrameWidth.
static const int LDZoomFrameWidth = 4;
// Delay before re-rendering after a resize; the stale bitmap is stretched meanwhile.
static const NSTimeInterval LDResizeRenderDelay = 0.12;

@interface LDTreemapView ()
- (void)adoptTreemap:(LDTreemap *)treemap pixels:(NSData *)pixels;
@end

@implementation LDTreemapView

- (id)initWithFrame:(NSRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    _options = LDTreemapDefaultOptions();
    _metric = LDSizeMetricPhysical;
    _needsRender = YES;
    _reselectStack = [[NSMutableArray alloc] init];
    _highlightColor = LDRGB(255, 255, 255);
  }
  return self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { (void)event; return YES; }

- (id)delegate { return _delegate; }
- (void)setDelegate:(id)delegate { _delegate = delegate; }
- (LDFileNode *)rootNode { return _rootNode; }
- (LDFileNode *)zoomNode { return _zoomNode ? _zoomNode : _rootNode; }
- (LDFileNode *)selectedNode { return _selectedNode; }
- (NSString *)highlightedExtensionKey { return _highlightedExtensionKey; }
- (LDTreemapOptions)options { return _options; }
- (BOOL)isDimmed { return _dimmed; }
- (BOOL)isZoomed { return _zoomNode != nil && _zoomNode != _rootNode; }
- (LDTreemap *)treemap { return _treemap; }
- (LDRGBColor)highlightColor { return _highlightColor; }

- (void)setHighlightColor:(LDRGBColor)color
{
  if (color != _highlightColor) {
    _highlightColor = color;
    [self setNeedsDisplay:YES];
  }
}

#pragma mark - Model

- (void)invalidateRender
{
  _needsRender = YES;
  [self setNeedsDisplay:YES];
}

- (void)setRootNode:(LDFileNode *)rootNode metric:(LDSizeMetric)metric colorIndexes:(NSDictionary *)colorIndexes
{
  _rootNode = rootNode;
  _zoomNode = nil;
  _selectedNode = nil;
  [_reselectStack removeAllObjects];
  _hoverNode = nil;
  _colorIndexes = colorIndexes;
  _metric = metric;
  _treemap = nil;
  _bitmap = nil;
  [self invalidateRender];
}

- (void)setRootNode:(LDFileNode *)rootNode
             metric:(LDSizeMetric)metric
       colorIndexes:(NSDictionary *)colorIndexes
            treemap:(LDTreemap *)treemap
             pixels:(NSData *)pixels
{
  [self setRootNode:rootNode metric:metric colorIndexes:colorIndexes];
  NSSize size = [self renderSize];
  LDTreemapOptions options = [treemap options];
  if (!treemap || [treemap rootNode] != rootNode || [treemap metric] != metric || _renderTimer
      || [treemap width] != (int)size.width || [treemap height] != (int)size.height
      || memcmp(&options, &_options, sizeof(options)) != 0
      || [pixels length] != (NSUInteger)[treemap width] * (NSUInteger)[treemap height] * 4) {
    return;
  }
  _needsRender = NO;
  [self adoptTreemap:treemap pixels:pixels];
}

- (NSSize)renderSize
{
  NSRect bounds = [self bounds];
  CGFloat scale = [self renderScale];
  return NSMakeSize(MAX(0.0, floor(bounds.size.width) - 1.0) * scale, MAX(0.0, floor(bounds.size.height) - 1.0) * scale);
}

- (CGFloat)renderScale
{
  return [LDPlatformUI backingScaleForView:self];
}

// The treemap's pixel size for an area in points.
- (NSSize)pixelSizeOfArea:(NSRect)area
{
  CGFloat scale = [self renderScale];
  return NSMakeSize(area.size.width * scale, area.size.height * scale);
}

- (void)setOptions:(LDTreemapOptions)options
{
  _options = options;
  [self invalidateRender];
}

- (void)storeSelectedNode:(LDFileNode *)node
{
  if (_selectedNode != node) {
    _selectedNode = node;
    [self setNeedsDisplay:YES];
  }
}

// Selection from elsewhere ends a Select Parent / Reselect Child walk.
- (void)setSelectedNode:(LDFileNode *)node
{
  if (node != _selectedNode) {
    [_reselectStack removeAllObjects];
  }
  [self storeSelectedNode:node];
}

- (void)setHighlightedExtensionKey:(NSString *)extensionKey
{
  if (_highlightedExtensionKey != extensionKey && ![_highlightedExtensionKey isEqualToString:extensionKey]) {
    _highlightedExtensionKey = [extensionKey copy];
    [self setNeedsDisplay:YES];
  }
}

- (void)setDimmed:(BOOL)dimmed
{
  if (_dimmed != dimmed) {
    _dimmed = dimmed;
    [self setNeedsDisplay:YES];
  }
}

#pragma mark - Geometry

NSRect LDWholePixelRectInside(NSRect rect)
{
  NSRect pixels = NSMakeRect(ceil(NSMinX(rect)), ceil(NSMinY(rect)), 0.0, 0.0);
  pixels.size.width = MAX(0.0, floor(NSMaxX(rect)) - NSMinX(pixels));
  pixels.size.height = MAX(0.0, floor(NSMaxY(rect)) - NSMinY(pixels));
  return pixels;
}

// The treemap area: inside the zoom frame, minus WinDirStat's 1px right and
// bottom edge.
- (NSRect)treemapArea
{
  NSRect bounds = [self bounds];
  if ([self isZoomed]) {
    bounds = NSInsetRect(bounds, LDZoomFrameWidth, LDZoomFrameWidth);
  }
  // The cells are blitted 1:1, so the area sits on whole window pixels even
  // when the view does not (GNUstep's split views put the panes beside a
  // 1px divider on half pixels).
  NSRect pixels = LDWholePixelRectInside([self convertRect:bounds toView:nil]);
  NSRect area = [self convertRect:pixels fromView:nil];
  area.size.width = MAX(0.0, floor(area.size.width + 0.5) - 1.0);
  area.size.height = MAX(0.0, floor(area.size.height + 0.5) - 1.0);
  return area;
}

- (NSRect)viewRectForCellRect:(LDTreemapRect)rect
{
  NSRect area = [self treemapArea];
  CGFloat scale = [self renderScale];
  return NSMakeRect(area.origin.x + rect.left / scale,
                    area.origin.y + rect.top / scale,
                    LDTreemapRectWidth(rect) / scale,
                    LDTreemapRectHeight(rect) / scale);
}

- (void)setFrameSize:(NSSize)size
{
  NSSize oldSize = [self frame].size;
  [super setFrameSize:size];
  if (NSEqualSizes(oldSize, size)) {
    return;
  }
  _needsRender = YES;
  [_renderTimer invalidate];
  _renderTimer = nil;
  if (_bitmap) {
    // Keep resizing smooth on large trees: stretch the old bitmap until the
    // size settles, as WinDirStat does.
    _renderTimer = [NSTimer scheduledTimerWithTimeInterval:LDResizeRenderDelay
                                                    target:self
                                                  selector:@selector(renderTimerFired:)
                                                  userInfo:nil
                                                   repeats:NO];
  }
  [self setNeedsDisplay:YES];
}

- (void)renderTimerFired:(NSTimer *)timer
{
  (void)timer;
  _renderTimer = nil;
  [self render];
  [self setNeedsDisplay:YES];
}

- (void)render
{
  _needsRender = NO;
  _treemap = nil;
  _bitmap = nil;

  LDFileNode *root = [self zoomNode];
  NSSize pixels = [self pixelSizeOfArea:[self treemapArea]];
  int width = (int)pixels.width;
  int height = (int)pixels.height;
  if (!root || width <= 0 || height <= 0) {
    return;
  }

  LDTreemap *treemap = [[LDTreemap alloc] initWithRootNode:root metric:_metric width:width height:height options:_options];
  [self adoptTreemap:treemap pixels:[treemap renderRGBAWithColorIndexes:_colorIndexes]];
}

- (void)adoptTreemap:(LDTreemap *)treemap pixels:(NSData *)pixels
{
  int width = [treemap width];
  int height = [treemap height];
  _treemap = treemap;
  _bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                    pixelsWide:width
                                                    pixelsHigh:height
                                                 bitsPerSample:8
                                               samplesPerPixel:4
                                                      hasAlpha:YES
                                                      isPlanar:NO
                                                colorSpaceName:NSDeviceRGBColorSpace
                                                   bytesPerRow:width * 4
                                                  bitsPerPixel:32];
  memcpy([_bitmap bitmapData], [pixels bytes], [pixels length]);
}

#pragma mark - Drawing

- (void)drawRect:(NSRect)dirtyRect
{
  (void)dirtyRect;
  NSRect bounds = [self bounds];

  if (!_rootNode) {
    [[NSColor controlBackgroundColor] set];
    NSRectFill(bounds);
    return;
  }

  NSRect area = [self treemapArea];
  // Moving the view (or its window to another display) can change the
  // area's pixels without resizing it.
  NSSize pixels = [self pixelSizeOfArea:area];
  BOOL areaChanged = _bitmap && ([_bitmap pixelsWide] != (NSInteger)pixels.width
                                 || [_bitmap pixelsHigh] != (NSInteger)pixels.height);
  if ((_needsRender || areaChanged) && !_renderTimer) {
    [self render];
  }

  [[NSColor controlBackgroundColor] set];
  NSRectFill(bounds);

  if ([self isZoomed]) {
    [[NSColor selectedControlColor] set];
    NSFrameRectWithWidth(bounds, LDZoomFrameWidth);
  }

  if (_bitmap) {
    [self drawBitmapInRect:area];
  }

  // WinDirStat draws a 1px shadow line on the right and bottom edges.
  [[NSColor controlShadowColor] set];
  NSRectFill(NSMakeRect(NSMaxX(area), area.origin.y, 1.0, area.size.height + 1.0));
  NSRectFill(NSMakeRect(area.origin.x, NSMaxY(area), area.size.width + 1.0, 1.0));

  if (!_renderTimer && _treemap) {
    if (_highlightedExtensionKey) {
      [self drawExtensionHighlights];
    } else if (_selectedNode) {
      [self drawSelection];
    }
  }

  if (_dimmed || _renderTimer) {
    [[NSColor colorWithCalibratedWhite:0.0 alpha:(175.0 / 255.0)] set];
    NSRectFillUsingOperation(area, NSCompositeSourceOver);
  }
}

- (void)drawBitmapInRect:(NSRect)rect
{
  // NSImageRep draws bottom-up in a flipped view; flip the CTM around the rect.
  NSGraphicsContext *context = [NSGraphicsContext currentContext];
  [context saveGraphicsState];
  [context setImageInterpolation:NSImageInterpolationNone];
  NSAffineTransform *transform = [NSAffineTransform transform];
  [transform translateXBy:0.0 yBy:NSMaxY(rect)];
  [transform scaleXBy:1.0 yBy:-1.0];
  [transform concat];
  [_bitmap drawInRect:NSMakeRect(rect.origin.x, 0.0, rect.size.width, rect.size.height)];
  [context restoreGraphicsState];
}

// Port of CTreeMapView::RenderHighlightRectangle.
- (void)drawHighlightRect:(NSRect)rect
{
  if (rect.size.width <= 0.0 || rect.size.height <= 0.0) {
    return;
  }
  [[NSColor colorWithCalibratedRed:LDRGBRed(_highlightColor) / 255.0
                              green:LDRGBGreen(_highlightColor) / 255.0
                               blue:LDRGBBlue(_highlightColor) / 255.0
                              alpha:1.0] set];
  if (rect.size.width >= 7.0 && rect.size.height >= 7.0) {
    NSFrameRectWithWidth(rect, 3.0);
  } else {
    NSRectFill(rect);
  }
}

- (void)drawSelection
{
  // A hard link has no area of its own; WinDirStat highlights its Index
  // folder under "<Hardlinks>" instead (TreeMapView.cpp).
  LDFileNode *shown = [_selectedNode isHardLink] ? ([LDHardLinks indexNodeForLink:_selectedNode] ?: _selectedNode) : _selectedNode;
  NSInteger index = [_treemap cellIndexForNode:shown];
  if (index < 0) {
    return;
  }
  NSRect rect = [self viewRectForCellRect:[_treemap rectOfCell:(NSUInteger)index]];
  // A single selection grows 1px outward where the view allows it.
  NSRect area = [self treemapArea];
  if (NSMinX(area) < NSMinX(rect)) { rect.origin.x -= 1.0; rect.size.width += 1.0; }
  if (NSMinY(area) < NSMinY(rect)) { rect.origin.y -= 1.0; rect.size.height += 1.0; }
  if (NSMaxX(rect) < NSMaxX(area)) { rect.size.width += 1.0; }
  if (NSMaxY(rect) < NSMaxY(area)) { rect.size.height += 1.0; }
  [self drawHighlightRect:rect];
}

- (void)drawExtensionHighlights
{
  NSUInteger count = [_treemap cellCount];
  NSUInteger i = 0;
  for (i = 0; i < count; i++) {
    if (![_treemap isCellRendered:i]) {
      continue;
    }
    LDFileNode *node = [_treemap nodeOfCell:i];
    LDFileNodeKind kind = [node kind];
    if (kind != LDFileNodeKindFile && kind != LDFileNodeKindSymlink) {
      continue;
    }
    if ([[node extensionKey] isEqualToString:_highlightedExtensionKey]) {
      [self drawHighlightRect:[self viewRectForCellRect:[_treemap rectOfCell:i]]];
    }
  }
}

#pragma mark - Hit testing and navigation

- (LDFileNode *)nodeAtPoint:(NSPoint)point
{
  if (!_treemap || _needsRender) {
    return nil;
  }
  NSRect area = [self treemapArea];
  CGFloat scale = [self renderScale];
  NSInteger index = [_treemap cellIndexAtX:(int)floor((point.x - area.origin.x) * scale)
                                         y:(int)floor((point.y - area.origin.y) * scale)];
  return index >= 0 ? [_treemap nodeOfCell:(NSUInteger)index] : nil;
}

- (void)selectNodeAndNotify:(LDFileNode *)node
{
  if (!node) {
    return;
  }
  [self setHighlightedExtensionKey:nil];
  [self storeSelectedNode:node];
  [_delegate treemapView:self didSelectNode:node];
}

- (void)setZoomNode:(LDFileNode *)node
{
  [self zoomToNode:node ?: _rootNode];
}

- (void)zoomToNode:(LDFileNode *)node
{
  if (node == [self zoomNode]) {
    return;
  }
  _zoomNode = (node == _rootNode) ? nil : node;
  [self invalidateRender];
  [_delegate treemapViewDidChangeZoom:self];
}

// WinDirStat zooms into the selected directory, or the parent of a selected file.
- (LDFileNode *)zoomInTarget
{
  LDFileNode *node = _selectedNode;
  if ([node isSpaceItem]) {
    return nil;
  }
  if (node && [node isLeaf]) {
    node = [node parent];
  }
  if (!node || node == [self zoomNode] || ![[self zoomNode] isAncestorOf:node]) {
    return nil;
  }
  return node;
}

- (BOOL)canZoomIn { return [self zoomInTarget] != nil; }
- (BOOL)canZoomOut { return [self isZoomed]; }

- (BOOL)canSelectParent
{
  return _selectedNode && _selectedNode != [self zoomNode] && [_selectedNode parent] != nil;
}

- (IBAction)zoomIn:(id)sender
{
  (void)sender;
  LDFileNode *target = [self zoomInTarget];
  if (target) {
    [self zoomToNode:target];
  }
}

- (IBAction)zoomOut:(id)sender
{
  (void)sender;
  if ([self isZoomed]) {
    [self zoomToNode:[_zoomNode parent] ? [_zoomNode parent] : _rootNode];
  }
}

- (IBAction)resetZoom:(id)sender
{
  (void)sender;
  if ([self isZoomed]) {
    [self zoomToNode:_rootNode];
  }
}

- (IBAction)selectParent:(id)sender
{
  (void)sender;
  if ([self canSelectParent]) {
    LDFileNode *child = _selectedNode;
    [self selectNodeAndNotify:[child parent]];
    [_reselectStack addObject:child];
  }
}

- (BOOL)canReselectChild
{
  return [_reselectStack count] > 0;
}

- (IBAction)reselectChild:(id)sender
{
  (void)sender;
  LDFileNode *child = [_reselectStack lastObject];
  if (child) {
    [_reselectStack removeLastObject];
    [self selectNodeAndNotify:child];
  }
}

#pragma mark - Events

- (void)mouseDown:(NSEvent *)event
{
  [[self window] makeFirstResponder:self];
  NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
  LDFileNode *node = [self nodeAtPoint:point];
  if (!node) {
    return;
  }
  [_reselectStack removeAllObjects];
  [self selectNodeAndNotify:node];
  if ([event clickCount] == 2) {
    [self zoomIn:self];
  }
}

// A right click selects what is under the pointer before the menu opens.
- (NSMenu *)menuForEvent:(NSEvent *)event
{
  LDFileNode *node = [self nodeAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
  if (!node) {
    return nil;
  }
  if (node != _selectedNode) {
    [_reselectStack removeAllObjects];
    [self selectNodeAndNotify:node];
  }
  return [self menu];
}

- (void)otherMouseDown:(NSEvent *)event
{
  (void)event;
  [self resetZoom:self];
}

- (void)scrollWheel:(NSEvent *)event
{
  BOOL towardsParent = [event deltaY] > 0.0;
  if ([event modifierFlags] & NSControlKeyMask) {
    if (towardsParent) {
      [self zoomOut:self];
    } else {
      [self zoomIn:self];
    }
    return;
  }
  if (towardsParent) {
    [self selectParent:self];
  }
}

- (void)updateHoverForEvent:(NSEvent *)event
{
  NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
  LDFileNode *node = NSPointInRect(point, [self bounds]) ? [self nodeAtPoint:point] : nil;
  if (node != _hoverNode) {
    _hoverNode = node;
    [_delegate treemapView:self didHoverNode:node];
  }
}

- (void)mouseMoved:(NSEvent *)event
{
  [self updateHoverForEvent:event];
}

- (void)mouseExited:(NSEvent *)event
{
  (void)event;
  if (_hoverNode) {
    _hoverNode = nil;
    [_delegate treemapView:self didHoverNode:nil];
  }
}

- (void)keyDown:(NSEvent *)event
{
  NSString *characters = [event charactersIgnoringModifiers];
  if ([characters isEqualToString:@"+"] || [characters isEqualToString:@"="]) {
    [self zoomIn:self];
  } else if ([characters isEqualToString:@"-"]) {
    [self zoomOut:self];
  } else if ([characters isEqualToString:@"/"]) {
    [self selectParent:self];
  } else if ([characters isEqualToString:@"*"]) {
    [self reselectChild:self];
  } else {
    [super keyDown:event];
  }
}

- (void)viewDidMoveToWindow
{
  [[self window] setAcceptsMouseMovedEvents:YES];
}

#if defined(__APPLE__)
// Moved to a display with another scale: render at its resolution.
- (void)viewDidChangeBackingProperties
{
  [super viewDidChangeBackingProperties];
  [self setNeedsDisplay:YES];
}
#endif

- (void)dealloc
{
  [_renderTimer invalidate];
}

@end
