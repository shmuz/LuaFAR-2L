PLUGNAME = polygon
CONFIG   = polygon.cfg
LANG_LUA = polygon_lang.lua
C_SOURCE = ../plug/polygon.c
MYCFLAGS = -I$(FARSOURCE)/luafar/src
FUNC_OPENLIBS = luaopen_polygon
SYS_ID = 0xD4BC5EA7

# Do not include COMPARE - it is in "polygon.c".
FAR_EXPORTS = \
  CLOSEPLUGIN        \
  CONFIGURE          \
  DELETEFILES        \
  FREEFINDDATA       \
  GETFINDDATA        \
  GETOPENPLUGININFO  \
  OPENFILEPLUGIN     \
  OPENPLUGIN         \
  PROCESSEVENT       \
  PROCESSKEY         \
  SETDIRECTORY

include ../../plugin.mak
