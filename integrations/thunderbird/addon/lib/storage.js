/**
 * The default city is the only value stored. storage.local stays on this
 * computer; storage.sync is not used.
 */

import { ApiError } from "./errors.js";
import { CITY_STORAGE_KEY, DEFAULT_CITY, isSlug } from "./parse.js";

export async function readStoredCity(storage) {
  const stored = await storage.local.get({ [CITY_STORAGE_KEY]: DEFAULT_CITY });
  const value = stored[CITY_STORAGE_KEY];
  return isSlug(value) ? value : DEFAULT_CITY;
}

export async function writeStoredCity(storage, city) {
  if (!isSlug(city)) {
    throw new ApiError("Invalid city slug", { code: "BAD_CITY" });
  }
  await storage.local.set({ [CITY_STORAGE_KEY]: city });
}
