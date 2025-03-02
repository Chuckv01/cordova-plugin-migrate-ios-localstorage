var exec = require('cordova/exec');

var MigrateLocalStorage = {
  migrate: function (successCallback, errorCallback) {
    try {
      // Check if localStorage already has data (besides our initialization keys)
      if (localStorage.length > 1) {
        console.log('localStorage already has data, skipping migration');
        successCallback(true);
        return;
      }

      console.log('Setting initialization marker in localStorage');
      var initValue = 'init-' + Date.now();
      localStorage.setItem('__init', initValue);

      // Begin polling to check when storage is ready
      this._pollForStorageReady(initValue, function (isReady) {
        if (isReady) {
          console.log('localStorage is ready, proceeding with migration');
          localStorage.removeItem('__init');

          // Call the native migration function
          exec(function (success) {
            if (success) {
              console.log('Migration successful');
              // Force WKWebView to reload localStorage data
              setTimeout(() => {
                console.log('Forcing reload of localStorage');
                var refreshKey = '__refresh_' + Date.now();
                localStorage.setItem(refreshKey, 'true');
                localStorage.removeItem(refreshKey);
                successCallback(success);
              }, 1000);
            }
          }, errorCallback, 'MigrateLocalStorage', 'migrate', []);
        } else {
          console.error('localStorage not ready after maximum attempts');
          errorCallback('Storage initialization failed');
        }
      });
    } catch (err) {
      console.error('Error initializing localStorage:', err);
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
      console.log('Checking localStorage readiness (attempt ' + attempts + '): ' + currentValue);

      if (currentValue === expectedValue) {
        console.log('localStorage is confirmed ready');
        callback(true);
      } else if (attempts < maxAttempts) {
        console.log('localStorage not ready yet, waiting...');
        setTimeout(checkStorage, interval);
      } else {
        console.log('Maximum attempts reached, giving up');
        callback(false);
      }
    };

    // Start polling
    setTimeout(checkStorage, interval);
  }
};

module.exports = MigrateLocalStorage;
