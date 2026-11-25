import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.resolve(here, "../out");
const port = Number(process.env.PORT || 4173);

const types = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".png": "image/png",
  ".jpg": "image/jpeg",
};

function safePath(requestPath) {
  const clean = decodeURIComponent(requestPath.split("?")[0]);
  const candidate = path.resolve(out, `.${clean}`);
  return candidate.startsWith(out) ? candidate : out;
}

createServer(async (request, response) => {
  try {
    let filePath = safePath(request.url || "/");
    const info = await stat(filePath).catch(() => null);
    if (info?.isDirectory()) filePath = path.join(filePath, "index.html");
    if (!info || !(await stat(filePath).catch(() => null))) {
      filePath = path.join(out, "404.html");
    }
    const body = await readFile(filePath);
    response.writeHead(200, { "content-type": types[path.extname(filePath)] || "application/octet-stream" });
    response.end(body);
  } catch {
    response.writeHead(404, { "content-type": "text/plain" });
    response.end("Not found");
  }
}).listen(port, "127.0.0.1", () => {
  console.log(`serving ${out} on http://127.0.0.1:${port}`);
});
