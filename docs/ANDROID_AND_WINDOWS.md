# Running the bot on Windows and using it from Android

MetaTrader 5 **does not execute Expert Advisors on Android or iOS**. That is a MetaQuotes platform limit, not something this bot can work around.

The supported architecture is: the EA runs on Windows, the phone only watches.

## 1. Windows PC (simplest)

1. Install MT5 for Windows from Deriv or metatrader5.com.
2. Log into the Deriv MT5 account (Financial for Gold, Synthetic for Step Index).
3. Compile and attach `DerivGoldStepEA` as described in the README.
4. Leave the PC on, lid open (or disable sleep). If Windows sleeps, the bot stops.

On your phone, install **MetaTrader 5**, log into the **same** account number and server. You will see every position the EA opens. You can close them from the phone. You cannot start the EA from the phone.

## 2. Windows VPS (recommended if you want 24/7)

Use any Windows VPS close to Deriv’s servers (often London or Singapore). Specs that are enough:

- Windows Server 2019/2022
- 1–2 GB RAM
- 1 vCPU
- ~20 GB disk

Then:

1. Remote Desktop into the VPS from Windows, or from Android with **RD Client** (Microsoft).
2. Install MT5 on the VPS, log in, attach the EA, Algo Trading green.
3. Disconnect RDP — MT5 keeps running on the VPS.
4. Use Android MT5 to monitor.

If Algo Trading turns off after an MT5 update, RDP in and turn it green again.

## 3. Android as a remote keyboard (optional)

Microsoft **RD Client** on Android lets you tap the VPS desktop, change inputs, or re-attach the EA. This is the only way to *control* the bot from a phone. The EA still executes on the Windows machine.

Do not use unofficial “MT5 EA for Android” APKs. They are not from MetaQuotes.

## 4. Two markets, two accounts

| Phone / VPS login | Market |
|---|---|
| Deriv Financial MT5 | Gold `XAUUSD` |
| Deriv Synthetic MT5 | `Step Index` |

Android MT5 can save both accounts and you switch between them in the app.

## 5. Quick “is it alive?” check from the phone

- A new position appears with comment `GS-EA BUY s7` (or SELL) — the bot is filling.
- If nothing trades for days: RDP in and confirm the panel says `Algo OK`, not `BLOCKED`, and that spread / session filters are not pausing it.
- Daily loss pause: panel shows `paused — daily loss`. It resets at next server midnight.
