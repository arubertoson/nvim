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

## Testing philosophy

- Test observable outcomes and domain concepts, not implementation structure or coverage targets.
- Prefer end-to-end and integration tests through real boundaries: Neovim APIs, buffers, filesystems, Treesitter, diagnostics, and subprocesses.
- Do not mock internal modules to confirm how they collaborate. When an external service is unavailable, nondeterministic, slow, or costly, use a deterministic substitute at the outermost boundary, such as a fixture executable that implements the real process protocol.
- Use test doubles only when they are necessary to control a genuine boundary condition, such as asynchronous completion or an external failure that cannot be produced reliably. Assert the resulting behavior rather than calls made to the double.
- Keep one test for each distinct behavioral guarantee. Merge or remove tests that exercise the same outcome through different internal paths.
- Avoid exhaustive validation matrices, branch-by-branch tests, tests of trivial helpers, and assertions against exact internal UI representation unless that representation is itself a supported contract.
- A regression test is warranted when a failure affects a meaningful user workflow, external protocol, data integrity, or lifecycle invariant. Coverage percentage alone is not a reason to add a test.

## Working practices

- Keep changes focused and avoid unrelated cleanup.
- Format Lua with `stylua`.
- Run the relevant tests with `just test-file <path>` and run `just test` after broader changes.
