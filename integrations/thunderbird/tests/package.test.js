import assert from "node:assert/strict";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";
import { JSDOM } from "jsdom";

const root = new URL("../addon/", import.meta.url);

test("manifest is MailExtension MV3 with only storage and the API host", () => {
  const manifest = JSON.parse(readFileSync(new URL("manifest.json", root), "utf8"));
  assert.equal(manifest.manifest_version, 3);
  assert.equal(manifest.name, "__MSG_extensionName__");
  assert.equal(manifest.description, "__MSG_extensionDescription__");
  assert.equal(manifest.version, "0.1.0");
  assert.equal(manifest.author, "CoworkingView");
  assert.equal(manifest.homepage_url, "https://coworkingview.com");
  assert.equal(manifest.default_locale, "en");
  assert.equal(manifest.browser_specific_settings.gecko.id, "coworkingview@coworkingview.com");
  assert.equal(manifest.browser_specific_settings.gecko.strict_min_version, "128.0");
  assert.equal(manifest.browser_specific_settings.gecko.strict_max_version, undefined);
  assert.equal(manifest.browser_specific_settings.gecko.data_collection_permissions, undefined);
  assert.equal(manifest.applications, undefined);
  assert.deepEqual(manifest.permissions, ["storage"]);
  assert.deepEqual(manifest.host_permissions, ["https://api.coworkingview.com/*"]);
  assert.equal(manifest.background, undefined);
  assert.equal(manifest.message_display_action.default_popup, "popup/popup.html");
  assert.equal(manifest.message_display_action.default_title, "__MSG_buttonLabel__");
  assert.equal(manifest.message_display_action.default_label, "__MSG_buttonLabel__");
  assert.equal(manifest.compose_action.default_popup, "popup/popup.html");
  assert.equal(manifest.options_ui.page, "options/options.html");
  for (const size of ["16", "32", "48", "64", "96", "128"]) {
    const path = manifest.icons[size];
    assert.ok(statSync(new URL(path, root)).size > 50, path);
  }
});

test("English strings match the listing name and the button label", () => {
  const en = JSON.parse(readFileSync(new URL("_locales/en/messages.json", root), "utf8"));
  const de = JSON.parse(readFileSync(new URL("_locales/de/messages.json", root), "utf8"));
  const es = JSON.parse(readFileSync(new URL("_locales/es/messages.json", root), "utf8"));
  assert.equal(en.extensionName.message, "CoworkingView – Workspace Prices");
  assert.equal(en.buttonLabel.message, "CoworkingView prices");
  assert.deepEqual(Object.keys(en).sort(), Object.keys(de).sort());
  assert.deepEqual(Object.keys(en).sort(), Object.keys(es).sort());
  for (const [key, entry] of Object.entries(en)) {
    assert.equal(typeof de[key].message, "string");
    assert.equal(typeof es[key].message, "string");
    assert.ok(de[key].message.length > 0, key);
    assert.ok(es[key].message.length > 0, key);
    assert.deepEqual(
      Object.keys(entry.placeholders || {}).sort(),
      Object.keys(de[key].placeholders || {}).sort(),
    );
    assert.deepEqual(
      Object.keys(entry.placeholders || {}).sort(),
      Object.keys(es[key].placeholders || {}).sort(),
    );
  }
});

test("pages localise every visible string and load no remote code", () => {
  for (const page of ["popup/popup.html", "options/options.html"]) {
    const html = readFileSync(new URL(page, root), "utf8");
    const dom = new JSDOM(html);
    const { document } = dom.window;
    const text = [...document.body.querySelectorAll("*")]
      .map((element) => {
        return [...element.childNodes]
          .filter((node) => node.nodeType === 3)
          .map((node) => node.textContent.trim())
          .join("");
      })
      .filter(Boolean);
    assert.deepEqual(text, [], page);
    for (const script of document.querySelectorAll("script")) {
      const src = script.getAttribute("src");
      assert.ok(src, page);
      assert.equal(src.startsWith("http"), false, src);
      assert.equal(script.getAttribute("type"), "module");
    }
    for (const link of document.querySelectorAll("link")) {
      assert.equal(link.getAttribute("href").startsWith("http"), false);
    }
    for (const image of document.querySelectorAll("img")) {
      assert.equal(image.getAttribute("src").startsWith("http"), false);
    }
  }
});

test("shipped JavaScript is readable source: no eval, innerHTML, or remote URL", () => {
  const files = walk(fileURLToPath(root)).filter((file) => file.endsWith(".js") || file.endsWith(".html") || file.endsWith(".css"));
  assert.ok(files.length > 0);
  const banned = [
    "eval(",
    "new Function",
    "innerHTML",
    "insertAdjacentHTML",
    "document.write",
    "javascript:",
  ];
  for (const file of files) {
    const source = readFileSync(file, "utf8");
    for (const token of banned) {
      assert.equal(source.includes(token), false, `${file} contains ${token}`);
    }
    assert.equal(source.includes("http://"), false, file);
  }
});

test("every data-i18n key exists in English", () => {
  const en = JSON.parse(readFileSync(new URL("_locales/en/messages.json", root), "utf8"));
  for (const page of ["popup/popup.html", "options/options.html"]) {
    const html = readFileSync(new URL(page, root), "utf8");
    const keys = [...html.matchAll(/data-i18n-[a-z-]+="([^"]+)"/g)].map((match) => match[1]);
    assert.ok(keys.length > 0, page);
    for (const key of keys) {
      assert.ok(en[key], `${page} missing ${key}`);
    }
  }
});

function walk(dir) {
  const files = [];
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) {
      files.push(...walk(path));
    } else {
      files.push(path);
    }
  }
  return files;
}

function fileURLToPath(url) {
  return decodeURIComponent(url.pathname);
}
