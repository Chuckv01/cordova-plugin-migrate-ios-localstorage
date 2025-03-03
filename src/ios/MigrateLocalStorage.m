#import "MigrateLocalStorage.h"

#define TAG @"\nMigrateLocalStorage"
#define ORIG_LS_FILEPATH @"WebKit/LocalStorage/file__0.localstorage"
#define ORIG_LS_CACHE @"Caches/file__0.localstorage"
#define TARGET_LS_ROOT_DIR @"WebKit"
#import <sqlite3.h>

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
  
  // Copy the files with WKWebView naming convention
  BOOL success1 = [self copy:original to:targetFile];
  BOOL success2 = [self copy:[original stringByAppendingString:@"-shm"]
                         to:[targetFile stringByAppendingString:@"-shm"]];
  BOOL success3 = [self copy:[original stringByAppendingString:@"-wal"]
                         to:[targetFile stringByAppendingString:@"-wal"]];
  
  NSLog(@"%@ Copy status for localstorage.sqlite3 files: %d %d %d", TAG, success1, success2, success3);
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
 * Deletes file if it exists
 */
- (BOOL) deleteFile:(NSString*)path
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    
    // If file doesn't exist, consider deletion successful
    if (![fileManager fileExistsAtPath:path]) {
        return YES;  // Nothing to delete
    }
    
    NSError* error = nil;
    BOOL result = [fileManager removeItemAtPath:path error:&error];
    
    if (!result) {
        NSLog(@"%@ Failed to delete file: %@ (Error: %@)", TAG, path, error);
    }
    
    return result;
}

/**
 * Copies an item from src to dest, replacing dest if it exists
 */
- (BOOL) copy:(NSString*)src to:(NSString*)dest
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    
    // Check if source file exists
    if (![fileManager fileExistsAtPath:src]) {
        NSLog(@"%@ Source file does not exist: %@", TAG, src);
        return NO;
    }
    
    // Always delete destination file if it exists
    if ([fileManager fileExistsAtPath:dest]) {
        NSLog(@"%@ Target file exists, removing: %@", TAG, dest);
        if (![self deleteFile:dest]) {
            NSLog(@"%@ Failed to remove existing target file, aborting copy", TAG);
            return NO;
        }
    }
    
    // Create path to dest
    NSString* destDir = [dest stringByDeletingLastPathComponent];
    NSError* dirError = nil;
    if (![fileManager createDirectoryAtPath:destDir
              withIntermediateDirectories:YES
                             attributes:nil
                                  error:&dirError]) {
        NSLog(@"%@ Error creating target directory %@: %@", TAG, destDir, dirError);
        return NO;
    }
    
    // Copy src to dest
    NSError* copyError = nil;
    BOOL result = [fileManager copyItemAtPath:src toPath:dest error:&copyError];
    
    if (!result) {
        NSLog(@"%@ Failed to copy %@ to %@: %@", TAG, src, dest, copyError);
    } else {
        NSLog(@"%@ Successfully copied %@ to %@", TAG, src, dest);
    }
    
    return result;
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
 * Checks if a SQLite database contains our initialization marker
 */
- (BOOL)sqliteFileContainsInitKey:(NSString*)sqlitePath {
  sqlite3 *database;
  if (sqlite3_open([sqlitePath UTF8String], &database) == SQLITE_OK) {
    sqlite3_stmt *statement;
    const char *query = "SELECT value FROM ItemTable WHERE key = '__init'";
    
    if (sqlite3_prepare_v2(database, query, -1, &statement, NULL) == SQLITE_OK) {
      if (sqlite3_step(statement) == SQLITE_ROW) {
        sqlite3_finalize(statement);
        sqlite3_close(database);
        return YES;
      }
      sqlite3_finalize(statement);
    }
    sqlite3_close(database);
  }
  return NO;
}

/**
 * Gets filepath of localStorage file we want to migrate to
 */
- (NSString*)resolveTargetLocalStorageFile {
  NSFileManager* fileManager = [NSFileManager defaultManager];
  NSString* appLibraryFolder = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0];
  
  // Search locations in order of preference
  NSArray* potentialBasePaths = @[
    [appLibraryFolder stringByAppendingPathComponent:@"WebKit/WebsiteData/Default"],
    [NSString stringWithFormat:@"%@/WebKit/%@/WebsiteData/Default",
     appLibraryFolder,
     [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"]]
  ];
  
  // Check each potential base path
  for (NSString* basePath in potentialBasePaths) {
    if (![fileManager fileExistsAtPath:basePath]) {
      continue;
    }
    
    NSError* error = nil;
    NSArray* contents = [fileManager contentsOfDirectoryAtPath:basePath error:&error];
    
    if (error || contents.count == 0) {
      continue;
    }
    
    // Check each hash directory
    for (NSString* hashDir in contents) {
      if ([hashDir hasPrefix:@"."]) continue;
      
      NSString* outerHashPath = [basePath stringByAppendingPathComponent:hashDir];
      NSString* innerHashPath = [outerHashPath stringByAppendingPathComponent:hashDir];
      NSString* lsPath = [innerHashPath stringByAppendingPathComponent:@"LocalStorage"];
      NSString* sqlitePath = [lsPath stringByAppendingPathComponent:@"localstorage.sqlite3"];
      
      if ([fileManager fileExistsAtPath:sqlitePath]) {
        NSLog(@"%@ Checking SQLite file: %@", TAG, sqlitePath);
        
        // Check if this SQLite file contains our initialization key
        if ([self sqliteFileContainsInitKey:sqlitePath]) {
          NSLog(@"%@ Found active WKWebView localStorage at: %@", TAG, lsPath);
          return lsPath;
        }
      }
    }
  }
  
  // If no directory with our marker was found, fallback to the first valid directory
  for (NSString* basePath in potentialBasePaths) {
    if (![fileManager fileExistsAtPath:basePath]) continue;
    
    NSArray* contents = [fileManager contentsOfDirectoryAtPath:basePath error:nil];
    
    for (NSString* hashDir in contents) {
      if ([hashDir hasPrefix:@"."]) continue;
      
      NSString* path = [[[basePath stringByAppendingPathComponent:hashDir]
                         stringByAppendingPathComponent:hashDir]
                        stringByAppendingPathComponent:@"LocalStorage"];
      
      if ([fileManager fileExistsAtPath:[path stringByAppendingPathComponent:@"localstorage.sqlite3"]]) {
        NSLog(@"%@ No directory with marker found, using first valid directory: %@", TAG, path);
        return path;
      }
    }
  }
  
  NSLog(@"%@ Could not find any WKWebView localStorage directory", TAG);
  return nil;
}

@end
