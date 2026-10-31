# Publish the CoworkingView Nextcloud app

The app id is `coworkingview`. The release archive is `coworkingview.tar.gz` with a single top-level folder `coworkingview/`. Build it from `integrations/nextcloud/coworkingview` with `make`. That archive is ready to sign. It does not contain `appinfo/signature.json`. Nextcloud signs the folder, and the signature has to be inside the archive you upload.

Keep the private key off this repository, off CI logs, and off the pull request. The commands below write it under `~/.nextcloud/certificates/` on the machine of the person who will publish the app.

## 1. Request the app certificate

The certificate is requested with a certificate signing request in a pull request to [nextcloud/app-certificate-requests](https://github.com/nextcloud/app-certificate-requests). The common name must be the app id.

```console
mkdir -p ~/.nextcloud/certificates
cd ~/.nextcloud/certificates
openssl req -nodes -newkey rsa:4096 -keyout coworkingview.key -out coworkingview.csr -subj "/CN=coworkingview"
```

`coworkingview.key` is the private key. Do not commit it, paste it, or send it. `coworkingview.csr` is the request. Open a pull request on that repository:

1. On <https://github.com/nextcloud/app-certificate-requests>, choose **Add file → Create new file**. This can be done in the GitHub web interface.
2. Name the file `coworkingview/coworkingview.csr`.
3. Paste the full contents of `~/.nextcloud/certificates/coworkingview.csr`, including the `BEGIN CERTIFICATE REQUEST` and `END CERTIFICATE REQUEST` lines.
4. Commit and open the pull request.
5. In the pull request body, link the public source: <https://github.com/coworkingview/flex-office-data> (the app lives in `integrations/nextcloud/coworkingview`).

You do not need to mention a reviewer. People who sign certificates are subscribed to that repository. Set your GitHub account so your email address is visible on your profile. Nextcloud may ask for something else to confirm that CoworkingView (`info@coworkingview.com`) owns the app.

When the request is approved, the signed certificate is added as `coworkingview/coworkingview.crt` in that repository. Copy it to `~/.nextcloud/certificates/coworkingview.crt` and remove any blank lines before `-----BEGIN CERTIFICATE-----` or after `-----END CERTIFICATE-----`. The file must start with `-----BEGIN CERTIFICATE-----`. It must not be the private key. A private key starts with `-----BEGIN PRIVATE KEY-----`.

If the private key is lost, open a new pull request that replaces `coworkingview/coworkingview.csr`, delete the old `coworkingview.crt` in that pull request, and say that the previous certificate should be revoked. Registering the new certificate deletes existing App Store releases, because their signatures no longer match.

The signing steps are also written in the [Nextcloud code signing manual](https://docs.nextcloud.com/server/stable/developer_manual/app_publishing_maintenance/code_signing.html) and the [App Store developer guide](https://nextcloudappstore.readthedocs.io/en/latest/developer.html).

## 2. Register the app

Registration is possible after the signed certificate exists. Sign in at <https://apps.nextcloud.com> and open the register-app form (developer apps, **New app**). The form asks for two values.

**Certificate.** Paste `~/.nextcloud/certificates/coworkingview.crt`.

**Signature.** A SHA-512 signature of the app id, not of the tarball:

```console
echo -n "coworkingview" | openssl dgst -sha512 -sign ~/.nextcloud/certificates/coworkingview.key | openssl base64
```

Paste the base64 line. The store checks that the certificate was signed by Nextcloud, that its common name is `coworkingview`, and that the signature was made with the matching private key. You are then the app owner and can publish releases.

The same call exists on the REST API as `POST /api/v1/apps` with a JSON body `{ "certificate": "...", "signature": "..." }` and a token from the store. The web form is enough for the first registration.

Do not post `coworkingview.key`.

## 3. Sign the release and upload it

Build the unsigned archive, sign the staged app folder, then pack the signed folder. Any change after signing requires signing again. `make` already omits tests, `src/`, `node_modules` and Composer files.

```console
cd integrations/nextcloud/coworkingview
make
# make leaves the staged tree at build/coworkingview and the unsigned
# archive at ../dist/coworkingview.tar.gz. Sign the staged tree:
sudo -u www-data php /path/to/nextcloud/occ integrity:sign-app \
  --privateKey=$HOME/.nextcloud/certificates/coworkingview.key \
  --certificate=$HOME/.nextcloud/certificates/coworkingview.crt \
  --path="$PWD/build/coworkingview"
tar -czf ../dist/coworkingview.tar.gz -C build coworkingview
python3 bin/check-tarball.py ../dist/coworkingview.tar.gz
```

`occ` writes `build/coworkingview/appinfo/signature.json`. That file must be inside the archive. Confirm the archive still has exactly one top-level directory, `coworkingview/`.

Host the `.tar.gz` at an `https://` URL. The store downloads it. The limit is 20 MB.

On the store's new-release form, provide:

- **Download:** the `https://` URL of `coworkingview.tar.gz`.
- **Nightly:** leave this unchecked for a normal release. A nightly upload is marked as a nightly on the store.
- **Signature:** a SHA-512 signature of the archive, not of the app id:

```console
openssl dgst -sha512 -sign ~/.nextcloud/certificates/coworkingview.key \
  integrations/nextcloud/dist/coworkingview.tar.gz | openssl base64
```

The REST equivalent is `POST /api/v1/apps/releases` with `{ "download": "https://...", "signature": "..." }`. Nightly releases set `"nightly": true`.

The store checks the signature, unpacks the archive, and validates `appinfo/info.xml` against <https://apps.nextcloud.com/schema/apps/info.xsd>. The archive must contain `coworkingview/appinfo/info.xml`. The version in that file is the release version. Ship a new version number for each upload. `CHANGELOG.md` in the archive is the text Nextcloud shows for the update.

## 4. What the store record should say

These values are already in `appinfo/info.xml`:

| Field | Value |
|---|---|
| App id | `coworkingview` |
| Name | CoworkingView |
| Licence | AGPL-3.0-or-later |
| Author | CoworkingView `<info@coworkingview.com>` |
| Website | <https://coworkingview.com> |
| Bugs | <https://github.com/coworkingview/flex-office-data/issues> |
| Repository | <https://github.com/coworkingview/flex-office-data> |
| Documentation | the app README on the default branch |
| Categories | tools, dashboard |
| Nextcloud | 33 through 35 |
| Screenshot | `integrations/nextcloud/coworkingview/screenshots/dashboard.png` on the default branch |

The screenshot URL in `info.xml` is the raw file on `main`. It starts working once that file is on the default branch. Replace it if the screenshot moves.
