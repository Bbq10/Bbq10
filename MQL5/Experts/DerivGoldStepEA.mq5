//+------------------------------------------------------------------+
//|                                             DerivGoldStepEA.mq5  |
//|           Automated Gold + Step Index Expert Advisor for MT5     |
//|                                                                  |
//|  Attach to an XAUUSD / GOLD chart (Deriv Financial) and/or a     |
//|  Step Index chart (Deriv Synthetic). Compiles in MetaEditor 5.   |
//|                                                                  |
//|  Android MT5 cannot run EAs. Run this on Windows (or a VPS) and  |
//|  monitor the same account from the Android app.                  |
//+------------------------------------------------------------------+
#property copyright "Bbq10"
#property link      "https://github.com/Bbq10/Bbq10"
#property version   "1.10"
#property description "Auto-trades Gold and Step Index on Deriv MT5."
#property description "Confluence entries, ATR stop-loss/take-profit, no martingale."
#property description "Places market orders without per-trade confirmation."

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum ENUM_STRATEGY
  {
   STRATEGY_AUTO = 0,           // Auto (Gold=trend, Step=mean-reversion)
   STRATEGY_TREND_PULLBACK = 1, // Trend pullback (recommended for Gold)
   STRATEGY_MEAN_REVERSION = 2  // Mean reversion (recommended for Step Index)
  };

enum ENUM_LOT_MODE
  {
   LOT_RISK_PERCENT = 0,        // Risk a % of equity
   LOT_FIXED = 1                // Fixed lot size
  };

enum ENUM_INSTRUMENT
  {
   INSTR_UNKNOWN = 0,
   INSTR_GOLD = 1,
   INSTR_STEP = 2
  };

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== 1. Core ==="
input ulong             InpMagic              = 910001;              // Magic number
input bool              InpAutoTrade          = true;                // Place trades automatically (no confirm)
sinput string           InpTradeComment       = "GS-EA";             // Order comment
input bool              InpAllowGold          = true;                // Allow Gold / XAUUSD
input bool              InpAllowStep          = true;                // Allow Step Index
input ENUM_STRATEGY     InpStrategy           = STRATEGY_AUTO;       // Strategy

input group "=== 2. Risk ==="
input ENUM_LOT_MODE     InpLotMode            = LOT_RISK_PERCENT;    // Lot calculation
input double            InpRiskPercent        = 1.0;                 // Risk percent per trade
input double            InpFixedLot           = 0.01;                // Fixed lot (if lot mode = fixed)
input int               InpMaxPositions       = 1;                   // Max open positions (this symbol)
input double            InpMaxDailyLossPct    = 4.0;                 // Pause if daily loss >= this %
input double            InpMaxDailyProfitPct  = 8.0;                 // Pause if daily profit >= this % (0=off)
input double            InpMinRR              = 1.20;                // Skip trade if reward/risk below this
input int               InpSlippagePoints     = 40;                  // Max slippage (points)

input group "=== 3. Stops (ATR based) ==="
input int               InpAtrPeriod          = 14;                  // ATR period
input double            InpAtrSL              = 1.80;                // Stop loss = ATR x this
input double            InpAtrTP              = 2.80;                // Take profit = ATR x this
input bool              InpUseTrailing        = true;                // Trailing stop
input double            InpTrailStartATR      = 1.20;                // Start trailing after profit = ATR x
input double            InpTrailATR           = 0.90;                // Trail distance = ATR x
input bool              InpBreakEven          = true;                // Move SL to breakeven
input double            InpBreakEvenATR       = 1.00;                // BE trigger = ATR x
input double            InpBreakEvenLockATR   = 0.12;                // Lock this much ATR past entry

input group "=== 4. Entry precision ==="
input int               InpMinScore           = 6;                   // Minimum confluence score (0-9)
input int               InpEmaFast            = 21;                  // Fast EMA
input int               InpEmaSlow            = 50;                  // Slow EMA
input int               InpEmaTrend           = 200;                 // Trend EMA
input int               InpRsiPeriod          = 14;                  // RSI period
input int               InpMacdFast           = 12;                  // MACD fast
input int               InpMacdSlow           = 26;                  // MACD slow
input int               InpMacdSignal         = 9;                   // MACD signal
input int               InpBbPeriod           = 20;                  // Bollinger period
input double            InpBbDeviation        = 2.0;                 // Bollinger deviation
input int               InpCooldownBars       = 3;                   // Bars to wait after a stop-out

input group "=== 5. Filters ==="
input int               InpMaxSpreadPoints    = 0;                   // Max spread (0 = auto per instrument)
input bool              InpUseSessionFilter   = true;                // Session filter (Gold only)
input int               InpSessionStartHour   = 7;                   // Session start (server hour)
input int               InpSessionEndHour     = 20;                  // Session end (server hour)
input bool              InpCloseFridayGold    = true;                // Flatten Gold before weekend
input int               InpFridayCloseHour    = 20;                  // Friday flatten hour (server)
input int               InpMaxTradesPerDay    = 8;                   // Cap trades per day (this symbol)

input group "=== 6. Display ==="
input bool              InpShowPanel          = true;                // On-chart panel
input bool              InpAlerts             = true;                // Terminal / push alerts
input color             InpPanelText          = clrWhite;            // Panel text
input color             InpPanelAccent        = clrGold;             // Panel accent

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CTrade            g_trade;
ENUM_INSTRUMENT   g_instr          = INSTR_UNKNOWN;
ENUM_STRATEGY     g_strategy       = STRATEGY_AUTO;
int               g_emaFast        = INVALID_HANDLE;
int               g_emaSlow        = INVALID_HANDLE;
int               g_emaTrend       = INVALID_HANDLE;
int               g_htfSlow        = INVALID_HANDLE;
int               g_htfTrend       = INVALID_HANDLE;
int               g_rsi            = INVALID_HANDLE;
int               g_macd           = INVALID_HANDLE;
int               g_atr            = INVALID_HANDLE;
int               g_bb             = INVALID_HANDLE;
datetime          g_lastBarTime    = 0;
datetime          g_cooldownUntil  = 0;
int               g_lastScore      = 0;
int               g_lastSignal     = 0;     // +1 buy, -1 sell, 0 none
string            g_lastReason     = "waiting for closed bar";
string            g_status         = "init";
double            g_dayStartEquity = 0.0;
int               g_dayStamp       = 0;
int               g_tradesToday    = 0;
double            g_lastATR        = 0.0;
double            g_lastSpreadPts  = 0.0;
bool              g_paused         = false;
string            g_pauseWhy       = "";
MqlTick           g_tick;

#define PANEL_PREFIX "GS_"
#define EA_NAME      "Deriv Gold/Step EA"

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpRiskPercent <= 0.0 || InpRiskPercent > 10.0)
     {
      Print("Risk percent must be between 0 and 10. Using 1%.");
     }
   if(InpAtrSL <= 0.0 || InpAtrTP <= 0.0)
     {
      Print("ATR SL/TP multipliers must be > 0");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_instr    = DetectInstrument(_Symbol);
   g_strategy = ResolveStrategy();

   if(g_instr == INSTR_GOLD && !InpAllowGold)
     {
      Print("This chart looks like Gold, but InpAllowGold is false.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(g_instr == INSTR_STEP && !InpAllowStep)
     {
      Print("This chart looks like Step Index, but InpAllowStep is false.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(g_instr == INSTR_UNKNOWN)
     {
      PrintFormat("Symbol %s is not recognised as Gold or Step Index. EA will still run using the selected strategy.", _Symbol);
     }

   ENUM_TIMEFRAMES htf = HigherTimeframe(_Period);

   g_emaFast  = iMA(_Symbol, _Period, InpEmaFast,  0, MODE_EMA, PRICE_CLOSE);
   g_emaSlow  = iMA(_Symbol, _Period, InpEmaSlow,  0, MODE_EMA, PRICE_CLOSE);
   g_emaTrend = iMA(_Symbol, _Period, InpEmaTrend, 0, MODE_EMA, PRICE_CLOSE);
   g_htfSlow  = iMA(_Symbol, htf,     InpEmaSlow,  0, MODE_EMA, PRICE_CLOSE);
   g_htfTrend = iMA(_Symbol, htf,     InpEmaTrend, 0, MODE_EMA, PRICE_CLOSE);
   g_rsi      = iRSI(_Symbol, _Period, InpRsiPeriod, PRICE_CLOSE);
   g_macd     = iMACD(_Symbol, _Period, InpMacdFast, InpMacdSlow, InpMacdSignal, PRICE_CLOSE);
   g_atr      = iATR(_Symbol, _Period, InpAtrPeriod);
   g_bb       = iBands(_Symbol, _Period, InpBbPeriod, 0, InpBbDeviation, PRICE_CLOSE);

   if(g_emaFast == INVALID_HANDLE || g_emaSlow == INVALID_HANDLE || g_emaTrend == INVALID_HANDLE ||
      g_htfSlow == INVALID_HANDLE || g_htfTrend == INVALID_HANDLE || g_rsi == INVALID_HANDLE ||
      g_macd == INVALID_HANDLE || g_atr == INVALID_HANDLE || g_bb == INVALID_HANDLE)
     {
      Print("Failed to create indicator handles. Error ", GetLastError());
      return INIT_FAILED;
     }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetAsyncMode(false);
   g_trade.LogLevel(LOG_LEVEL_ERRORS);
   ApplyFillingMode();

   ResetDailyCounters();
   g_lastBarTime = iTime(_Symbol, _Period, 0);
   g_status = "scanning";

   PrintFormat("%s initialised | symbol=%s instrument=%s strategy=%s filling=%s",
               EA_NAME, _Symbol, InstrumentName(g_instr), StrategyName(g_strategy),
               EnumToString(g_trade.RequestTypeFilling()));
   Print("Algo Trading must be GREEN in the toolbar. Android MT5 cannot run this EA - use Windows/VPS.");

   if(InpShowPanel)
      DrawPanel();

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(g_emaFast);
   IndicatorRelease(g_emaSlow);
   IndicatorRelease(g_emaTrend);
   IndicatorRelease(g_htfSlow);
   IndicatorRelease(g_htfTrend);
   IndicatorRelease(g_rsi);
   IndicatorRelease(g_macd);
   IndicatorRelease(g_atr);
   IndicatorRelease(g_bb);
   DeletePanel();
   Comment("");
  }

//+------------------------------------------------------------------+
//| Tick                                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
     {
      g_status = "symbol not tradable";
      if(InpShowPanel) DrawPanel();
      return;
     }

   ResetDailyCounters();
   ManageOpenPositions();

   if(g_instr == INSTR_GOLD && InpCloseFridayGold && IsFridayFlattenTime())
     {
      CloseOurPositions("Friday flatten");
      g_status = "Friday flatten";
      g_paused = true;
      g_pauseWhy = "weekend flatten";
      if(InpShowPanel) DrawPanel();
      return;
     }

   if(!PassesRiskGuards())
     {
      if(InpShowPanel) DrawPanel();
      return;
     }

   if(!IsNewBar())
     {
      if(InpShowPanel) DrawPanel();
      return;
     }

   if(CountOurPositions() >= InpMaxPositions)
     {
      g_status = "in position";
      g_lastReason = "max positions reached";
      if(InpShowPanel) DrawPanel();
      return;
     }

   if(TimeCurrent() < g_cooldownUntil)
     {
      g_status = "cooldown";
      g_lastReason = "waiting after stop-out";
      if(InpShowPanel) DrawPanel();
      return;
     }

   if(!SpreadOK())
     {
      g_status = "spread too wide";
      if(InpShowPanel) DrawPanel();
      return;
     }

   if(g_instr == INSTR_GOLD && InpUseSessionFilter && !InSession())
     {
      g_status = "outside session";
      g_lastReason = "Gold session filter";
      if(InpShowPanel) DrawPanel();
      return;
     }

   int signal = 0;
   int score  = 0;
   string reason = "";

   if(g_strategy == STRATEGY_MEAN_REVERSION)
      signal = MeanReversionSignal(score, reason);
   else
      signal = TrendPullbackSignal(score, reason);

   g_lastSignal = signal;
   g_lastScore  = score;
   g_lastReason = reason;

   if(signal == 0 || score < InpMinScore)
     {
      g_status = "scanning";
      if(InpShowPanel) DrawPanel();
      return;
     }

   if(!InpAutoTrade)
     {
      g_status = "signal (auto-trade OFF)";
      if(InpAlerts)
         Alert(EA_NAME, " signal ", (signal > 0 ? "BUY" : "SELL"), " ", _Symbol, " score ", score, " - auto-trade is off");
      if(InpShowPanel) DrawPanel();
      return;
     }

   if(!TradingAllowed())
     {
      g_status = "Algo Trading disabled";
      g_lastReason = "Enable Algo Trading (toolbar must be green)";
      if(InpShowPanel) DrawPanel();
      return;
     }

   if(OpenTrade(signal, score, reason))
     {
      g_status = (signal > 0 ? "BUY filled" : "SELL filled");
      g_tradesToday++;
     }
   else
      g_status = "order failed";

   if(InpShowPanel) DrawPanel();
  }

//+------------------------------------------------------------------+
//| Instrument / strategy helpers                                    |
//+------------------------------------------------------------------+
ENUM_INSTRUMENT DetectInstrument(const string symbol)
  {
   string u = symbol;
   StringToUpper(u);
   StringReplace(u, " ", "");
   StringReplace(u, "_", "");
   StringReplace(u, ".", "");
   StringReplace(u, "-", "");

   if(StringFind(u, "STEP") >= 0)
      return INSTR_STEP;
   if(StringFind(u, "XAU") >= 0 || StringFind(u, "GOLD") >= 0)
      return INSTR_GOLD;
   return INSTR_UNKNOWN;
  }

ENUM_STRATEGY ResolveStrategy()
  {
   if(InpStrategy != STRATEGY_AUTO)
      return InpStrategy;
   if(g_instr == INSTR_STEP)
      return STRATEGY_MEAN_REVERSION;
   return STRATEGY_TREND_PULLBACK;
  }

string InstrumentName(const ENUM_INSTRUMENT v)
  {
   if(v == INSTR_GOLD) return "GOLD";
   if(v == INSTR_STEP) return "STEP INDEX";
   return "OTHER";
  }

string StrategyName(const ENUM_STRATEGY v)
  {
   if(v == STRATEGY_MEAN_REVERSION) return "Mean reversion";
   if(v == STRATEGY_TREND_PULLBACK) return "Trend pullback";
   return "Auto";
  }

ENUM_TIMEFRAMES HigherTimeframe(const ENUM_TIMEFRAMES tf)
  {
   const int sec = PeriodSeconds(tf);
   if(sec <= PeriodSeconds(PERIOD_M5))  return PERIOD_M15;
   if(sec <= PeriodSeconds(PERIOD_M15)) return PERIOD_H1;
   if(sec <= PeriodSeconds(PERIOD_H1))  return PERIOD_H4;
   return PERIOD_D1;
  }

//+------------------------------------------------------------------+
//| Filling mode - Deriv often uses IOC                              |
//+------------------------------------------------------------------+
void ApplyFillingMode()
  {
   long filling = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else
      g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
  }

//+------------------------------------------------------------------+
//| Indicator readers                                                |
//+------------------------------------------------------------------+
bool ReadBuf(const int handle, const int buffer, const int count, double &out[])
  {
   ArraySetAsSeries(out, true);
   if(CopyBuffer(handle, buffer, 0, count, out) < count)
      return false;
   return true;
  }

bool ClosedBarReady()
  {
   return (Bars(_Symbol, _Period) >= InpEmaTrend + 5);
  }

//+------------------------------------------------------------------+
//| Trend-pullback confluence (Gold default)                         |
//| Score 0-9. Uses the last CLOSED bar so the entry is not a wick.  |
//+------------------------------------------------------------------+
int TrendPullbackSignal(int &score, string &reason)
  {
   score = 0;
   reason = "no setup";
   if(!ClosedBarReady())
     {
      reason = "not enough bars";
      return 0;
     }

   double emaF[], emaS[], emaT[], htfS[], htfT[], rsi[], macdM[], macdS[], atr[];
   if(!ReadBuf(g_emaFast,  0, 4, emaF))  return 0;
   if(!ReadBuf(g_emaSlow,  0, 4, emaS))  return 0;
   if(!ReadBuf(g_emaTrend, 0, 4, emaT))  return 0;
   if(!ReadBuf(g_htfSlow,  0, 3, htfS))  return 0;
   if(!ReadBuf(g_htfTrend, 0, 3, htfT))  return 0;
   if(!ReadBuf(g_rsi,      0, 4, rsi))   return 0;
   if(!ReadBuf(g_macd,     0, 4, macdM)) return 0;
   if(!ReadBuf(g_macd,     1, 4, macdS)) return 0;
   if(!ReadBuf(g_atr,      0, 4, atr))   return 0;

   g_lastATR = atr[1];
   if(g_lastATR <= 0.0)
     {
      reason = "ATR not ready";
      return 0;
     }

   const double o = iOpen(_Symbol, _Period, 1);
   const double h = iHigh(_Symbol, _Period, 1);
   const double l = iLow(_Symbol, _Period, 1);
   const double c = iClose(_Symbol, _Period, 1);
   if(h - l <= 0.0)
      return 0;

   const bool htfUp   = (htfS[1] > htfT[1]);
   const bool htfDown = (htfS[1] < htfT[1]);
   const bool ltfUp   = (emaS[1] > emaT[1] && c > emaT[1]);
   const bool ltfDown = (emaS[1] < emaT[1] && c < emaT[1]);

   const double pullDist = 0.35 * g_lastATR;
   const bool touchedFastBuy  = (l <= emaF[1] + pullDist && c >= emaF[1] - pullDist);
   const bool touchedFastSell = (h >= emaF[1] - pullDist && c <= emaF[1] + pullDist);

   const bool rsiBuyOk  = (rsi[1] > 40.0 && rsi[1] < 62.0 && rsi[1] >= rsi[2]);
   const bool rsiSellOk = (rsi[1] < 60.0 && rsi[1] > 38.0 && rsi[1] <= rsi[2]);

   const bool macdBuy  = (macdM[1] > macdS[1] && macdM[1] >= macdM[2]);
   const bool macdSell = (macdM[1] < macdS[1] && macdM[1] <= macdM[2]);

   const double body = MathAbs(c - o);
   const double range = h - l;
   const bool bullClose = (c > o && body >= 0.45 * range && c > emaF[1]);
   const bool bearClose = (c < o && body >= 0.45 * range && c < emaF[1]);
   const bool bullPin   = ((MathMin(o, c) - l) >= 0.45 * range && (h - MathMax(o, c)) <= 0.30 * range && c >= o);
   const bool bearPin   = ((h - MathMax(o, c)) >= 0.45 * range && (MathMin(o, c) - l) <= 0.30 * range && c <= o);

   int buyScore = 0;
   int sellScore = 0;
   if(htfUp)   buyScore  += 2;
   if(htfDown) sellScore += 2;
   if(ltfUp)   buyScore  += 1;
   if(ltfDown) sellScore += 1;
   if(touchedFastBuy)  buyScore  += 2;
   if(touchedFastSell) sellScore += 2;
   if(rsiBuyOk)  buyScore  += 1;
   if(rsiSellOk) sellScore += 1;
   if(macdBuy)  buyScore  += 1;
   if(macdSell) sellScore += 1;
   if(bullClose || bullPin) buyScore  += 2;
   if(bearClose || bearPin) sellScore += 2;

   if(buyScore >= sellScore && buyScore >= InpMinScore && htfUp)
     {
      score = buyScore;
      reason = StringFormat("trend BUY  HTF-up pullback EMA%d RSI=%.1f MACD+ candle", InpEmaFast, rsi[1]);
      return 1;
     }
   if(sellScore > buyScore && sellScore >= InpMinScore && htfDown)
     {
      score = sellScore;
      reason = StringFormat("trend SELL HTF-down pullback EMA%d RSI=%.1f MACD- candle", InpEmaFast, rsi[1]);
      return -1;
     }

   score = MathMax(buyScore, sellScore);
   reason = StringFormat("trend wait (buy=%d sell=%d need=%d)", buyScore, sellScore, InpMinScore);
   return 0;
  }

//+------------------------------------------------------------------+
//| Mean-reversion confluence (Step Index default)                   |
//| Wait for a closed-bar return inside Bollinger after an extreme.  |
//+------------------------------------------------------------------+
int MeanReversionSignal(int &score, string &reason)
  {
   score = 0;
   reason = "no setup";
   if(!ClosedBarReady())
     {
      reason = "not enough bars";
      return 0;
     }

   double mid[], up[], lo[], rsi[], atr[], emaT[];
   if(!ReadBuf(g_bb,  0, 5, mid)) return 0;
   if(!ReadBuf(g_bb,  1, 5, up))  return 0;
   if(!ReadBuf(g_bb,  2, 5, lo))  return 0;
   if(!ReadBuf(g_rsi, 0, 5, rsi)) return 0;
   if(!ReadBuf(g_atr, 0, 4, atr)) return 0;
   if(!ReadBuf(g_emaTrend, 0, 4, emaT)) return 0;

   g_lastATR = atr[1];
   if(g_lastATR <= 0.0)
     {
      reason = "ATR not ready";
      return 0;
     }

   const double o = iOpen(_Symbol, _Period, 1);
   const double h = iHigh(_Symbol, _Period, 1);
   const double l = iLow(_Symbol, _Period, 1);
   const double c = iClose(_Symbol, _Period, 1);
   const double prevL = iLow(_Symbol, _Period, 2);
   const double prevH = iHigh(_Symbol, _Period, 2);
   if(h - l <= 0.0)
      return 0;

   const bool wasBelow = (prevL < lo[2] || l < lo[1]);
   const bool wasAbove = (prevH > up[2] || h > up[1]);
   const bool closeBackInLow  = (c > lo[1] && c < mid[1]);
   const bool closeBackInHigh = (c < up[1] && c > mid[1]);
   const bool rsiOversold   = (rsi[1] <= 32.0);
   const bool rsiOverbought = (rsi[1] >= 68.0);
   const bool rsiTurningUp   = (rsi[1] > rsi[2]);
   const bool rsiTurningDown = (rsi[1] < rsi[2]);
   const bool bullReject = (c > o);
   const bool bearReject = (c < o);

   // Mild trend filter: do not fade a very strong EMA-200 slope
   const double slope = emaT[1] - emaT[3];
   const bool violentUp   = (slope >  1.25 * g_lastATR);
   const bool violentDown = (slope < -1.25 * g_lastATR);

   int buyScore = 0;
   int sellScore = 0;
   if(wasBelow)        buyScore  += 2;
   if(wasAbove)        sellScore += 2;
   if(closeBackInLow)  buyScore  += 2;
   if(closeBackInHigh) sellScore += 2;
   if(rsiOversold)     buyScore  += 2;
   if(rsiOverbought)   sellScore += 2;
   if(rsiTurningUp)    buyScore  += 1;
   if(rsiTurningDown)  sellScore += 1;
   if(bullReject)      buyScore  += 2;
   if(bearReject)      sellScore += 2;

   if(violentDown) buyScore = 0;
   if(violentUp)   sellScore = 0;

   if(buyScore >= sellScore && buyScore >= InpMinScore && wasBelow && closeBackInLow)
     {
      score = buyScore;
      reason = StringFormat("reversion BUY  back inside BB RSI=%.1f", rsi[1]);
      return 1;
     }
   if(sellScore > buyScore && sellScore >= InpMinScore && wasAbove && closeBackInHigh)
     {
      score = sellScore;
      reason = StringFormat("reversion SELL back inside BB RSI=%.1f", rsi[1]);
      return -1;
     }

   score = MathMax(buyScore, sellScore);
   reason = StringFormat("reversion wait (buy=%d sell=%d need=%d)", buyScore, sellScore, InpMinScore);
   return 0;
  }

//+------------------------------------------------------------------+
//| Order execution                                                  |
//+------------------------------------------------------------------+
bool OpenTrade(const int signal, const int score, const string reason)
  {
   RefreshRates();
   ApplyFillingMode();

   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
      return false;

   double atr = g_lastATR;
   if(atr <= 0.0)
      atr = ReadATR();
   if(atr <= 0.0)
     {
      Print("Cannot size stops - ATR is 0");
      return false;
     }

   double sl = 0.0, tp = 0.0;
   if(!BuildStops(signal, ask, bid, atr, sl, tp))
     {
      Print("Stops failed RR or stop-level check. ", reason);
      return false;
     }

   const double slDist = (signal > 0 ? (ask - sl) : (sl - bid));
   double lot = CalculateLot(slDist);
   if(lot <= 0.0)
     {
      Print("Lot size is 0 - check margin / min lot / risk %");
      return false;
     }

   const string cmt = StringFormat("%s %s s%d", InpTradeComment, (signal > 0 ? "BUY" : "SELL"), score);

   bool ok = false;
   if(signal > 0)
      ok = g_trade.Buy(lot, _Symbol, ask, sl, tp, cmt);
   else
      ok = g_trade.Sell(lot, _Symbol, bid, sl, tp, cmt);

   if(!ok)
     {
      PrintFormat("Order failed retcode=%u desc=%s lastError=%d",
                  g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription(), GetLastError());
      if(!MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION))
         Sleep(200);
      RefreshRates();
      ApplyFillingMode();
      const double ask2 = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      const double bid2 = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(!BuildStops(signal, ask2, bid2, atr, sl, tp))
         return false;
      if(signal > 0)
         ok = g_trade.Buy(lot, _Symbol, ask2, sl, tp, cmt);
      else
         ok = g_trade.Sell(lot, _Symbol, bid2, sl, tp, cmt);
     }

   if(ok)
     {
      PrintFormat("TRADE %s %s lot=%.2f sl=%s tp=%s score=%d | %s",
                  (signal > 0 ? "BUY" : "SELL"), _Symbol, lot,
                  DoubleToString(sl, _Digits), DoubleToString(tp, _Digits),
                  score, reason);
      if(InpAlerts)
         Alert(EA_NAME, " ", (signal > 0 ? "BUY" : "SELL"), " ", _Symbol,
               " lot ", DoubleToString(lot, 2), " SL ", DoubleToString(sl, _Digits),
               " TP ", DoubleToString(tp, _Digits));
     }
   else
     {
      PrintFormat("Order retry failed retcode=%u desc=%s",
                  g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
     }
   return ok;
  }

bool BuildStops(const int signal, const double ask, const double bid,
                const double atr, double &sl, double &tp)
  {
   const double slDist = atr * InpAtrSL;
   double       tpDist = atr * InpAtrTP;

   if(g_strategy == STRATEGY_MEAN_REVERSION)
     {
      double mid[];
      if(ReadBuf(g_bb, 0, 3, mid) && mid[1] > 0.0)
        {
         if(signal > 0)
            tpDist = MathMax(tpDist * 0.70, MathAbs(mid[1] - ask));
         else
            tpDist = MathMax(tpDist * 0.70, MathAbs(bid - mid[1]));
        }
     }

   if(signal > 0)
     {
      sl = NormalizePrice(ask - slDist);
      tp = NormalizePrice(ask + tpDist);
     }
   else
     {
      sl = NormalizePrice(bid + slDist);
      tp = NormalizePrice(bid - tpDist);
     }

   const double entry = (signal > 0 ? ask : bid);
   const double realSL = MathAbs(entry - sl);
   const double realTP = MathAbs(tp - entry);
   if(realSL <= 0.0 || realTP / realSL < InpMinRR)
     {
      g_lastReason = StringFormat("RR %.2f below min %.2f", (realSL > 0 ? realTP / realSL : 0.0), InpMinRR);
      return false;
     }

   if(!RespectStopLevels(signal, entry, sl, tp))
      return false;
   return true;
  }

bool RespectStopLevels(const int signal, const double entry, double &sl, double &tp)
  {
   const int stops  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const int freeze = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   const double minDist = (stops + freeze) * _Point;
   if(minDist <= 0.0)
      return true;

   if(signal > 0)
     {
      if(entry - sl < minDist) sl = NormalizePrice(entry - minDist);
      if(tp - entry < minDist) tp = NormalizePrice(entry + minDist);
     }
   else
     {
      if(sl - entry < minDist) sl = NormalizePrice(entry + minDist);
      if(entry - tp < minDist) tp = NormalizePrice(entry - minDist);
     }
   return (sl > 0.0 && tp > 0.0);
  }

double CalculateLot(const double slDistance)
  {
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(minLot <= 0.0) minLot = 0.01;
   if(step   <= 0.0) step   = 0.01;
   if(tickSz <= 0.0) tickSz = _Point;

   double lot = InpFixedLot;

   if(InpLotMode == LOT_RISK_PERCENT)
     {
      const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double riskPct = InpRiskPercent;
      if(riskPct <= 0.0) riskPct = 1.0;
      if(riskPct > 10.0) riskPct = 10.0;
      const double riskMoney = equity * riskPct / 100.0;

      if(tickVal <= 0.0 || slDistance <= 0.0)
         lot = minLot;
      else
        {
         const double ticks = slDistance / tickSz;
         lot = riskMoney / (ticks * tickVal);
        }
     }

   lot = MathFloor(lot / step + 1e-8) * step;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;

   // Margin check - scale down if needed
   double margin = 0.0;
   const ENUM_ORDER_TYPE otype = ORDER_TYPE_BUY;
   if(OrderCalcMargin(otype, _Symbol, lot, SymbolInfoDouble(_Symbol, SYMBOL_ASK), margin))
     {
      const double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      int guard = 0;
      while(margin > free * 0.70 && lot > minLot && guard < 20)
        {
         lot = MathMax(minLot, lot - step);
         if(!OrderCalcMargin(otype, _Symbol, lot, SymbolInfoDouble(_Symbol, SYMBOL_ASK), margin))
            break;
         guard++;
        }
      if(margin > free * 0.90)
        {
         Print("Not enough free margin for even min lot");
         return 0.0;
        }
     }

   int digits = 0;
   double s = step;
   while(s < 1.0 && digits < 8)
     {
      s *= 10.0;
      digits++;
     }
   return NormalizeDouble(lot, digits);
  }

//+------------------------------------------------------------------+
//| Position management - trailing + breakeven                       |
//+------------------------------------------------------------------+
void ManageOpenPositions()
  {
   const double atr = (g_lastATR > 0.0 ? g_lastATR : ReadATR());
   if(atr <= 0.0)
      return;

   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;

      const long   type   = PositionGetInteger(POSITION_TYPE);
      const double sl     = PositionGetDouble(POSITION_SL);
      const double tp     = PositionGetDouble(POSITION_TP);
      const double open   = PositionGetDouble(POSITION_PRICE_OPEN);

      double newSL = sl;
      bool   mod   = false;

      if(type == POSITION_TYPE_BUY)
        {
         const double move = bid - open;
         if(InpBreakEven && move >= atr * InpBreakEvenATR)
           {
            const double be = NormalizePrice(open + atr * InpBreakEvenLockATR);
            if(be > sl + _Point)
              {
               newSL = be;
               mod = true;
              }
           }
         if(InpUseTrailing && move >= atr * InpTrailStartATR)
           {
            const double trail = NormalizePrice(bid - atr * InpTrailATR);
            if(trail > newSL + _Point && trail < bid)
              {
               newSL = trail;
               mod = true;
              }
           }
        }
      else if(type == POSITION_TYPE_SELL)
        {
         const double move = open - ask;
         if(InpBreakEven && move >= atr * InpBreakEvenATR)
           {
            const double be = NormalizePrice(open - atr * InpBreakEvenLockATR);
            if(sl == 0.0 || be < sl - _Point)
              {
               newSL = be;
               mod = true;
              }
           }
         if(InpUseTrailing && move >= atr * InpTrailStartATR)
           {
            const double trail = NormalizePrice(ask + atr * InpTrailATR);
            if((sl == 0.0 || trail < newSL - _Point) && trail > ask)
              {
               newSL = trail;
               mod = true;
              }
           }
        }

      if(mod)
        {
         double tpKeep = tp;
         if(!RespectStopLevels((type == POSITION_TYPE_BUY ? 1 : -1),
                               (type == POSITION_TYPE_BUY ? bid : ask), newSL, tpKeep))
            continue;
         if(!g_trade.PositionModify(ticket, newSL, tpKeep))
            Print("Modify failed ", g_trade.ResultRetcodeDescription());
        }

      if(type == POSITION_TYPE_BUY && sl > 0.0 && bid <= sl)
        {
         g_trade.PositionClose(ticket);
         ArmCooldown();
        }
      else if(type == POSITION_TYPE_SELL && sl > 0.0 && ask >= sl)
        {
         g_trade.PositionClose(ticket);
         ArmCooldown();
        }
     }
  }

void CloseOurPositions(const string why)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(g_trade.PositionClose(ticket))
         Print("Closed #", ticket, " (", why, ")");
     }
  }

int CountOurPositions()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      n++;
     }
   return n;
  }

void ArmCooldown()
  {
   const int sec = PeriodSeconds(_Period) * MathMax(1, InpCooldownBars);
   g_cooldownUntil = TimeCurrent() + sec;
  }

//+------------------------------------------------------------------+
//| Risk / session / spread guards                                   |
//+------------------------------------------------------------------+
bool PassesRiskGuards()
  {
   g_paused = false;
   g_pauseWhy = "";

   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_dayStartEquity <= 0.0)
      g_dayStartEquity = equity;

   const double pnlPct = 100.0 * (equity - g_dayStartEquity) / g_dayStartEquity;
   const double closed = ClosedPnLToday();

   if(InpMaxDailyLossPct > 0.0 && (pnlPct <= -InpMaxDailyLossPct || closed <= -(g_dayStartEquity * InpMaxDailyLossPct / 100.0)))
     {
      g_paused = true;
      g_pauseWhy = "daily loss limit";
      g_status = "paused - daily loss";
      return false;
     }
   if(InpMaxDailyProfitPct > 0.0 && pnlPct >= InpMaxDailyProfitPct)
     {
      g_paused = true;
      g_pauseWhy = "daily profit lock";
      g_status = "paused - daily profit";
      return false;
     }
   if(InpMaxTradesPerDay > 0 && g_tradesToday >= InpMaxTradesPerDay)
     {
      g_paused = true;
      g_pauseWhy = "max trades today";
      g_status = "paused - trade cap";
      return false;
     }
   return true;
  }

bool TradingAllowed()
  {
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return false;
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
      return false;
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      return false;
   return true;
  }

bool SpreadOK()
  {
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
      return false;
   g_lastSpreadPts = (ask - bid) / _Point;

   int maxPts = InpMaxSpreadPoints;
   if(maxPts <= 0)
     {
      if(g_instr == INSTR_GOLD)
         maxPts = 50;          // 0.50 on 2-digit gold, 5.0 on 3-digit - see note in README
      else if(g_instr == INSTR_STEP)
         maxPts = 30;
      else
         maxPts = 40;
      // If gold is quoted with 3 digits, 50 points is 0.050 which is too tight.
      // Scale auto cap by typical ATR so it stays instrument-agnostic.
      const double atr = (g_lastATR > 0.0 ? g_lastATR : ReadATR());
      if(atr > 0.0)
        {
         const int atrPts = (int)MathRound(atr / _Point);
         maxPts = MathMax(maxPts, atrPts / 8);
        }
     }
   if(g_lastSpreadPts > maxPts)
     {
      g_lastReason = StringFormat("spread %.1f > max %d", g_lastSpreadPts, maxPts);
      return false;
     }
   return true;
  }

bool InSession()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   const int h = dt.hour;
   if(InpSessionStartHour == InpSessionEndHour)
      return true;
   if(InpSessionStartHour < InpSessionEndHour)
      return (h >= InpSessionStartHour && h < InpSessionEndHour);
   return (h >= InpSessionStartHour || h < InpSessionEndHour);
  }

bool IsFridayFlattenTime()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_week == 5 && dt.hour >= InpFridayCloseHour);
  }

void ResetDailyCounters()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   const int stamp = dt.year * 10000 + dt.mon * 100 + dt.day;
   if(stamp == g_dayStamp)
      return;
   g_dayStamp       = stamp;
   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_tradesToday    = CountDealsToday();
   g_paused         = false;
   g_pauseWhy       = "";
  }

int CountDealsToday()
  {
   datetime start = DayStart();
   if(!HistorySelect(start, TimeCurrent()))
      return 0;
   int n = 0;
   const int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      const ulong t = HistoryDealGetTicket(i);
      if(t == 0)
         continue;
      if(HistoryDealGetString(t, DEAL_SYMBOL) != _Symbol)
         continue;
      if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagic)
         continue;
      if((int)HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;
      n++;
     }
   return n;
  }

double ClosedPnLToday()
  {
   datetime start = DayStart();
   if(!HistorySelect(start, TimeCurrent()))
      return 0.0;
   double pnl = 0.0;
   const int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      const ulong t = HistoryDealGetTicket(i);
      if(t == 0)
         continue;
      if(HistoryDealGetString(t, DEAL_SYMBOL) != _Symbol)
         continue;
      if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagic)
         continue;
      pnl += HistoryDealGetDouble(t, DEAL_PROFIT)
             + HistoryDealGetDouble(t, DEAL_SWAP)
             + HistoryDealGetDouble(t, DEAL_COMMISSION);
     }
   return pnl;
  }

datetime DayStart()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return StructToTime(dt);
  }

bool IsNewBar()
  {
   const datetime t = iTime(_Symbol, _Period, 0);
   if(t == 0)
      return false;
   if(t == g_lastBarTime)
      return false;
   g_lastBarTime = t;
   return true;
  }

double ReadATR()
  {
   double a[];
   if(!ReadBuf(g_atr, 0, 3, a))
      return 0.0;
   return a[1];
  }

double NormalizePrice(const double price)
  {
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0)
      tick = _Point;
   return NormalizeDouble(MathRound(price / tick) * tick, _Digits);
  }

void RefreshRates()
  {
   SymbolInfoTick(_Symbol, g_tick);
  }

//+------------------------------------------------------------------+
//| Panel                                                            |
//+------------------------------------------------------------------+
void DrawPanel()
  {
   const int x = 12;
   int y = 22;
   const int line = 16;

   CreateRect(PANEL_PREFIX + "BG", x - 6, 14, 310, 230);

   Put(PANEL_PREFIX + "T", x, y, EA_NAME + "  v1.10", InpPanelAccent, 11);
   y += line + 4;
   Put(PANEL_PREFIX + "1", x, y, "Symbol   " + _Symbol + "   [" + InstrumentName(g_instr) + "]", InpPanelText, 9);
   y += line;
   Put(PANEL_PREFIX + "2", x, y, "Strategy " + StrategyName(g_strategy) + "   TF " + TFstr(_Period), InpPanelText, 9);
   y += line;
   Put(PANEL_PREFIX + "3", x, y, "AutoTrade " + (InpAutoTrade ? "ON" : "OFF") + "   Algo " + (TradingAllowed() ? "OK" : "BLOCKED"),
       TradingAllowed() && InpAutoTrade ? clrLime : clrOrangeRed, 9);
   y += line;
   Put(PANEL_PREFIX + "4", x, y, "Status   " + g_status, StatusColor(), 9);
   y += line;
   Put(PANEL_PREFIX + "5", x, y,
       StringFormat("Score    %d / 9   need %d   last %s",
                    g_lastScore, InpMinScore, (g_lastSignal > 0 ? "BUY" : (g_lastSignal < 0 ? "SELL" : "-"))),
       InpPanelText, 9);
   y += line;
   Put(PANEL_PREFIX + "6", x, y, Trunc("Reason   " + g_lastReason, 42), clrSilver, 9);
   y += line;
   Put(PANEL_PREFIX + "7", x, y,
       StringFormat("Spread   %.1f pts    ATR %s", g_lastSpreadPts, DoubleToString(g_lastATR, _Digits)),
       InpPanelText, 9);
   y += line;
   Put(PANEL_PREFIX + "8", x, y,
       StringFormat("Risk     %.2f%%    positions %d/%d    trades %d/%d",
                    InpRiskPercent, CountOurPositions(), InpMaxPositions, g_tradesToday, InpMaxTradesPerDay),
       InpPanelText, 9);
   y += line;
   const double pnl = ClosedPnLToday();
   Put(PANEL_PREFIX + "9", x, y,
       StringFormat("Day P/L  %s   equity %s",
                    DoubleToString(pnl, 2), DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2)),
       pnl >= 0.0 ? clrLime : clrOrangeRed, 9);
   y += line;
   Put(PANEL_PREFIX + "10", x, y,
       g_paused ? ("PAUSED  " + g_pauseWhy) : "Scanning closed bars - no martingale / no grid",
       g_paused ? clrOrangeRed : clrGray, 9);
   y += line;
   Put(PANEL_PREFIX + "11", x, y, "Windows/VPS run  |  Android = monitor only", clrDimGray, 8);

   ChartRedraw(0);
  }

void Put(const string name, const int x, const int y, const string text, const color clr, const int size)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
  }

void CreateRect(const string name, const int x, const int y, const int w, const int h)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C'12,16,28');
      ObjectSetInteger(0, name, OBJPROP_COLOR, C'198,160,64');
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
  }

void DeletePanel()
  {
   ObjectsDeleteAll(0, PANEL_PREFIX);
  }

color StatusColor()
  {
   if(StringFind(g_status, "BUY") >= 0 || StringFind(g_status, "SELL") >= 0)
      return clrLime;
   if(StringFind(g_status, "fail") >= 0 || StringFind(g_status, "BLOCK") >= 0 || StringFind(g_status, "paused") >= 0)
      return clrOrangeRed;
   if(StringFind(g_status, "spread") >= 0 || StringFind(g_status, "session") >= 0)
      return clrOrange;
   return InpPanelAccent;
  }

string TFstr(const ENUM_TIMEFRAMES tf)
  {
   return StringSubstr(EnumToString(tf), 7);
  }

string Trunc(const string s, const int n)
  {
   if(StringLen(s) <= n)
      return s;
   return StringSubstr(s, 0, n - 1) + "...";
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(trans.symbol != _Symbol)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic)
      return;
   const long reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   if(reason == DEAL_REASON_SL)
      ArmCooldown();
  }

double OnTester()
  {
   return TesterStatistics(STAT_PROFIT_FACTOR);
  }
//+------------------------------------------------------------------+
