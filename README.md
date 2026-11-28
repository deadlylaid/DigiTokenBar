<div align="center">

# DigiTokenBar

**Raise a Digimon with your AI coding tokens, right in your macOS menu bar.**

**English** · [한국어](README.ko.md) · [日本語](README.ja.md)

</div>

> **Status:** a personal fork of [PokeTokenBar](https://github.com/chattymin/PokeTokenBar), in development.
> Download the [latest release](https://github.com/deadlylaid/DigiTokenBar/releases/latest), or build it
> from source.

DigiTokenBar reads the AI coding tokens you already use (Claude Code, Codex, Gemini CLI and the
other tools below) from local logs and turns them into experience for a Digimon companion.
Underneath, it is PokeTokenBar's usage tracker: today's tokens, cost, and official 5-hour / weekly
limits.

## Install

macOS 14 or later, Apple Silicon or Intel.

**With Homebrew** (recommended):

```sh
brew install --cask deadlylaid/tap/digitokenbar; open -a DigiTokenBar
```

This installs the app and opens it (even if brew complains about something else). The first time, a window with the egg picker opens; after that the app
lives in the menu bar (top right), with no Dock icon. If the menu bar is full, macOS hides the icon behind
the notch: open the app again (Spotlight, Applications, `open -a DigiTokenBar`) and the window comes back.
Homebrew clears the download quarantine, so the app opens without the warning in step 3 below. Then
continue with step 4.

**Or download it:**

1. Download **DigiTokenBar.zip** from the
   [latest release](https://github.com/deadlylaid/DigiTokenBar/releases/latest) and unzip it.
2. Move **DigiTokenBar.app** to Applications and open it.
3. The first time, macOS says it cannot verify the developer and does not open the app. DigiTokenBar is
   a free fan project and is not notarized by Apple. Open **System Settings → Privacy & Security**,
   scroll down and click **Open Anyway** next to DigiTokenBar. Or run this in Terminal:

   ```sh
   xattr -dr com.apple.quarantine /Applications/DigiTokenBar.app
   ```

4. For Claude Code's official limits, the app reads Claude Code's login from the Keychain, so macOS
   asks once. Choose **Always Allow**: every release is signed the same way, so it keeps working after
   updates.

**Upgrade:** when a new version is out, the app tells you. Click Update: a Homebrew install upgrades
itself (`brew upgrade --cask deadlylaid/tap/digitokenbar` does the same); otherwise the release page opens,
and you replace the app with the one in the new `DigiTokenBar.zip`. Your Digimon, saves and settings stay.

## How it works

1. **Pick an egg.** Three eggs are drawn at random from the lines you have not raised yet. A line you
   have raised to graduation can always be picked again. Without a pick, one is chosen after a day.
2. **Code as usual.** 200,000 tokens make 1 experience point, and every token counts: there is no daily
   cap. A whole life, from egg to graduation, needs 10,200 points at 1×, about ten days at 200 million
   tokens a day. Pick the pace in Settings (0.5×, 1×, 1.5×, 2× or 5×): faster if you code little,
   slower if you code a lot.
3. **Evolve.** Each line is a Vital Bracelet card: 40 lines and 636 Digimon (22 of them Armor), Baby I
   to Ultimate.
   Growth follows the card's own routes. The card's requirements open them: Vital Values count your
   coding hours a day, trophies your good days (coding, staying within limits, using two tools), and
   battles and win ratio your battles.
   Among the open routes, a weighted draw picks one, and how you code tilts it: steady daytime use
   leans Vaccine, many tools over many days Data, more late nights or full limits Virus. A route that
   keeps the current attribute weighs a little more. Each stage draws once; reopening the app does not
   reroll it. With nothing met, it takes the easy route. A few forms are hidden (catch 20 bugs, or fill
   3 usage limits); earning one always wins the draw.
4. **Armor evolution.** Some Child Digimon can take a Digimental instead of growing as usual and become
   an Armor Digimon. Collect fragments (a rare golden bug, a visitor's gift, a full stamp card, or
   surprise points); three of a kind make a Digimental. The golden Digimentals of Miracles and Fate
   come whole, rarely, and skip stages (V-mon → Magnamon).
5. **Jogress with a friend.** When a stage that has a Jogress on its card is full, your Digimon waits
   up to 24 hours for a friend's code (the same code as for battles). If the friend's Digimon fits a
   partner the card names ("a Virus Perfect", or "Angemon"), they merge, and the scene shows the
   friend's Digimon walking in. Without a code, or with "Evolve without it", it grows as usual; EXP
   earned while waiting carries over. Named Ultimate merges (War Greymon + Metal Garurumon = Omegamon,
   and ten more) also need the partner raised before.
6. **Graduate.** A full Ultimate graduates into your dex, and a new egg arrives.

## Features

- **Scene:** the Digimon walks, sleeps and attacks bugs with its signature move. Big bugs take
  three hits. It looks sick while a usage limit is full and sleepy late at night. Now and then it
  washes up, cooks and eats, climbs a little wall, naps with a nose bubble, kicks a ball around, or
  types on a tiny laptop while your coding agent works.
- **Dex:** every line by stage. Digimon you have raised are shown; the rest are silhouettes, with
  hints for hidden forms, Digimentals and the Jogress partners of merge-only forms. Search by name,
  filter and sort across all lines.
- **Desktop pet and menu bar:** the Digimon on your desktop (Settings → Desktop pet) and in the
  menu bar, with its growth %. Rub it with the pointer for hearts, double-click to make it jump, and
  pick a small, medium or large size. Settings → Digimon → Stay in place keeps it in the middle instead
  of walking around.
- **Agent activity:** the desktop pet reacts to Claude Code: dots while it works, a bubble when it
  needs you, a cheer when it is done. Set it up once with `sh tools/digimon/install-agent-hooks.sh`
  (it backs up `~/.claude/settings.json` and keeps your existing hooks). Any other agent can open
  `digitokenbar://agent?state=<working|waiting|done|idle>&label=<name>`.
- **Battles:** battle other DigiTokenBar users with battle codes. Copy your code, send it in any
  chat, and paste theirs: both apps play the same battle, no server needed. Five practice battles a
  day against wild Digimon count too. Battles give no EXP; they fill the card's battle and
  win-ratio requirements. Friends use the same code for a Jogress. The code holds only a random player
  number and your Digimon.
- **Today:** every day has a fortune (clear, bug swarm, fighting spirit, busy day, meteor shower), and
  visiting Digimon drop by. Most come from your dex; one in a hundred is a Digimon you have never seen,
  which then stays in the dex as "met". Visitors add surprise points. Each day you code adds a stamp;
  seven bring a very rare Digimon you have never seen, at once. Luck does not grow with usage and cannot
  be rerolled.
- **Saves:** automatic backups (at launch and every 12 hours, newest 10 kept), and export / import to
  move your Digimon to another Mac.
- **Growth speed:** 0.5×, 1×, 1.5×, 2× or 5× in Settings; a stage already full at the new speed evolves at once.
- **Usage charts:** this month by day, the last 16 weeks, or today by hour with your usual day faintly
  behind it. Pick the one the popover opens on in Settings; click the chart to look at the others.
- **Fast growth (testing):** a tenth of the experience per stage on top of the speed, to try the app out.

The Digimon screens are in Korean and English.

## Works with

Claude Code, Codex, Gemini CLI, Antigravity, OpenCode, Hermes Agent, Cursor, Grok Build CLI,
Copilot CLI, Kiro CLI, Pi Agent, omp, omo, Aside, Kimi Code and Devin CLI. Official limits for
Claude Code, Codex, Antigravity, OpenCode Go and Grok. This part is unchanged from
PokeTokenBar; see its [data sources](https://github.com/chattymin/PokeTokenBar#data-sources) for
where each tool's usage is read from.

## Build from source

macOS 14 or later, Xcode with Swift 6.

```sh
bash scripts/create-signing-cert.sh            # once: a local signing identity, so Keychain "Always Allow" survives rebuilds
PTB_NATIVE_ARCH_ONLY=1 bash scripts/build-app.sh  # builds and installs /Applications/DigiTokenBar.app
swift test --parallel                          # tests
```

## Where the Digimon data comes from

- **Species and evolutions:** [Wikimon](https://wikimon.net), text licensed CC BY-SA 3.0. Built by
  `tools/digimon/build_data.py` and `gen_catalog.py`.
- **Routes per card** (which evolutions a card has, which are a Jogress): fan documentation of the
  devices, mainly humulos.com. Notes in `tools/digimon/research`.
- **Moves and Korean names:** the official Korean Digimon reference (digimon.net/reference_ko).
- **Sprites are not in this repository or the app.** The app downloads them from wikimon.net while
  it runs and caches them in `~/Library/Application Support/DigiTokenBar/digimon-sprites`.

## Privacy

- Token usage is read on your Mac and never uploaded.
- Outbound requests: wikimon.net for sprites, PokeTokenBar's official-limit and status requests,
  and GitHub's latest-release page of this repository for the update check. Nothing is downloaded
  from PokéAPI.
- Claude Code hooks are installed only when you run the installer yourself.
- The Digimon save and its backups live in `~/Library/Application Support/DigiTokenBar/`.

## Credits and license

- Forked from [PokeTokenBar](https://github.com/chattymin/PokeTokenBar) by chattymin. The usage
  tracking, providers, limits and most of the app are theirs. PokeTokenBar's Pokémon features were
  removed.
- **MIT**, see [LICENSE](LICENSE); the original copyright notice is kept. The license covers this
  project's source code only. It grants no rights to third-party trademarks, artwork or data.
- DigiTokenBar is an **unofficial, non-commercial fan project**. It is not affiliated with, endorsed
  or sponsored by Bandai, Toei Animation or Bandai Namco. "Digimon" and all related names,
  characters and images belong to their owners. The app bundles no Digimon artwork.
- `tools/digimon/research` keeps short quotes of third-party sites, with their sources, for checking
  the data.
