--[[--
端到端：插件装到 plugins/ 后，月读把「重置此书 X-Ray」收进阅读快捷面板。

月读的 source/registry.lua 从自己的源码路径反推插件根目录，模式写死正斜杠
（^@(.*)/source/registry%.lua$），Windows 下 require 记的是反斜杠，匹配不上，
扩展发现这一层在 Windows 上跑不通（设备是 Linux，不受影响）。
所以这里把「发现」换成真实扫描得到的扩展，后面几层全走月读真代码：
External.collect 的前缀与隔离、面板注册表的字段校验与 id 查重。
--]]

local Assert = require("support.assert")

package.preload["l10n"] = function() return { apply = function() end } end
package.preload["gettext"] = function() return function(value) return value end end

local ROOT = _G.BOOK_TEST_ROOT or "."
local PLUGIN_ROOT = ROOT .. "/xrayreset.koplugin"

-- 插件目录要像真插件那样在 package.path 上：<root>/?.lua 能命中 xrayreset/reset.lua。
package.path = PLUGIN_ROOT .. "/?.lua;" .. package.path

-- 月读的 source/registry.lua：extensions() 给扩展清单。Windows 上发现层跑不通，
-- 这里按月读的 readDescriptor 契约真实读一遍描述表，再交回月读的 features 取值。
package.preload["source.registry"] = function()
    local Registry = {}
    Registry.API = 1
    local desc = dofile(PLUGIN_ROOT .. "/moon_source.lua")
    assert(type(desc) == "table" and desc.api == Registry.API, "api mismatch")
    local id = desc.id
    assert(type(id) == "string" and id:match("^ext%.[%w_%-]+$"), "id must look like ext.<name>")
    local ext = { id = id, desc = desc, source = false, home_widgets = {} }
    ext.features = desc.provides and desc.provides.features
    Registry.extensions = function() return { ext } end
    Registry.extensionsReady = function() return true end
    return Registry
end

-- 月读的面板动作注册表要加载内置动作，其中几个 require device（真 KOReader 模块）。
package.preload["device"] = function()
    return {
        screen = { scaleBySize = function(_, n) return n end, getWidth = function() return 600 end },
        hasKeys = function() return false end,
        isTouchDevice = function() return true end,
    }
end

-- 内置动作的其它外部依赖：日志、几何、网络等。
package.preload["ui/network/manager"] = function()
    return { isConnected = function() return false end }
end

-- 内置的「字体」动作会 require KOReader 的 ui/font、fontlist（真模块不在本地）。
-- 整个链换成空壳：本测试只关心第三方动作能不能进注册表。
package.preload["ui.font"] = function() return {} end
package.preload["ui.fonts"] = function() return {} end
package.preload["ui.fonts.reader"] = function() return {} end

local External = require("utils.external")
local items, ready = External.collect("panel")
Assert.is_true(ready, "插件已加载完，扩展清单可缓存")
Assert.eq(#items, 1, "扩展清单里有一项")
Assert.eq(items[1].id, "ext.xrayreset")

-- 月读的 utils.external 拿到 panel 挂点并调用 actions()。
local actions = items[1].mod.actions()
Assert.eq(type(actions), "table")
Assert.is_nil(actions.id, "actions 必须返回列表（带 id 会被判为非列表）")
Assert.is_nil(actions.scope, "actions 必须返回列表")
Assert.eq(#actions, 1)

local raw = actions[1]
-- 月读的校验规则（features/panel/actions/registry.lua）：
-- id 可加前缀、scope 合法、有 title 与 icon、有 run 或 event。
local id = External.prefix("ext.xrayreset", raw.id)
Assert.not_nil(id, "action needs id")
Assert.eq(id, "ext.xrayreset.reset", "id 自动补扩展前缀")
Assert.is_true(raw.scope == "desktop" or raw.scope == "reader", "unknown scope " .. tostring(raw.scope))
Assert.eq(raw.scope, "reader")
Assert.is_true(raw.title and raw.icon, "action needs title and icon")
Assert.is_true(raw.run or raw.event, "action needs run or event")
Assert.eq(type(raw.run), "function")

-- 与月读内置动作不撞 id：内置的 reader 动作有 xray / xray_marks / xray_refresh，
-- 前缀后是 ext.xrayreset.reset，必不撞。
Assert.is_true(id ~= "xray" and id ~= "xray_marks" and id ~= "xray_refresh")

-- 走月读真实的面板注册表：内置动作全加载 + 第三方动作并入 + 查重。
local PanelRegistry = require("features.panel.actions.registry")
local registered = PanelRegistry.get("ext.xrayreset.reset")
Assert.not_nil(registered, "动作要进得了月读的快捷面板注册表")
Assert.eq(registered.scope, "reader")
Assert.eq(registered.title, "重置此书 X-Ray")
Assert.eq(type(registered.run), "function")
-- 回调经 External.wrap 隔离：出错只记日志，不影响月读自己。
Assert.eq(registered.id, "ext.xrayreset.reset")

return true
