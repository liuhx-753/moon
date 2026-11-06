--[[--
X-Ray 重置：清掉当前书的全部 X-Ray 数据（实体、续扫游标、墓碑、已识别章节记录）。

独立于月读插件的扩展：月读更新不会覆盖这里，卸载这个扩展即可还原。

四张表的名单与月读 features/xray/events.lua 的 book_removed 一致，
逐表经 DB.removeIdentity 删，不另写 SQL、不另起事务。墓碑也清：
重置就是不保留任何历史，删过的实体重新生成时还能收录。

@module koplugin.xrayreset.xrayreset
--]]

-- 月读的翻译模块只在月读装好后才在 package.path 上；没装月读时这里不能硬失败，
-- 插件整体降级为「只有月读才能用」，但不影响 KOReader 其它部分启动。
pcall(function() require("l10n").apply() end)

local _ = require("gettext")

local XrayReset = {}

--- 清掉这本书全部 X-Ray 数据的表名单。顺序与月读 events.lua 的 book_removed 一致。
local TABLES = { "xray_entities", "xray_scan", "xray_removed", "xray_chapter" }

--- 当前阅读会话的书籍身份；没有会话时 nil。
---@return BookIdentity|nil
local function currentIdentity()
    local ok, Session = pcall(require, "reader.session")
    if not ok then return nil end
    local current = Session.current()
    return current and current.identity
end

--- 弹一条 3 秒自动消失的提示。
---@param text string
local function info(text)
    require("ui.themes.widgets.toast"):new{ text = text, timeout = 3 }:show()
end

--- 本书 X-Ray 是否正在生成（任务在跑就不能删：删完会被写回半截结果）。
---@param identity BookIdentity
---@return boolean
local function running(identity)
    local ok, Tasks = pcall(require, "workers.tasks")
    if not ok then return false end
    local key = "xray\0" .. identity.source_id .. "\0" .. identity.stable_id
    return Tasks.get(key) ~= nil
end

--- 删掉这本书的四张表数据。
---@param identity BookIdentity
---@return boolean ok
function XrayReset.clear(identity)
    local ok, DB = pcall(require, "utils.db")
    if not ok then return false end
    for _idx, tbl in ipairs(TABLES) do
        if not DB.removeIdentity(tbl, identity.source_id, identity.stable_id) then
            return false
        end
    end
    return true
end

--- 重置此书 X-Ray：先确认，确认后清掉这本书全部数据。
--- 询问期间任务可能从 waiting 被唤醒接着写库，所以检查必须放在确认回调里、
--- 真正删除之前，不能拦在确认框弹出前：框开着时扫描继续，删完又被写回半截结果。
---@param ui table|nil
function XrayReset.run(ui)
    local identity = currentIdentity()
    if not identity then
        info(_("当前书籍没有可用身份"))
        return
    end
    require("ui.themes.widgets.confirm"):new{
        text = _("重置此书 X-Ray？将清空已收录的人物 / 地点 / 专有名词、删除记录与分析进度，之后需重新生成。"),
        ok_text = _("重置"),
        ok_callback = function()
            -- 真正删除前再看一眼：确认框开着时任务可能已从 waiting 唤醒。
            if running(identity) then
                info(_("本书 X-Ray 正在生成，请先取消或等待完成"))
                return
            end
            if not XrayReset.clear(identity) then
                info(_("重置失败"))
                return
            end
            local ok, Marks = pcall(require, "features.xray.marks")
            if ok and Marks.invalidate then Marks.invalidate() end
            info(_("已重置此书 X-Ray"))
        end,
    }:show()
end

--- 快捷面板动作：与月读内置的「X-Ray」「刷新 X-Ray」并列。
---@return BookQuickPanelAction[]
function XrayReset.actions()
    return {
        {
            id = "reset",
            title = _("重置此书 X-Ray"),
            icon = "delete",
            scope = "reader",
            available = function()
                local ok, Xray = pcall(require, "features.xray")
                if not ok or type(Xray) ~= "table" then return false end
                local available_ok, enabled = pcall(Xray.available, Xray)
                if not available_ok or not enabled then return false end
                return currentIdentity() ~= nil
            end,
            ---@param ctx BookQuickPanelContext
            run = function(ctx)
                XrayReset.run(ctx.ui)
            end,
        },
    }
end

return XrayReset
