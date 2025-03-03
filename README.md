# Cordova Plugin: Migrate LocalStorage

A Cordova plugin that migrates localStorage data from UIWebView to WKWebView on iOS. This plugin is useful when transitioning from UIWebView to WKWebView in Capacitor or Cordova iOS applications.

## Description

When migrating a Cordova app from UIWebView to WKWebView, localStorage data is stored in different locations, which can cause users to lose their data during the transition. This plugin handles the migration of localStorage data from the UIWebView storage location to the WKWebView storage location.

## Installation

```bash
cordova plugin add cordova-plugin-migrate-ios-localstorage
```

Or directly from GitHub:

```bash
cordova plugin add https://github.com/Chuckv01/cordova-plugin-migrate-ios-localstorage.git
```

## Usage

The plugin provides a simple API to migrate localStorage data. Call the migrate method early in your app initialization:

```javascript
document.addEventListener('deviceready', function() {
  if (cordova.platformId === 'ios') {
    cordova.plugins.MigrateLocalStorage.migrate(
      function(success) {
        console.log('Migration completed successfully: ' + success);
      },
      function(error) {
        console.error('Migration failed: ' + error);
      }
    );
  }
}, false);
```

### API

`migrate(successCallback, errorCallback)`

Migrates localStorage data from UIWebView to WKWebView.

- *successCallback*: Function called when migration completes (receives boolean indicating success)
- *errorCallback*: Function called when migration fails (receives error message)

## How it Works

1. The plugin checks if localStorage already has data in WKWebView format
2. If not, it initializes localStorage with a marker
3. It polls until storage is confirmed ready
4. Then it copies the SQLite database files from the UIWebView location to the WKWebView location
5. After migration, it forces a reload of localStorage

## Requirements

- Cordova iOS 4.0.0+
- iOS 9.0+
- Capacitor

## License

This project is licensed under the Apache License 2.0.
