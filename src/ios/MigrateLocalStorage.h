#import <Cordova/CDVPlugin.h>

@interface MigrateLocalStorage : CDVPlugin {}

- (BOOL) move:(NSString*)src to:(NSString*)dest;
- (BOOL) migrateLocalStorage;
- (void) pluginInitialize;

@end
