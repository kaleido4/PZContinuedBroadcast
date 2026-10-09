# PZContinuedBroadcast
Continued PZ Life and Living Broadcast

A Project Zomboid (Build 42) mod that keeps **Life and Living TV** (channel 203) on the air forever.
In vanilla the channel airs its how-to shows (XP and recipes) for the first 9 days and then goes silent.
With this mod, the whole schedule reruns from episode 1 every 10 days.

## Sandbox options

Found on the **Continued TV Broadcast** page of the sandbox settings.

| Option | Values | Default |
|---|---|---|
| **Life and Living Rerun Schedule** | *Back to back*: the schedule restarts the day after it ends.<br>*Monthly (from the 1st)*: the schedule airs from the 1st of every in-game month and ends at noon on the 10th. The channel is then off air until the next 1st. | Back to back |
| **Days Off Air Between Reruns** | 0–365. *Back to back* only: full days off air between runs. | 0 |
| **Reruns Give XP Again** | Checkbox. *On*: every airing gives skill XP (still limited by the vanilla *Media XP Level Cutoff*).<br>*Off*: each character gets skill XP from each line of a show only the first time they watch it. Reruns still reduce boredom and teach missed recipes. | On |

Watch history for *Reruns Give XP Again* is saved per character, using the same "known media lines" list vanilla uses for VHS tapes. It's recorded even while the option is on, so turning it off later works as expected. Lines watched before this version of the mod weren't recorded, so they give XP one more time. Tracking is per line: if you only caught half a show, a rerun still gives XP for the half you missed.

Either way, the original broadcast at the start of the game is left as in vanilla. Reruns follow after it.

## How it works

Everything is in [`PZCB_LifeAndLivingLoop.lua`](Contents/mods/PZContinuedBroadcast/common/media/lua/server/radio/PZCB_LifeAndLivingLoop.lua).
It doesn't replace `RadioData.xml`. Instead it uses the game's `OnLoadRadioScripts` event to change the vanilla script at runtime:

1. The Life and Living `main` script normally ends with ~2.5 days of `<bzzt>` static (day 9 afternoon to day 11). The mod trims every broadcast after the last one that carries interaction codes (XP, recipes, etc.).
2. **Back to back:** it adds an exit option from `main` back to `main`, with *Days Off Air* as the start delay. When the last programme ends (day 9, noon), the script restarts at midnight of the next day plus the delay. With 0 that gives a 10-day cycle: 4 shows a day on days 0 to 8 and 2 on day 9, the same as vanilla.
   **Monthly:** no exit option. When the script ends the channel has no script, and the hourly check schedules `main` with a start day on the next 1st of the month. A script whose start day is in the future simply waits.
3. On game or server start, and every in-game hour, if the channel has no active script it schedules the next run. *Back to back* starts from episode 1 today, which covers saves that went silent before the mod was added. *Monthly* resumes this month's run on the right dates if the run would still be going, and otherwise starts on the next 1st.

TV lines are sent without a media-line GUID, so the vanilla "already seen this line" check (which applies to VHS/CDs) never blocks them. Reruns grant XP again, still capped by the vanilla **Media XP Level Cutoff** sandbox option, and `RCP=` lines teach any recipe the character doesn't know yet.

For *Reruns Give XP Again = Off*, the mod swaps vanilla's `OnDeviceText` handler for a wrapper, because vanilla ignores the event's 7th argument (the TV). When the TV is tuned to Life and Living, the wrapper reads the channel's airing broadcast and line counter to build an ID (`PZCB:<broadcast id>:<line number>`). It also wraps `ISRadioInteractions` `checkPlayer`: lines with skill codes are added to the character's known media lines, and on later airings the skill codes are removed before vanilla applies them. Stat codes (boredom, stress, ...) and `RCP=` recipes always go through. XP is only granted on the server or in singleplayer (`addXp` does nothing on multiplayer clients), which is where this code runs.

Radio scripts only run in singleplayer and on the server, so the file lives in `media/lua/server` and returns early on multiplayer clients.

## Layout

```
PZContinuedBroadcast/              <- Workshop item folder (this repo)
├── preview.png                    <- Workshop thumbnail (256x256)
├── workshop.txt                   <- Workshop title/description/tags
└── Contents/mods/PZContinuedBroadcast/
    ├── common/media/
    │   ├── sandbox-options.txt
    │   ├── lua/server/radio/PZCB_LifeAndLivingLoop.lua
    │   └── lua/shared/Translate/EN/Sandbox.json
    └── 42/
        ├── mod.info
        ├── poster.png
        └── icon.png
```

## Testing locally

The game loads local mods from `%UserProfile%\Zomboid\Workshop`. Link this repo there (run in `cmd`):

```
mklink /J "%UserProfile%\Zomboid\Workshop\PZContinuedBroadcast" "E:\Git Projects\PZContinuedBroadcast"
```

Then enable **Continued TV Broadcast: Life and Living** in the Mods menu. `console.txt` shows lines prefixed with `[PZContinuedBroadcast]` when the patch is applied:

```
[PZContinuedBroadcast] trimmed 12 static broadcasts, programmes end at minute 13680 (day 9)
[PZContinuedBroadcast] 'main' now loops forever
```

To test quickly, start a game in debug mode (`-debug` launch option) and skip time forward past day 10, or load an old save that's past day 12. You should see `channel was off the air, restarted reruns...` and Life and Living back on channel 203.

## Uploading to the Workshop

1. Main menu → **Workshop** → **Create and update items** → pick `PZContinuedBroadcast`.
2. The uploader reads `workshop.txt` and `preview.png` and writes the Workshop `id=` into `workshop.txt` after the first upload. Commit that change so later uploads update the same item.
