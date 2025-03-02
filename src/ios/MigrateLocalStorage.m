#import "MigrateLocalStorage.h"

#define TAG @"\nMigrateLocalStorage"
#define ORIG_LS_FILEPATH @"WebKit/LocalStorage/file__0.localstorage"
#define ORIG_LS_CACHE @"Caches/file__0.localstorage"
#define TARGET_LS_ROOT_DIR @"WebKit"

@implementation MigrateLocalStorage

- (void)pluginInitialize {
    // No automatic initialization - will be called from JavaScript
    NSLog(@"%@ Plugin initialized - waiting for JavaScript to request migration", TAG);
}

/**
 * JavaScript-callable method to start migration
 */
- (void)migrate:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        NSLog(@"%@ Starting localStorage migration", TAG);
        BOOL success = [self migrateLocalStorage];
        // Return result to JavaScript
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                              messageAsBool:success];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    }];
}

/**
* Checks if localStorage file should be migrated. If so, migrate.
* NOTE: Will only migrate data if there is no localStorage data for WKWebView. This only happens when WKWebView is set up for the first time.
*/
- (BOOL)migrateLocalStorage
{
    NSString* original = [self resolveOriginalLocalStorageFile];
    NSString* target = [self resolveTargetLocalStorageFile];
    NSString* targetFile = [target stringByAppendingPathComponent:@"localstorage.sqlite3"];

    NSLog(@"%@ 📦 original %@", TAG, original);
    NSLog(@"%@ 🏹 target %@", TAG, targetFile);

    NSFileManager* fileManager = [NSFileManager defaultManager];

    // Check if original file exists
    if (![fileManager fileExistsAtPath:original]) {
        NSLog(@"%@ ⚠️ Original localStorage file not found. Nothing to migrate.", TAG);
        return NO;
    }

    // Remove existing empty sqlite files (created by initialization)
    if ([fileManager fileExistsAtPath:targetFile]) {
        NSLog(@"%@ 🗑️ Removing existing initialization files to replace with migration data", TAG);
        [self deleteFile:targetFile];
        [self deleteFile:[targetFile stringByAppendingString:@"-shm"]];
        [self deleteFile:[targetFile stringByAppendingString:@"-wal"]];
    }

    // Ensure target directory exists
    if (![fileManager createDirectoryAtPath:target
                withIntermediateDirectories:YES
                               attributes:nil
                                    error:nil]) {
        NSLog(@"%@ Failed to create target directory", TAG);
        return NO;
    }

    // Move the files with WKWebView naming convention
    BOOL success1 = [self move:original to:targetFile];
    BOOL success2 = [self move:[original stringByAppendingString:@"-shm"]
                          to:[targetFile stringByAppendingString:@"-shm"]];
    BOOL success3 = [self move:[original stringByAppendingString:@"-wal"]
                          to:[targetFile stringByAppendingString:@"-wal"]];

    NSLog(@"%@ Migration status for localstorage.sqlite3 files: %d %d %d", TAG, success1, success2, success3);
    return success1 && success2 && success3;
}

- (void)debugLogDirectoryStructure
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSString* appLibraryFolder = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString* webkitPath = [appLibraryFolder stringByAppendingPathComponent:@"WebKit"];
    NSLog(@"%@ Checking WebKit path: %@", TAG, webkitPath);
    NSError* error = nil;
    NSArray* contents = [fileManager contentsOfDirectoryAtPath:webkitPath error:&error];
    NSLog(@"%@ WebKit contents: %@", TAG, contents);
    if (error) {
        NSLog(@"%@ Error reading WebKit directory: %@", TAG, error);
    }
}

/**
* Replaces an item found at dest with item found at src
*/
- (BOOL) deleteFile:(NSString*)path
{
    NSFileManager* fileManager = [NSFileManager defaultManager];

    // Bail out if source file does not exist // not really necessary <- error case already handle by fileManager copyItemAtPath
    if (![fileManager fileExistsAtPath:path]) {
        NSLog(@"%@ Source file does not exist", TAG);
        return NO;
    }

    BOOL res = [fileManager removeItemAtPath:path error:nil];
    return res;
}

/**
* Moves an item from src to dest. Works only if dest file has not already been created.
*/
- (BOOL) move:(NSString*)src to:(NSString*)dest
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    // Bail out if source file does not exist // not really necessary <- error case already handle by fileManager copyItemAtPath
    if (![fileManager fileExistsAtPath:src]) {
        NSLog(@"%@ Source file does not exist", TAG);
        return NO;
    }
    // Bail out if dest file exists
    if ([fileManager fileExistsAtPath:dest]) { // not really necessary <- error case already handle by fileManager copyItemAtPath
        NSLog(@"%@ Target file exists", TAG);
        return NO;
    }
    // create path to dest
    if (![fileManager createDirectoryAtPath:[dest stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil]) {
        NSLog(@"%@ error creating target file", TAG);
        return NO;
    }
    // copy src to dest
    BOOL res = [fileManager moveItemAtPath:src toPath:dest error:nil];
    return res;
}

/**
* Gets filepath of localStorage file we want to migrate from
*/
- (NSString*) resolveOriginalLocalStorageFile
{
    NSString* appLibraryFolder = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString* original;
    NSString* originalLSFilePath = [appLibraryFolder stringByAppendingPathComponent:ORIG_LS_FILEPATH];

    if ([[NSFileManager defaultManager] fileExistsAtPath:originalLSFilePath]) {
        original = originalLSFilePath;
    } else {
        original = [appLibraryFolder stringByAppendingPathComponent:ORIG_LS_CACHE];
    }
    return original;
}

/**
* Gets filepath of localStorage file we want to migrate to
*/
- (NSString*) resolveTargetLocalStorageFile
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSString* appLibraryFolder = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString* bundleIdentifier = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];

    // Build base path to WebKit directory
    NSString* webkitRoot = [appLibraryFolder stringByAppendingPathComponent:TARGET_LS_ROOT_DIR];
    NSString* bundleDir = [webkitRoot stringByAppendingPathComponent:bundleIdentifier];
    NSString* defaultPath = [bundleDir stringByAppendingPathComponent:@"WebsiteData/Default"];

    // Find the hash directory that WKWebView created
    NSError* error = nil;
    NSArray* contents = [fileManager contentsOfDirectoryAtPath:defaultPath error:&error];

    if (error != nil) {
        NSLog(@"%@ Unable to read Default directory: %@", TAG, error);
        return nil;
    }

    // Look for hash directory (excluding hidden files)
    for (NSString* hashDir in contents) {
        if ([hashDir hasPrefix:@"."]) continue;

        // Check if this directory contains a nested directory of the same name
        NSString* outerHashPath = [defaultPath stringByAppendingPathComponent:hashDir];
        NSString* innerHashPath = [outerHashPath stringByAppendingPathComponent:hashDir];
        NSString* localStoragePath = [innerHashPath stringByAppendingPathComponent:@"LocalStorage"];

        if ([fileManager fileExistsAtPath:localStoragePath]) {
            NSLog(@"%@ Found WKWebView localStorage at: %@", TAG, localStoragePath);
            return localStoragePath;
        }
    }

    NSLog(@"%@ No WKWebView localStorage directory found. Has localStorage been initialized?", TAG);
    return nil;
}

@end
