# Deriv Gold / Step Index MT5 Bot

Automated MetaTrader 5 Expert Advisor that trades **Gold (XAUUSD)** and **Step Index** on [Deriv](https://deriv.com).

It waits for a high-confluence closed-bar setup, then:

1. Calculates stop loss and take profit from ATR (no guessing pips)
2. Sizes the lot from a fixed risk percent of equity
3. Sends a market order **without asking you to confirm each trade**
4. Manages the position with breakeven + trailing stop

**This is not a money printer.** Markets can and will hit the stop. Demo-test first. Never risk money you cannot lose.

---

## Android vs Windows (important)

| Platform | Can the bot place trades? |
|---|---|
| **Windows** MT5 desktop | Yes — this is where the EA actually runs |
| **Windows VPS** (recommended 24/7) | Yes — same as desktop |
| **Android / iPhone MT5 app** | **No.** MetaQuotes does not allow Expert Advisors on mobile |
| MT5 WebTerminal | No |

There is no legal/official way to run an EA *inside* the Android MT5 app.

**The working setup:**

```
Windows PC or VPS  ──►  MT5 Desktop + this EA  ──►  trades 24/7
         │
         └── same Deriv login ──►  Android MT5 app (watch / close only)
```

You still “use it from Android”: open the phone app, see the bot’s positions, and close them if you need to. The brain has to stay on Windows.

A cheap Forex/Windows VPS (~$8–15/month, Windows Server, 1 GB RAM is enough) is the usual way to keep it running when your laptop is off.

---

## Deriv accounts — Gold and Step Index are usually separate

Deriv splits markets across MT5 account types:

| You want to trade | Deriv MT5 account | Typical symbol |
|---|---|---|
| Gold | **Financial** or **Financial STP** | `XAUUSD` |
| Step Index | **Synthetic Indices** | `Step Index` |

They are different servers. One login will not show both. Open two accounts if you want both markets, install the EA twice (one chart each).

---

## How entries work

The EA **does not** use martingale, grid, averaging, or recovery lots. One setup → one position → hard SL and TP.

It scores the last **closed** bar (so it does not chase a forming wick) out of 9 points and only trades at `MinScore` (default 6).

### Gold — Trend pullback (default)

Needs **all** of the important pieces, not just one indicator:

- Higher-timeframe EMA 50 above/below EMA 200 (direction)
- Chart-timeframe trend agrees
- Price pulls back into the fast EMA (21)
- RSI is not extended, and turning with the trend
- MACD histogram agrees
- Rejection candle (strong close or pin bar)

Stops: `SL = 1.8 × ATR`, `TP = 2.8 × ATR` (about 1:1.55 reward/risk). Gold also has a London/NY session filter and an optional Friday flatten so you are not holding over the weekend.

**Recommended chart:** `XAUUSD` · **M15**

### Step Index — Mean reversion (default)

Classic Step Index is a balanced 0.1-step random walk. Chasing trend there is a coin flip, so the default is fade-the-extreme:

- Price poked **outside** the Bollinger Band
- Closed bar **came back inside**
- RSI was oversold/overbought and is turning
- Rejection candle
- Skip if EMA 200 slope is violent (don’t fade a spike)

Take profit leans toward the Bollinger middle. Synthetic indices trade 24/7, so there is no session filter.

**Recommended chart:** `Step Index` · **M5**

Attach the EA to each chart you want traded. Strategy `Auto` picks the profile from the symbol name (`XAU`/`GOLD` vs `STEP`).

---

## Install on Windows (5 minutes)

1. Install [MetaTrader 5](https://www.metatrader5.com/en/download) and log into your **Deriv** MT5 account  
   (Deriv → Trader’s Hub → MT5 → the Financial or Synthetic account).
2. Copy `MQL5/Experts/DerivGoldStepEA.mq5` into your terminal’s Experts folder.  
   In MT5: **File → Open Data Folder → `MQL5/Experts/`**.  
   Or run `scripts/install_windows.bat`.
3. Restart MT5 (or right-click **Navigator → Expert Advisors → Refresh**).
4. Open MetaEditor (`F4`), open `DerivGoldStepEA.mq5`, press **Compile** (`F7`). You want `0 error(s)`.
5. Open the Gold or Step Index chart, **drag the EA onto the chart**.
6. In MT5: **Tools → Options → Expert Advisors**
   - ☑ Allow algorithmic trading
   - ☑ Allow live trading (if present)
   - uncheck “Disable automated trading when the account has been changed” if you switch demo/live often
7. In the EA Common tab:
   - ☑ Allow Algo Trading
8. Click the toolbar **Algo Trading** button so it is **green**.
9. You should see the gold panel on the chart: `AutoTrade ON   Algo OK`.

Optional: load `presets/Gold.set` or `presets/StepIndex.set` from the Inputs tab (Load).

### First run checklist

- [ ] Demo account, not live
- [ ] Algo Trading is green
- [ ] Symbol matches the account type (Gold on Financial, Step on Synthetic)
- [ ] Strategy Tester backtest on that symbol before going live
- [ ] Risk percent left at **1.0** until you understand the stop size
- [ ] VPS if you want it running overnight

---

## Inputs that matter

| Input | Default | Meaning |
|---|---|---|
| `InpAutoTrade` | true | Send orders with no pop-up confirmation |
| `InpRiskPercent` | 1.0 | Lose at most ~1% of equity if SL hits |
| `InpMinScore` | 6 | Raise to 7–8 for fewer, stricter entries |
| `InpAtrSL` / `InpAtrTP` | 1.8 / 2.8 | Stop and target as ATR multiples |
| `InpMaxDailyLossPct` | 4.0 | Bot stands down after a bad day |
| `InpMaxDailyProfitPct` | 8.0 | Bot stands down after a good day |
| `InpMaxPositions` | 1 | Never stacks / grids |
| `InpUseSessionFilter` | true | Gold only, server time 07:00–20:00 |
| `InpMagic` | 910001 | Change if you run two copies on one account |

Lot mode `Fixed` is there if you prefer a constant 0.01. Risk-percent is the safer default.

---

## Backtest (do this)

In MT5: **View → Strategy Tester**.

- Expert: `DerivGoldStepEA`
- Symbol: `XAUUSD` or `Step Index`
- Period: M15 (Gold) / M5 (Step)
- Modelling: **Every tick based on real ticks** if Deriv provides them, otherwise 1-minute OHLC
- Dates: at least 6–12 months
- Deposit / leverage: match your real account

Read profit factor, max drawdown, and number of trades. If it only took 8 trades, the sample is too small to mean anything.

---

## What this bot will not do

- Run inside the Android or iOS MT5 app
- Guarantee profit, especially on Step Index (equal up/down probability)
- Martingale a loser into a bigger loser
- Trade both Gold and Step Index from one Deriv login
- Bypass the MT5 **Algo Trading** master switch (that is a platform safety lock)

---

## Risk

Trading leveraged CFDs can wipe the account. Synthetic indices and gold are volatile. Past backtests are not future results. Start on **Deriv demo**, then a size you can afford to lose.

Nothing here is financial advice.

---

## Files

```
MQL5/Experts/DerivGoldStepEA.mq5   ← the bot (compile this)
presets/Gold.set
presets/StepIndex.set
scripts/install_windows.bat
docs/ANDROID_AND_WINDOWS.md
```
