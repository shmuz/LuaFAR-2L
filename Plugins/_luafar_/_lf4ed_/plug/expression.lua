--[[
 Goal: evaluate Lua expression.
 Start: 2006-02-?? by Shmuel Zeigerman
--]]

local far2_dialog = require "far2.dialog"
local M = require "lf4ed_message"
local F = far.Flags

local function ErrMsg (msg)
  far.Message(msg, M.MError, M.MOk, "w")
end

local function GetNearestWord (pattern)
  local line = editor.GetString(nil, 2)
  local pos = editor.GetInfo().CurPos
  local r = regex.new(pattern)
  local start = 1
  while true do
    local from, to, word = r:find(line, start)
    if not from then break end
    if pos <= to then return from, to, word end
    start = to + 1
  end
end

local function GetAllText()
  local ei = editor.GetInfo()
  if ei then
    local t = {}
    for n = 1, ei.TotalLines do
      table.insert(t, editor.GetString(n, 2))
    end
    editor.SetPosition(ei)
    return table.concat(t, "\n")
  end
end

local function GetSelectedText()
  local ei = editor.GetInfo()
  if ei and ei.BlockType ~= F.BTYPE_NONE then
    local t = {}
    local n = ei.BlockStartLine
    while true do
      local s = editor.GetString(n, 1)
      if not s or s.SelStart == 0 then
        break
      end
      local sel = s.StringText:sub (s.SelStart, s.SelEnd)
      table.insert(t, sel)
      n = n + 1
    end
    editor.SetPosition(ei)
    return table.concat(t, "\n"), n-1
  end
end

local function CompileParams (s1, s2, s3, s4)
  local p1 = assert(loadstring("return "..s1, "Parameter #1"))
  local p2 = assert(loadstring("return "..s2, "Parameter #2"))
  local p3 = assert(loadstring("return "..s3, "Parameter #3"))
  local p4 = assert(loadstring("return "..s4, "Parameter #4"))
  return p1, p2, p3, p4
end

local function ParamsDialog (aData)
  local HIST_PARAM = "LuaFAR\\LuaScript\\Parameter"
  local D = far2_dialog.NewDialog()
  D._             = {"DI_DOUBLEBOX",3, 1, 52,14,0, 0, 0, 0, M.MScriptParams}
  D.label         = {"DI_TEXT",     5, 3,  0,0, 0, 0, 0, 0, "&1."}
  D.sParam1       = {"DI_EDIT",     8, 3, 49,0, 0, HIST_PARAM, "DIF_HISTORY",0,""}
  D.label         = {"DI_TEXT",     5, 5,  0,0, 0, 0, 0, 0, "&2."}
  D.sParam2       = {"DI_EDIT",     8, 5, 49,0, 0, HIST_PARAM, "DIF_HISTORY",0,""}
  D.label         = {"DI_TEXT",     5, 7,  0,0, 0, 0, 0, 0, "&3."}
  D.sParam3       = {"DI_EDIT",     8, 7, 49,0, 0, HIST_PARAM, "DIF_HISTORY",0,""}
  D.label         = {"DI_TEXT",     5, 9,  0,0, 0, 0, 0, 0, "&4."}
  D.sParam4       = {"DI_EDIT",     8, 9, 49,0, 0, HIST_PARAM, "DIF_HISTORY",0,""}
  D.bParamsEnable = {"DI_CHECKBOX", 5,11,  0,0, 0, 0, 0, 0, M.MScriptParamsEnable}
  D.sep           = {"DI_TEXT",     0,12,  0,0, 0, 0, {DIF_BOXCOLOR=1,DIF_SEPARATOR=1},0,""}
  D.btnRun        = {"DI_BUTTON",   0,13,  0,0, 0, 0, "DIF_CENTERGROUP", 1, M.MRunScript}
  D.btnStore      = {"DI_BUTTON",   0,13,  0,0, 0, 0, "DIF_CENTERGROUP", 0, M.MStoreParams}
  D.btnCancel     = {"DI_BUTTON",   0,13,  0,0, 0, 0, "DIF_CENTERGROUP", 0, M.MCancel}
  ------------------------------------------------------------------------------
  local function DlgProc (hDlg, msg, param1, param2)
    if msg == F.DN_CLOSE then
      if param1 == D.btnStore.id or param1 == D.btnRun.id then
        local s1 = D.sParam1:GetText(hDlg)
        local s2 = D.sParam2:GetText(hDlg)
        local s3 = D.sParam3:GetText(hDlg)
        local s4 = D.sParam4:GetText(hDlg)
        local ok, msg2 = pcall(CompileParams, s1, s2, s3, s4)
        if not ok then ErrMsg(msg2); return 0; end
      end
    end
  end
  far2_dialog.LoadData(D, aData)
  local ret = far.Dialog (-1,-1,56,16,"ScriptParams",D,0,DlgProc)
  ret = (ret==D.btnStore.id) and "store" or (ret==D.btnRun.id) and "run"
  if ret then
    far2_dialog.SaveData(D, aData)
  end
  return ret
end

-- WARNING:
--   don't change the string literals "selection" and "all text",
--   since export.OnError relies on them being exactly such.
local function LuaScript (data)
  local text, chunkname = GetSelectedText(), "selection"
  if not text then
    text, chunkname = GetAllText(), "all text"
    if text and text:sub(1,1)=="#" then text = "--"..text end
  end
  if text then
    local chunk, msg = loadstring(text, chunkname)
    if not chunk then error(msg,3) end
    if data.bParamsEnable then
      local p1,p2,p3,p4 = CompileParams(data.sParam1, data.sParam2,
                                        data.sParam3, data.sParam4)
      p1 = p1(); p2 = p2(); p3 = p3(); p4 = p4()
      return chunk (p1,p2,p3,p4)
    else
      return chunk()
    end
  end
end

local function ResultDialog (aHelpTopic, aData, result)
  local Title = (aHelpTopic=="LuaExpression") and M.MExpr or M.MBlockSum
  local D = far2_dialog.NewDialog()
  ------------------------------------------------------------------------------
  D._         = {"DI_DOUBLEBOX",3, 1,42,7,  0, 0, 0, 0, Title}
  D.lblResult = {"DI_TEXT",     5, 2, 0,0,  0, 0, 0, 0, M.MResult}
  D.edtResult = {"DI_EDIT",     0, 2,40,0,  0, 0, 0, 0, result, _noautoload=1}
  D.cbxInsert = {"DI_CHECKBOX", 5, 3, 0,0,  0, 0, 0, 0, M.MInsertText}
  D.cbxCopy   = {"DI_CHECKBOX", 5, 4, 0,0,  0, 0, 0, 0, M.MCopyToClipboard}
  D.sep       = {"DI_TEXT",     0, 5, 0,0,  0, 0, {DIF_BOXCOLOR=1,DIF_SEPARATOR=1}, 0, ""}
  D.btnOk     = {"DI_BUTTON",   0, 6, 0,0,  0, 0, "DIF_CENTERGROUP", 1, M.MOk}
  D.btnCancel = {"DI_BUTTON",   0, 6, 0,0,  0, 0, "DIF_CENTERGROUP", 0, M.MCancel}
  D.edtResult.X1 = D.lblResult.X1 + D.lblResult.Data:len()
  ------------------------------------------------------------------------------
  far2_dialog.LoadData(D, aData)
  local ret = far.Dialog (-1,-1,46,9,aHelpTopic,D)
  far2_dialog.SaveData(D, aData)
  return (ret == D.btnOk.id)
end

local function BlockSum (history)
  local ei = assert(editor.GetInfo(), "EditorGetInfo failed")
  local blockEndLine
  local sum = 0
  local x_start, x_dot, has_dots
  local pattern = [[(\S[\w.]*)]]

  if ei.BlockType ~= F.BTYPE_NONE then
    local r = regex.new(pattern)
    for n=ei.BlockStartLine, ei.TotalLines do
      local s = editor.GetString (n)
      if s.SelEnd == 0 or s.SelStart < 1 then
        blockEndLine = n - 1
        break
      end
      local start, fin, sel = r:find( s.StringText:sub(s.SelStart, s.SelEnd) ) -- 'start' in selection
      if start then
        x_start = editor.RealToTab(n, s.SelStart + start - 1) -- 'start' column in line
        local num = tonumber(sel)
        if num then
          sum = sum + num
          local x = regex.find(sel, "\\.")
          if x then
            has_dots = true
            x_dot = x_start + x - 1  -- 'dot' column in line
          else
            x_dot = editor.RealToTab(n, s.SelStart + fin)
          end
        end
      end
    end
  else
    local start, fin, word = GetNearestWord(pattern)
    if start then
      x_start = editor.RealToTab(nil, start)
      local num = tonumber(word)
      if num then
        sum = sum + num
        local x = regex.find(word, "\\.")
        if x then
          has_dots = true
          x_dot = x_start + x - 1
        else
          x_dot = editor.RealToTab(nil, 1 + fin)
        end
      end
    end
  end

  if has_dots then
    sum = tostring(sum)
    local last = sum:match("%.(%d+)$")
    sum = sum .. (last and ("0"):rep(2 - #last) or ".00")
  end
  if not ResultDialog("BlockSum", history, sum) then return end

  sum = history.edtResult
  if history.cbxCopy then
    far.CopyToClipboard(sum)
  end
  if history.cbxInsert then
    local y = blockEndLine or ei.CurLine -- position of the last line
    local s = editor.GetString(y)                     -- get last line
    editor.SetPosition (y, s.StringText:len()+1)      -- insert a new line
    editor.InsertString()                             -- +
    local prefix = "="
    if x_dot then
      local x = regex.find(tostring(sum), "\\.") or #sum+1
      if x then x_start = x_dot - (x - 1) end
    end
    if x_start then
      x_start = x_start>#prefix and x_start-#prefix or 1
    else
      x_start = (ei.BlockType==F.BTYPE_COLUMN) and s.SelStart or 1
    end
    editor.SetPosition (y+1, x_start, nil, nil, ei.LeftPos)
    editor.InsertText(prefix .. sum)
    editor.Redraw()
  else
    editor.SetPosition (ei) -- restore the position
  end
end

local function LuaExpr (history)
  local edInfo = editor.GetInfo()
  local text, numline = GetSelectedText()
  if not text then
    numline = edInfo.CurLine
    text = editor.GetString(numline, 2)
  end

  local func, msg = loadstring("return " .. text)
  if not func then
    ErrMsg(msg) return
  end

  local env = {}
  for k,v in pairs(math) do env[k]=v end
  setmetatable(env, { __index=_G })
  setfenv(func, env)
  local ok, result = pcall(func)
  if not ok then
    ErrMsg(result) return
  end

  result = tostring(result)
  if not ResultDialog("LuaExpression", history, result) then
    return
  end

  result = history.edtResult
  if history.cbxInsert then
    local line = editor.GetString(numline)
    local pos = (edInfo.BlockType==F.BTYPE_NONE) and line.StringLength or line.SelEnd
    editor.SetPosition(numline, pos+1)
    editor.InsertText(" = " .. result .. " ;")
    editor.Redraw()
  end
  if history.cbxCopy then
    far.CopyToClipboard(result)
  end
end

local funcs = {
  BlockSum     = BlockSum,
  LuaExpr      = LuaExpr,
  LuaScript    = function(aData) return LuaScript(aData) end, -- keep errorlevel==3
  ScriptParams = function(aData)
      if ParamsDialog(aData) == "run" then return LuaScript(aData) end
    end,
}

do
  local arg = ...
  return assert (funcs[arg[1]]) (unpack(arg, 2))
end

