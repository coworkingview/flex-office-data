import { createConfigSchematics } from "@lmstudio/sdk";

// Per-chat settings. LM Studio stores these with the chat and shows them in the plugin sidebar.
// There is no API key: the CoworkingView API is public and read-only.

export const configSchematics = createConfigSchematics()
  .field(
    "language",
    "select",
    {
      displayName: "Default language",
      hint: "Locale sent as the locale query parameter when a tool call does not set language. The API accepts en, de, and es.",
      options: [
        { value: "en", displayName: "English" },
        { value: "de", displayName: "Deutsch" },
        { value: "es", displayName: "Español" },
      ],
    },
    "en",
  )
  .field(
    "requestTimeoutSeconds",
    "numeric",
    {
      displayName: "Request timeout (seconds)",
      hint: "How long one HTTPS request to api.coworkingview.com may take before it is aborted. A 429 or 5xx response is retried once.",
      int: true,
      min: 1,
      max: 120,
      slider: { min: 1, max: 60, step: 1 },
    },
    20,
  )
  .build();
