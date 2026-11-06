--[[--
月读扩展：X-Ray 重置。

不是书源，只往阅读快捷面板加一个「重置此书 X-Ray」动作。
月读更新不会覆盖本插件（独立 KOReader 插件目录），卸载本扩展即可还原。

契约见 examples/moonsource-demo.koplugin/moon_source.lua 头注释。

- provides.source = false：不进数据源列表，不需要 meta / new。
- provides.features.panel 往月读的阅读快捷面板追加动作，id 由月读补成 ext.xrayreset.reset。
- 动作默认追加在内置 feature 之后，与「X-Ray」「刷新 X-Ray」并列。
--]]

local _ = require("gettext")

local ID = "ext.xrayreset"

local features = {
    panel = {
        actions = function()
            -- 延迟 require：月读加载插件时本扩展的描述文件可能先于月读模块就绪。
            return require("xrayreset.reset").actions()
        end,
    },
}

return {
    api = 1,
    id = ID,
    provides = { source = false, features = features },
}
