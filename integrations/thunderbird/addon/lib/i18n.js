/**
 * Fills data-i18n-* attributes from browser.i18n messages.
 * The same attributes are used by the Thunderbird i18n sample.
 * Text is assigned with textContent.
 */

const ATTRIBUTES = [
  ["data-i18n-content", "content"],
  ["data-i18n-placeholder", "placeholder"],
  ["data-i18n-title", "title"],
  ["data-i18n-aria-label", "aria-label"],
];

export function localizeDocument(doc, translate) {
  const selector = ATTRIBUTES.map(([attribute]) => `[${attribute}]`).join(", ");
  for (const element of doc.querySelectorAll(selector)) {
    for (const [attribute, target] of ATTRIBUTES) {
      if (!element.hasAttribute(attribute)) {
        continue;
      }
      const key = element.getAttribute(attribute);
      const value = translate(key) || "";
      if (target === "content") {
        element.textContent = value;
      } else {
        element.setAttribute(target, value);
      }
    }
  }
}

/**
 * Stand-in for browser.i18n.getMessage, used by tests and the screenshot
 * tool. Named placeholders ($COUNT$) expand from content "$1", "$2", …
 */
export function translatorFromMessages(messages) {
  return (key, substitutions) => {
    const entry = messages[key];
    if (!entry || typeof entry.message !== "string") {
      return "";
    }
    const values =
      substitutions == null
        ? []
        : Array.isArray(substitutions)
          ? substitutions
          : [substitutions];
    let text = entry.message;
    const placeholders = entry.placeholders || {};
    for (const [name, spec] of Object.entries(placeholders)) {
      const index = Number(String(spec.content).replace(/\$/g, "")) - 1;
      const replacement = values[index] == null ? "" : String(values[index]);
      text = text.replaceAll(new RegExp(`\\$${name}\\$`, "gi"), replacement);
    }
    return text;
  };
}
