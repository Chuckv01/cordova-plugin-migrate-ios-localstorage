interface CordovaPlugins {
  MigrateLocalStorage: {
    /**
     * Migrates localStorage data from UIWebView to WKWebView
     * @returns Promise that resolves to true if migration was successful
     */
    migrate(): Promise<boolean>;
  };
}

interface CordovaMigrateLocalStorage {
  /**
   * Migrates localStorage data from UIWebView to WKWebView
   * @returns Promise that resolves to true if migration was successful
   */
  migrate(): Promise<boolean>;
}

interface Cordova {
  plugins: CordovaPlugins;
}

interface Window {
  cordova: Cordova;
  MigrateLocalStorage?: CordovaMigrateLocalStorage;
}

declare const MigrateLocalStorage: CordovaMigrateLocalStorage;

export = MigrateLocalStorage;