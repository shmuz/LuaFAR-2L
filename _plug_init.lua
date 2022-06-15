local mdir = far.PluginStartupInfo().ModuleDir
local path1 = mdir .. "?.lua"
local path2 = mdir:gsub("[^/]+/[^/]+/$", "lua_share/?.lua") -- don't use ../..

package.path = ("%s;%s;%s"):format(path1, path2, package.path)
