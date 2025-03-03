#import <Cordova/CDVPlugin.h>

@interface MigrateLocalStorage : CDVPlugin {}

- (BOOL) migrateLocalStorage;
- (void) pluginInitialize;

@end
