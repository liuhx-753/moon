--[[--
X-Ray 重置扩展：删四张表、确认后才动数据、任务在跑时不动数据。

独立插件，不进月读仓库；测试放本仓库跑，验证行为与原 PR 一致。
--]]

local Assert = require("support.assert")

package.preload["l10n"] = function() return { apply = function() end } end
package.preload["gettext"] = function() return function(value) return value end end

--- 删表记录：{ sql, args }
local calls = {}
local remove_ok = true
package.preload["utils.db"] = function()
    return {
        removeIdentity = function(tbl, source_id, stable_id)
            calls[#calls + 1] = { tbl = tbl, source_id = source_id, stable_id = stable_id }
            return remove_ok
        end,
    }
end

local toasts = {}
package.preload["ui.themes.widgets.toast"] = function()
    return { new = function(_, opts)
        opts.show = function() toasts[#toasts + 1] = opts.text end
        opts.close = function() end
        return opts
    end }
end

local confirm
package.preload["ui.themes.widgets.confirm"] = function()
    return { new = function(_, opts)
        opts.show = function() confirm = opts end
        return opts
    end }
end

local running_task
package.preload["workers.tasks"] = function()
    return { get = function() return running_task end }
end

local invalidated = 0
package.preload["features.xray.marks"] = function()
    return { invalidate = function() invalidated = invalidated + 1 end }
end

local identity = { source_id = "moon", stable_id = "book-1" }
package.preload["reader.session"] = function()
    return { current = function() return { identity = identity } end }
end

-- X-Ray 是否可用：真模块会去读月读的 settings（需要真实配置文件），这里只测开关本身。
local xray_available = true
package.preload["features.xray"] = function()
    return { available = function() return xray_available end }
end

--- 插件目录不在 package.path 上（它是要装到设备上的独立插件），直接按文件加载。
local XrayReset = dofile((_G.BOOK_TEST_ROOT or ".") .. "/xrayreset.koplugin/xrayreset/reset.lua")

-- 快捷面板动作：字段齐全，scope 为 reader。
local actions = XrayReset.actions()
Assert.eq(#actions, 1)
local action = actions[1]
Assert.eq(action.id, "reset")
Assert.eq(action.scope, "reader")
Assert.eq(action.title, "重置此书 X-Ray")
Assert.is_true(type(action.run) == "function")
Assert.is_true(type(action.available) == "function")

-- 有当前书身份时可用。
Assert.is_true(action.available())

-- 重置：先确认，确认前不动数据。
calls = {}
toasts = {}
confirm = nil
XrayReset.run(nil)
Assert.not_nil(confirm)
Assert.eq(confirm.ok_text, "重置")
Assert.len(calls, 0, "确认前不动数据")

-- 确认后删四张表：逐表 DELETE，名单与月读 events.lua 的 book_removed 一致。
confirm.ok_callback()
local tables = {}
for _idx, c in ipairs(calls) do
    tables[#tables + 1] = c.tbl
    Assert.eq(c.source_id, "moon")
    Assert.eq(c.stable_id, "book-1")
end
Assert.eq(table.concat(tables, ","), "xray_entities,xray_scan,xray_removed,xray_chapter")
Assert.eq(toasts[#toasts], "已重置此书 X-Ray")
Assert.eq(invalidated, 1, "标记缓存一起失效")

-- 删除失败：只提示，不算已重置。
calls = {}
toasts = {}
remove_ok = false
confirm = nil
XrayReset.run(nil)
confirm.ok_callback()
Assert.eq(toasts[#toasts], "重置失败")
remove_ok = true

-- 确认框开着时任务被唤醒：检查放在确认回调里、真正删除之前，不删数据只提示。
calls = {}
toasts = {}
confirm = nil
running_task = { key = "xray\0moon\0book-1" }
XrayReset.run(nil)
Assert.eq(confirm.ok_text, "重置", "有任务也先弹确认，不提前拦")
confirm.ok_callback()
Assert.len(calls, 0, "真正删除前再查任务，任务在跑不动数据")
Assert.eq(toasts[#toasts], "本书 X-Ray 正在生成，请先取消或等待完成")
running_task = nil

-- 没有当前书身份：提示并退出，不弹确认。
confirm = nil
package.preload["reader.session"] = function() return { current = function() return nil end } end
package.loaded["reader.session"] = nil
local XrayReset2 = dofile((_G.BOOK_TEST_ROOT or ".") .. "/xrayreset.koplugin/xrayreset/reset.lua")
XrayReset2.run(nil)
Assert.is_nil(confirm, "没有身份不弹确认")
Assert.eq(toasts[#toasts], "当前书籍没有可用身份")

return true
