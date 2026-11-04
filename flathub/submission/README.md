# Flathub submission

These files are prepared for a pull request against the `new-pr` branch of [flathub/flathub](https://github.com/flathub/flathub). Nothing here has been submitted.

## Files to copy

Copy `com.coworkingview.Rates.yml` to the root of a branch created from `new-pr`. Do not add application source, the screenshot, or this README. Flathub builds the app from tag `flatpak-v0.1.0` (`ed36919deefd893aed73c23d6723b7b6e6601e3d`) of https://github.com/coworkingview/flex-office-data.

Open the pull request against `new-pr`, not `master`. Title: `Add com.coworkingview.Rates`.

## Permissions to explain in the pull request

`--share=network` reads the public Price Index at `https://api.coworkingview.com`. The API needs no key. The app sends no account and no analytics. `--socket=wayland`, `--socket=fallback-x11` and `--share=ipc` are the display sockets. `--device=dri` lets GTK use the GPU.

## Before opening the pull request

Flathub does not accept an AI-written manifest. Review `com.coworkingview.Rates.yml` and replace it with a manifest you wrote before submitting. Say in the pull request that the application code was written with AI assistance. Do not ask an agent to open the pull request or to comment on it. When a reviewer asks for a test build, comment `bot, build`.
