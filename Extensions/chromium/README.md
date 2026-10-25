# Linkway for Chromium

Requires the Linkway desktop app on macOS and Chromium 116 or later. This is a plain Manifest V3 extension with no build step or dependencies.

## Install

1. In Linkway Settings → General → Browser Extension & Bookmarklet, click **Show Extension Folder**. In a source checkout, use this `Extensions/chromium` folder.
2. Open `chrome://extensions`, enable **Developer mode**, and choose **Load unpacked**.
3. Select the extension folder itself, then pin Linkway to the toolbar if desired.

The same unpacked-install workflow is available in Edge (`edge://extensions`), Brave (`brave://extensions`), Vivaldi (`vivaldi://extensions`), and Opera (`opera://extensions`). These browsers have not been manually verified for this release; this is not a tested-support matrix.

## Use

- Click **Open in Linkway** or press **Alt+Shift+L** (**Option+Shift+L** on Mac) to show the desktop picker for the active page. Change conflicting shortcuts in the browser's extension keyboard-shortcuts settings.
- Right-click a link → **Open Link in Linkway** to show the picker, or **Route Link with Linkway Rules** to apply routing rules.
- Right-click the page → **Open Page in Linkway** to show the picker.

Only HTTP/HTTPS pages and HTTP/HTTPS/mailto links are forwarded. Other schemes, empty URLs, and URLs longer than 32,768 UTF-16 code units are ignored. Links use `linkway://prompt?url=` or `linkway://open?url=` with `encodeURIComponent`, preserving query strings, fragments, existing percent escapes, and Unicode.

The browser's **Open Linkway?** protocol prompt is expected. Accept it and select **Always allow** if offered and desired. Install and launch Linkway first; if it is missing or browser policy blocks the protocol, no picker will open. The extension cannot confirm that the app received a URL. Declining the prompt keeps the page open.

Delivery uses `chrome.tabs.update` on the invoking tab, without creating or closing tabs. Chromium hands external protocols to the OS and aborts that navigation without committing a replacement document (see [navigation loader](https://chromium.googlesource.com/chromium/src/+/main/content/browser/loader/navigation_url_loader_impl.cc), `UnknownSchemeCallback`, and [external protocol handler](https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/external_protocol/external_protocol_handler.cc)). This keeps the original page and protocol prompt together. Live protocol prompts and page preservation still require manual verification across browsers.

## Bookmarklet

Copy the bookmarklet from Linkway Settings → General, create a bookmark, and paste it as the bookmark's URL. Activate it on a web page to show the picker. Safari can use the bookmarklet; this extension is Chromium-only. Some pages and browser security policies block bookmarklets or external protocols, and browser-internal pages are not supported.

## Privacy

No data leaves the browser except the URL explicitly handed to the local Linkway app. The extension makes no network requests, stores no data, and uses only `contextMenus` and `activeTab`. There are no host permissions, content scripts, or remote code. Linkway's own URL-processing preferences apply after handoff.
