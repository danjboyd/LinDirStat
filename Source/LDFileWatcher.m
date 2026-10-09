#import "LDFileWatcher.h"
#import "LDFileWatcher+Backend.h"

static const NSTimeInterval LDFileWatcherBatchInterval = 0.25;

@interface LDFileWatcherEvent ()
- (void)updateTime:(NSTimeInterval)time logicalSize:(unsigned long long)logicalSize;
@end

@implementation LDFileWatcherEvent

+ (LDFileWatcherEvent *)eventWithPathData:(NSData *)path
                                   action:(LDFileWatcherAction)action
                                     time:(NSTimeInterval)time
                              logicalSize:(unsigned long long)logicalSize
                              isDirectory:(BOOL)isDirectory
{
  LDFileWatcherEvent *event = [[LDFileWatcherEvent alloc] init];
  event->_pathData = [path copy];
  event->_action = action;
  event->_time = time;
  event->_logicalSize = logicalSize;
  event->_directory = isDirectory;
  return event;
}

- (NSData *)pathData { return _pathData; }
- (LDFileWatcherAction)action { return _action; }
- (NSTimeInterval)time { return _time; }
- (unsigned long long)logicalSize { return _logicalSize; }
- (BOOL)isDirectory { return _directory; }

- (void)updateTime:(NSTimeInterval)time logicalSize:(unsigned long long)logicalSize
{
  _time = time;
  _logicalSize = logicalSize;
}

- (NSString *)path
{
  NSString *path = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:[_pathData bytes]
                                                                               length:[_pathData length]];
  if (!path) {
    path = [[NSString alloc] initWithData:_pathData encoding:NSUTF8StringEncoding];
  }
  return path ?: [[NSString alloc] initWithData:_pathData encoding:NSISOLatin1StringEncoding];
}

+ (NSString *)titleForAction:(LDFileWatcherAction)action
{
  switch (action) {
    case LDFileWatcherActionCreated: return @"Created";
    case LDFileWatcherActionDeleted: return @"Deleted";
    case LDFileWatcherActionModified: return @"Modified";
    case LDFileWatcherActionRenamedOld: return @"Renamed (Old)";
    case LDFileWatcherActionRenamedNew: return @"Renamed (New)";
  }
  return @"";
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"%@ %@", [LDFileWatcherEvent titleForAction:_action], [self path]];
}

@end

@interface LDFileWatcher ()
- (void)sink:(LDFileWatcherSink *)sink deliverEvents:(NSArray *)events;
- (void)sink:(LDFileWatcherSink *)sink deliverMessage:(NSString *)message;
@end

@implementation LDFileWatcherSink

- (id)initWithWatcher:(LDFileWatcher *)watcher
{
  self = [super init];
  if (self) {
    _watcher = watcher;
    _queue = dispatch_queue_create("LinDirStat.FileWatcher", DISPATCH_QUEUE_SERIAL);
    _pending = [[NSMutableArray alloc] init];
    _lastIndexByPath = [[NSMutableDictionary alloc] init];
  }
  return self;
}

- (dispatch_queue_t)queue
{
  return _queue;
}

- (void)flush
{
  _flushScheduled = NO;
  NSArray *events = [_pending copy];
  [_pending removeAllObjects];
  [_lastIndexByPath removeAllObjects];
  if ([events count] == 0) {
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    [self->_watcher sink:self deliverEvents:events];
  });
}

- (void)addEvent:(LDFileWatcherEvent *)event
{
  NSData *path = [event pathData];
  NSNumber *last = [_lastIndexByPath objectForKey:path];
  LDFileWatcherEvent *previous = last ? [_pending objectAtIndex:[last unsignedIntegerValue]] : nil;
  // Writes after a creation or a write, or a creation seen twice (a new
  // folder's contents are listed while its watch starts), update that row.
  BOOL repeat = ([event action] == LDFileWatcherActionModified
                 && ([previous action] == LDFileWatcherActionModified || [previous action] == LDFileWatcherActionCreated))
    || ([event action] == LDFileWatcherActionCreated && [previous action] == LDFileWatcherActionCreated);
  if (repeat) {
    [previous updateTime:[event time] logicalSize:[event logicalSize]];
    return;
  }
  [_lastIndexByPath setObject:[NSNumber numberWithUnsignedInteger:[_pending count]] forKey:path];
  [_pending addObject:event];
  if (!_flushScheduled) {
    _flushScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(LDFileWatcherBatchInterval * NSEC_PER_SEC)), _queue, ^{
      [self flush];
    });
  }
}

- (void)reportMessage:(NSString *)message
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [self->_watcher sink:self deliverMessage:message];
  });
}

@end

@implementation LDFileWatcher

+ (BOOL)isSupported
{
  return [self platformIsSupported];
}

+ (NSUInteger)maximumListedEvents
{
  return 10000;
}

- (id)initWithRootPaths:(NSArray *)roots
{
  self = [super init];
  if (self) {
    _roots = [roots copy];
  }
  return self;
}

- (NSArray *)rootPaths
{
  return _roots;
}

- (void)setEventHandler:(void (^)(NSArray *events))handler
{
  _eventHandler = [handler copy];
}

- (void)setMessageHandler:(void (^)(NSString *message))handler
{
  _messageHandler = [handler copy];
}

- (BOOL)startWithError:(NSError **)error
{
  [self stop];
  LDFileWatcherSink *sink = [[LDFileWatcherSink alloc] initWithWatcher:self];
  id backend = [self platformStartWatchingRoots:_roots sink:sink error:error];
  if (!backend) {
    return NO;
  }
  _sink = sink;
  _backend = backend;
  return YES;
}

- (void)stop
{
  if (_backend) {
    [self platformStopWatching:_backend];
  }
  _backend = nil;
  _sink = nil;
}

- (BOOL)isRunning
{
  return _backend != nil;
}

// Batches from a stopped (or replaced) backend are dropped here, on the
// main queue, so nothing arrives after -stop.
- (void)sink:(LDFileWatcherSink *)sink deliverEvents:(NSArray *)events
{
  if (sink == _sink && _eventHandler) {
    _eventHandler(events);
  }
}

- (void)sink:(LDFileWatcherSink *)sink deliverMessage:(NSString *)message
{
  if (sink == _sink && _messageHandler) {
    _messageHandler(message);
  }
}

- (void)dealloc
{
  [self stop];
}

@end
