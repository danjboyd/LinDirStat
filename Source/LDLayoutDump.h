#import <AppKit/AppKit.h>

// Debug-only description of the app's windows for the full-window GUI parity
// gate (scripts/gui-parity-gate.sh). Rects are screen pixels with the origin
// at the top left of the screen, as screenshots use: [x, y, width, height].
// Nothing here runs unless LINDIRSTAT_DUMP_LAYOUT names an output file.
@interface LDLayoutDump : NSObject

// The LINDIRSTAT_DUMP_LAYOUT path from environment, or nil when unset or empty.
+ (NSString *)requestedPathInEnvironment:(NSDictionary *)environment;

// rect (bottom-left origin screen coordinates) flipped to the top left of a
// screen screenHeight tall, with its edges rounded to whole pixels.
+ (NSArray *)arrayForScreenRect:(NSRect)rect screenHeight:(CGFloat)screenHeight;

// Collapses hit-test samples (one item or NSNull per sample at x = start +
// i * step) into runs: [{"item": item, "start": x, "end": x}] for non-null items.
+ (NSArray *)runsOfSamples:(NSArray *)samples start:(CGFloat)start step:(CGFloat)step;

// A view in window, in the rect convention above.
+ (NSArray *)rectOfView:(NSView *)view;
+ (NSArray *)rect:(NSRect)rect ofView:(NSView *)view;

// The view tree under view (visible views only). roles names views of
// interest: view -> role string.
+ (NSDictionary *)describeViewTree:(NSView *)view roles:(NSMapTable *)roles;
// Columns, header title metrics, visible rows and selection of a table.
// labels gives a row's label (row -> string), or nil.
+ (NSDictionary *)describeTable:(NSTableView *)table rowLabels:(NSString *(^)(NSInteger row))labels;
// Tab labels with the rects of their tabs, found by hit-testing the strip.
+ (NSDictionary *)describeTabView:(NSTabView *)tabView;
+ (NSArray *)titlesOfMenu:(NSMenu *)menu;
// Starts following menu tracking (NSMenuDidBegin/EndTrackingNotification).
+ (void)startTrackingMenus;
// The menus being tracked now, outermost first, as their item titles: on
// macOS menus are not windows, so context menus are only seen this way.
+ (NSArray *)openMenus;
// Every visible window, with its view tree.
+ (NSArray *)describeWindowsWithRoles:(NSMapTable *)roles;

// Writes object as JSON to path atomically. Returns NO on failure.
+ (BOOL)writeJSONObject:(id)object toPath:(NSString *)path;

@end
