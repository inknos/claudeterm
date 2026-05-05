# TODO

## Nice to have

- [x] Commands that open the terminal panel vs. commands that don't:
      some commands (e.g. `refsend`) should optionally open the terminal
      panel when executed; others should stay silent. Make this
      configurable per-command (e.g. `g:circuit_show_on_refsend`).

- [x] Configurable terminal size: allow the user to set the terminal
      split height/width independently of `g:circuit_split_ratio`
      (e.g. fixed column count or row count).

- [ ] Provider-aware floating prompt options: the command prompt should
      show different options depending on the active provider. For
      example, Claude Code and OpenCode support different slash commands
      and modes — the prompt should only list what the current provider
      actually supports.

- [ ] Smarter sorting in the floating prompt: sort options by relevance
      or frequency of use rather than alphabetically. Consider showing
      recently used commands first and grouping related commands.

- [ ] Manual test: verify `term_start()` with `env` option works
      correctly with a real opencode session. Confirm
      `OPENCODE_EXPERIMENTAL_PLAN_MODE=1` is visible in the terminal
      environment and that plan mode works as expected.
