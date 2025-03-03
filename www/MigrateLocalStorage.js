var exec = require('cordova/exec');

var MigrateLocalStorage = {
  migrate: function (successCallback, errorCallback) {
    try {
      // Check if localStorage already has data
      if (localStorage.length > 0) {
        console.log('MigrateLocalStorage: localStorage already has data, skipping migration');
        successCallback(true);
        return;
      }

      console.log('MigrateLocalStorage: Setting initialization marker in localStorage');
      var initValue = 'init-' + Date.now();
      localStorage.setItem('__init', initValue);

      // Begin polling to check when storage is ready
      this._pollForStorageReady(initValue, function (isReady) {
        if (isReady) {
          console.log('MigrateLocalStorage: localStorage is ready, proceeding with migration');
          localStorage.removeItem('__init');

          // Call the native migration function
          exec(function (success) {
            if (success) {
              console.log('MigrateLocalStorage: Migration successful');
              // Force WKWebView to reload localStorage data
              setTimeout(() => {
                console.log('MigrateLocalStorage: Forcing reload of localStorage');
                var refreshKey = '__refresh_' + Date.now();
                localStorage.setItem(refreshKey, 'true');
                localStorage.removeItem(refreshKey);
                successCallback(success);
              }, 1000);
            }
          }, errorCallback, 'MigrateLocalStorage', 'migrate', []);
        } else {
          console.error('MigrateLocalStorage: localStorage not ready after maximum attempts');
          errorCallback('Storage initialization failed');
        }
      });
    } catch (err) {
      console.error('MigrateLocalStorage: Error initializing localStorage:', err);
      errorCallback(err);
    }
  },

  _pollForStorageReady: function (expectedValue, callback) {
    var attempts = 0;
    var maxAttempts = 10; // Maximum 10 seconds of waiting
    var interval = 1000; // Poll every second

    var checkStorage = function () {
      attempts++;

      // Get the current value and check if it matches
      var currentValue = localStorage.getItem('__init');
      console.log('MigrateLocalStorage: Checking localStorage readiness (attempt ' + attempts + '): ' + currentValue);

      if (currentValue === expectedValue) {
        console.log('MigrateLocalStorage: localStorage is confirmed ready');
        callback(true);
      } else if (attempts < maxAttempts) {
        console.log('MigrateLocalStorage: localStorage not ready yet, waiting...');
        setTimeout(checkStorage, interval);
      } else {
        console.log('MigrateLocalStorage: Maximum attempts reached, giving up');
        callback(false);
      }
    };

    // Start polling
    setTimeout(checkStorage, interval);
  }
};

module.exports = MigrateLocalStorage;
