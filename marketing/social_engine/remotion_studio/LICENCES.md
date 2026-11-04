# Licence notes for the Remotion studio

## Remotion 4.0.540

Read from the installed package's `LICENSE.md` on 2026-11-04, and matching spec Section 8.1.

- **Free License.** Eligible: "an individual", "a for-profit organization with up to 3 employees", non-profits, and anyone evaluating it. "Individuals and small companies are allowed to use Remotion to create videos for free (even commercial)".
- **Why it applies.** The owner operates this personally, as an individual (D27). This rests on the owner's statement and is not a legal conclusion. If a company turns out to operate the app or the channels, this and spec item L3 are checked again.
- **Remotion 5.0.** The licence says it will "slightly change" in 5.0, so it is re-read before any move to 5.0. All `@remotion/*` packages stay pinned to exactly 4.0.540.

## Telemetry and network use

- Read from the installed code on 2026-11-04. There is no telemetry switch to set. The only usage reporting is `internalRegisterUsageEvent` in `@remotion/renderer` and `@remotion/cli`, which posts to `remotion.pro` only when a licence key is passed.
- With no key, `licenseKey` stays `null`, and the code skips that call. The value `free-license` would send the event, so it must not be passed either.
- This studio passes no key anywhere, and `tests/test_brand_tokens.py` fails if one appears.
- `npx remotion` commands used here make no other call to any service, apart from the once-only download of Remotion's headless browser into `node_modules` of `remotion_work`.

## Not installed machine-wide

`npm` runs only in `remotion_work`, under `data_root`. FFmpeg is the copy Remotion ships inside `node_modules`, reached through `npx remotion ffmpeg` (plan Section 2.4). Renders go to `out/` in `remotion_work`.

## Other packages

Fonts are recorded in `assets/branding/fonts/LICENCES.md`. `pngjs` (MIT) reads frames in the render check, and is a development dependency only.
