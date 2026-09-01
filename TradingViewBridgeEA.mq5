//+------------------------------------------------------------------+
//| TradingViewBridgeEA.mq5                                         |
//| Reads TradingView webhook signals from Common\Files\tv_signal.csv |
//| and places MT5 market orders.                                   |
//+------------------------------------------------------------------+
#property strict
#property version   "1.05"

#include <Trade/Trade.mqh>

input string SignalFileName = "tv_signal.csv";
input string ProcessedIdsFileName = "tv_signal_processed_ids.txt";
input string LogFileName = "tv_bridge_ea.log";
input int PollSeconds = 1;
input int DeviationPoints = 20;
input ulong MagicNumber = 20260623;
input int MaxProcessedIdsInMemory = 1000;
input bool ProcessExistingSignalsOnStart = false;

CTrade trade;
string processed_ids[];
int effective_poll_seconds = 1;
datetime last_poll_local = 0;
datetime last_heartbeat_local = 0;
int poll_count = 0;
string last_status = "initializing";

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(DeviationPoints);

   LoadProcessedIds();
   if(!ProcessExistingSignalsOnStart)
      MarkExistingSignalIdsProcessed();

   effective_poll_seconds = PollSeconds;
   if(effective_poll_seconds < 1)
      effective_poll_seconds = 1;
   EventSetTimer(effective_poll_seconds);

   LogLine("EA started. Common files path: " + TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files");
   LogLine("Watching signal file: " + SignalFileName + " poll_seconds=" + IntegerToString(effective_poll_seconds));
   UpdateChartStatus("running");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   Comment("");
   LogLine("EA stopped. reason=" + IntegerToString(reason));
}

void OnTimer()
{
   MaybeProcessSignalFile("timer");
}

void OnTick()
{
   MaybeProcessSignalFile("tick");
}

void MaybeProcessSignalFile(const string source)
{
   datetime now = TimeLocal();
   if(last_poll_local != 0 && now - last_poll_local < effective_poll_seconds)
      return;

   last_poll_local = now;
   poll_count++;
   ProcessSignalFile(source);
}

void ProcessSignalFile(const string source)
{
   if(TimeLocal() - last_heartbeat_local >= 30)
   {
      last_heartbeat_local = TimeLocal();
      LogLine("Heartbeat source=" + source +
              " polls=" + IntegerToString(poll_count) +
              " signal_exists=" + BoolText(FileIsExist(SignalFileName, FILE_COMMON)) +
              " processed_ids=" + IntegerToString(ArraySize(processed_ids)));
   }

   int handle = FileOpen(SignalFileName, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(handle == INVALID_HANDLE)
   {
      int err = GetLastError();
      if(err != 5004)
         LogLine("Cannot open signal file " + SignalFileName + ". error=" + IntegerToString(err));
      last_status = "waiting for " + SignalFileName;
      UpdateChartStatus(last_status);
      ResetLastError();
      return;
   }

   int rows_seen = 0;
   int new_rows = 0;
   while(!FileIsEnding(handle))
   {
      string line = FileReadString(handle);
      StringTrimLeft(line);
      StringTrimRight(line);
      if(FileIsEnding(handle) && line == "")
         break;
      if(line == "")
         continue;

      string timestamp = "";
      string signal_id = "";
      string action = "";
      string symbol = "";
      string trade_type = "";
      string lot_text = "";
      string sl_text = "";
      string tp_text = "";

      if(!ParseSignalLine(line, timestamp, signal_id, action, symbol, trade_type, lot_text, sl_text, tp_text))
      {
         LogLine("Skipped malformed signal line: " + line);
         continue;
      }
      if(IsHeaderRow(timestamp, signal_id))
         continue;
      rows_seen++;
      if(signal_id == "" || action == "" || symbol == "")
      {
         LogLine("Skipped malformed signal row number=" + IntegerToString(rows_seen) +
                 " timestamp=" + timestamp +
                 " id=" + signal_id +
                 " action=" + action +
                 " symbol=" + symbol +
                 " trade_type=" + trade_type);
         continue;
      }
      if(IsProcessed(signal_id))
         continue;

      new_rows++;
      double lot = StringToDouble(lot_text);
      double sl = StringToDouble(sl_text);
      double tp = StringToDouble(tp_text);

      LogLine("Received signal id=" + signal_id +
              " timestamp=" + timestamp +
              " action=" + action +
              " symbol=" + symbol +
              " trade_type=" + trade_type +
              " lot=" + DoubleToString(lot, 8) +
              " sl=" + DoubleToString(sl, 8) +
              " tp=" + DoubleToString(tp, 8));

      ExecuteSignal(signal_id, action, symbol, trade_type, lot, sl, tp);
      RememberProcessedId(signal_id);
   }

   FileClose(handle);
   last_status = "polls=" + IntegerToString(poll_count) +
                 " rows=" + IntegerToString(rows_seen) +
                 " new=" + IntegerToString(new_rows);
   UpdateChartStatus(last_status);
}

bool ParseSignalLine(const string line, string &timestamp, string &signal_id, string &action, string &symbol, string &trade_type, string &lot_text, string &sl_text, string &tp_text)
{
   string fields[];
   ushort comma = StringGetCharacter(",", 0);
   int count = StringSplit(line, comma, fields);
   if(count < 7)
      return false;

   for(int i = 0; i < count; i++)
   {
      StringTrimLeft(fields[i]);
      StringTrimRight(fields[i]);
   }

   timestamp = fields[0];
   signal_id = fields[1];
   action = fields[2];
   symbol = fields[3];

   if(count >= 8)
   {
      trade_type = fields[4];
      lot_text = fields[5];
      sl_text = fields[6];
      tp_text = fields[7];
   }
   else
   {
      trade_type = "";
      lot_text = fields[4];
      sl_text = fields[5];
      tp_text = fields[6];
   }

   return true;
}

bool IsHeaderRow(const string timestamp, const string signal_id)
{
   return timestamp == "timestamp" && signal_id == "id";
}

string NormalizeTradeType(const string trade_type)
{
   string value = trade_type;
   StringTrimLeft(value);
   StringTrimRight(value);
   StringToLower(value);
   return value;
}

string PositionCommentForTradeType(const string trade_type)
{
   return "TV:" + trade_type;
}

bool PositionCommentMatchesTradeType(const string comment, const string trade_type)
{
   string expected = PositionCommentForTradeType(trade_type);
   return comment == expected;
}

bool ExecuteSignal(const string signal_id, const string action, const string symbol, const string trade_type, const double lot, const double sl, const double tp)
{
   if(action == "close_all")
      return CloseAllBridgePositions(signal_id, symbol);

   if(action != "buy" && action != "sell")
   {
      LogLine("Rejected signal id=" + signal_id + " invalid action=" + action);
      return false;
   }

   string normalized_trade_type = NormalizeTradeType(trade_type);
   if(normalized_trade_type == "")
   {
      LogLine("Rejected signal id=" + signal_id + " missing trade_type");
      return false;
   }

   if(lot <= 0.0 || sl <= 0.0 || tp <= 0.0)
   {
      LogLine("Rejected signal id=" + signal_id + " invalid numeric values");
      return false;
   }

   if(!SymbolSelect(symbol, true))
   {
      LogLine("Rejected signal id=" + signal_id + " cannot select symbol=" + symbol + " error=" + IntegerToString(GetLastError()));
      ResetLastError();
      return false;
   }

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
   {
      LogLine("Rejected signal id=" + signal_id + " no valid market tick for symbol=" + symbol);
      return false;
   }

   if(!ValidateStops(signal_id, action, symbol, sl, tp, tick))
      return false;

   if(!ValidateVolume(signal_id, symbol, lot))
      return false;

   ulong matching_tickets[];
   CollectMatchingBridgePositionTickets(action, symbol, normalized_trade_type, matching_tickets);

   string comment = PositionCommentForTradeType(normalized_trade_type);
   bool sent = false;
   if(action == "buy")
      sent = trade.Buy(lot, symbol, 0.0, sl, tp, comment);
   else
      sent = trade.Sell(lot, symbol, 0.0, sl, tp, comment);

   uint retcode = trade.ResultRetcode();
   string ret_desc = trade.ResultRetcodeDescription();

   if(sent && IsSuccessfulRetcode(retcode))
   {
      LogLine("Executed trade id=" + signal_id +
              " action=" + action +
              " symbol=" + symbol +
              " trade_type=" + normalized_trade_type +
              " lot=" + DoubleToString(lot, 8) +
              " order=" + IntegerToString((long)trade.ResultOrder()) +
              " deal=" + IntegerToString((long)trade.ResultDeal()) +
              " retcode=" + IntegerToString((int)retcode) +
              " " + ret_desc);

      bool updated = TryModifyMatchingBridgePositions(signal_id, action, symbol, normalized_trade_type, sl, tp, matching_tickets);
      return updated;
   }

   LogLine("Trade failed id=" + signal_id +
           " action=" + action +
           " symbol=" + symbol +
           " trade_type=" + normalized_trade_type +
           " retcode=" + IntegerToString((int)retcode) +
           " " + ret_desc +
           " last_error=" + IntegerToString(GetLastError()));
   ResetLastError();
   return false;
}

bool CloseAllBridgePositions(const string signal_id, const string symbol)
{
   if(!SymbolSelect(symbol, true))
   {
      LogLine("Rejected close_all id=" + signal_id + " cannot select symbol=" + symbol + " error=" + IntegerToString(GetLastError()));
      ResetLastError();
      return false;
   }

   int matched = 0;
   int closed = 0;
   int failed = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      string pos_symbol = PositionGetString(POSITION_SYMBOL);
      long pos_magic = PositionGetInteger(POSITION_MAGIC);

      if(pos_symbol != symbol || (ulong)pos_magic != MagicNumber)
         continue;

      matched++;
      double volume = PositionGetDouble(POSITION_VOLUME);
      long pos_type = PositionGetInteger(POSITION_TYPE);
      string type_text = pos_type == POSITION_TYPE_BUY ? "buy" : "sell";

      bool sent = trade.PositionClose(ticket);
      uint retcode = trade.ResultRetcode();
      string ret_desc = trade.ResultRetcodeDescription();

      if(sent && IsSuccessfulRetcode(retcode))
      {
         closed++;
         LogLine("Closed position id=" + signal_id +
                 " ticket=" + IntegerToString((long)ticket) +
                 " symbol=" + symbol +
                 " type=" + type_text +
                 " volume=" + DoubleToString(volume, 8) +
                 " retcode=" + IntegerToString((int)retcode) +
                 " " + ret_desc);
      }
      else
      {
         failed++;
         LogLine("Close position failed id=" + signal_id +
                 " ticket=" + IntegerToString((long)ticket) +
                 " symbol=" + symbol +
                 " type=" + type_text +
                 " retcode=" + IntegerToString((int)retcode) +
                 " " + ret_desc +
                 " last_error=" + IntegerToString(GetLastError()));
         ResetLastError();
      }
   }

   LogLine("Executed close_all id=" + signal_id +
           " symbol=" + symbol +
           " matched=" + IntegerToString(matched) +
           " closed=" + IntegerToString(closed) +
           " failed=" + IntegerToString(failed));

   return failed == 0;
}

void CollectMatchingBridgePositionTickets(const string action, const string symbol, const string trade_type, ulong &tickets[])
{
   ArrayResize(tickets, 0);
   long expected_type = action == "buy" ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      string pos_symbol = PositionGetString(POSITION_SYMBOL);
      long pos_magic = PositionGetInteger(POSITION_MAGIC);
      long pos_type = PositionGetInteger(POSITION_TYPE);
      string pos_comment = PositionGetString(POSITION_COMMENT);

      if(pos_symbol != symbol ||
         (ulong)pos_magic != MagicNumber ||
         pos_type != expected_type ||
         !PositionCommentMatchesTradeType(pos_comment, trade_type))
         continue;

      int size = ArraySize(tickets);
      ArrayResize(tickets, size + 1);
      tickets[size] = ticket;
   }
}

bool TryModifyMatchingBridgePositions(const string signal_id, const string action, const string symbol, const string trade_type, const double sl, const double tp, const ulong &tickets[])
{
   int matched = ArraySize(tickets);
   int modified = 0;
   int failed = 0;

   for(int i = 0; i < matched; i++)
   {
      ulong ticket = tickets[i];
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
      {
         failed++;
         LogLine("Modify matching position failed id=" + signal_id +
                 " ticket=" + IntegerToString((long)ticket) +
                 " symbol=" + symbol +
                 " action=" + action +
                 " trade_type=" + trade_type +
                 " reason=position not found after new trade");
         continue;
      }

      long expected_type = action == "buy" ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      string pos_symbol = PositionGetString(POSITION_SYMBOL);
      long pos_magic = PositionGetInteger(POSITION_MAGIC);
      long pos_type = PositionGetInteger(POSITION_TYPE);
      string pos_comment = PositionGetString(POSITION_COMMENT);

      if(pos_symbol != symbol ||
         (ulong)pos_magic != MagicNumber ||
         pos_type != expected_type ||
         !PositionCommentMatchesTradeType(pos_comment, trade_type))
      {
         failed++;
         LogLine("Modify matching position skipped id=" + signal_id +
                 " ticket=" + IntegerToString((long)ticket) +
                 " symbol=" + symbol +
                 " action=" + action +
                 " trade_type=" + trade_type +
                 " reason=position changed before SL/TP update");
         continue;
      }

      double old_sl = PositionGetDouble(POSITION_SL);
      double old_tp = PositionGetDouble(POSITION_TP);
      double volume = PositionGetDouble(POSITION_VOLUME);

      bool sent = trade.PositionModify(ticket, sl, tp);
      uint retcode = trade.ResultRetcode();
      string ret_desc = trade.ResultRetcodeDescription();

      if(sent && IsSuccessfulRetcode(retcode))
      {
         modified++;
         LogLine("Modified matching position id=" + signal_id +
                 " ticket=" + IntegerToString((long)ticket) +
                 " symbol=" + symbol +
                 " action=" + action +
                 " trade_type=" + trade_type +
                 " volume=" + DoubleToString(volume, 8) +
                 " old_sl=" + DoubleToString(old_sl, 8) +
                 " old_tp=" + DoubleToString(old_tp, 8) +
                 " new_sl=" + DoubleToString(sl, 8) +
                 " new_tp=" + DoubleToString(tp, 8) +
                 " retcode=" + IntegerToString((int)retcode) +
                 " " + ret_desc);
      }
      else
      {
         failed++;
         LogLine("Modify matching position failed id=" + signal_id +
                 " ticket=" + IntegerToString((long)ticket) +
                 " symbol=" + symbol +
                 " action=" + action +
                 " trade_type=" + trade_type +
                 " retcode=" + IntegerToString((int)retcode) +
                 " " + ret_desc +
                 " last_error=" + IntegerToString(GetLastError()));
         ResetLastError();
      }
   }

   if(matched > 0)
   {
      LogLine("Updated pre-existing same-type positions after new trade id=" + signal_id +
              " symbol=" + symbol +
              " action=" + action +
              " trade_type=" + trade_type +
              " modified=" + IntegerToString(modified) +
              " failed=" + IntegerToString(failed));
   }

   return failed == 0;
}

bool ValidateStops(const string signal_id, const string action, const string symbol, const double sl, const double tp, const MqlTick &tick)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   long stops_level_points = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double min_distance = (double)stops_level_points * point;

   if(action == "buy")
   {
      if(sl >= tick.ask || tp <= tick.ask)
      {
         LogLine("Rejected signal id=" + signal_id + " invalid buy SL/TP for ask=" + DoubleToString(tick.ask, digits));
         return false;
      }
      if(min_distance > 0.0 && (tick.ask - sl < min_distance || tp - tick.ask < min_distance))
      {
         LogLine("Rejected signal id=" + signal_id + " buy SL/TP too close to market");
         return false;
      }
   }
   else
   {
      if(sl <= tick.bid || tp >= tick.bid)
      {
         LogLine("Rejected signal id=" + signal_id + " invalid sell SL/TP for bid=" + DoubleToString(tick.bid, digits));
         return false;
      }
      if(min_distance > 0.0 && (sl - tick.bid < min_distance || tick.bid - tp < min_distance))
      {
         LogLine("Rejected signal id=" + signal_id + " sell SL/TP too close to market");
         return false;
      }
   }

   return true;
}

bool ValidateVolume(const string signal_id, const string symbol, const double lot)
{
   double min_volume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   if(lot < min_volume || lot > max_volume)
   {
      LogLine("Rejected signal id=" + signal_id +
              " volume out of range. lot=" + DoubleToString(lot, 8) +
              " min=" + DoubleToString(min_volume, 8) +
              " max=" + DoubleToString(max_volume, 8));
      return false;
   }

   return true;
}

bool IsSuccessfulRetcode(const uint retcode)
{
   return retcode == TRADE_RETCODE_DONE ||
          retcode == TRADE_RETCODE_PLACED ||
          retcode == TRADE_RETCODE_DONE_PARTIAL;
}

bool IsProcessed(const string signal_id)
{
   for(int i = 0; i < ArraySize(processed_ids); i++)
   {
      if(processed_ids[i] == signal_id)
         return true;
   }
   return false;
}

void RememberProcessedId(const string signal_id)
{
   if(!AddProcessedId(signal_id))
      return;

   TrimProcessedIds();
   SaveProcessedIds();
}

bool AddProcessedId(const string signal_id)
{
   if(signal_id == "" || IsProcessed(signal_id))
      return false;

   int size = ArraySize(processed_ids);
   ArrayResize(processed_ids, size + 1);
   processed_ids[size] = signal_id;
   return true;
}

void TrimProcessedIds()
{
   int size = ArraySize(processed_ids);
   int limit = MaxProcessedIdsInMemory;
   if(limit < 1)
      limit = 1;
   if(size <= limit)
      return;

   int remove_count = size - limit;
   for(int i = remove_count; i < size; i++)
      processed_ids[i - remove_count] = processed_ids[i];
   ArrayResize(processed_ids, limit);
}

void LoadProcessedIds()
{
   ArrayResize(processed_ids, 0);

   int handle = FileOpen(ProcessedIdsFileName, FILE_READ | FILE_TXT | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(handle == INVALID_HANDLE)
   {
      ResetLastError();
      return;
   }

   while(!FileIsEnding(handle))
   {
      string id = FileReadString(handle);
      StringTrimLeft(id);
      StringTrimRight(id);
      if(id == "")
         continue;

      int size = ArraySize(processed_ids);
      ArrayResize(processed_ids, size + 1);
      processed_ids[size] = id;
   }

   FileClose(handle);
   TrimProcessedIds();
}

void MarkExistingSignalIdsProcessed()
{
   int handle = FileOpen(SignalFileName, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(handle == INVALID_HANDLE)
   {
      ResetLastError();
      return;
   }

   int marked = 0;
   while(!FileIsEnding(handle))
   {
      string line = FileReadString(handle);
      StringTrimLeft(line);
      StringTrimRight(line);
      if(FileIsEnding(handle) && line == "")
         break;
      if(line == "")
         continue;

      string timestamp = "";
      string signal_id = "";
      string action = "";
      string symbol = "";
      string trade_type = "";
      string lot_text = "";
      string sl_text = "";
      string tp_text = "";

      if(!ParseSignalLine(line, timestamp, signal_id, action, symbol, trade_type, lot_text, sl_text, tp_text))
         continue;
      if(IsHeaderRow(timestamp, signal_id))
         continue;
      if(signal_id == "")
         continue;
      if(AddProcessedId(signal_id))
         marked++;
   }

   FileClose(handle);
   if(marked > 0)
   {
      TrimProcessedIds();
      SaveProcessedIds();
      LogLine("Marked existing startup signal ids as processed. count=" + IntegerToString(marked));
   }
}

void SaveProcessedIds()
{
   int handle = FileOpen(ProcessedIdsFileName, FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(handle == INVALID_HANDLE)
   {
      LogLine("Cannot save processed ids. error=" + IntegerToString(GetLastError()));
      ResetLastError();
      return;
   }

   for(int i = 0; i < ArraySize(processed_ids); i++)
      FileWriteString(handle, processed_ids[i] + "\r\n");

   FileClose(handle);
}

void LogLine(const string message)
{
   string line = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + " " + message;
   Print(line);

   int handle = FileOpen(LogFileName, FILE_READ | FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(handle == INVALID_HANDLE)
   {
      ResetLastError();
      return;
   }

   FileSeek(handle, 0, SEEK_END);
   FileWriteString(handle, line + "\r\n");
   FileClose(handle);
}

string BoolText(const bool value)
{
   if(value)
      return "true";
   return "false";
}

void UpdateChartStatus(const string status)
{
   Comment("TradingViewBridgeEA 1.05\n",
           "Status: ", status, "\n",
           "Common/Files: ", TerminalInfoString(TERMINAL_COMMONDATA_PATH), "\\Files\n",
           "Signal: ", SignalFileName, "\n",
           "Polls: ", IntegerToString(poll_count));
}
