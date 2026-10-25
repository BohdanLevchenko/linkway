import { buildLinkwayURL } from "./linkway.js";

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: "prompt-link", title: "Open Link in Linkway", contexts: ["link"]
    });
    chrome.contextMenus.create({
      id: "prompt-page", title: "Open Page in Linkway", contexts: ["page"],
      documentUrlPatterns: ["http://*/*", "https://*/*"]
    });
    chrome.contextMenus.create({
      id: "route-link", title: "Route Link with Linkway Rules", contexts: ["link"]
    });
  });
});

async function deliver(link, mode, tab) {
  const url = buildLinkwayURL(link, mode);
  if (!url || !Number.isInteger(tab?.id)) return;
  try {
    // Chromium aborts external-protocol navigation without committing a new page.
    await chrome.tabs.update(tab.id, { url });
  } catch {
    // The tab may have closed, or browser policy may block external protocols.
  }
}

chrome.action.onClicked.addListener((tab) => { void deliver(tab.url, "prompt", tab); });
chrome.contextMenus.onClicked.addListener((info, tab) => {
  switch (info.menuItemId) {
    case "prompt-link": void deliver(info.linkUrl, "prompt", tab); break;
    case "prompt-page": void deliver(info.pageUrl, "prompt", tab); break;
    case "route-link": void deliver(info.linkUrl, "open", tab); break;
  }
});
chrome.commands.onCommand.addListener((command, tab) => {
  if (command === "open-page") void deliver(tab?.url, "prompt", tab);
});
