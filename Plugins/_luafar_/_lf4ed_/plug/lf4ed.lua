-------------------------------------------------------------------------------
-- LuaFAR for Editor: main script
-------------------------------------------------------------------------------

local PluginVersion = "2.9.0"
local ReqLuafarVer = "2.8"

local SETTINGS_KEY = "shmuz"
local SETTINGS_NAME = "plugin_lf4ed"

-- CONFIGURATION : keep it at the file top !!
local DefaultCfg = {
  -- Default script will be recompiled and run every time OpenPlugin/OpenFilePlugin
  -- are called: set true for debugging, false for normal use;
  ReloadDefaultScript = false,

  -- Reload Lua libraries each time they are require()d:
  -- set true for libraries debugging, false for normal use;
  RequireWithReload   = false,

  -- After executing utility from main menu, return to the menu again
  ReturnToMainMenu    = false,

  UseStrict           = false, -- Use require 'strict'
}

-- UPVALUES : keep them above all function definitions !!
local Sett  = require "far2.settings"
local Utils = require "far2.utils"
local M     = require "lf4ed_message"
local F = far.Flags
local field = Sett.field
local VK = win.GetVirtualKeys()
local FirstRun = not _Plugin
local band, bor, bnot = bit.band, bit.bor, bit.bnot
local dirsep = package.config:sub(1,1)
lf4ed = lf4ed or {}
local SetExportFunctions -- forward declaration

local _Cfg
local _History
local _ModuleDir

local function ErrMsg(msg, buttons, flags)
  return far.Message(msg, "Error", buttons, flags or "w")
end

local function ScriptErrMsg(msg)
  (type(export.OnError)=="function" and export.OnError or ErrMsg)(msg)
end

local function ShallowCopy (src)
  local trg = {}; for k,v in pairs(src) do trg[k]=v end
  return trg
end

local RequireWithReload, ResetPackageLoaded do
  local bypass_reload = {
    -- Lua global tables --
    _G=1; coroutine=1; debug=1; io=1; math=1; os=1; package=1; string=1; table=1;
    -- LuaFAR global tables --
    actl=1; bit=1; editor=1; far=1; panel=1; regex=1; utf8=1; viewer=1; win=1;
    -- Other libraries
    moonscript=1;
  }

  RequireWithReload = function(name)
    if name and not bypass_reload[name] then
      package.loaded[name] = nil
    end
    return _Plugin.OriginalRequire(name)
  end

  ResetPackageLoaded = function()
    for name in pairs(package.loaded) do
      if not bypass_reload[name] then
        package.loaded[name] = nil
      end
    end
  end
end

local function OnConfigChange (cfg)
  -- 1 --
  package.loaded.strict = nil
  if cfg.UseStrict then require "strict"
  else setmetatable(_G, nil)
  end
  -- 2 --
  require = cfg.RequireWithReload and RequireWithReload or _Plugin.OriginalRequire --luacheck:ignore 121
  -- 3 --
  far.ReloadDefaultScript = cfg.ReloadDefaultScript
end

-------------------------------------------------------------------------------
-- @param newcfg: if given, it is a table with configuration parameters to set.
-- @return: a copy of the configuration table (as it was before the call).
-------------------------------------------------------------------------------
local function plug_config (newcfg)
  assert(not newcfg or (type(newcfg) == "table"))
  local t = {}
  for k in pairs(DefaultCfg) do t[k] = _Cfg[k] end
  if newcfg then
    for k,v in pairs(newcfg) do
      if DefaultCfg[k] ~= nil then _Cfg[k] = v end
    end
    OnConfigChange(_Cfg)
  end
  return t
end

local function ConvertUserHotkey(str)
  local d = 0
  for elem in str:upper():gmatch("[^+%-]+") do
    if elem == "ALT" then d = bor(d, 0x01)
    elseif elem == "CTRL" then d = bor(d, 0x02)
    elseif elem == "SHIFT" then d = bor(d, 0x04)
    else d = d .. "+" .. elem; break
    end
  end
  return d
end

local function RunFile (filespec, aArg)
  for file in filespec:gmatch("[^|]+") do
    if file:find("^%<") then
      local ok, func = pcall(require, file) -- embedded file
      if ok then return func(aArg) end
    else
      local func = loadfile(_ModuleDir .. file) -- disk file
      if func then return func(aArg) end
    end
  end
  error ('could not load file from filespec: "' .. filespec .. '"')
end

local function RunUserFunc (aArgTable, aItem, ...)
  assert(aItem.action, "no action")
  -- copy "fixed" arguments
  local argCopy = ShallowCopy(aArgTable)
  for i,v in ipairs(aItem.arg) do argCopy[i] = v end
  -- append "variable" arguments
  for i=1,select("#", ...) do argCopy[#argCopy+1] = select(i, ...) end
  -- run the chunk
  aItem.action(argCopy)
end

local function fSort (aArg)
  local sortlines = require "sortlines"
  aArg[1] = field(_History, "SortDialog")
  repeat
    local normal, msg = pcall(sortlines.SortWithDialog, aArg)
    if not normal then
      -- "Cancel" breaks infinite loop when exception is thrown by far.Dialog()
      if 1 ~= ErrMsg(msg, ";RetryCancel") then break end
    end
  until normal
end

local function fWrap (aArg)
  aArg[1] = field(_History, "WrapDialog")
  return RunFile("<wrap|wrap.lua", aArg)
end

local function fBlockSum (aArg)
  aArg[1], aArg[2] = "BlockSum", field(_History, "BlockSum")
  return RunFile("<expression|expression.lua", aArg)
end

local function fExpr (aArg)
  aArg[1], aArg[2] = "LuaExpr", field(_History, "LuaExpression")
  return RunFile("<expression|expression.lua", aArg)
end

local function fScript (aArg)
  aArg[1], aArg[2] = "LuaScript", field(_History, "LuaScript")
  return RunFile("<expression|expression.lua", aArg)
end

local function fScriptParams (aArg)
  aArg[1], aArg[2] = "ScriptParams", field(_History, "LuaScript")
  return RunFile("<expression|expression.lua", aArg)
end

local function fPluginConfig (aArg)
  aArg[1] = _Cfg
  if RunFile("<config|config.lua", aArg) then
    OnConfigChange(_Cfg)
    return true
  end
end

local EditorMenuItems = {
  { text = "::MSort",         action = fSort },
  { text = "::MWrap",         action = fWrap },
  { text = "::MBlockSum",     action = fBlockSum },
  { text = "::MExpr",         action = fExpr },
  { text = "::MScript",       action = fScript },
  { text = "::MScriptParams", action = fScriptParams },
}

-- Split command line into separate arguments.
-- * The function does not raise errors: any input string is acceptable and
--   is split into arguments according to the rules below.
-- * An argument is:
--   a) sequence enclosed within a pair of non-escaped double quotes; can
--      contain spaces; enclosing double quotes are stripped from the argument.
--   b) sequence containing non-space, non-unescaped-double-quote characters.
-- * Arguments of both kinds can contain escaped double quotes;
-- * Backslashes escape only double quotes; non-escaped double qoutes either
--   start or end an argument.
local function SplitCommandLine (str)
  local out = {}
  local from = 1
  while true do
    local to
    from = regex.find(str, "\\S", from)
    if not from then break end
    if str:sub(from,from) == '"' then
      from, to = from+1, from+1
      while true do
        local c = str:sub(to,to)
        if c == '' or c == '"' then
          out[#out+1] = str:sub(from,to-1)
          from = to+1
          break
        elseif str:sub(to,to+1) == [[\"]] then to = to+2
        else to = to+1
        end
      end
    else
      to = from
      while true do
        local c = str:sub(to,to)
        if c == '' or c == '"' or c:find("%s") then break
        elseif str:sub(to,to+1) == [[\"]] then to = to+2
        else to = to+1
        end
      end
      out[#out+1] = str:sub(from,to-1)
      from = to
    end
  end
  for i,v in ipairs(out) do out[i]=v:gsub([[\"]], [["]]) end
  return out
end

local function MakeAddCommand (Items, Env)
  return function (aCommand, aAction, ...)
    if type(aCommand)=="string" and type(aAction)=="function" then
      setfenv(aAction, Env)
      _Plugin.CommandTable[aCommand] = { arg = {...}; action = aAction; }
    end
  end
end

local function MakeAddToMenu (Items, Env)
  local function AddToMenu (aWhere, aItemText, aHotKey, aHandler, ...)
    if type(aWhere) ~= "string" then return end
    aWhere = aWhere:lower()
    if not aWhere:find("[evpdc]") then return end
    ---------------------------------------------------------------------------
    local tp = type(aHandler)
    local SepText = type(aItemText)=="string" and aItemText:match("^:sep:(.*)")
    local tUserItem, bInternal
    if not SepText then
      if tp == "number" then
        bInternal = true
      elseif tp=="function" then
        setfenv(aHandler, Env)
        tUserItem = { arg={...}; useritem=true; action=aHandler; }
      end
    end
    if not (SepText or tUserItem or bInternal) then
      return
    end
    ---------------------------------------------------------------------------
    if (tUserItem or bInternal) and aWhere:find("[ec]") and type(aHotKey)=="string" then
      local HotKeyTable = _Plugin.HotKeyTable
      aHotKey = ConvertUserHotkey (aHotKey)
      if tUserItem then
        HotKeyTable[aHotKey] = tUserItem
      else
        HotKeyTable[aHotKey] = aHandler
      end
    end
    ---------------------------------------------------------------------------
    if SepText or (tUserItem and aItemText) then
      local item
      if SepText then
        item = { text=SepText, separator=true }
      else
        tUserItem.text = tostring(aItemText)
        item = tUserItem
      end
      if aWhere:find"c" then table.insert(Items.config, item) end
      if aWhere:find"d" then table.insert(Items.dialog, item) end
      if aWhere:find"e" then table.insert(Items.editor, item) end
      if aWhere:find"p" then table.insert(Items.panels, item) end
      if aWhere:find"v" then table.insert(Items.viewer, item) end
    end
  end
  return AddToMenu
end

local function RunExitScriptHandlers()
  local t = _Plugin.ExitScriptHandlers
  for i = 1,#t do t[i]() end
end

local function AddEvent (EventName, EventHandler)
  if type(EventHandler) == "function" then
    local env = setmetatable({}, { __index=_G })
    setfenv(EventHandler, env)
    if     EventName=="EditorInput" then table.insert(_Plugin.EditorInputHandlers, EventHandler)
    elseif EventName=="EditorEvent" then table.insert(_Plugin.EditorEventHandlers, EventHandler)
    elseif EventName=="ViewerEvent" then table.insert(_Plugin.ViewerEventHandlers, EventHandler)
    elseif EventName=="DialogEvent" then table.insert(_Plugin.DialogEventHandlers, EventHandler)
    elseif EventName=="ExitScript"  then table.insert(_Plugin.ExitScriptHandlers,  EventHandler)
    end
  end
end

local function MakeAddUserFile (aEnv, aItems)
  local uDepth, uStack, uMeta = 0, {}, {__index = _G}
  local function AddUserFile (filename)
    uDepth = uDepth + 1
    filename = _ModuleDir .. filename
    if uDepth == 1 then
      -- if top-level _usermenu.lua doesn't exist, it isn't error
      local info = win.GetFileInfo(filename)
      if not info or info.FileAttributes:find("d") then return end
    end
    ---------------------------------------------------------------------------
    local chunk, msg1 = loadfile(filename)
    if not chunk then error(msg1, 3) end
    setfenv(chunk, aEnv)
    ---------------------------------------------------------------------------
    uStack[uDepth] = setmetatable({}, uMeta)
    aEnv.AddToMenu = MakeAddToMenu(aItems, uStack[uDepth])
    aEnv.AddCommand = MakeAddCommand(aItems, uStack[uDepth])
    local ok, msg2 = pcall(chunk, filename)
    if not ok then error(msg2, 3) end
    uDepth = uDepth - 1
  end
  return AddUserFile
end

local function MakeAutoInstall (AddUserFile)
  local function AutoInstall (startpath, filepattern, depth)
    assert(type(startpath)=="string", "bad arg. #1 to AutoInstall")
    assert(filepattern==nil or type(filepattern)=="string", "bad arg. #2 to AutoInstall")
    assert(depth==nil or type(depth)=="number", "bad arg. #3 to AutoInstall")
    ---------------------------------------------------------------------------
    startpath = _ModuleDir .. startpath:gsub("[\\/]*$", dirsep, 1)
    filepattern = filepattern or "^_usermenu%.lua$"
    ---------------------------------------------------------------------------
    local first = depth
    local offset = _ModuleDir:len() + 1
    for _, item in ipairs(far.GetDirList(startpath) or {}) do
      if first then
        first = false
        local _, m = item.FileName:gsub(dirsep, "")
        depth = depth + m
      end
      if not item.FileAttributes:find"d" then
        local try = true
        if depth then
          local _, n = item.FileName:gsub(dirsep, "")
          try = (n <= depth)
        end
        if try then
          local relName = item.FileName:sub(offset)
          local Name = relName:match("[^\\/]+$")
          if Name:match(filepattern) then AddUserFile(relName) end
        end
      end
    end
  end
  return AutoInstall
end

local function fReloadUserFile()
  if not FirstRun then
    RunExitScriptHandlers()
    ResetPackageLoaded()
  end
  package.path = _Plugin.PackagePath -- restore to original value
  _Plugin.HotKeyTable = {}
  _Plugin.CommandTable = {}
  _Plugin.EditorInputHandlers = {}
  _Plugin.EditorEventHandlers = {}
  _Plugin.ViewerEventHandlers = {}
  _Plugin.DialogEventHandlers = {}
  _Plugin.ExitScriptHandlers  = {}
  -----------------------------------------------------------------------------
  _Plugin.UserItems = { editor={},viewer={},panels={},config={},cmdline={},dialog={} }
  local env = setmetatable({}, {__index=_G})
  env.AddUserFile  = MakeAddUserFile(env, _Plugin.UserItems)
  env.AutoInstall  = MakeAutoInstall(env.AddUserFile)
  env.AddEvent = AddEvent
  -----------------------------------------------------------------------------
  env.AddUserFile("_usermenu.lua")
  SetExportFunctions()
end

local function traceback3(msg)
  return debug.traceback(msg, 3)
end

local function RunMenuItem(aArg, aItem, aRestoreConfig)
  aArg = ShallowCopy(aArg) -- prevent parasite connection between utilities
  local restoreConfig = aRestoreConfig and plug_config()

  local function wrapfunc()
    if aItem.useritem then
      return RunUserFunc(aArg, aItem)
    end
    return aItem.action(aArg)
  end

  local ok, result = xpcall(wrapfunc, traceback3)
  local result2 = _Cfg.ReturnToMainMenu
  if restoreConfig then
    plug_config(restoreConfig)
  end
  if not ok then
    ScriptErrMsg(result)
  end
  return ok, result, result2
end

local function Configure (aArg)
  local properties, items = {
    Flags = F.FMENU_WRAPMODE+F.FMENU_AUTOHIGHLIGHT, Title = M.MPluginNameCfg,
    HelpTopic = "Contents",
  }, {
    { text=M.MPluginSettings, action=fPluginConfig },
    { text=M.MReloadUserFile, action=fReloadUserFile },
  }
  for _,v in ipairs(_Plugin.UserItems.config) do items[#items+1]=v end
  while true do
    local item, pos = far.Menu(properties, items)
    if not item then return end
    local ok, result = RunMenuItem(aArg, item, false)
    if not ok then return end
    if result then
      Sett.msave(SETTINGS_KEY, SETTINGS_NAME, _History)
    end
    if item.action == fReloadUserFile then return "reloaded" end
    properties.SelectIndex = pos
  end
end

local function export_Configure (ItemNumber)
  Configure({From="config"})
  return false
end

local function AddMenuItems (src, trg)
  trg = trg or {}
  for _, item in ipairs(src) do
    local text = item.text
    if type(text)=="string" and text:sub(1,2)=="::" then
      local newitem = {}
      for k,v in pairs(item) do newitem[k] = v end
      newitem.text = M[text:sub(3)]
      trg[#trg+1] = newitem
    else
      trg[#trg+1] = item
    end
  end
  return trg
end

local function MakeMainMenu(aFrom)
  local properties = {
    Flags = F.FMENU_WRAPMODE+F.FMENU_AUTOHIGHLIGHT, Title = M.MPluginName,
    HelpTopic = "Contents", Bottom = "ctrl+sh+f9 (settings)", }
  --------
  local items = {}
  if aFrom == "editor" then AddMenuItems(EditorMenuItems, items) end
  AddMenuItems(_Plugin.UserItems[aFrom], items)
  --------
  local keys = {{ BreakKey="CS+F9", action=Configure },}
  return properties, items, keys
end

local function CommandSyntaxMessage()
  local syn = [[

Syntax:
  lfe: [<options>] <command>|-r<filename> [<arguments>]
    or
  CallPlugin(0x10000, [<options>] <command>|-r<filename>
                                          [<arguments>])
Options:
  -a          asynchronous execution
  -e <str>    execute string <str>
  -l <lib>    load library <lib>

Available commands:
]]

  if next(_Plugin.CommandTable) then
    local arr = {}
    for k in pairs(_Plugin.CommandTable) do arr[#arr+1] = k end
    table.sort(arr)
    syn = syn .. "  " .. table.concat(arr, ", ")
  else
    syn = syn .. "  <no commands available>"
  end
  far.Message(syn, M.MPluginName..": "..M.MCommandSyntaxTitle, ";Ok", "l")
end

local function ExecuteCommand (args, sFrom)
  local env = setmetatable({}, {__index=_G})
  for _,v in ipairs(args) do
    if v.command then
      local oldConfig = plug_config()
      local wrapfunc = function()
        return RunUserFunc({From=sFrom}, v.command, unpack(v))
      end
      local ok, res = xpcall(wrapfunc, traceback3)
      plug_config(oldConfig)
      if not ok then ScriptErrMsg(res) end
      break
    elseif v.opt == "r" then
      local f = assert(loadfile(v.param))
      setfenv(f, env)(unpack(v))
      break
    elseif v.opt == "e" then
      local f = assert(loadstring(v.param))
      setfenv(f, env)()
    elseif v.opt == "l" then
      require(v.param)
    end
  end
end

-------------------------------------------------------------------------------
-- This function processes both command line calls and calls from macros.
-------------------------------------------------------------------------------
local function ProcessCommand (source, sFrom)
  local args = SplitCommandLine(source)
  if #args==0 then return CommandSyntaxMessage() end
  local opt, async
  local args2 = {}
  for i,v in ipairs(args) do
    local param
    if opt then
      param = v
    elseif v:sub(1,1) == "-" then
      opt, param = v:match("^%-([aelr])(.*)")
      if not opt then return CommandSyntaxMessage() end
    else
      local command = _Plugin.CommandTable[v]
      if not command then return CommandSyntaxMessage() end
      table.insert(args2, { command=command; unpack(args, i+1); })
      break
    end
    if opt == "a" then
      opt, async = nil, true
    elseif param ~= "" then
      if opt=="r" then
        table.insert(args2, { opt=opt; param=param; unpack(args, i+1); })
        break
      else
        table.insert(args2, { opt=opt; param=param; })
      end
      opt = nil
    end
  end
  if async then
    ---- autocomplete:good; Escape response:bad when timer period < 20;
    far.Timer(30, function(h) h:Close() ExecuteCommand(args2, sFrom) end)
  else
    ---- autocomplete:bad; Escape responsiveness:good;
    return ExecuteCommand(args2, sFrom)
  end
end

local function export_OpenPlugin (aFrom, aItem)

  -- Called from macro
  if band(aFrom, F.OPEN_FROMMACRO) ~= 0 then
    if band(aFrom, F.OPEN_FROMMACROSTRING) ~= 0 then
      local map = {
        [F.MACROAREA_SHELL]  = "panels",
        [F.MACROAREA_EDITOR] = "editor",
        [F.MACROAREA_VIEWER] = "viewer",
        [F.MACROAREA_DIALOG] = "dialog",
      }
      local area = band(aFrom, F.OPEN_FROM_MASK)
      ProcessCommand(aItem, map[area] or aFrom)
    end
    return
  end

  -- Called from command line
  if aFrom == F.OPEN_COMMANDLINE then
    local to_show = aItem:match("^%s*=(.*)")
    if to_show then
      local f = assert(loadstring("far.Show(".. to_show..")"))
      local env = setmetatable({}, {__index=_G})
      setfenv(f,env)()
    else
      ProcessCommand(aItem, "panels")
    end
    return
  end

  -- Called from a not supported source
  local map = {
    [F.OPEN_PLUGINSMENU] = "panels",
    [F.OPEN_EDITOR] = "editor",
    [F.OPEN_VIEWER] = "viewer",
    [F.OPEN_DIALOG] = "dialog",
  }
  if map[aFrom] == nil then
    return
  end

  -----------------------------------------------------------------------------
  local sFrom = map[aFrom]
  local history = field(_History, "Menu", sFrom)
  local properties, items, keys = MakeMainMenu(sFrom)
  properties.SelectIndex = history.position
  while true do
    local item, pos = far.Menu(properties, items, keys)
    if not item then break end

    history.position = pos
    local arg = { From = sFrom }
    if sFrom == "dialog" then arg.hDlg = aItem.hDlg end
    local ok, result, bRetToMainMenu = RunMenuItem(arg, item, item.action~=Configure)
    if not ok then break end

    Sett.msave(SETTINGS_KEY, SETTINGS_NAME, _History)
    if not (bRetToMainMenu or item.action==Configure) then break end

    if item.action==Configure and result=="reloaded" then
      properties, items, keys = MakeMainMenu(sFrom)
    else
      properties.SelectIndex = pos
    end
  end
end

local function export_GetPluginInfo()
  local flags = bor(F.PF_EDITOR, F.PF_DISABLEPANELS)
  local useritems = _Plugin.UserItems
  if useritems then
    if #useritems.panels > 0 then flags = band(flags, bnot(F.PF_DISABLEPANELS)) end
    if #useritems.viewer > 0 then flags = bor(flags, F.PF_VIEWER) end
    if #useritems.dialog > 0 then flags = bor(flags, F.PF_DIALOG) end
  end
  return {
    Flags = flags,
    PluginMenuStrings = { M.MPluginName },
    PluginConfigStrings = { M.MPluginName },
    CommandPrefix = "lfe",
    SysId = 0x10000,
  }
end

local function export_ExitFAR()
  RunExitScriptHandlers()
  Sett.msave(SETTINGS_KEY, SETTINGS_NAME, _History)
end

local function KeyComb (Rec)
  local f = 0
  local state = Rec.ControlKeyState
  local ALT   = bor(F.LEFT_ALT_PRESSED, F.RIGHT_ALT_PRESSED)
  local CTRL  = bor(F.LEFT_CTRL_PRESSED, F.RIGHT_CTRL_PRESSED)
  local SHIFT = F.SHIFT_PRESSED

  if 0 ~= band(state, ALT) then f = bor(f, 0x01) end
  if 0 ~= band(state, CTRL) then f = bor(f, 0x02) end
  if 0 ~= band(state, SHIFT) then f = bor(f, 0x04) end
  local name = VK[Rec.VirtualKeyCode%256]
  if name then f = f .. "+" .. name; end
  return f
end

local function export_ProcessEditorInput (Rec)
  local EventType = Rec.EventType
  if (EventType==F.FARMACRO_KEY_EVENT) or (EventType==F.KEY_EVENT) then
    local item = _Plugin.HotKeyTable[KeyComb(Rec)]
    if item then
      if Rec.KeyDown then
        if type(item)=="number" then item = EditorMenuItems[item] end
        if item then RunMenuItem({From="editor"}, item, item.action~=Configure) end
      end
      return true
    end
  end
  for _,f in ipairs(_Plugin.EditorInputHandlers) do
    if f(Rec) then return true end
  end
end

local function export_ProcessEditorEvent (Event, Param)
  for _,f in ipairs(_Plugin.EditorEventHandlers) do
    f(Event, Param)
  end
end

local function export_ProcessViewerEvent (Event, Param)
  for _,f in ipairs(_Plugin.ViewerEventHandlers) do
    f(Event, Param)
  end
end

local function export_ProcessDialogEvent (Event, Param)
  for _,f in ipairs(_Plugin.DialogEventHandlers) do
    local ret = f(Event, Param)
    if ret then return ret end
  end
end

local function alive(t)
  return t and t[1]
end

SetExportFunctions = function()
  export.Configure          = export_Configure
  export.ExitFAR            = export_ExitFAR
  export.GetPluginInfo      = export_GetPluginInfo
  export.OpenPlugin         = export_OpenPlugin
  export.ProcessEditorInput = export_ProcessEditorInput
  export.ProcessEditorEvent = alive(_Plugin.EditorEventHandlers) and export_ProcessEditorEvent
  export.ProcessViewerEvent = alive(_Plugin.ViewerEventHandlers) and export_ProcessViewerEvent
  export.ProcessDialogEvent = alive(_Plugin.DialogEventHandlers) and export_ProcessDialogEvent
end

local function InitUpvalues (_Plugin)
  _ModuleDir = _Plugin.ModuleDir
  _History = _Plugin.History
  _Cfg = field(_History, "Settings")
  setmetatable(_Cfg, { __index=DefaultCfg })
end

local function main()
  if FirstRun then
    export.OnError = Utils.OnError
    _Plugin = {}
    _Plugin.ModuleDir = far.PluginStartupInfo().ModuleDir
    local repvalue = (";%sscripts%s?.lua;"):format(_Plugin.ModuleDir, dirsep)
    _Plugin.PackagePath = package.path:gsub(";", repvalue, 1)
    _Plugin.OriginalRequire = require
    _Plugin.History = Sett.mload(SETTINGS_KEY, SETTINGS_NAME) or {}
  end

  InitUpvalues(_Plugin)
  OnConfigChange(_Cfg)
  SetExportFunctions()

  if FirstRun then
    local ok, msg = pcall(fReloadUserFile) -- here pcall leaves plugin alive in case of errors in the user file
    if not ok then
      msg = string.gsub(msg, "\t", "    ") -- use string.gsub to avoid "invalid UTF-8 code" error
      far.Message(msg, M.MPluginName, nil, "wl")
    end
    FirstRun = false -- needed when (ReloadDefaultScript == false)
  end
end

lf4ed.config  = plug_config
lf4ed.reload  = fReloadUserFile
lf4ed.version = function() return PluginVersion end

main()
