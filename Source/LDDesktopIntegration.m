#import "LDDesktopIntegration.h"

#if !defined(__APPLE__)

#import <AppKit/AppKit.h>
#import "LDDesktop.h"
#import "LDDesktopEntry.h"
#import "LDLocalization.h"
#import "LDMimeApps.h"
#import "LDPreferences.h"

static const NSTimeInterval LDSnoozeSeconds = 7.0 * 24.0 * 60.0 * 60.0;
static NSString *const LDEntryName = @"lindirstat.desktop";
static NSString *const LDIconName = @"lindirstat.png";
static NSString *const LDWindowClass = @"LinDirStat";
// Marks an entry as ours, so only ours is ever rewritten or removed.
static NSString *const LDOwnerKey = @"X-LinDirStat-Integration";
// Marks the icon as ours too: an icon of that name may be someone else's.
static NSString *const LDIconOwnerKey = @"X-LinDirStat-Icon";

@implementation LDDesktopIntegration
{
  NSString *_appImage;
  NSString *_appDir;
  NSArray *_applicationDirectories;
}

+ (LDDesktopIntegration *)integrationForEnvironment:(NSDictionary *)environment
{
  LDDesktopIntegration *integration = [[self alloc] init];
  integration->_appImage = [environment objectForKey:@"APPIMAGE"];
  integration->_appDir = [environment objectForKey:@"APPDIR"];
  integration->_applicationDirectories = [LDMimeApps applicationDirectoriesForEnvironment:environment];
  return integration;
}

- (NSString *)dataHome
{
  return [[_applicationDirectories objectAtIndex:0] stringByDeletingLastPathComponent];
}

- (NSString *)entryPath
{
  return [[_applicationDirectories objectAtIndex:0] stringByAppendingPathComponent:LDEntryName];
}

- (NSString *)iconPath
{
  return [[[self dataHome] stringByAppendingPathComponent:@"icons/hicolor/256x256/apps"]
    stringByAppendingPathComponent:LDIconName];
}

// The Exec value: the path as one quoted argument (Desktop Entry Specification,
// "The Exec key"), % doubled as a field code would be, then escaped as any
// string value is, so a backslash from the quoting is written twice.
- (NSString *)execValue
{
  NSMutableString *quoted = [NSMutableString stringWithString:_appImage];
  for (NSString *special in @[@"\\", @"\"", @"`", @"$"]) {
    [quoted replaceOccurrencesOfString:special
                            withString:[@"\\" stringByAppendingString:special]
                               options:NSLiteralSearch
                                 range:NSMakeRange(0, [quoted length])];
  }
  [quoted replaceOccurrencesOfString:@"%" withString:@"%%" options:NSLiteralSearch range:NSMakeRange(0, [quoted length])];
  return [[self class] escapedValue:[NSString stringWithFormat:@"\"%@\" %%F", quoted]];
}

+ (NSString *)escapedValue:(NSString *)value
{
  NSMutableString *escaped = [NSMutableString stringWithString:value];
  [escaped replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:NSLiteralSearch range:NSMakeRange(0, [escaped length])];
  [escaped replaceOccurrencesOfString:@"\n" withString:@"\\n" options:NSLiteralSearch range:NSMakeRange(0, [escaped length])];
  return escaped;
}

- (NSString *)entryText
{
  return [self entryTextOwningIcon:YES];
}

- (NSString *)entryTextOwningIcon:(BOOL)ownsIcon
{
  return [@[
    @"[Desktop Entry]",
    @"Type=Application",
    @"Name=LinDirStat",
    @"Comment=GNUstep disk usage viewer inspired by WinDirStat.",
    [@"TryExec=" stringByAppendingString:[[self class] escapedValue:_appImage]],
    [@"Exec=" stringByAppendingString:[self execValue]],
    @"Icon=lindirstat",
    @"Terminal=false",
    [@"StartupWMClass=" stringByAppendingString:LDWindowClass],
    @"Categories=System;FileTools;",
    @"MimeType=inode/directory;",
    [LDOwnerKey stringByAppendingString:@"=true"],
    [NSString stringWithFormat:@"%@=%@", LDIconOwnerKey, ownsIcon ? @"true" : @"false"],
    @""
  ] componentsJoinedByString:@"\n"];
}

- (BOOL)entryIsForLinDirStat:(LDDesktopEntry *)entry
{
  if (![entry isApplication] || [entry isHidden]) {
    return NO;
  }
  // Lowercased, as a message to a missing value would compare as the same.
  NSString *wanted = [LDWindowClass lowercaseString];
  if ([[[entry stringForKey:@"StartupWMClass"] lowercaseString] isEqualToString:wanted]
      || [[[entry stringForKey:@"X-AppImage-Name"] lowercaseString] isEqualToString:wanted]) {
    return YES;
  }
  // AppImageLauncher and Gear Lever point Exec at the AppImage they moved.
  NSString *program = [[[LDDesktopEntry argumentsForExec:[entry exec] ?: @""] firstObject] lastPathComponent];
  NSString *lower = [program lowercaseString];
  return [lower hasPrefix:@"lindirstat"] && [lower hasSuffix:@".appimage"];
}

- (LDDesktopIntegrationState)state
{
  if ([_appImage length] == 0) {
    return LDDesktopIntegrationUnavailable;
  }
  NSFileManager *manager = [NSFileManager defaultManager];
  LDDesktopEntry *ours = [LDDesktopEntry entryWithContentsOfFile:[self entryPath] identifier:LDEntryName];
  BOOL isOurs = [ours booleanForKey:LDOwnerKey];
  for (NSString *directory in _applicationDirectories) {
    for (NSString *name in [manager contentsOfDirectoryAtPath:directory error:NULL]) {
      if (![[name pathExtension] isEqualToString:@"desktop"]) {
        continue;
      }
      NSString *path = [directory stringByAppendingPathComponent:name];
      if (isOurs && [path isEqualToString:[self entryPath]]) {
        continue;
      }
      LDDesktopEntry *entry = [LDDesktopEntry entryWithContentsOfFile:path identifier:name];
      // Our name without our mark is someone's own: never overwrite it.
      if (entry && ([name isEqualToString:LDEntryName] || [self entryIsForLinDirStat:entry])) {
        return LDDesktopIntegrationExternal;
      }
    }
  }
  if (!isOurs) {
    return LDDesktopIntegrationNotInstalled;
  }
  return [[ours stringForKey:@"TryExec"] isEqualToString:_appImage] ? LDDesktopIntegrationInstalled : LDDesktopIntegrationMoved;
}

- (NSString *)iconSource
{
  NSString *packaged = [_appDir stringByAppendingPathComponent:LDIconName];
  if (packaged && [[NSFileManager defaultManager] isReadableFileAtPath:packaged]) {
    return packaged;
  }
  return [[NSBundle mainBundle] pathForResource:@"LinDirStat" ofType:@"png"];
}

// So that "Open With" on a folder finds the entry straight away. The AppImage's
// libraries must not reach a system program.
- (void)updateDesktopDatabase
{
  NSArray *command = @[@"env", @"-u", @"LD_LIBRARY_PATH", @"update-desktop-database", [_applicationDirectories objectAtIndex:0]];
  [LDDesktop runFirstSuccessfulCommand:@[command] inDirectory:nil queue:nil completion:^(BOOL succeeded) { (void)succeeded; }];
}

- (BOOL)install:(NSError **)error
{
  NSFileManager *manager = [NSFileManager defaultManager];
  NSData *icon = [NSData dataWithContentsOfFile:[self iconSource] ?: @""];
  NSData *existingIcon = [NSData dataWithContentsOfFile:[self iconPath]];
  LDDesktopEntry *previous = [LDDesktopEntry entryWithContentsOfFile:[self entryPath] identifier:LDEntryName];
  BOOL hadIcon = [previous booleanForKey:LDOwnerKey] && [previous booleanForKey:LDIconOwnerKey];
  // Someone else's icon of that name stays, and the entry shows it.
  BOOL ownsIcon = !existingIcon || hadIcon || [existingIcon isEqualToData:icon];
  // The icon first, so the shell never sees the entry without it. An entry
  // without its icon still gives the app grid and Open With.
  if (ownsIcon && icon && [manager createDirectoryAtPath:[[self iconPath] stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL]) {
    [icon writeToFile:[self iconPath] atomically:YES];
  }
  if (![manager createDirectoryAtPath:[[self entryPath] stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:error]
      || ![[self entryTextOwningIcon:ownsIcon] writeToFile:[self entryPath] atomically:YES encoding:NSUTF8StringEncoding error:error]) {
    return NO;
  }
  [self updateDesktopDatabase];
  return YES;
}

- (BOOL)remove:(NSError **)error
{
  LDDesktopEntry *ours = [LDDesktopEntry entryWithContentsOfFile:[self entryPath] identifier:LDEntryName];
  if (![ours booleanForKey:LDOwnerKey]) {
    return YES;
  }
  NSFileManager *manager = [NSFileManager defaultManager];
  if (![manager removeItemAtPath:[self entryPath] error:error]) {
    return NO;
  }
  if ([ours booleanForKey:LDIconOwnerKey]) {
    [manager removeItemAtPath:[self iconPath] error:NULL];
  }
  [self updateDesktopDatabase];
  return YES;
}

+ (BOOL)mayOfferWithPreferences:(LDPreferences *)preferences now:(NSDate *)now
{
  if ([preferences desktopIntegrationDeclined]) {
    return NO;
  }
  NSDate *snoozed = [preferences desktopIntegrationSnoozedAt];
  NSTimeInterval since = snoozed ? [now timeIntervalSinceDate:snoozed] : LDSnoozeSeconds;
  // A date ahead of the clock can't be waited out.
  return since >= LDSnoozeSeconds || since < 0.0;
}

+ (void)offerAfterLaunch
{
  static BOOL offered = NO;
  if (offered) {
    return;
  }
  offered = YES;
  NSDictionary *environment = [[NSProcessInfo processInfo] environment];
  LDDesktopIntegration *integration = [self integrationForEnvironment:environment];
  LDDesktopIntegrationState state = [integration state];
  if (state == LDDesktopIntegrationMoved) {
    [integration install:NULL];
    return;
  }
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  if (state != LDDesktopIntegrationNotInstalled || ![self mayOfferWithPreferences:preferences now:[NSDate date]]
      || [[environment objectForKey:@"LINDIRSTAT_DESKTOP_PROMPT"] isEqualToString:@"off"]) {
    return;
  }
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText:LDLocalized(@"Add LinDirStat to your applications?")];
  [alert setInformativeText:LDLocalized(@"It gets its own icon, and you can start it from your applications or with Open With on a folder.")];
  [alert addButtonWithTitle:LDLocalized(@"Add")];
  [alert addButtonWithTitle:LDLocalized(@"Not Now")];
  [alert addButtonWithTitle:LDLocalized(@"Don't Ask Again")];
  NSInteger response = [alert runModal];
  if (response == NSAlertThirdButtonReturn) {
    [preferences setDesktopIntegrationDeclined:YES];
  } else if (response == NSAlertSecondButtonReturn) {
    [preferences setDesktopIntegrationSnoozedAt:[NSDate date]];
  } else if (response == NSAlertFirstButtonReturn) {
    NSError *error = nil;
    if (![integration install:&error]) {
      NSAlert *failure = [[NSAlert alloc] init];
      [failure setMessageText:LDLocalized(@"LinDirStat couldn't be added to your applications.")];
      [failure setInformativeText:[error localizedDescription] ?: @""];
      [failure runModal];
    }
  }
}

@end

#else

@implementation LDDesktopIntegration

+ (LDDesktopIntegration *)integrationForEnvironment:(NSDictionary *)environment { (void)environment; return [[self alloc] init]; }
- (LDDesktopIntegrationState)state { return LDDesktopIntegrationUnavailable; }
- (BOOL)install:(NSError **)error { (void)error; return NO; }
- (BOOL)remove:(NSError **)error { (void)error; return NO; }
- (NSString *)entryPath { return nil; }
- (NSString *)iconPath { return nil; }
- (NSString *)entryText { return nil; }
+ (BOOL)mayOfferWithPreferences:(LDPreferences *)preferences now:(NSDate *)now { (void)preferences; (void)now; return NO; }
+ (void)offerAfterLaunch {}

@end

#endif
