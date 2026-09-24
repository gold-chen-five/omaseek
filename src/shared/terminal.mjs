// How a terminal the panel opens ends (bin/searxng-up, bin/keybind): wait for a
// key, so what happened stays readable — and, for the welcome page, bring the
// panel back afterwards. It stepped aside for the terminal, which needs the
// keyboard for a password or a yes, and someone who has just installed omaseek
// may not know yet how to open it again.

/** The shell text after the script: `comeBack` is a command to run once a key is pressed, or ''. */
export function terminalEnding (comeBack) {
  const back = String(comeBack ?? '').trim()
  return back
    ? "echo; read -n1 -r -p 'press any key to go back to omaseek'; " + back
    : "echo; read -n1 -r -p 'press any key to close'"
}

/** The command that opens a plugin's panel through the shell, as its bar icon does. */
export function summonCommand (pluginId) {
  const id = String(pluginId ?? '').replace(/[^A-Za-z0-9._-]/g, '')
  return id ? 'omarchy-shell shell summon ' + id + " '{}'" : ''
}
