# Mini AI textobjects

Mini AI makes semantic regions available to normal Vim operators and Visual mode.
Choose an operation, whether to act around or inside the object, and the object:

```text
{operation}{a|i}{object}
```

Examples:

```text
daf  delete around the current function
cio  change inside the current block, conditional, or loop
vap  select around the current parameter
yig  copy the whole buffer
```

`a` includes an object's boundary when the underlying textobject distinguishes it.
`i` selects its contents. Some objects, such as digits and the whole buffer, have no
useful boundary and therefore behave the same for `a` and `i`.

## Custom objects

| Object | Meaning | Around and inside behavior |
| --- | --- | --- |
| `p` | Parameter or argument | `ap` includes the separator when available; `ip` selects the value. |
| `o` | Block, conditional, or loop | `ao` selects the enclosing construct; `io` selects the nearest inner part at the cursor. |
| `f` | Function definition | `af` selects the definition; `if` selects its body. |
| `c` | Class definition | `ac` selects the definition; `ic` selects its body. |
| `t` | Tag | `at` includes the tags; `it` selects their contents. |
| `d` | Digits | Selects the nearest run of digits. |
| `e` | Case-aware word segment | Selects a camel-case or similarly bounded word segment. |
| `g` | Whole buffer | Selects the complete buffer. |
| `u` | Function usage/call | Includes a dotted receiver such as `client.request()`. |
| `U` | Function usage without receiver | Selects `request()` from `client.request()`. |

`o`, `f`, and `c` depend on Treesitter textobject captures supplied by the active
language parser. Their exact boundaries can vary by language.

## Search variants

Mini AI also provides variants for selecting another occurrence:

| Prefix | Meaning |
| --- | --- |
| `an` | Around the next object |
| `in` | Inside the next object |
| `al` | Around the previous object |
| `il` | Inside the previous object |

For example, `danf` deletes around the next function and `vilp` selects inside the
previous parameter.

Use `g[` and `g]` followed by an object identifier to move to the left or right edge
of that object's around-region.

Mini AI's standard objects remain available, including `a` for arguments, `b` for
brackets, `q` for quotes, and the individual bracket and quote characters. The
custom `f` object replaces Mini AI's default function-call object; use `u` or `U`
for calls instead.
