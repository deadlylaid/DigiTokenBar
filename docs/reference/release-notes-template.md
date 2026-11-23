<!-- Shape follows upstream PokeTokenBar v2.5.3: https://github.com/chattymin/PokeTokenBar/releases/tag/v2.5.3
Write in English. Replace every instruction with actual release content.
Keep all sections; use 'None.' if a change category is empty.
Keep the Install / Upgrade lines below as they are: DigiTokenBar ships a zip, has no Homebrew cask,
and is not notarized, so the first open needs "Open Anyway" (scripts/release-metadata.py checks this). -->
## New

<!-- **Feature title** (#PR, @author) — explain the user-visible behavior. -->

## Fixed

<!-- - Describe the resolved symptom (#PR, @author). -->

## Other

<!-- - Documentation, maintenance, or other changes. -->

## Contributors

<!-- Deduplicated GitHub handles, verified against every included PR and actual
human coauthor: @alice · @bob. Do not copy the previous release's list.
When there are none, write exactly: No external contributors in this release. -->

<!-- Add 'Thank you all.' below a nonempty contributor list. -->

---

**Install:** download `DigiTokenBar.zip` below, unzip it and move `DigiTokenBar.app` to Applications (macOS 14 or later, Apple Silicon or Intel). The app is not notarized, so macOS blocks the first open: go to System Settings › Privacy & Security and click **Open Anyway**, or run `xattr -dr com.apple.quarantine /Applications/DigiTokenBar.app` in Terminal.

**Upgrade:** the app tells you when a new version is out and opens this page. Quit DigiTokenBar, replace the app with the one in the new `DigiTokenBar.zip`, and open it again. Your Digimon and settings stay.
