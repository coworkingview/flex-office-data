/**
 * Renders the popup and the options page in headless Chrome.
 * The pages use the add-on's own renderer and the recorded API fixtures.
 * Nothing is requested from api.coworkingview.com.
 */

import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { mkdtempSync, readFileSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { extname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("..", import.meta.url));
const types = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json",
  ".png": "image/png",
};

const popupHtml = readFileSync(join(root, "addon/popup/popup.html"), "utf8")
  .replace('href="popup.css"', 'href="/addon/popup/popup.css"')
  .replace('src="../icons/icon-32.png"', 'src="/addon/icons/icon-32.png"')
  .replace(
    '<script type="module" src="popup.js"></script>',
    '<script type="module" src="/tools/shot/popup.js"></script>',
  );
const optionsHtml = readFileSync(join(root, "addon/options/options.html"), "utf8")
  .replace('href="options.css"', 'href="/addon/options/options.css"')
  .replace(
    '<script type="module" src="options.js"></script>',
    '<script type="module" src="/tools/shot/options.js"></script>',
  );

const server = createServer((request, response) => {
  const url = new URL(request.url, "http://127.0.0.1");
  if (url.pathname === "/shot/popup.html") {
    response.writeHead(200, { "content-type": types[".html"] });
    response.end(popupHtml);
    return;
  }
  if (url.pathname === "/shot/options.html") {
    response.writeHead(200, { "content-type": types[".html"] });
    response.end(optionsHtml);
    return;
  }
  const path = join(root, decodeURIComponent(url.pathname).replace(/^\/+/, ""));
  if (!path.startsWith(root)) {
    response.writeHead(404);
    response.end();
    return;
  }
  try {
    const body = readFileSync(path);
    response.writeHead(200, { "content-type": types[extname(path)] || "application/octet-stream" });
    response.end(body);
  } catch {
    response.writeHead(404);
    response.end();
  }
});

await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const { port } = server.address();
const shots = [
  ["/shot/popup.html", "docs/screenshots/popup-berlin.png", "480,860"],
  ["/shot/options.html", "docs/screenshots/options.png", "880,900"],
];

for (const [pathname, file, size] of shots) {
  const target = join(root, file);
  await runChrome(`http://127.0.0.1:${port}${pathname}`, target, size);
  console.log(target);
}

server.close();

function runChrome(url, output, size) {
  return new Promise((resolve, reject) => {
    const profile = mkdtempSync(join(tmpdir(), "cv-chrome-"));
    const child = spawn(
      "google-chrome",
      [
        "--headless=new",
        "--disable-gpu",
        "--no-sandbox",
        "--disable-dev-shm-usage",
        "--hide-scrollbars",
        `--user-data-dir=${profile}`,
        "--virtual-time-budget=8000",
        `--window-size=${size}`,
        `--screenshot=${output}`,
        url,
      ],
      { stdio: "inherit" },
    );
    const started = Date.now();
    const poll = setInterval(() => {
      try {
        if (statSync(output).size > 1000 && Date.now() - started > 1500) {
          child.kill("SIGKILL");
        }
      } catch {
        // The screenshot file is written at the end of the page load.
      }
    }, 300);
    const timer = setTimeout(() => child.kill("SIGKILL"), 20000);
    child.on("exit", () => {
      clearTimeout(timer);
      clearInterval(poll);
      setTimeout(() => {
        try {
          rmSync(profile, { recursive: true, force: true });
        } catch {
          // Chrome may still be releasing the profile directory.
        }
      }, 500);
      let bytes = 0;
      try {
        bytes = statSync(output).size;
      } catch {
        bytes = 0;
      }
      if (bytes > 1000) {
        resolve();
        return;
      }
      reject(new Error(`chrome wrote ${bytes} bytes for ${url}`));
    });
  });
}
