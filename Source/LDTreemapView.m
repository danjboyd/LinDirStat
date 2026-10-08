#import "LDTreemapView.h"
#import "LDExtensionStats.h"

// WinDirStat's CTreeMapView::ZoomFrameWidth.
static const int LDZoomFrameWidth = 4;
// Delay before re-rendering after a resize; the stale bitmap is stretched meanwhile.
static const NSTimeInterval LDResizeRenderDelay = 0.12;

@implementation LDTreemapView

- (id)initWithFrame:(NSRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    _options = LDTreemapDefaultOptions();
    _metric = LDSizeMetricPhysical;
    _needsRender = YES;
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
  _hoverNode = nil;
  _colorIndexes = colorIndexes;
  _metric = metric;
  _bitmap = nil;
  [self invalidateRender];
}

- (void)setOptions:(LDTreemapOptions)options
{
  _options = options;
  [self invalidateRender];
}

- (void)setSelectedNode:(LDFileNode *)node
{
  if (_selectedNode != node) {
    _selectedNode = node;
    [self setNeedsDisplay:YES];
  }
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

// The treemap area: inside the zoom frame, minus WinDirStat's 1px right and
// bottom edge.
- (NSRect)treemapArea
{
  NSRect bounds = [self bounds];
  if ([self isZoomed]) {
    bounds = NSInsetRect(bounds, LDZoomFrameWidth, LDZoomFrameWidth);
  }
  bounds.size.width = MAX(0.0, floor(bounds.size.width) - 1.0);
  bounds.size.height = MAX(0.0, floor(bounds.size.height) - 1.0);
  return bounds;
}

- (NSRect)viewRectForCellRect:(LDTreemapRect)rect
{
  NSRect area = [self treemapArea];
  return NSMakeRect(area.origin.x + rect.left,
                    area.origin.y + rect.top,
                    LDTreemapRectWidth(rect),
                    LDTreemapRectHeight(rect));
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
  NSRect area = [self treemapArea];
  int width = (int)area.size.width;
  int height = (int)area.size.height;
  if (!root || width <= 0 || height <= 0) {
    return;
  }

  _treemap = [[LDTreemap alloc] initWithRootNode:root metric:_metric width:width height:height options:_options];
  NSData *pixels = [_treemap renderRGBAWithColorIndexes:_colorIndexes];
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

  if (_needsRender && !_renderTimer) {
    [self render];
  }

  [[NSColor controlBackgroundColor] set];
  NSRectFill(bounds);

  if ([self isZoomed]) {
    [[NSColor selectedControlColor] set];
    NSFrameRectWithWidth(bounds, LDZoomFrameWidth);
  }

  NSRect area = [self treemapArea];
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
  [[NSColor whiteColor] set];
  if (rect.size.width >= 7.0 && rect.size.height >= 7.0) {
    NSFrameRectWithWidth(rect, 3.0);
  } else {
    NSRectFill(rect);
  }
}

- (void)drawSelection
{
  NSInteger index = [_treemap cellIndexForNode:_selectedNode];
  if (index < 0) {
    return;
  }
  NSRect rect = [self viewRectForCellRect:[_treemap cells][index].rect];
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
  const LDTreemapCell *cells = [_treemap cells];
  NSUInteger count = [_treemap cellCount];
  NSUInteger i = 0;
  for (i = 0; i < count; i++) {
    if (!cells[i].rendered) {
      continue;
    }
    LDFileNodeKind kind = [cells[i].node kind];
    if (kind != LDFileNodeKindFile && kind != LDFileNodeKindSymlink) {
      continue;
    }
    if ([[cells[i].node extensionKey] isEqualToString:_highlightedExtensionKey]) {
      [self drawHighlightRect:[self viewRectForCellRect:cells[i].rect]];
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
  NSInteger index = [_treemap cellIndexAtX:(int)floor(point.x - area.origin.x)
                                         y:(int)floor(point.y - area.origin.y)];
  return index >= 0 ? [_treemap cells][index].node : nil;
}

- (void)selectNodeAndNotify:(LDFileNode *)node
{
  if (!node) {
    return;
  }
  [self setHighlightedExtensionKey:nil];
  [self setSelectedNode:node];
  [_delegate treemapView:self didSelectNode:node];
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
    [self selectNodeAndNotify:[_selectedNode parent]];
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
  [self selectNodeAndNotify:node];
  if ([event clickCount] == 2) {
    [self zoomIn:self];
  }
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
  } else {
    [super keyDown:event];
  }
}

- (void)viewDidMoveToWindow
{
  [[self window] setAcceptsMouseMovedEvents:YES];
}

- (void)dealloc
{
  [_renderTimer invalidate];
}

@end
