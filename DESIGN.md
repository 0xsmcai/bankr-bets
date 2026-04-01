# Design System — SMCFactory

## Product Context
- **What this is:** Autonomous AI startup factory on Base chain
- **Who it's for:** Onchain traders, DeFi investors, degen builders on Base
- **Space/industry:** AI agents, DeFi, Zero-Human Companies
- **Project type:** Dark-aesthetic landing page + narrative page

## Aesthetic Direction
- **Direction:** Retro-Futuristic Terminal meets Degen Machine
- **Decoration level:** Intentional (CRT scanlines, mascot floating through text, subtle warm glow)
- **Mood:** An autonomous agent that builds real things. Technical credibility with degen personality. Dark, warm, alive. Not corporate, not meme. Something in between that says "I ship code and I don't need permission."
- **Reference sites:** https://rick.dhr.wtf/, https://www.base.org/brand

## Typography

### Font Stack
- **Display/Hero:** Space Grotesk 700 — geometric, crypto-native, angular terminals give it edge
- **Body:** Satoshi 400 — clean geometric sans, reads well on dark backgrounds, builder energy
- **UI/Labels/Data:** Space Mono 400/700 — the most crypto-native monospace, used for subtitles, contract addresses, footer

### Loading
- Space Grotesk + Space Mono: Google Fonts CDN
- Satoshi: Fontshare CDN (`https://api.fontshare.com/v2/css?f[]=satoshi@300,400,500,700`)

### Scale
| Role | Font | Size | Weight | Line Height | Letter Spacing |
|------|------|------|--------|-------------|----------------|
| Headline (index) | Space Grotesk | auto-fit to viewport | 700 | 0.95em | -0.03em |
| Subtitle | Space Mono | 12px | 400 | 1.4 | 1px |
| Body (index matrix) | Satoshi | 13px | 400 | 19px | normal |
| Body (about page) | Satoshi | 16px | 400 | 1.75 | normal |
| Section headings | Space Grotesk | 22px | 600 | 1.3 | -0.02em |
| Back link / nav | Space Mono | 12px | 400 | 1.4 | 1px |
| Footer | Space Mono | 11px | 400 | 1.4 | 1px |
| Contract address | Space Mono | 14px | 400 | 1.4 | normal |

## Color

### Palette (derived from mascot robot)
| Token | Hex | Source | Usage |
|-------|-----|--------|-------|
| `--bg` | `#1a1210` | Leather jacket darkest tone | Page background |
| `--text` | `#d4d0c8` | Warm off-white | Default body text |
| `--text-bright` | `#e8e4dc` | Highlight white | Headlines, emphasis |
| `--text-muted` | `rgba(212,208,200,0.45)` | — | Subtitles, labels |
| `--text-dim` | `rgba(212,208,200,0.25)` | — | Footer, decorative |
| `--crimson` | `#b53943` | Camera eye lenses | "SMCFactory" word color, highlights |
| `--teal` | `#98d4e0` | $SMCF jacket text | "$SMCF" word color, links |
| `--chrome` | `#a9a4a1` | Mechanical joints | Contract address color, secondary text |
| `--amber` | `#c4a35a` | Golden accent | Selection highlight, hover states, social link hover |

### Semantic Colors
| Role | Value |
|------|-------|
| "SMCFactory" in body | `#b53943` (crimson) |
| "$SMCF" in body | `#98d4e0` (teal) |
| Contract addresses | `#a9a4a1` (chrome) |
| Links | `#98d4e0` (teal) |
| Text selection | `#c4a35a` bg, `#1a1210` text |
| Social hover | `#c4a35a` (amber) |

### Color Approach
Restrained. Three accent colors pulled directly from the mascot image, each assigned to a specific word/purpose. No gradients. No decorative color. Color is information, not decoration.

## Spacing
- **Base unit:** 4px
- **Density:** Comfortable on about page, dense/terminal on index
- **Scale:** xs(4) sm(8) md(16) lg(24) xl(32) 2xl(48) 3xl(64)

### Specific Spacing
| Context | Value |
|---------|-------|
| Headline → subtitle | 20px mobile / 28px desktop |
| Subtitle → body | 44px mobile / 56px desktop |
| Page top padding | 32px mobile / 48px desktop |
| Section heading → body | 16px |
| Between sections | 48px |
| Paragraph spacing | 20px |
| Content max-width | 1200px (index) / 720px (about) |
| Gutter | 20px mobile / 48px desktop |
| Column gap | 40px (2-col desktop) |

## Layout
- **Approach:** Creative-editorial for index, single-column for about
- **Index page:** Pretext-powered 2-column text matrix (desktop), 1-column (mobile), floating circular mascot obstacle, auto-fit headline
- **About page:** Single column, max-width 720px, vertical flow
- **Responsive breakpoint:** 760px
- **Border radius:** 4px (contract box)

## Motion
- **Approach:** Intentional
- **Mascot movement:** Lissajous curve with incommensurate frequencies, chaotic wandering across full content area
- **Text reflow:** Real-time via Pretext `layoutNextLine()`, body text reflows around mascot each frame
- **CRT scanlines:** Static `repeating-linear-gradient` overlay on all pages
- **Transitions:** link hover 0.2s ease, page fade-in 0.8s ease

## Interactive Elements
- **Mascot circle:** Clickable/tappable → navigates to about.html. Pointer cursor on hover.
- **Social links:** X and GitHub icons in footer, muted → amber on hover
- **Back link:** Muted → bright on hover

## CRT Scanline Overlay
Present on all pages. Fixed position, `pointer-events: none`, `z-index: 100`.
```css
background: repeating-linear-gradient(0deg,
  transparent, transparent 2px,
  rgba(0,0,0,0.03) 2px, rgba(0,0,0,0.03) 4px);
```

## Assets
| File | Purpose | Size |
|------|---------|------|
| `mascot.jpg` | Robot avatar (camera eyes, leather jacket, $SMCF) | 113KB |
| `pretext.js` | Pretext text layout library (local bundle) | 55KB |

## Decisions Log
| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-03-31 | Space Grotesk + Satoshi + Space Mono | Crypto-native geometric stack. No AI agent competitor uses this combo. Space Grotesk says web3, Satoshi says builder, Space Mono says data. |
| 2026-03-31 | Dark warm brown `#1a1210` background | Pulled from mascot's leather jacket. Not pure black (too cold), not gray (too corporate). Warm brown = leather, machine, craft. |
| 2026-03-31 | Three-word, three-color system | Each word in body text gets its mascot-derived color: crimson (eyes) for name, teal (jacket text) for ticker, chrome (joints) for address. |
| 2026-03-31 | Golden amber `#c4a35a` accent | Not Base blue (Coinbase owns). Not teal (that's the ticker). Amber = "I generate value." Selection + hover only. |
| 2026-03-31 | Pretext editorial layout | Real-time text reflow around floating mascot. Inspired by rick.dhr.wtf. |
| 2026-03-31 | Retired Fraunces + Bricolage Grotesque | Too editorial/literary for degen AI agent identity. Space family is more crypto-native. |
| 2026-03-31 | Retired JetBrains Mono | Great for IDEs but Space Mono has more crypto cultural weight. |
| 2026-03-31 | Retired `#0e0e0e` background | Too cold/neutral. Warm brown from mascot jacket is more distinctive. |
