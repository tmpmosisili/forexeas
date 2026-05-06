#property strict
#property version "8.0"

// =====================================================
// ======== USER INPUTS =================================
// =====================================================

// --- Core Trading ---
input int      Magic_Number     = 1680673860;
input double   Entry_Amount     = 0.01;

// --- ATR SL/TP ---
input bool     Use_ATR_SLTP     = true;
input int      ATR_Period       = 14;
input double   ATR_SL_Mult      = 1.2;   // tighter for EURUSD
input double   ATR_TP_Mult      = 2.0;

// --- Fixed fallback ---
input int      Stop_Loss_Pips   = 25;
input int      Take_Profit_Pips = 50;

// --- Trend Filter ---
input int      ADX_Period       = 21;
input double   ADX_Min_Level    = 20.0;

// --- EMA ---
input int      Fast_EMA         = 20;
input int      Slow_EMA         = 50;

// --- Session Filter (SA Time) ---
input int StartHour = 9;
input int EndHour   = 17;

// --- Spread Filter ---
input double MaxSpreadPoints = 20;

// --- News Filter ---
input bool   UseNewsFilter      = true;
input int    NewsMinutesBefore  = 30;
input int    NewsMinutesAfter   = 30;

// =====================================================
int adxHandle, fastEmaHandle, slowEmaHandle, atrHandle;
double pip;

// =====================================================
int OnInit()
{
   pip = (_Digits == 5 || _Digits == 3) ? _Point * 10 : _Point;

   adxHandle     = iADX(_Symbol, _Period, ADX_Period);
   fastEmaHandle = iMA (_Symbol, _Period, Fast_EMA, 0, MODE_EMA, PRICE_CLOSE);
   slowEmaHandle = iMA (_Symbol, _Period, Slow_EMA, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle     = iATR(_Symbol, _Period, ATR_Period);

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(adxHandle);
   IndicatorRelease(fastEmaHandle);
   IndicatorRelease(slowEmaHandle);
   IndicatorRelease(atrHandle);
}

// =====================================================
void OnTick()
{
   static datetime lastBar = 0;
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar == lastBar) return;
   lastBar = curBar;

   // --- SESSION FILTER ---
   int hour = TimeHour(TimeCurrent());
   if(hour < StartHour || hour > EndHour)
      return;

   // --- SPREAD FILTER ---
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = (ask - bid) / _Point;
   if(spread > MaxSpreadPoints)
      return;

   // --- NEWS FILTER ---
   if(UseNewsFilter && IsHighImpactNews())
      return;

   if(HasOpenPosition()) return;

   int signal = GetEntrySignal();
   if(signal != 0)
      OpenTrade(signal, bid, ask);
}

// =====================================================
bool IsHighImpactNews()
{
   datetime now = TimeCurrent();

   MqlCalendarValue values[];
   datetime from = now - 3600;
   datetime to   = now + 3600;

   if(CalendarValueHistory(values, from, to) <= 0)
      return false;

   for(int i=0; i<ArraySize(values); i++)
   {
      if(values[i].importance == CALENDAR_IMPORTANCE_HIGH)
      {
         datetime newsTime = values[i].time;
         if(MathAbs((int)(newsTime - now)) <= NewsMinutesBefore * 60)
            return true;
      }
   }
   return false;
}

// =====================================================
int GetEntrySignal()
{
   double adx[], emaFast[], emaSlow[];

   if(CopyBuffer(adxHandle, 0, 1, 1, adx) <= 0) return 0;
   if(CopyBuffer(fastEmaHandle, 0, 1, 2, emaFast) <= 0) return 0;
   if(CopyBuffer(slowEmaHandle, 0, 1, 2, emaSlow) <= 0) return 0;

   if(adx[0] < ADX_Min_Level)
      return 0;

   bool crossUp   = emaFast[1] < emaSlow[1] && emaFast[0] > emaSlow[0];
   bool crossDown = emaFast[1] > emaSlow[1] && emaFast[0] < emaSlow[0];

   if(crossUp)   return ORDER_TYPE_BUY;
   if(crossDown) return ORDER_TYPE_SELL;

   return 0;
}

// =====================================================
void OpenTrade(int type, double bid, double ask)
{
   double sl = GetStopLoss(type, bid, ask);
   double tp = GetTakeProfit(type, bid, ask);

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action   = TRADE_ACTION_DEAL;
   req.symbol   = _Symbol;
   req.volume   = Entry_Amount;
   req.type     = type;
   req.price    = (type == ORDER_TYPE_BUY) ? ask : bid;
   req.sl       = sl;
   req.tp       = tp;
   req.magic    = Magic_Number;
   req.deviation= 10;

   if(!OrderSend(req, res))
   {
      Print("OrderSend failed: ", GetLastError());
      return;
   }

   if(res.retcode != TRADE_RETCODE_DONE)
   {
      Print("Trade failed: ", res.retcode);
   }
   else
   {
      Print("Trade opened. Ticket: ", res.order);
   }
}

// =====================================================
double GetStopLoss(int type, double bid, double ask)
{
   double atr[];
   if(CopyBuffer(atrHandle, 0, 1, 1, atr) <= 0) return 0;

   double d = atr[0] * ATR_SL_Mult;
   return NormalizeDouble(type == ORDER_TYPE_BUY ? bid - d : ask + d, _Digits);
}

double GetTakeProfit(int type, double bid, double ask)
{
   double atr[];
   if(CopyBuffer(atrHandle, 0, 1, 1, atr) <= 0) return 0;

   double d = atr[0] * ATR_TP_Mult;
   return NormalizeDouble(type == ORDER_TYPE_BUY ? bid + d : ask - d, _Digits);
}

// =====================================================
bool HasOpenPosition()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         if(PositionGetInteger(POSITION_MAGIC)==Magic_Number &&
            PositionGetString(POSITION_SYMBOL)==_Symbol)
            return true;
   }
   return false;
}
