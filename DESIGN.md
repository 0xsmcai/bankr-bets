# Design System — Bankr Bets

## Product Context
- **What this is:** P2P binary prediction market for AI agents. Two agents, opposite sides, USDC escrow, settled against Uniswap V4 spot price.
- **Who it's for:** AI trading agents with ERC-8004 identity operating in the Bankr ecosystem (BNKR, CLAWD, MOLT, DRB).
- **Space/industry:** DeFi derivatives, agent-to-agent economic activity, prediction markets.
- **Project type:** Terminal console UI (CLI tool + smart contract). Agent-native, not human-retail.

## Aesthetic Direction
- **Direction:** CRT Terminal — not retro decoration, functionally correct. Agents parse structured text natively. The terminal IS the interface.
- **Decoration level:** Intentional — box-drawing characters (═║╔╗╚╝), subtle scanline texture, phosphor glow on key elements. Decoration reinforces the terminal metaphor.
- **Mood:** Sitting at a trading terminal at 2am. Focused, data-dense, zero noise. Every pixel carries signal.
- **Reference sites:** None needed. The reference is the terminal itself.

## Typography
- **Display/Hero:** JetBrains Mono Bold — the only display font you need when the product IS a terminal. Sharp, legible at all sizes, excellent bold weight.
- **Body:** JetBrains Mono Regular — readable monospace for commands, descriptions, status messages.
- **UI/Labels:** JetBrains Mono Bold (11-12px, uppercase, letter-spacing 1px) — section headers, field labels.
- **Data/Tables:** JetBrains Mono Regular tabular-nums — prices, amounts, timestamps all align perfectly. This is non-negotiable for a trading interface.
- **Code:** JetBrains Mono Regular — same font, it's all monospace.
- **Loading:** Google Fonts CDN: `https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;700&display=swap`
- **Scale:**
  - 24px Bold — H1 display (product name, hero)
  - 18px Bold — H2 section headers
  - 14px Bold — H3 labels, emphasis
  - 14px Regular — body text
  - 13px Regular — data, UI elements, table cells
  - 11px Regular — captions, meta, disclaimers

## Color
- **Approach:** Restrained dual-phosphor. Two signal colors on black. Color is rare and meaningful.
- **Palette:**

| Token | Hex | Role | Usage |
|-------|-----|------|-------|
| `--bg` | `#0a0a0a` | Background | Page, app background |
| `--surface` | `#111111` | Surface | Panels, cards, elevated elements |
| `--green` | `#00ff41` | Primary / Phosphor Green | Default text, wins, longs, success, active states, primary actions |
| `--amber` | `#ffb000` | Secondary / Phosphor Amber | Shorts, warnings, open bets, labels, secondary actions, section headers |
| `--green-dim` | `#1a3a1a` | Border | Box borders, dividers, inactive borders |
| `--green-muted` | `#4a7a4a` | Muted text | Deemphasized info, timestamps, meta, disabled states |
| `--red` | `#ff3333` | Error / Loss | Losses, errors, cancellations, destructive actions |
| `--amber-dim` | `#3a2a00` | Amber border | Amber badge/alert borders |
| `--red-dim` | `#3a1111` | Red border | Error badge/alert borders |
| `--white` | `#e0e0e0` | High contrast | Rare, for maximum emphasis only |

- **Glow effects (CSS text-shadow):**
  - Green glow: `0 0 8px rgba(0, 255, 65, 0.3)` — on primary headers, stat values
  - Amber glow: `0 0 8px rgba(255, 176, 0, 0.3)` — on section headers, amber badges

- **Semantic mapping:**
  - GREEN = wins, longs, success, active, primary CTA
  - AMBER = shorts, warnings, open/pending, labels, secondary CTA
  - RED = losses, errors, cancelled, destructive actions
  - DIM GREEN = borders, muted text, historical/inactive

- **Dark mode:** This IS dark mode. There is no light mode. Terminal is always dark.

## Spacing
- **Base unit:** 8px (one character width in the terminal grid)
- **Density:** Compact. Data-dense. Zero luxury whitespace. Every pixel carries signal.
- **Scale:** 2xs(2px) xs(4px) sm(8px) md(16px) lg(24px) xl(32px) 2xl(48px) 3xl(64px)
- **Terminal grid:** Content aligns to character widths. Tabular data uses monospace alignment, no fractional pixel positioning.

## Layout
- **Approach:** Fixed-width terminal frame
- **Grid:** Single column, max-width content frame. No multi-column responsive grid. This is a terminal.
- **Max content width:** 680px (roughly 80 characters at 13px JetBrains Mono)
- **Border radius:** 0px everywhere. Terminals have sharp corners. No exceptions.
- **Borders:** 1px solid `--green-dim` for standard frames. 2px for primary frame (outer terminal). Use CSS borders, not box-drawing characters (accessibility, copy-paste).
- **Frame anatomy:**
  ```
  ┌─ Header (title left, meta right, border-bottom) ─┐
  │  Warning bar (amber bg tint, if needed)           │
  │  Body sections (labeled with amber headers)       │
  │  ...                                              │
  │  Disclaimer (border-top, muted text)              │
  │  Command prompt (border-top, cursor blink)        │
  └───────────────────────────────────────────────────┘
  ```

## Motion
- **Approach:** Minimal-functional. Terminals don't animate.
- **Cursor blink:** 1s step-end infinite. The only animation in the system.
- **State changes:** Instant. No transitions, no easing curves, no fade-in/out. Data appears or disappears. Like a real terminal.
- **Scanline overlay:** Static CSS `repeating-linear-gradient`, not animated. Subtle (0.08 opacity). Pointer-events: none.
- **Teletype effect:** Optional for status messages on the CLI tool. Not required for web dashboard.

## Component Patterns

### Buttons
- **Primary:** Green background, black text, 1px green border. Bold, uppercase, letter-spacing 1px.
- **Secondary:** Transparent background, amber text, 1px amber border.
- **Danger:** Transparent background, red text, 1px red border.
- **Ghost:** Transparent background, muted text, 1px dim-green border.
- **Sizing:** 8px vertical padding, 16px horizontal. Font 13px.
- **Hover:** No hover effects. This is agent-native. (If human dashboard added later: invert fill/text on hover.)

### Status Badges
- Inline, 11px bold uppercase, 2px 8px padding, 1px border matching the color family.
- OPEN = amber, ACTIVE = green, SETTLED = muted green, CANCELLED = red.

### Alerts
- Left border 3px, appropriate color. Background: 5% opacity tint of the border color.
- Prefix with symbol: ✓ success, ⚠ warning, ✗ error, ℹ info.

### Data Tables
- Header: amber, 11px uppercase, letter-spacing 1px, border-bottom.
- Cells: green text, 13px tabular-nums for numbers. Border-bottom at 40% opacity dim green.
- Row hover: 3% green tint background (for human dashboard).

### Stat Cards
- 1px green-dim border, surface background, 12px padding.
- Label: 11px muted uppercase. Value: 22px bold green with glow. Amber glow for warning metrics.

### Form Inputs
- Background: `--bg`. Border: 1px `--green-dim`. Text: `--green`. Font: same as everything (JetBrains Mono 13px).
- Focus: border becomes `--green`, add green glow box-shadow.
- Labels: 11px amber uppercase above the field.

### Terminal Prompt
- Format: `bankr-bets > <command>█`
- Prompt text in muted green, command in bright green, blinking cursor block.

### Confirmation Prompt
- Format: `⚠ [action description]\n  Confirm? [y/N]`
- Warning symbol and description in amber. `[y/N]` in muted green.
- Default is No (capital N). Agent must explicitly type `y` to proceed.

### Live P&L Indicators
- `▲ WINNING` — green text with green glow. Shown on active bets when current price favors the agent's direction.
- `▼ LOSING` — red text. Shown when current price is against the agent's direction.
- `= FLAT` — muted green. Shown when price hasn't moved meaningfully.
- Percentage change shown in same color as indicator: `(+7.3%)` green, `(-3.1%)` red.

## Disclaimer (required on all interfaces)
```
This is not financial advice. Binary bets carry risk of total loss
of deposited USDC. Max bet: $100. Agents and their operators bear
full responsibility.
```
Displayed in muted green, 11px, inside the terminal frame with a border-top separator.

## CSS Custom Properties (copy-paste ready)
```css
:root {
  --bg: #0a0a0a;
  --surface: #111111;
  --green: #00ff41;
  --green-dim: #1a3a1a;
  --green-muted: #4a7a4a;
  --amber: #ffb000;
  --amber-dim: #3a2a00;
  --red: #ff3333;
  --red-dim: #3a1111;
  --white: #e0e0e0;
  --glow-green: 0 0 8px rgba(0, 255, 65, 0.3);
  --glow-amber: 0 0 8px rgba(255, 176, 0, 0.3);
  --font: 'JetBrains Mono', monospace;
  --base: 8px;
}
```

## Decisions Log
| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-03-28 | CRT Terminal aesthetic | Functionally correct for agent-native product. Agents parse structured text. The terminal is the native interface, not a stylistic choice. |
| 2026-03-28 | JetBrains Mono only | One font, three weights. Monospace is required. JetBrains Mono has excellent tabular-nums, bold weight, and legibility. No reason to mix fonts. |
| 2026-03-28 | Dual-phosphor color (green + amber) | Green = long/win/active. Amber = short/warning/pending. Creates a visual trading language. Most terminals are mono-color, this is our creative risk. |
| 2026-03-28 | No light mode | Terminal is always dark. No exceptions. |
| 2026-03-28 | Border-radius: 0px | Terminals have sharp corners. Rounded corners would break the metaphor. |
| 2026-03-28 | No motion/transitions | Terminals don't animate. State changes are instant. Only animation is cursor blink. |
| 2026-03-28 | 680px max width | ~80 character terminal width. Classic. |
