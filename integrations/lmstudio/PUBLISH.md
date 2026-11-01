# Publish to the LM Studio Hub

The plugin is published with the LM Studio CLI as `coworkingview/coworkingview-workspace-prices`. LM Studio installs `lms` and the Node.js runtime the plugin runs on. The manifest in this directory already has `owner` set to `coworkingview` and `name` set to `coworkingview-workspace-prices`, revision 1.

Run the commands from this directory (`integrations/lmstudio`), so `lms` reads this `manifest.json`.

Documentation used for the steps below:

- Login: https://lmstudio.ai/docs/cli/develop-and-publish/login
- Push: https://lmstudio.ai/docs/cli/develop-and-publish/push
- Sharing plugins (organization owner): https://lmstudio.ai/docs/typescript/plugins/publish-plugins
- What the saved session is for: https://lmstudio.ai/docs/app/modelyaml/publish

## What `lms login` asks for

`lms login` authenticates the CLI with LM Studio Hub.

The published login page does not name OAuth scopes. It does not document a scope list, and it does not ask for access to local models, chats, or files. The permission it requests is a Hub sign-in:

1. The CLI opens a browser window for authentication. If a browser cannot be opened, copy the printed URL into a browser.
2. Approve that page. The current CLI prints a one-time code, a page where you enter the code, and a URL that already includes the code. That is the same browser sign-in the login page describes.
3. After you approve access, the session token is saved locally so the CLI can publish artifacts (plugins, presets, and `model.yaml` files).

Publishing this plugin uses that session to upload to the **organization** named in `manifest.json` (`coworkingview`), not to a personal account. The signed-in Hub user must be allowed to publish for that organization. The model.yaml publish guide describes the same requirement as write access to the user or organization named as the publisher. The plugins guide says: set `owner` to the organization name and `lms push` publishes to the organization instead of the personal account.

No CoworkingView API key is involved. Hub login is only for the upload.

### CI-style login

The login page also documents a non-interactive login. It uses pre-generated keys rather than a browser. The page does not describe those keys as OAuth scopes:

```bash
lms login --with-pre-authenticated-keys \
  --key-id <KEY_ID> \
  --public-key <PUBLIC_KEY> \
  --private-key <PRIVATE_KEY>
```

Do not put the private key in this repository or on the command line of a shared machine if it will be logged. The flag is for a CI secret store.

## Check the plugin before uploading

```bash
cd integrations/lmstudio
npm ci
npm run typecheck
npm test
npm run build
```

`npm test` is offline. It reads `spec/fixtures/` and does not call the API.

To try the tools inside LM Studio before publishing:

```bash
cd integrations/lmstudio
npm install
lms dev
```

`lms dev` rebuilds and reloads the plugin while it is running. Stop it with Ctrl+C before `lms push`.

## Push

```bash
cd integrations/lmstudio
lms login
lms push
```

`lms push` packages this folder and uploads a new revision to LM Studio Hub. For a plugin it asks you to confirm unless you pass `-y`. Read the file list before confirming. `node_modules` and `dist` are gitignored; do not force them into the upload.

Leave the artifact public. Do not pass `--private` unless you intend the first publish to be private. That flag does not change the visibility of an artifact that already exists.

Leave `revision` in `manifest.json` as it is in git. `--write-revision` rewrites the file with the revision number the Hub returns. Use it only when you mean to commit that change.

Useful flags from the push documentation:

```bash
lms push -y --write-revision
lms push --description "CoworkingView workspace prices" --overrides '{"tags": ["coworking"]}'
```

The first form skips the confirmation and writes the returned revision into `manifest.json`. The second overrides the description for that upload only.

After a successful push, the plugin is the Hub artifact `coworkingview/coworkingview-workspace-prices`.
