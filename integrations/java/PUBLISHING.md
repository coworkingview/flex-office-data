# Publish `io.github.coworkingview:coworkingview` to Maven Central

The coordinates are:

| | |
|---|---|
| groupId | `io.github.coworkingview` |
| artifactId | `coworkingview` |
| version | `0.1.0` |
| namespace | `io.github.coworkingview` |

Publishing uses the [Sonatype Central Portal](https://central.sonatype.com) (`org.sonatype.central:central-publishing-maven-plugin` 0.12.0). `autoPublish` is `false`: a deployment that validates stays in the portal until a person clicks Publish. The `release` profile runs `maven-gpg-plugin` 3.2.7. `mvn verify` does not sign and does not upload.

Do this from a machine that has the private key and the portal token. Do not commit either, and do not put them in CI logs or in the pull request.

The plugin reads server id `central` from `~/.m2/settings.xml`. That id matches `<publishingServerId>central</publishingServerId>` in `pom.xml`.

## 1. Central Portal account

1. Open <https://central.sonatype.com> and sign in with GitHub.
2. Use a GitHub user that can create public repositories in the **`coworkingview`** account. The namespace `io.github.coworkingview` belongs to that GitHub account (user or organization), not to a personal fork.
3. If the portal asks you to finish the account (name, email), use an address you can read. `info@coworkingview.com` is the address in the POM.

## 2. Verify the namespace `io.github.coworkingview`

Central checks that the GitHub account `coworkingview` owns the namespace by looking for a **temporary public repository whose name is a verification key**. The key is shown only in the portal. It is not a fixed string, and it changes if you start verification again. Do not invent one.

1. In the portal, open **Namespaces** (or **View Namespaces**) and choose **Add Namespace**.
2. Enter `io.github.coworkingview`. Submit it.
3. Choose the GitHub verification method. The portal shows a **verification key** (a token string).
4. While signed in as `coworkingview` on GitHub, create a new repository:
   - Owner: `coworkingview`
   - Name: the verification key, character for character
   - Visibility: **Public**
   - It can be empty. It must not be a fork, and it must not be private.
   - The URL will look like `https://github.com/coworkingview/<verification-key>`.
5. Back in the portal, click **Verify** (or **Verify Namespace**). Central requests that URL. When the namespace status is **Verified**, you can publish under `io.github.coworkingview`.
6. Delete the temporary repository. Verification stays after the repository is gone.

If verification fails, the usual causes are: the repository is private, the name does not match the key, the repository is under a different owner, or the portal session is not the `coworkingview` account. Start again and use the new key the portal shows.

Official reference: <https://central.sonatype.org/register/namespace/>.

## 3. Generate a GPG key and publish it

Central verifies signatures against a public key server. The key's email should be `info@coworkingview.com`, the same address as in the POM.

Create a key. This example has **no passphrase**, which is simpler for a one-shot release on a trusted machine. Prefer a passphrase on a key you will keep; the settings block below shows where it goes.

```console
gpg --batch --gen-key <<'EOF'
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: CoworkingView
Name-Email: info@coworkingview.com
Expire-Date: 2y
%no-protection
%commit
EOF

gpg --list-keys --keyid-format LONG info@coworkingview.com
```

Copy the long key id from the line that starts with `pub`. It is the 16 hex characters after `rsa4096/`, for example `ABCDEF0123456789`. Below, that value is `KEYID`.

Upload the public key. Central's documentation uses `keyserver.ubuntu.com`. Send it there, and to `keys.openpgp.org` as well. `keys.openpgp.org` may refuse the key until the address `info@coworkingview.com` is confirmed from their verification mail; the Ubuntu server does not require that.

```console
gpg --keyserver keyserver.ubuntu.com --send-keys KEYID
gpg --keyserver keys.openpgp.org --send-keys KEYID
```

Wait a minute, then confirm the server has it:

```console
gpg --keyserver keyserver.ubuntu.com --recv-keys KEYID
```

Keep the private key. `gpg --export-secret-keys` output does not belong in git. If the key has a passphrase, `maven-gpg-plugin` is already configured with `--pinentry-mode loopback`, and the passphrase goes in `settings.xml` as `gpg.passphrase` (next section). You can also put the passphrase in the agent with `gpg --export-secret-keys` left alone and `export GPG_TTY=$(tty)` before Maven, but loopback plus `gpg.passphrase` is what works in a non-interactive shell.

## 4. `~/.m2/settings.xml`

In the portal: account menu → **Generate User Token** (or **View Account** → **Generate Token**). The token is a **username and a password**, not a single bearer string. It is shown once. The username is not your GitHub login.

Create `~/.m2/settings.xml` (or merge this into the file you already have). Replace the three placeholders. The server `id` must stay `central`.

```xml
<settings>
  <servers>
    <server>
      <id>central</id>
      <username>TOKEN_USERNAME</username>
      <password>TOKEN_PASSWORD</password>
    </server>
  </servers>
  <profiles>
    <profile>
      <id>gpg</id>
      <properties>
        <gpg.keyname>KEYID</gpg.keyname>
        <!-- Omit the next line when the key was created with %no-protection. -->
        <gpg.passphrase>PASSPHRASE</gpg.passphrase>
      </properties>
    </profile>
  </profiles>
  <activeProfiles>
    <activeProfile>gpg</activeProfile>
  </activeProfiles>
</settings>
```

`gpg.keyname` may be the long key id, the fingerprint, or `info@coworkingview.com` when that address matches only one key.

## 5. Deploy

From `integrations/java`, with JDK 11 or newer and `gpg` on `PATH`:

```console
cd integrations/java
mvn -B -P release deploy
```

What that does, in order:

1. Compiles, tests, and builds the main jar, the `sources` jar and the `javadoc` jar.
2. The `release` profile signs each of those, and the POM, with `maven-gpg-plugin` (`*.asc`).
3. `central-publishing-maven-plugin` builds a bundle (Maven repository layout, checksums, signatures) and uploads it to the Central Portal.
4. Because `autoPublish` is `false` and `waitUntil` is `validated`, Maven waits until the portal has **validated** the bundle, then stops. It does **not** publish it to Maven Central.

If validation fails, the build fails and the portal's deployment page has the reason (a missing signature, a POM field, or a key the keyserver does not have yet). Fix that and run the same command again. A failed deployment can be dropped in the portal.

## 6. Publish in the portal

1. Open <https://central.sonatype.com/publishing/deployments>.
2. The deployment is named `coworkingview-0.1.0`. Its state should be **VALIDATED**.
3. Open it, review the files, and click **Publish**.

Publishing is not instant. The artifact usually appears on <https://central.sonatype.com/artifact/io.github.coworkingview/coworkingview> within a few minutes, and on Maven Central search a bit later. The first publish of a namespace can take longer.

After it is visible:

```xml
<dependency>
  <groupId>io.github.coworkingview</groupId>
  <artifactId>coworkingview</artifactId>
  <version>0.1.0</version>
</dependency>
```

## Alternative: build a bundle and upload it by hand

Use this when you want to inspect the zip, or when you would rather upload in the browser than let Maven upload.

### Signed bundle, no upload

Plugin 0.12.0 can stop after writing the zip. You still need the GPG key. You do **not** need the portal token for this step.

```console
cd integrations/java
mvn -B -P release deploy -DskipUpload=true
```

The plugin logs the path of the zip (under `target/`, in the central-publishing output directory). Upload that file at <https://central.sonatype.com/publishing/deployments> with **Publish Component**. The deployment still waits for you to click **Publish**, because `autoPublish` is false. Drop it if you were only inspecting.

### Unsigned bundle (not accepted by Central)

An unsigned zip is useful to check layout and checksums. The portal rejects it until every artifact has a `.asc` signature. `bundle-unsigned.sh` builds one without GPG:

```console
cd integrations/java
./bundle-unsigned.sh
```

The zip is `dist/coworkingview-0.1.0-bundle.zip`. Inside, paths are the Maven repository layout, with no extra top-level directory:

```text
io/github/coworkingview/coworkingview/0.1.0/coworkingview-0.1.0.pom
io/github/coworkingview/coworkingview/0.1.0/coworkingview-0.1.0.pom.md5
io/github/coworkingview/coworkingview/0.1.0/coworkingview-0.1.0.pom.sha1
io/github/coworkingview/coworkingview/0.1.0/coworkingview-0.1.0.jar
io/github/coworkingview/coworkingview/0.1.0/coworkingview-0.1.0.jar.md5
io/github/coworkingview/coworkingview/0.1.0/coworkingview-0.1.0.jar.sha1
io/github/coworkingview/coworkingview/0.1.0/coworkingview-0.1.0-sources.jar
io/github/coworkingview/coworkingview/0.1.0/coworkingview-0.1.0-sources.jar.md5
io/github/coworkingview/coworkingview/0.1.0/coworkingview-0.1.0-sources.jar.sha1
io/github/coworkingview/coworkingview/0.1.0/coworkingview-0.1.0-javadoc.jar
io/github/coworkingview/coworkingview/0.1.0/coworkingview-0.1.0-javadoc.jar.md5
io/github/coworkingview/coworkingview/0.1.0/coworkingview-0.1.0-javadoc.jar.sha1
```

To assemble that zip yourself:

```console
cd integrations/java
mvn -B package
stage=$(mktemp -d)
base="$stage/io/github/coworkingview/coworkingview/0.1.0"
mkdir -p "$base"
cp pom.xml "$base/coworkingview-0.1.0.pom"
cp target/coworkingview-0.1.0.jar "$base/"
cp target/coworkingview-0.1.0-sources.jar "$base/"
cp target/coworkingview-0.1.0-javadoc.jar "$base/"
for f in "$base"/*; do
  md5sum "$f" | awk '{print $1}' > "$f.md5"
  sha1sum "$f" | awk '{print $1}' > "$f.sha1"
done
mkdir -p dist
( cd "$stage" && zip -r -X "$OLDPWD/dist/coworkingview-0.1.0-bundle.zip" io )
```

Checksum files are the hex digest and a newline, not the `md5sum` filename suffix. After signing, each of the four artifacts also needs a sibling `.asc` (detached signature) before Central will accept the zip:

```console
gpg --detach-sign --armor -u KEYID \
  io/github/coworkingview/coworkingview/0.1.0/coworkingview-0.1.0.jar
# same for the pom, the sources jar and the javadoc jar; name them *.asc
```

Then zip `io/` again from the staging directory and upload the zip in the portal.

## Requirements this POM already meets

Central checks the POM, not just the jars. `pom.xml` includes:

- `name`, `description`, and `<url>https://coworkingview.com</url>`
- MIT licence (`https://opensource.org/licenses/MIT`, distribution `repo`)
- one developer: CoworkingView, `info@coworkingview.com`, `organizationUrl` `https://coworkingview.com`
- `scm` `connection`, `developerConnection`, and `url` `https://github.com/coworkingview/flex-office-data`
- `maven-source-plugin` and `maven-javadoc-plugin` attached on `package`
- `maven-gpg-plugin` in the `release` profile
- `central-publishing-maven-plugin` with `autoPublish` `false`

There are no runtime dependencies, so the published POM has no dependency block to keep in sync.
