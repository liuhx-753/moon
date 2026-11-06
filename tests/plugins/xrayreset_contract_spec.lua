--[[--
X-Ray 重置扩展的月读契约：描述表能被 source.registry 识别，panel 动作能被 utils.external 收走。

这两处是月读侧的加载路径，本地不装月读就跑不到，只能对着源码断言契约形状。
--]]

local Assert = require("support.assert")

package.preload["l10n"] = function() return { apply = function() end } end
package.preload["gettext"] = function() return function(value) return value end end

local ROOT = _G.BOOK_TEST_ROOT or "."

-- 描述表：按月读的契约读（api / id / provides.source / provides.features）。
-- 描述表里的 panel.actions 会 require 插件自己的模块；设备上插件目录在 package.path 上，
-- 本地没有，这里先 stub 出动作再读描述表。
local stub_actions = {
    {
        id = "reset",
        title = "重置此书 X-Ray",
        icon = "delete",
        scope = "reader",
        run = function() end,
    },
}
package.preload["xrayreset.reset"] = function()
    return { actions = function() return stub_actions end }
end

local desc = dofile(ROOT .. "/xrayreset.koplugin/moon_source.lua")

-- api 必须等于月读的 Registry.API（source/registry.lua 里的 Registry.API = 1）。
local Registry = require("source.registry")
Assert.eq(desc.api, Registry.API, "描述表 api 要等于月读的 Registry.API")

-- 非书源：id 写顶层，必须形如 ext.<name>。
Assert.eq(type(desc.id), "string")
Assert.is_true(desc.id:match("^ext%.[%w_%-]+$") ~= nil, "id 必须形如 ext.<name>")
Assert.eq(desc.provides.source, false, "本扩展不是书源")

-- 月读的 Registry.features 会把 provides.features 原样取出。
local features = Registry.features(desc)
Assert.not_nil(features, "provides.features 要能被 Registry.features 取出")
Assert.not_nil(features.panel, "要声明 panel 挂点")
Assert.eq(type(features.panel.actions), "function", "panel.actions 是函数")

-- panel 动作的形状：月读 registry 只认这些字段，缺字段只记日志跳过。
local actions = features.panel.actions()
Assert.eq(#actions, 1)
local action = actions[1]
Assert.eq(type(action.id), "string", "缺 id 会静默跳过")
Assert.not_nil(action.id:match("^%w[%w_%-]*$"), "id 只能是字母数字下划线横线")
Assert.eq(type(action.title), "string", "缺 title 会静默跳过")
Assert.eq(type(action.icon), "string", "缺 icon 会静默跳过")
Assert.eq(action.scope, "reader", "scope 只能是 desktop / reader")
Assert.eq(type(action.run), "function", "缺 run 会静默跳过")

-- id 会被月读补成 <扩展 id>.<短 id>，不能自己带前缀。
Assert.is_true(action.id:sub(1, #"ext.xrayreset." + 1) ~= "ext.xrayreset.", "短 id 不要自带扩展前缀")
-- 前缀后是 ext.xrayreset.reset，与月读内置动作（xray / xray_marks / xray_refresh）不撞名。
Assert.eq("ext.xrayreset." .. action.id, "ext.xrayreset.reset")

-- 图标名必须是月读内置图标字体里有的名字，否则面板上会显示英文字面而不是图标。
local icon_names = dofile(ROOT .. "/book.koplugin/ui/themes/widgets/icon/names.lua")
local icon_set = {}
for _idx, name in ipairs(icon_names) do icon_set[name] = true end
Assert.is_true(icon_set[action.icon] == true, "图标名不在月读图标字体内：" .. tostring(action.icon))

return true
