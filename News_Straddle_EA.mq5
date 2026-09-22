#property strict
#property version   "1.00"
#property description "News Straddle / Breakout EA for MetaTrader 5"
#property description "Buy Stop + Sell Stop with OCO, SL/TP and Trailing Stop"

input group "=== ORDER SETTINGS ==="
input double InpLotSize             = 0.10;
input int    InpDistancePoints      = 300;
input int    InpStopLossPoints      = 500;
input int    InpTakeProfitPoints    = 1000;

input group "=== TRAILING STOP ==="
input bool   InpUseTrailing         = true;
input int    InpTrailingStopPoints  = 300;
input int    InpTrailingStepPoints  = 50;

input group "=== EA SETTINGS ==="
input ulong  InpMagicNumber         = 20260923;
input int    InpSlippagePoints      = 30;

input group "=== STRADDLE SETTINGS ==="
input bool   InpAutoPlaceOrders     = false;
input bool   InpDeleteAfterPosition = true;

input group "=== MANUAL BUTTONS ==="
input bool   InpShowButtons         = true;

string BTN_PLACE  = "NEWS_STRADDLE_PLACE";
string BTN_DELETE = "NEWS_STRADDLE_DELETE";
bool g_ordersPlaced = false;

int OnInit()
{
   if(InpLotSize <= 0 || InpDistancePoints <= 0 ||
      InpStopLossPoints < 0 || InpTakeProfitPoints < 0)
      return(INIT_PARAMETERS_INCORRECT);

   if(InpUseTrailing &&
      (InpTrailingStopPoints <= 0 || InpTrailingStepPoints < 0))
      return(INIT_PARAMETERS_INCORRECT);

   if(InpShowButtons)
      CreateButtons();

   if(InpAutoPlaceOrders && !HasOurPosition() && !HasOurPendingOrders())
      PlaceStraddleOrders();

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   ObjectDelete(0, BTN_PLACE);
   ObjectDelete(0, BTN_DELETE);
}

void OnTick()
{
   if(InpDeleteAfterPosition && HasOurPosition())
      DeleteOurPendingOrders();

   if(InpUseTrailing)
      ManageTrailingStop();

   if(InpAutoPlaceOrders && !HasOurPosition() && !HasOurPendingOrders())
      PlaceStraddleOrders();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD &&
      InpDeleteAfterPosition && HasOurPosition())
      DeleteOurPendingOrders();
}

void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam == BTN_PLACE)
   {
      PlaceStraddleOrders();
      ObjectSetInteger(0, BTN_PLACE, OBJPROP_STATE, false);
   }
   else if(sparam == BTN_DELETE)
   {
      DeleteOurPendingOrders();
      ObjectSetInteger(0, BTN_DELETE, OBJPROP_STATE, false);
   }

   ChartRedraw();
}

bool PlaceStraddleOrders()
{
   if(HasOurPosition() || HasOurPendingOrders())
      return(false);

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return(false);

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double buyPrice  = NormalizeDouble(tick.ask + InpDistancePoints * point, digits);
   double sellPrice = NormalizeDouble(tick.bid - InpDistancePoints * point, digits);

   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stopsLevel * point;

   if(buyPrice - tick.ask < minDist)
      buyPrice = NormalizeDouble(tick.ask + minDist, digits);

   if(tick.bid - sellPrice < minDist)
      sellPrice = NormalizeDouble(tick.bid - minDist, digits);

   double volume = NormalizeVolume(InpLotSize);
   if(volume <= 0)
      return(false);

   bool buyResult = PlaceBuyStop(buyPrice, volume);
   bool sellResult = PlaceSellStop(sellPrice, volume);

   if(buyResult || sellResult)
   {
      g_ordersPlaced = true;
      return(true);
   }

   return(false);
}

bool PlaceBuyStop(double price, double volume)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_PENDING;
   request.symbol = _Symbol;
   request.volume = volume;
   request.type = ORDER_TYPE_BUY_STOP;
   request.price = price;
   request.magic = InpMagicNumber;
   request.deviation = InpSlippagePoints;
   request.type_filling = ORDER_FILLING_RETURN;
   request.type_time = ORDER_TIME_GTC;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(InpStopLossPoints > 0)
      request.sl = NormalizeDouble(price - InpStopLossPoints * point, digits);

   if(InpTakeProfitPoints > 0)
      request.tp = NormalizeDouble(price + InpTakeProfitPoints * point, digits);

   request.comment = "NewsStraddle BUY";

   ResetLastError();
   if(!OrderSend(request, result))
      return(false);

   if(result.retcode != TRADE_RETCODE_DONE &&
      result.retcode != TRADE_RETCODE_PLACED)
      return(false);

   return(true);
}

bool PlaceSellStop(double price, double volume)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_PENDING;
   request.symbol = _Symbol;
   request.volume = volume;
   request.type = ORDER_TYPE_SELL_STOP;
   request.price = price;
   request.magic = InpMagicNumber;
   request.deviation = InpSlippagePoints;
   request.type_filling = ORDER_FILLING_RETURN;
   request.type_time = ORDER_TIME_GTC;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(InpStopLossPoints > 0)
      request.sl = NormalizeDouble(price + InpStopLossPoints * point, digits);

   if(InpTakeProfitPoints > 0)
      request.tp = NormalizeDouble(price - InpTakeProfitPoints * point, digits);

   request.comment = "NewsStraddle SELL";

   ResetLastError();
   if(!OrderSend(request, result))
      return(false);

   if(result.retcode != TRADE_RETCODE_DONE &&
      result.retcode != TRADE_RETCODE_PLACED)
      return(false);

   return(true);
}

void DeleteOurPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;

      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;

      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber)
         continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type != ORDER_TYPE_BUY_STOP && type != ORDER_TYPE_SELL_STOP)
         continue;

      MqlTradeRequest request;
      MqlTradeResult result;
      ZeroMemory(request);
      ZeroMemory(result);

      request.action = TRADE_ACTION_REMOVE;
      request.order = ticket;
      request.symbol = _Symbol;
      request.magic = InpMagicNumber;

      OrderSend(request, result);
   }

   g_ordersPlaced = false;
}

bool HasOurPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;

      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;

      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber)
         continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP)
         return(true);
   }

   return(false);
}

bool HasOurPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         return(true);
   }

   return(false);
}

void ManageTrailingStop()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      ENUM_POSITION_TYPE type =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      double newSL = 0.0;
      bool modify = false;

      if(type == POSITION_TYPE_BUY)
      {
         double profitPoints = (tick.bid - openPrice) / point;
         if(profitPoints < InpTrailingStopPoints)
            continue;

         newSL = NormalizeDouble(
            tick.bid - InpTrailingStopPoints * point, digits);

         if(currentSL == 0.0 ||
            newSL > currentSL + InpTrailingStepPoints * point)
            modify = true;
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double profitPoints = (openPrice - tick.ask) / point;
         if(profitPoints < InpTrailingStopPoints)
            continue;

         newSL = NormalizeDouble(
            tick.ask + InpTrailingStopPoints * point, digits);

         if(currentSL == 0.0 ||
            newSL < currentSL - InpTrailingStepPoints * point)
            modify = true;
      }

      if(modify)
         ModifyPosition(ticket, newSL, currentTP);
   }
}

bool ModifyPosition(ulong ticket, double newSL, double newTP)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol = _Symbol;
   request.magic = InpMagicNumber;
   request.sl = newSL;
   request.tp = newTP;

   if(!OrderSend(request, result))
      return(false);

   return(result.retcode == TRADE_RETCODE_DONE);
}

double NormalizeVolume(double volume)
{
   double minVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(stepVolume <= 0 || volume < minVolume)
      return(0);

   if(volume > maxVolume)
      volume = maxVolume;

   double normalized = MathFloor(volume / stepVolume) * stepVolume;

   int digits = 2;
   if(stepVolume >= 1.0) digits = 0;
   else if(stepVolume >= 0.1) digits = 1;
   else if(stepVolume >= 0.01) digits = 2;
   else if(stepVolume >= 0.001) digits = 3;

   return(NormalizeDouble(normalized, digits));
}

void CreateButtons()
{
   ObjectDelete(0, BTN_PLACE);
   ObjectDelete(0, BTN_DELETE);

   ObjectCreate(0, BTN_PLACE, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, BTN_PLACE, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, BTN_PLACE, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, BTN_PLACE, OBJPROP_YDISTANCE, 30);
   ObjectSetInteger(0, BTN_PLACE, OBJPROP_XSIZE, 160);
   ObjectSetInteger(0, BTN_PLACE, OBJPROP_YSIZE, 35);
   ObjectSetString(0, BTN_PLACE, OBJPROP_TEXT, "PLACE STRADDLE");
   ObjectSetInteger(0, BTN_PLACE, OBJPROP_FONTSIZE, 10);

   ObjectCreate(0, BTN_DELETE, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, BTN_DELETE, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, BTN_DELETE, OBJPROP_XDISTANCE, 180);
   ObjectSetInteger(0, BTN_DELETE, OBJPROP_YDISTANCE, 30);
   ObjectSetInteger(0, BTN_DELETE, OBJPROP_XSIZE, 160);
   ObjectSetInteger(0, BTN_DELETE, OBJPROP_YSIZE, 35);
   ObjectSetString(0, BTN_DELETE, OBJPROP_TEXT, "DELETE PENDING");
   ObjectSetInteger(0, BTN_DELETE, OBJPROP_FONTSIZE, 10);

   ChartRedraw();
}
