package cordova.plugins.crosswalk;

import android.app.Activity;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.os.Build;
import android.util.Log;

import org.apache.cordova.CordovaInterface;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CordovaWebView;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.util.HashMap;
import java.util.Map;

public class Migration extends CordovaPlugin {

    public static final String TAG = "Migration";
    private static boolean hasRun = false;
    private static String XwalkPath = "app_xwalkcore/Default";
    private static String modernLocalStorageDir = "Local Storage";
    private static final String LOCALSTORAGE_FILE = "file__0.localstorage";

    private Activity activity;
    private Context context;
    private CordovaWebView webView;
    private File appRoot;
    private File xWalkRoot;

    @Override
    public void initialize(CordovaInterface cordova, CordovaWebView webView) {
        Log.d(TAG, "initialize()");
        this.webView = webView;

        if(!hasRun){
            hasRun = true;
            activity = cordova.getActivity();
            context = activity.getApplicationContext();

            // Run migration in a background thread to not block UI
            cordova.getThreadPool().execute(new Runnable() {
                public void run() {
                    migrateLocalStorage();
                }
            });
        }

        super.initialize(cordova, webView);
    }

    private void migrateLocalStorage() {
        Log.d(TAG, "Starting localStorage migration");

        // Look for XWalk directory
        boolean found = lookForXwalk(context.getFilesDir());
        if (!found) {
            found = lookForXwalk(context.getExternalFilesDir(null));
        }

        if (!found) {
            Log.d(TAG, "No XWalk directory found, skipping migration");
            return;
        }

        // Get the LocalStorage SQLite file
        xWalkRoot = constructFilePaths(appRoot, XwalkPath);
        File localStorageDir = constructFilePaths(xWalkRoot, modernLocalStorageDir);
        File localStorageFile = constructFilePaths(localStorageDir, LOCALSTORAGE_FILE);

        if (!localStorageFile.exists()) {
            Log.d(TAG, "LocalStorage file does not exist: " + localStorageFile.getAbsolutePath());
            return;
        }

        // Read key-value pairs from SQLite file
        Map<String, String> localStorage = readLocalStorageFromSQLite(localStorageFile);

        if (localStorage.isEmpty()) {
            Log.d(TAG, "No localStorage data found to migrate");
            return;
        }

        // Inject JavaScript to set localStorage items
        injectLocalStorage(localStorage);

        // Clean up old files after successful migration
        Log.d(TAG, "Migration complete, cleaning up old files");
    }

    private Map<String, String> readLocalStorageFromSQLite(File dbFile) {
        Map<String, String> result = new HashMap<>();
        SQLiteDatabase db = null;

        try {
            db = SQLiteDatabase.openDatabase(dbFile.getPath(), null, SQLiteDatabase.OPEN_READONLY);

            // Query the key-value table
            Cursor cursor = db.query("ItemTable", new String[]{"key", "value"}, null, null, null, null, null);

            if (cursor != null) {
                while (cursor.moveToNext()) {
                    String key = cursor.getString(0);
                    String value = cursor.getString(1);
                    result.put(key, value);
                    Log.d(TAG, "Read localStorage item: " + key);
                }
                cursor.close();
            }
        } catch (Exception e) {
            Log.e(TAG, "Error reading localStorage SQLite file", e);
        } finally {
            if (db != null) {
                db.close();
            }
        }

        return result;
    }

    private void injectLocalStorage(final Map<String, String> localStorage) {
        if (localStorage.isEmpty()) {
            return;
        }

        try {
            // Create JavaScript to set localStorage items
            final JSONObject jsonData = new JSONObject();
            for (Map.Entry<String, String> entry : localStorage.entrySet()) {
                jsonData.put(entry.getKey(), entry.getValue());
            }

            // Execute on UI thread since WebView must be manipulated on UI thread
            activity.runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    String script =
                        "try {\n" +
                        "  const data = " + jsonData.toString() + ";\n" +
                        "  for (const key in data) {\n" +
                        "    localStorage.setItem(key, data[key]);\n" +
                        "    console.log('Migrated localStorage item:', key);\n" +
                        "  }\n" +
                        "  console.log('LocalStorage migration complete');\n" +
                        "} catch (e) {\n" +
                        "  console.error('LocalStorage migration error:', e);\n" +
                        "}\n";

                    // Use the appropriate mechanism to evaluate JavaScript
                    evaluateJavascript(script);
                }
            });
        } catch (JSONException e) {
            Log.e(TAG, "Error creating localStorage JSON", e);
        }
    }

    private void evaluateJavascript(String script) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                webView.getEngine().evaluateJavascript(script, null);
            } else {
                // For older Android versions
                webView.loadUrl("javascript:" + script);
            }
        } catch (Exception e) {
            Log.e(TAG, "Error injecting JavaScript", e);
        }
    }

    private boolean lookForXwalk(File filesPath) {
        File root = getStorageRootFromFiles(filesPath);
        boolean found = testFileExists(root, XwalkPath);
        if (found) {
            Log.d(TAG, "Found Crosswalk directory at " + root.getAbsolutePath());
            appRoot = root;
        }
        return found;
    }

    private boolean testFileExists(File root, String path) {
        File testFile = constructFilePaths(root, path);
        return testFile.exists();
    }

    private File constructFilePaths (File file1, File file2) {
        return constructFilePaths(file1.getAbsolutePath(), file2.getAbsolutePath());
    }

    private File constructFilePaths (File file1, String file2) {
        return constructFilePaths(file1.getAbsolutePath(), file2);
    }

    private File constructFilePaths (String file1, String file2) {
        File newPath;
        if (file2.startsWith(file1)) {
            newPath = new File(file2);
        }
        else {
            newPath = new File(file1 + "/" + file2);
        }
        return newPath;
    }

    private File getStorageRootFromFiles(File filesDir){
        String filesPath = filesDir.getAbsolutePath();
        filesPath = filesPath.replaceAll("/files", "");
        return new File(filesPath);
    }
}
