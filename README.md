# Herdr Bots

Every [herdr](https://herdr.dev) agent as a little cube on your screen, for [Omarchy](https://omarchy.org). Busy ones build or type, waiting ones flash red until you answer, finished ones show off until you look, and the idle ones sleep together in a pile in the corner.

![Three cubes along the bottom of the screen: one finishes with confetti, one starts waiting and a click sends it back to work, one is picked up and put somewhere else, the finished one is clicked and goes to sleep in the corner, and after H they all drop off the screen and hop back a minute later](assets/demo.gif)

## What they do

Each pet follows one agent, with the agent's name on a plate under it. They behave like Tamagotchis, and each one keeps its own rhythm.

- **Working**: the cube builds a stack of blocks next to it, or fills its sides with text. Now and then it takes a breather and looks up at you.
- **Waiting on you** (herdr's `blocked`: an approval or a question on screen): it rocks and flashes red under an exclamation mark, and it gets more insistent the longer you leave it. Its plate gets a red edge.
- **Finished**: it cheers and hops under sparkles, with a gold edge on its plate. It keeps asking for attention for at least ten minutes, even after herdr counts it as seen, because a glance at the tab is not the same as looking after it. Leave it long enough and it gets bored, and shows it.
- **Idle**: it goes to sleep in the pile in the corner, which shows how many are asleep.

The changes are the moments worth seeing, so every change of state has an animation of its own: confetti when work finishes, a startled jump when an agent starts waiting on you, a stretch when one wakes up, and a heart and a yawn when you have looked after it and it goes back to sleep.

## Using them

- **Hover** a pet for its name, its workspace and how long it has been in this state.
- **Click** a pet to land on its pane. The herdr window showing that session comes to the front, or a new one opens in `foot` when there is none. Clicking is also what tells a finished pet you have seen it.
- **Drag** a pet to pick it up. It hangs from a climbing hold under the pointer until you put it down, and then it stays where you left it, asleep or awake.
- **Click the pile** for a list of everyone asleep, the most recent first. Click a name to go to that agent, or drag one out of the pile or out of the list to put it somewhere on its own. Put it back on the line in the corner and it rejoins the pile.
- **Press H** while pointing at any of them, or with the list open, and they drop off the bottom of the screen one after another, out of the way of whatever they were standing in front of. A minute later they hop back. Escape closes the list.

The pets only take the keyboard while you point at one or have the list open, so they never take keys from the window you are typing in.

## Saved SSH machines

Agents on the saved SSH machines in `herdr machine list` are part of the herd too, with a green **SSH** tag in front of their name. Clicking one focuses its pane on that machine and brings up the window attached to it, the way herdr opens one: `herdr --remote <target>`, in a new `foot` window when there is none yet. A machine that does not answer within a few seconds is left out, and asked again a minute later.

## Settings

The pets have no bar widget. They are set in their own entry in the top-level `plugins` list in `~/.config/omarchy/shell.json`:

```jsonc
{
  "id": "jankeesvw.herdr-bots",
  "monitor": "DP-3",      // output name; default is the one focused when the shell starts
  "side": "right",        // "right" or "left" corner
  "marginX": 24,
  "marginY": 8,
  "scale": 1.0,           // 1.0 makes the body 26 logical pixels square
  "look": "cube",         // "cube", or "robot" for little robots with faces
  "sleepers": true        // the pile of idle agents in the corner
}
```

They also answer over IPC, which is handy for a keybinding:

```bash
omarchy-shell jankeesvw.herdr-bots attend   # go to whoever has waited longest, then whoever finished longest ago
omarchy-shell jankeesvw.herdr-bots toggle   # hide or show them (also: show, hide)
omarchy-shell jankeesvw.herdr-bots unfold   # open or close the list of sleepers
```

## Installing it

```bash
omarchy plugin add https://github.com/jankeesvw/omarchy-herdr-bots
omarchy plugin enable jankeesvw.herdr-bots
```

Needs `herdr`, `jq` and `hyprctl` on `$PATH`. `hyprctl` is what pairs a session with the window showing it, and a new window is opened in `foot`, falling back to `xdg-terminal-exec`. Agents on saved SSH machines need herdr 0.9.1 or newer, both here and on each machine.

## Demo mode

The data script has a demo mode with invented agents, so a screenshot never carries real project names:

```bash
~/.config/omarchy/plugins/jankeesvw.herdr-bots/bin/herdr-bots demo on
# ... take the screenshot ...
~/.config/omarchy/plugins/jankeesvw.herdr-bots/bin/herdr-bots demo off
```

Clicking a pet does nothing while it is on.

## Removing it

```bash
omarchy plugin disable jankeesvw.herdr-bots
omarchy plugin remove jankeesvw.herdr-bots
rm -rf ~/.cache/omarchy-herdr-bots
```

That cache directory holds nothing about your work: the demo flag, and an empty marker for each saved machine that did not answer, so it is left alone for a minute. Every name on screen is read from herdr when it is drawn.

## License

MIT
