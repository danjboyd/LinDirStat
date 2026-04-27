#import "LDFileActionPlan.h"

@implementation LDFileActionPlan

+ (id)planWithActionType:(LDFileActionType)actionType targetPath:(NSString *)targetPath
{
  return [[[self alloc] initWithActionType:actionType targetPath:targetPath] autorelease];
}

- (id)initWithActionType:(LDFileActionType)actionType targetPath:(NSString *)targetPath
{
  self = [super init];
  if (self) {
    _actionType = actionType;
    _targetPath = [targetPath copy];
    _allowed = targetPath && [[NSFileManager defaultManager] fileExistsAtPath:targetPath];
    _destructive = (actionType == LDFileActionMoveToTrash || actionType == LDFileActionPermanentDelete);
    _requiresConfirmation = _destructive;
    if (!_allowed) {
      _message = [@"The selected path no longer exists." copy];
    } else if (actionType == LDFileActionPermanentDelete) {
      _message = [@"Permanent deletion is intentionally disabled until a dedicated reviewed workflow is implemented." copy];
      _allowed = NO;
    } else if (actionType == LDFileActionMoveToTrash) {
      _message = [@"Move the selected item to the platform trash after confirmation." copy];
    } else if (actionType == LDFileActionReveal) {
      _message = [@"Reveal the selected item in the platform file manager." copy];
    } else {
      _message = [@"Open the selected item with the platform default application." copy];
    }
  }
  return self;
}

- (LDFileActionType)actionType { return _actionType; }
- (NSString *)targetPath { return _targetPath; }
- (BOOL)isAllowed { return _allowed; }
- (BOOL)isDestructive { return _destructive; }
- (BOOL)requiresConfirmation { return _requiresConfirmation; }
- (NSString *)message { return _message; }

- (NSDictionary *)snapshotDictionary
{
  return [NSDictionary dictionaryWithObjectsAndKeys:
          [NSNumber numberWithInt:_actionType], @"action_type",
          _targetPath ? _targetPath : @"", @"target_path",
          [NSNumber numberWithBool:_allowed], @"allowed",
          [NSNumber numberWithBool:_destructive], @"destructive",
          [NSNumber numberWithBool:_requiresConfirmation], @"requires_confirmation",
          _message ? _message : @"", @"message",
          nil];
}

- (void)dealloc
{
  [_targetPath release];
  [_message release];
  [super dealloc];
}

@end
