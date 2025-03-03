interface MigrateLocalStorageInterface {
  /**
   * Migrates localStorage data from UIWebView to WKWebView
   * @returns Promise that resolves to true if migration was successful
   */
  migrate(): Promise<boolean>;
}

// Extend the global Window interface
declare global {
  interface Window {
    MigrateLocalStorage: MigrateLocalStorageInterface;
  }
}

export {};