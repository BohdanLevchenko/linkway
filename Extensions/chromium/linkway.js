export function buildLinkwayURL(link, mode) {
  if (typeof link !== "string" || !link || link.length > 32768 ||
      (mode !== "prompt" && mode !== "open") ||
      !/^(https?:\/\/[^/?#\s]+|mailto:)/i.test(link) || /[\u0000-\u0020\u007f]/.test(link)) return null;
  try {
    return `linkway://${mode}?url=${encodeURIComponent(link)}`;
  } catch {
    return null;
  }
}
