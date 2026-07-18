# AGENTS.md

## Design principles

Apply these rules when adding or changing code in this repository.

1. **Types are contracts.** Required fields and parameters are trusted internally. Do not repeatedly validate what their types already guarantee.
2. **Validate at boundaries.** Validate only where uncertainty enters, such as public APIs, Neovim events, external data, configuration, Treesitter results, and asynchronous callbacks.
3. **Optional means legitimately absent.** Use `?` only when absence is a valid domain or lifecycle state, not as general protection against programming errors.
4. **Model lifecycle states explicitly.** Represent active and inactive states separately instead of making every active-state field nullable.
5. **Establish invariants once.** Boundary code should validate or construct a valid value; downstream helpers should operate under that established contract.
6. **Fail visibly on invariant violations.** Avoid `pcall`, silent fallbacks, ignored failures, and defensive defaults around internal operations. Bugs should surface as errors.
7. **Distinguish expected outcomes from errors.** Missing external data, exhausted navigation, or changed asynchronous context may be normal outcomes. Missing required internal state is a bug.
8. **Guard real asynchronous races.** Revalidate session identity and external Neovim objects after timers or scheduled callbacks because they can legitimately change over time.
9. **Keep ownership explicit.** Session-bound resources such as timers and extmarks should be created, owned, and destroyed by the active session.
10. **Do not hide malformed values with defaults.** Avoid `value or fallback` when the contract says `value` is required.
11. **Adapt only where change is expected.** Clamp or translate persisted/external values at the relevant boundary, not throughout internal code.
12. **Prefer meaningful helpers over defensive wrappers.** Helpers should express an operation, algorithm, boundary, ownership rule, or invariant—not merely add nil checks.
13. **One use is a signal, not a rule.** Inline trivial one-use helpers, but retain helpers that name meaningful behavior or establish a contract.
14. **Separate persistent and volatile data.** Keep durable domain state separate from buffer handles, windows, timers, extmarks, and other session resources.
15. **Tests obey production contracts.** Tests should construct valid state rather than rely on defensive behavior that normal execution does not require.

## Working practices

- Keep changes focused and avoid unrelated cleanup.
- Format Lua with `stylua`.
- Run the relevant tests with `just test-file <path>` and run `just test` after broader changes.
