--[[--
划词工具栏：复用 KOReader 原生 ButtonDialog，按 Book 设置裁剪、排序并五列排版。

按钮工厂、回调、锚点和关闭行为全部保持原生；这里只接管收集和分行。
所有已注册按钮（KOReader 自带、其它插件、用户补丁、本插件）都受显隐与排序设置控制：
弹窗时扫描到的按钮记进 `reader_popup_seen`（设置键 → { title, origin }），设置页据此列出。

原生长按起手只选词不高亮菜单，要松手才弹窗：滑完才发现选错就得整段重来。
这里让按住起手即弹窗（`reader_popup_on_hold` 可关），并把选中的文字写进菜单标题，
抬手即知选对了没有。松手不重复弹窗、不抢原生查词典。

@module koplugin.book.reader.highlight_menu
--]]

require("l10n").apply()

local MoonSettings = require("utils.settings")
local Ext = require("utils.extension")
local Text = require("utils.text")
local _ = require("gettext")

---@class BookReaderHighlightMenu
local HighlightMenu = {}

local TOOLBAR_COLUMNS = 5

--- ReaderHighlight._highlight_buttons 键 → 设置项 id；不在表里的按钮直接用原键作设置项 id。
---@type table<string, string>
local INDEX_TO_KEY = {
    ["01_select"] = "select",
    ["02_highlight"] = "highlight",
    ["03_copy"] = "copy",
    ["04_add_note"] = "add_note",
    ["05_wikipedia"] = "wikipedia",
    ["06_dictionary"] = "dictionary",
    ["07_translate"] = "translate",
    ["09_view_html"] = "view_html",
    ["12_generate_qr_code"] = "qrcode",
    ["12_search"] = "search",
    ["12_xray_lookup"] = "xray",
    ["12_ai_explain"] = "ai_explain",
}

local OWN_PLUGIN = debug.getinfo(1, "S").source:match("([^/]+)%.koplugin/")

---@param index string
---@return string
local function keyOf(index)
    return INDEX_TO_KEY[index] or index
end

--- 按钮工厂定义在哪：`book`（本插件）、`koreader`、`plugin:<目录名>`、`patch:<文件名>`、`unknown`。
---@param factory function
---@return string
function HighlightMenu.originOf(factory)
    local source = debug.getinfo(factory, "S").source
    local plugin = source:match("([^/]+)%.koplugin/")
    if plugin then
        return plugin == OWN_PLUGIN and "book" or "plugin:" .. plugin
    end
    local patch = source:match("patches/([^/]+)%.lua$")
    if patch then return "patch:" .. patch end
    if source:find("frontend/", 1, true) then return "koreader" end
    return "unknown"
end

--- 记下扫描到的按钮字段，有变化才落盘。
---@param key string
---@param field "title"|"origin"
---@param value string
local function remember(key, field, value)
    local reader = MoonSettings.get("reader")
    local entry = reader.reader_popup_seen[key]
    if not entry then
        entry = {}
        reader.reader_popup_seen[key] = entry
    end
    if entry[field] == value then return end
    entry[field] = value
    MoonSettings.save("reader")
end

--- 划词弹窗某项是否应在菜单中显示。
---@param key string
---@return boolean
function HighlightMenu.isEnabled(key)
    return MoonSettings.get("reader").reader_popup_buttons[key] ~= false
end

--- 按住起手是否立即显示划词菜单（reader_popup_on_hold，缺省开）。
---@return boolean
function HighlightMenu.onHoldEnabled()
    return MoonSettings.get("reader").reader_popup_on_hold ~= false
end

--- 合并用户顺序、内置默认顺序与扫描到的按钮，旧配置或重复项不会让按钮消失。
--- 用户顺序里既非内置、又已被 forgetMissing 忘掉的键（卸掉的插件）不列出；期间没调过顺序的话，
--- 装回来重新扫到就照旧排回原位。
---@return string[]
function HighlightMenu.order()
    local reader = MoonSettings.get("reader")
    local defaults = require("reader.setting").defaults.reader_popup_button_order
    local builtin = {}
    for _idx, key in ipairs(defaults) do builtin[key] = true end
    local out, seen = {}, {}
    for _idx, key in ipairs(reader.reader_popup_button_order or {}) do
        if type(key) == "string" and not seen[key] and (builtin[key] or reader.reader_popup_seen[key]) then
            out[#out + 1], seen[key] = key, true
        end
    end
    for _idx, key in ipairs(defaults) do
        if not seen[key] then
            out[#out + 1], seen[key] = key, true
        end
    end
    local scanned = {}
    for key in pairs(reader.reader_popup_seen) do
        if not seen[key] then scanned[#scanned + 1] = key end
    end
    table.sort(scanned)
    for _idx, key in ipairs(scanned) do out[#out + 1] = key end
    return out
end

--- 按用户顺序列出当前已注册的工厂；未知插件按钮稳定地排在末尾。
---@param highlight table
---@return { index: string, factory: function }[]
function HighlightMenu.orderedFactories(highlight)
    local position = {}
    for i, key in ipairs(HighlightMenu.order()) do
        position[key] = i
    end
    local factories = {}
    for index, factory in pairs(highlight._highlight_buttons or {}) do
        factories[#factories + 1] = {
            index = index,
            factory = factory,
            position = position[keyOf(index)] or math.huge,
        }
    end
    table.sort(factories, function(a, b)
        if a.position ~= b.position then
            return a.position < b.position
        end
        return a.index < b.index
    end)
    return factories
end

---@param fn function
---@param key string
---@return function
local function wrapFactory(fn, key)
    return function(this, index)
        local button = fn(this, index)
        if not button then
            return button
        end
        -- 事件 id 保持不变；按钮行为被扩展接管时由它给新名字。
        for _idx, relabel in ipairs(Ext.list("highlight.relabel")) do
            local text = relabel(key)
            if text then
                button.text = text
                break
            end
        end
        local orig_show = button.show_in_highlight_dialog_func
        button.show_in_highlight_dialog_func = function()
            if not HighlightMenu.isEnabled(key) then
                return false
            end
            return not orig_show or orig_show()
        end
        return button
    end
end

--- 给当前 ReaderHighlight 实例的全部按钮挂上显隐门控并记下来源（含晚注册、重新注册的按钮）。
---@param highlight table|nil
function HighlightMenu.ensureWrapped(highlight)
    if not highlight or not highlight._highlight_buttons then
        return
    end
    -- 按工厂函数而非键记：原生自定义目录开关时会移除再注册同一个键。
    highlight._book_popup_wrapped = highlight._book_popup_wrapped or {}
    local wrapped = highlight._book_popup_wrapped
    for idx, factory in pairs(highlight._highlight_buttons) do
        if not wrapped[factory] then
            local key = keyOf(idx)
            remember(key, "origin", HighlightMenu.originOf(factory))
            local wrapper = wrapFactory(factory, key)
            wrapped[wrapper] = true
            highlight._highlight_buttons[idx] = wrapper
        end
    end
end

--- 菜单标题里显示的选中文字：折行压平、限长，超长截断加省略号。
--- 墨屏菜单很窄，整段长文选进来会把按钮挤出屏幕。
---@param highlight table ReaderHighlight
---@param index number|nil 已有标注的序号（nil = 新划词）
---@return string|nil
local function selectionTitle(highlight, index)
    local selected = highlight.selected_text
    local text
    if index then
        local annotation = highlight.ui and highlight.ui.annotation and highlight.ui.annotation.annotations
        text = annotation and annotation[index] and annotation[index].text
    else
        text = selected and selected.text
    end
    if type(text) ~= "string" then
        return nil
    end
    text = text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if #text == 0 then
        return nil
    end
    -- 118 / 120 都是字节口径（#text 按字节）；一行放得下墨屏菜单的中文约 39 字。
    if #text > 120 then
        text = Text.truncateUtf8(text, 118) .. "…"
    end
    return text
end

--- 弹窗时已注册的按钮就是全部：卸掉的插件、删掉的补丁不再留在设置页。显隐与顺序设置不动，装回来照旧生效。
---@param highlight table ReaderHighlight
local function forgetMissing(highlight)
    local present = {}
    for idx in pairs(highlight._highlight_buttons) do present[keyOf(idx)] = true end
    local reader = MoonSettings.get("reader")
    local changed = false
    for key in pairs(reader.reader_popup_seen) do
        if not present[key] then
            reader.reader_popup_seen[key] = nil
            changed = true
        end
    end
    if changed then MoonSettings.save("reader") end
end

--- 在 ReaderHighlight 类上挂一次钩子，弹窗前补齐按钮门控。
--- 必须在弹窗时机而非安装时机包装，因为别的插件会晚注册按钮；类级标记保证只打一次补丁。
local function patchShowMenu()
    local ReaderHighlight = require("apps/reader/modules/readerhighlight")
    if ReaderHighlight._book_popup_patched then
        return
    end
    ReaderHighlight._book_popup_patched = true
    --- 原生实现把 columns 写死为 2。保留其余生命周期，仅改为工具栏五列与可配顺序。
    ---@param self table ReaderHighlight
    ---@param index number|nil 已有标注的序号；新划词为 nil
    local function showMenu(self, index)
        HighlightMenu.ensureWrapped(self)
        if not self.selected_text then
            return
        end
        -- 扫描页选区没有文字层：先 OCR，按钮才拿得到文字；识别不出来就提示并不弹菜单。
        local fill = Ext.last("highlight.fill_selection")
        if fill and not fill(self) then
            return
        end
        forgetMissing(self)
        local ButtonDialog = require("ui/widget/buttondialog")
        local UIManager = require("ui/uimanager")
        local buttons = { {} }
        for _idx, item in ipairs(HighlightMenu.orderedFactories(self)) do
            local button = item.factory(self, index)
            local title = button.text or button.text_func and button.text_func()
            if title then remember(keyOf(item.index), "title", title) end
            if not button.show_in_highlight_dialog_func or button.show_in_highlight_dialog_func() then
                if #buttons[#buttons] >= TOOLBAR_COLUMNS then
                    buttons[#buttons + 1] = {}
                end
                buttons[#buttons][#buttons[#buttons] + 1] = button
            end
        end
        self.highlight_dialog = ButtonDialog:new{
            buttons = buttons,
            -- 菜单标题就是当前选中的文字：按住起手即弹窗，选的是什么一眼可见；
            -- 滑动改选区后菜单重开，标题跟着换成新选区的文字。
            title = selectionTitle(self, index),
            anchor = function()
                local Selection = require("reader.selection")
                if not index and Selection.enabled() then
                    local placed, pop_down = Selection.menuAnchorFor(self, self.highlight_dialog)
                    if placed then
                        return placed, pop_down
                    end
                end
                return self:_getDialogAnchor(self.highlight_dialog, index)
            end,
            tap_close_callback = function()
                if self.hold_pos then
                    self:clear()
                end
            end,
        }
        local dialog = self.highlight_dialog
        -- 原生 "[ui]" 不带区域 = 整屏刷新；这里只刷菜单自身，"[ui]" 仍禁止合并（Sage 内核 alpha 混合 bug）。
        UIManager:show(dialog, function()
            return "[ui]", dialog.movable.dimen
        end)
        -- 没挂手柄时选区可能刚变（原生 extendSelection 不自刷），按原生刷整屏。
        if not require("reader.selection").attach(self, index) then
            UIManager:setDirty(nil, "[ui]")
        end
        return true
    end
    ReaderHighlight.onShowHighlightMenu = require("ui.guard").wrap("highlight menu", showMenu)
end

--- 按住起手就把划词菜单显示出来：选中的文字直接写在菜单标题里，
--- 选错抬手就走，不用等滑完、更不用等松手弹窗才发现选错了段。
--- 只接管新划词（onShowHighlightMenu 的 index 为 nil）；已有标注的菜单仍走原生。
local function patchHoldMenu()
    local ReaderHighlight = require("apps/reader/modules/readerhighlight")
    if ReaderHighlight._book_hold_menu_patched then
        return
    end
    ReaderHighlight._book_hold_menu_patched = true

    local orig_on_hold = ReaderHighlight.onHold
    function ReaderHighlight:onHold(arg, ges)
        local handled = orig_on_hold(self, arg, ges)
        -- 原生没接住（按住图片 / 页外 / 长按设成「什么都不做」）时不弹。
        -- 已划词后菜单开着又按住别处：等松手，避免连弹两次。
        if handled and self.selected_text and not self.highlight_dialog
            and HighlightMenu.onHoldEnabled() then
            self:onShowHighlightMenu()
        end
        return handled
    end

    local orig_on_hold_release = ReaderHighlight.onHoldRelease
    function ReaderHighlight:onHoldRelease()
        -- 起手已经弹了菜单：松手归菜单自理（按钮已够用），
        -- 不再走原生的查词典 / 默认动作，否则同一个选区上会叠两个窗。
        if self.highlight_dialog then
            return true
        end
        return orig_on_hold_release(self)
    end
end

--- 安装划词弹窗显隐门控；重复调用无副作用。
---@param ui table|nil
function HighlightMenu.install(ui)
    patchShowMenu()
    patchHoldMenu()
    if not ui or not ui.highlight then
        return
    end
    HighlightMenu.ensureWrapped(ui.highlight)
    -- Reader onCreate 在 ReaderReady 事件内执行，此时 postInitCallback 已被清空。
    if ui.registerPostReaderReadyCallback then
        ui:registerPostReaderReadyCallback(function()
            HighlightMenu.ensureWrapped(ui.highlight)
        end)
    end
end

return HighlightMenu
