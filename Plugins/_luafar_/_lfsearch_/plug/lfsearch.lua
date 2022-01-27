-- replace.lua

--[[----------------------------------------------------------------------------
*  LuaFAR 2.6 is required because of 'gsub' method of compiled Far regex.
   This method is used in the "fast count" case, namely
      (aOp == "count") and not aParams.bSearchBack,
   that greatly speeds up counting matches.
   *  Counting using PCRE with the PCRE_UCP flag set is by far slower than with
      other regex libraries being used.

*  LuaFAR 2.8 is required because of DM_LISTSETDATA, DM_LISTGETDATA.
------------------------------------------------------------------------------]]
local ReqLuafarVersion = "2.8"

-- CONFIGURATION : keep it at the file top !!
local Cfg = {
  --  Default script will be recompiled and run every time OpenPlugin/
  --  OpenFilePlugin are called: set true for debugging, false for normal use;
  ReloadDefaultScript = true,

  --  Reload lua libraries each time they are require()d:
  --  set true for libraries debugging, false for normal use;
  ReloadOnRequire = true,

  histfield_Main   = "main",
  histfield_Menu   = "menu",
  histfield_Config = "config",

  UserMenuFile = "@_usermenu.lua",
  RegPath = "LuaFAR\\LF Search\\",
}

-- Upvalues --
local Utils = require "far2.utils"
local M     = require "lfs_message"
local F = far.Flags

local LibFunc, History, ModuleDir

local function Require (name)
  if Cfg.ReloadOnRequire then package.loaded[name] = nil; end
  return require(name)
end

local function InitUpvalues (_Plugin)
  LibFunc   = Require("luarepl").SearchOrReplace
  History   = _Plugin.History
  History:field(Cfg.histfield_Config)
  ModuleDir = _Plugin.ModuleDir
end

local function ResolvePath (template, dir)
  return (template:gsub("@", dir or ModuleDir))
end

local function MakeAddToMenu (Items)
  return function (aItemText, aFileName, aParam1, aParam2)
    local SepText = type(aItemText)=="string" and aItemText:match("^:sep:(.*)")
    if SepText then
      table.insert(Items, { text=SepText, separator=true })
    elseif type(aFileName)=="string" then
      table.insert(Items, { text=tostring(aItemText),
        filename=ModuleDir..aFileName, param1=aParam1, param2=aParam2 })
    end
  end
end

local function MakeMenuItems (aUserMenuFile)
  local items = {
    {text=M.MMenuFind,    action="search" },
    {text=M.MMenuReplace, action="replace"},
    {text=M.MMenuRepeat,  action="repeat" },
    {text=M.MMenuConfig,  action="config" },
  }
  local Info = win.GetFileInfo(aUserMenuFile)
  if Info and not Info.FileAttributes:find("d") then
    local f = assert(loadfile(aUserMenuFile))
    local env = setmetatable( {AddToMenu=MakeAddToMenu(items)}, {__index=_G} )
    setfenv(f, env)()
  end
  return items
end

local function export_OpenPlugin (From, Item)
  if not Utils.CheckLuafarVersion(ReqLuafarVersion, M.MMenuTitle) then
    return
  end

  if bit.band(From, F.OPEN_FROMMACRO) ~= 0 then
    far.Message(Item); return
  end

  if From == F.OPEN_EDITOR then
    local hMenu = History:field(Cfg.histfield_Menu)
    local items = MakeMenuItems(ResolvePath(Cfg.UserMenuFile))
    local ret, pos = far.Menu( {
      Flags = {FMENU_WRAPMODE=1, FMENU_AUTOHIGHLIGHT=1},
      Title = M.MMenuTitle,
      HelpTopic = "Contents",
      SelectIndex = hMenu.position,
    }, items)
    if ret then
      hMenu.position = pos
      if ret.action then
        local data = History:field(Cfg.histfield_Main)
        data.fUserChoiceFunc = nil
        LibFunc (ret.action, data, false)
      elseif ret.filename then
        assert(loadfile(ret.filename))(ret.param1, ret.param2)
      end
      History:save()
    end

  elseif From == F.OPEN_PLUGINSMENU then
    local SearchFromPanel = Require("lfs_panels")
    SearchFromPanel(History)
    History:save()
  end
end

local function export_GetPluginInfo()
  return {
    Flags = F.PF_EDITOR,
    PluginMenuStrings = { M.MMenuTitle },
    SysId = 0x10001,
  }
end

function SearchOrReplace (aOp, aData)
  assert(type(aOp)=="string", "arg #1: string expected")
  assert(type(aData)=="table", "arg #2: table expected")
  local newdata = {}; for k,v in pairs(aData) do newdata[k] = v end
  History:setfield(Cfg.histfield_Main, newdata)
  return LibFunc(aOp, newdata, true)
end

local function SetExportFunctions()
  export.GetPluginInfo = export_GetPluginInfo
  export.OpenPlugin    = export_OpenPlugin
end

local function main()
  if not _Plugin then
    _Plugin = Utils.InitPlugin("LuaFAR Search")
    _Plugin.RegPath = Cfg.RegPath
    package.cpath = _Plugin.ModuleDir .. "?.dl;" .. package.cpath
  end
  SetExportFunctions()
  InitUpvalues(_Plugin)
  far.ReloadDefaultScript = Cfg.ReloadDefaultScript
end

main()
