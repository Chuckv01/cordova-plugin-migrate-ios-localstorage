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
    // Start background work
    [self.commandDelegate runInBackground:^{
        NSLog(@"%@ Starting localStorage migration", TAG);
        
        // Extract data in background thread
        NSString* original = [self resolveOriginalLocalStorageFile];
        NSMutableDictionary* migrationData = nil;
        
        if (original) {
            migrationData = [self extractDataFromSQLite:original];
            NSLog(@"%@ Found %lu localStorage items to migrate", TAG, (unsigned long)migrationData.count);
        }
        
        if (!migrationData || migrationData.count == 0) {
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                                    messageAsString:@"No data to migrate"]
                                       callbackId:command.callbackId];
            return;
        }
        
        // Convert each value to base64 to avoid any escaping issues
        NSMutableDictionary *base64Data = [NSMutableDictionary dictionaryWithCapacity:migrationData.count];
        for (NSString *key in migrationData) {
            NSString *value = migrationData[key];
            NSData *valueData = [value dataUsingEncoding:NSUTF8StringEncoding];
            NSString *base64Value = [valueData base64EncodedStringWithOptions:0];
            [base64Data setObject:base64Value forKey:key];
        }
        
        // Convert entire dictionary to JSON
        NSError *jsonError;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:base64Data options:0 error:&jsonError];
        if (jsonError) {
            NSLog(@"%@ Error creating JSON: %@", TAG, jsonError);
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                                    messageAsString:@"JSON serialization error"]
                                       callbackId:command.callbackId];
            return;
        }
        
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        
        // Create JavaScript with the original code
        NSString *jsCode = [NSString stringWithFormat:@"(function() {\n"
                           "  var migrationCount = 0;\n"
                           "  var base64Data = %@;\n"
                           "  \n"
                           "  // Function to decode base64\n"
                           "  function base64ToUtf8(base64) {\n"
                           "    try {\n"
                           "      return decodeURIComponent(escape(window.atob(base64)));\n"
                           "    } catch (e) {\n"
                           "      console.error('Base64 decode error:', e);\n"
                           "      return '';\n"
                           "    }\n"
                           "  }\n"
                           "  \n"
                           "  // Process each item\n"
                           "  for (var key in base64Data) {\n"
                           "    try {\n"
                           "      var decodedValue = base64ToUtf8(base64Data[key]);\n"
                           "      localStorage.setItem(key, decodedValue);\n"
                           "      migrationCount++;\n"
                           "    } catch (e) {\n"
                           "      console.error('Error migrating key ' + key + ':', e);\n"
                           "    }\n"
                           "  }\n"
                           "  \n"
                           "  window.dispatchEvent(new CustomEvent('localStorageMigrationComplete', {\n"
                           "    detail: { success: true, migrated: migrationCount }\n"
                           "  }));\n"
                           "  return migrationCount;\n"
                           "})();", jsonString];
        
        // Move to main thread for WKWebView JavaScript execution
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.webViewEngine evaluateJavaScript:jsCode completionHandler:^(id result, NSError *error) {
                if (error) {
                    NSLog(@"%@ JavaScript migration error: %@", TAG, error);
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                              messageAsString:[error localizedDescription]]
                                               callbackId:command.callbackId];
                } else {
                    NSInteger itemsMigrated = [result integerValue];
                    BOOL success = (itemsMigrated > 0);
                    NSLog(@"%@ Migration completed via JavaScript: %ld items", TAG, (long)itemsMigrated);
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                              messageAsBool:success]
                                               callbackId:command.callbackId];
                }
            }];
        });
    }];
}

/**
* Extracts all localStorage key-value pairs from a SQLite database
*/
- (NSMutableDictionary*)extractDataFromSQLite:(NSString*)sqlitePath {
    NSMutableDictionary* data = [NSMutableDictionary dictionary];
    sqlite3 *database;
    
    if (sqlite3_open_v2([sqlitePath UTF8String], &database, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK) {
        // Read data, handling binary correctly
        sqlite3_stmt *statement;
        const char *query = "SELECT key, value FROM ItemTable";
        
        if (sqlite3_prepare_v2(database, query, -1, &statement, NULL) == SQLITE_OK) {
            while (sqlite3_step(statement) == SQLITE_ROW) {
                const unsigned char *keyText = sqlite3_column_text(statement, 0);
                int keyLength = sqlite3_column_bytes(statement, 0);
                
                const void *valueData = sqlite3_column_blob(statement, 1);
                int valueLength = sqlite3_column_bytes(statement, 1);
                
                if (keyText && valueData && valueLength > 0) {
                    NSString *key = [[NSString alloc] initWithBytes:keyText
                                                             length:keyLength
                                                           encoding:NSUTF8StringEncoding];
                    
                    NSString *value = [[NSString alloc] initWithBytes:valueData
                                                               length:valueLength
                                                             encoding:NSUTF8StringEncoding];
                    
                    if (key && value) {
                        [data setObject:value forKey:key];
                    }
                }
            }
            sqlite3_finalize(statement);
        }
        sqlite3_close(database);
    }
    
    return data;
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
    const char *query = "SELECT value FROM ItemTable WHERE key = '__MigrateLocalStorageInit'";

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
