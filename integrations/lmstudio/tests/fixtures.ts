import { readFileSync } from "node:fs";
import { join } from "node:path";

import type { GetFn, HttpResponse } from "../src/client";

const FIXTURES = join(process.cwd(), "..", "..", "spec", "fixtures");

export function readFixture(name: string): unknown {
  return JSON.parse(readFileSync(join(FIXTURES, name), "utf8")) as unknown;
}

export function jsonResponse(body: unknown, status = 200, headers: Record<string, string> = {}): HttpResponse {
  return {
    status,
    statusText: status === 200 ? "OK" : "Error",
    headers,
    body: JSON.stringify(body),
  };
}

export function textResponse(body: string, status: number, headers: Record<string, string> = {}): HttpResponse {
  return { status, statusText: "Error", headers, body };
}

export function scripted(responses: HttpResponse[]): {
  get: GetFn;
  urls: string[];
  headers: Record<string, string>[];
} {
  const urls: string[] = [];
  const headers: Record<string, string>[] = [];
  const queue = [...responses];
  const get: GetFn = async (url, init) => {
    urls.push(url);
    headers.push(init.headers);
    const next = queue.shift();
    if (!next) {
      throw new Error("unexpected extra request");
    }
    return next;
  };
  return { get, urls, headers };
}
