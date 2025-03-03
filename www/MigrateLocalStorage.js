var exec = require('cordova/exec');

var MigrateLocalStorage = {
  /**
   * Migrates localStorage data from UIWebView to WKWebView
   * @returns {Promise<boolean>} Promise that resolves to true if migration was successful
   */
  migrate: function() {
    return new Promise((resolve, reject) => {
      try {
        // Check if localStorage already has data
        if (localStorage.length > 0) {
          console.log('MigrateLocalStorage: localStorage already has data, skipping migration');
          resolve(true);
          return;
        }

        console.log('MigrateLocalStorage: Setting initialization marker in localStorage');
        var initValue = 'init-' + Date.now();
        localStorage.setItem('__MigrateLocalStorageInit', initValue);

        // Begin polling to check when storage is ready
        this._pollForStorageReady(initValue, function(isReady) {
          if (isReady) {
            console.log('MigrateLocalStorage: localStorage is ready, proceeding with migration');

            // Call the native migration function
            exec(function(success) {
              if (success) {
                console.log('MigrateLocalStorage: Migration successful');
                // Force WKWebView to reload localStorage data
                setTimeout(() => {
                  console.log('MigrateLocalStorage: Forcing reload of localStorage');
                  var refreshKey = '__refresh_' + Date.now();
                  localStorage.setItem(refreshKey, 'true');
                  localStorage.removeItem(refreshKey);
                  resolve(success);
                }, 1000);
              } else {
                resolve(false);
              }
            }, function(error) {
              console.error('MigrateLocalStorage: Native migration failed:', error);
              reject(error);
            }, 'MigrateLocalStorage', 'migrate', []);
          } else {
            console.error('MigrateLocalStorage: localStorage not ready after maximum attempts');
            reject('Storage initialization failed');
          }
        });
      } catch (err) {
        console.error('MigrateLocalStorage: Error initializing localStorage:', err);
        reject(err);
      }
    });
  },

  _pollForStorageReady: function (expectedValue, callback) {
    var attempts = 0;
    var maxAttempts = 10; // Maximum 10 seconds of waiting
    var interval = 1000; // Poll every second

    var checkStorage = function () {
      attempts++;

      // Get the current value and check if it matches
      var currentValue = localStorage.getItem('__MigrateLocalStorageInit');
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
