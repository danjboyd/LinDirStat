#import "LDUpdates.h"

#if defined(GNUSTEP)
#import "GPUpdater.h"
#import "GPStandardUpdaterController.h"
#endif

@implementation LDUpdates
{
#if defined(GNUSTEP)
  GPUpdaterConfiguration *_configuration;
  GPStandardUpdaterController *_controller;
#endif
}

#if defined(GNUSTEP)

- (instancetype)initWithConfiguration:(GPUpdaterConfiguration *)configuration
{
  self = [super init];
  if (self) {
    _configuration = configuration;
  }
  return self;
}

+ (instancetype)packagedUpdates
{
  NSError *error = nil;
  GPUpdaterConfiguration *configuration = [GPUpdaterConfiguration packagedConfigurationWithError:&error];
  return configuration ? [[self alloc] initWithConfiguration:configuration] : nil;
}

+ (instancetype)updatesWithConfigurationFile:(NSString *)path error:(NSError **)error
{
  GPUpdaterConfiguration *configuration = [GPUpdaterConfiguration configurationWithContentsOfFile:path error:error];
  return configuration ? [[self alloc] initWithConfiguration:configuration] : nil;
}

- (NSString *)currentVersion
{
  return [_configuration currentVersion];
}

// The controller is made on first use: a check runs only once the app has
// started it or the user asks.
- (GPStandardUpdaterController *)controller
{
  if (_controller == nil) {
    GPUpdater *updater = [[GPUpdater alloc] initWithConfiguration:_configuration];
    // It finds gp-update-helper next to the executable, where the build
    // puts it.
    _controller = [[GPStandardUpdaterController alloc] initWithUpdater:updater];
  }
  return _controller;
}

- (void)startWithWindow:(NSWindow *)window
{
  [[self controller] setParentWindow:window];
  [[self controller] start];
}

- (void)checkForUpdates:(id)sender
{
  [[self controller] checkForUpdates:sender];
}

- (NSString *)newerVersionFromFeedWithError:(NSError **)error
{
  GPUpdater *updater = [[GPUpdater alloc] initWithConfiguration:_configuration];
  GPUpdateCheckResult *result = [updater checkForUpdatesSynchronously:error];
  return [result hasUpdate] ? [result latestVersion] : nil;
}

#else

+ (instancetype)packagedUpdates
{
  return nil;
}

+ (instancetype)updatesWithConfigurationFile:(NSString *)path error:(NSError **)error
{
  (void)path;
  if (error) {
    *error = [NSError errorWithDomain:@"LDUpdates" code:1
                             userInfo:@{NSLocalizedDescriptionKey: @"This build has no updater."}];
  }
  return nil;
}

- (NSString *)currentVersion
{
  return nil;
}

- (void)startWithWindow:(NSWindow *)window
{
  (void)window;
}

- (void)checkForUpdates:(id)sender
{
  (void)sender;
}

- (NSString *)newerVersionFromFeedWithError:(NSError **)error
{
  (void)error;
  return nil;
}

#endif

@end
