---@diagnostic disable: undefined-field, missing-fields, redundant-parameter, missing-parameter, inject-field, assign-type-mismatch, param-type-mismatch, cast-type-mismatch, return-type-mismatch, cast-local-type

--[[-- reader.highlight_menu：划词按钮显隐门控、来源扫描与排序。 --]]

local Assert = require("support.assert")
local Stubs = require("support.stubs")
Stubs.install()
Stubs.reset()

package.preload["l10n"] = function() return { apply = function() end } end
package.preload["gettext"] = function() return function(value) return value end end
package.preload["ui/widget/buttondialog"] = function() return {} end

local settings = {
    reader_popup_buttons = { dictionary = false, qrcode = false },
    reader_popup_button_order = { "translate", "dictionary" },
    reader_popup_seen = {},
}
local saves = 0
package.preload["utils.settings"] = function()
    return {
        get = function() return settings end,
        save = function(owner)
            Assert.eq(owner, "reader")
            saves = saves + 1
        end,
    }
end

local factories = {
    ["06_dictionary"] = function()
        return { text = "Dictionary" }
    end,
    ["12_generate_qr_code"] = function()
        return { text = "Generate QR code" }
    end,
}

-- ReaderHighlight 类 stub 带原生 onHold / onHoldRelease：按住弹菜单补丁要包它们，
-- 装上时就看得见原生方法，不用像别的补丁那样等补丁装完再摆回来。
local hold_returns = true
local release_calls = 0
local ReaderHighlight = {
    onHold = function(self, arg, ges)
        self.hold_arg = { arg = arg, ges = ges }
        return hold_returns
    end,
    onHoldRelease = function(self)
        release_calls = release_calls + 1
        return "native"
    end,
}
package.preload["apps/reader/modules/readerhighlight"] = function() return ReaderHighlight end

-- highlight 实例经 __index 走类 stub：self:onShowHighlightMenu() / self:onHoldRelease() 都在类上。
local highlight = setmetatable({ _highlight_buttons = factories }, { __index = ReaderHighlight })
local ui = { highlight = highlight }

local HighlightMenu = require("reader.highlight_menu")
HighlightMenu.ensureWrapped(highlight)

local dict = highlight._highlight_buttons["06_dictionary"]({}, nil)
Assert.is_false(dict.show_in_highlight_dialog_func())

local qr = highlight._highlight_buttons["12_generate_qr_code"]({}, nil)
Assert.is_false(qr.show_in_highlight_dialog_func())

settings.reader_popup_buttons.dictionary = true
Assert.is_true(dict.show_in_highlight_dialog_func())

HighlightMenu.ensureWrapped(highlight)
local dict2 = highlight._highlight_buttons["06_dictionary"]({}, nil)
Assert.is_true(dict2.show_in_highlight_dialog_func())

factories["07_translate"] = function() return { text = "Translate" } end
HighlightMenu.ensureWrapped(highlight)
local ordered = HighlightMenu.orderedFactories(highlight)
Assert.eq(ordered[1].index, "07_translate")
Assert.eq(ordered[2].index, "06_dictionary")

-- 来源：按工厂函数所在文件判断
local function defined_in(path)
    return load("return function() return { text = 'x' } end", "@" .. path)()
end
Assert.eq(HighlightMenu.originOf(defined_in("/mnt/us/koreader/plugins/qrclipboard.koplugin/main.lua")), "plugin:qrclipboard")
Assert.eq(HighlightMenu.originOf(defined_in("/mnt/us/koreader/plugins/book.koplugin/features/ai/explain.lua")), "book")
Assert.eq(HighlightMenu.originOf(defined_in("frontend/apps/reader/modules/readerhighlight.lua")), "koreader")
Assert.eq(HighlightMenu.originOf(defined_in("/mnt/us/koreader/patches/2-my-button.lua")), "patch:2-my-button")
Assert.eq(HighlightMenu.originOf(defined_in("somewhere.lua")), "unknown")

-- 未登记的按钮也受控：扫描记下来源，设置项 id 就是原键，可单独屏蔽
local saves_before = saves
factories["12_0_make_handmade_toc_item"] = defined_in("frontend/apps/reader/modules/readerhandmade.lua")
HighlightMenu.ensureWrapped(highlight)
Assert.eq(settings.reader_popup_seen["12_0_make_handmade_toc_item"].origin, "koreader")
Assert.eq(settings.reader_popup_seen.translate.origin, "unknown", "登记过的按钮按设置项 id 记")
Assert.is_true(saves > saves_before)
local toc_button = highlight._highlight_buttons["12_0_make_handmade_toc_item"]({}, nil)
Assert.is_true(toc_button.show_in_highlight_dialog_func())
settings.reader_popup_buttons["12_0_make_handmade_toc_item"] = false
Assert.is_false(toc_button.show_in_highlight_dialog_func())

-- 再扫一遍不重复包装、来源没变不落盘
saves_before = saves
local wrapped_toc = highlight._highlight_buttons["12_0_make_handmade_toc_item"]
HighlightMenu.ensureWrapped(highlight)
Assert.eq(highlight._highlight_buttons["12_0_make_handmade_toc_item"], wrapped_toc)
Assert.eq(saves, saves_before)

-- 原生移除后用同一个键重新注册：新工厂也要挂上门控
factories["12_0_make_handmade_toc_item"] = defined_in("frontend/apps/reader/modules/readerhandmade.lua")
HighlightMenu.ensureWrapped(highlight)
Assert.is_false(highlight._highlight_buttons["12_0_make_handmade_toc_item"]({}, nil).show_in_highlight_dialog_func())

-- 扫描到的按钮进排序：排在内置默认顺序之后
local order = HighlightMenu.order()
Assert.eq(order[#order], "12_0_make_handmade_toc_item")

-- 弹窗时已注册的就是全部：卸掉的插件按钮从设置页消失，显隐设置保留
-- ReaderHighlight stub 见前（已带原生 onHold / onHoldRelease）。
package.preload["ui/widget/buttondialog"] = function()
    return { new = function(_, o) o.movable = { dimen = {} } return o end }
end
package.preload["reader.selection"] = function()
    return { enabled = function() return false end, attach = function() return true end }
end
package.loaded["ui/widget/buttondialog"] = nil
HighlightMenu.install(nil)
settings.reader_popup_seen["12_gone_plugin"] = { title = "Gone", origin = "plugin:gone" }
-- 用户调过顺序：保存的顺序里也有它
local saved_order = HighlightMenu.order()
settings.reader_popup_button_order = saved_order
Assert.is_true(table.concat(saved_order, ","):find("12_gone_plugin", 1, true) ~= nil)
highlight.selected_text = { text = "x" }
ReaderHighlight.onShowHighlightMenu(highlight)
Assert.is_nil(settings.reader_popup_seen["12_gone_plugin"])
Assert.is_nil(table.concat(HighlightMenu.order(), ","):find("12_gone_plugin", 1, true),
    "保存的顺序里还有，也不再列出")
Assert.eq(settings.reader_popup_button_order, saved_order, "保存的顺序不动")
Assert.not_nil(settings.reader_popup_seen["12_0_make_handmade_toc_item"])
Assert.is_false(settings.reader_popup_buttons["12_0_make_handmade_toc_item"], "显隐设置不动")
Assert.not_nil(highlight.highlight_dialog)
Assert.is_nil(highlight.highlight_dialog._added_widgets)

-- 按住起手即弹菜单：选中的文字写进菜单标题，抬头就知选对了没有。
-- 真 utils.text 的 truncateUtf8 按字符截：中文标题限长不吃字节。
package.preload["ui/uimanager"] = function()
    return { show = function() end, setDirty = function() end, close = function() end }
end

-- 起手选词成功：立刻弹菜单，标题就是选中的文字。
local empty = table.remove(settings.reader_popup_button_order, 2)
highlight.selected_text = { text = "x" }
highlight.highlight_dialog = nil
hold_returns = true
ReaderHighlight.onHold(highlight)
Assert.not_nil(highlight.highlight_dialog, "按住即弹菜单，不等松手")
Assert.eq(highlight.highlight_dialog.title, "x", "菜单标题显示当前选中的文字")

-- 菜单已经开着又按住别处：不连弹两次。
ReaderHighlight.onHold(highlight)
Assert.eq(highlight.highlight_dialog.title, "x", "菜单开着不重弹")

-- 原生没接住（按在图片 / 页外 / 长按设成什么都不做）：不弹。
highlight.selected_text = { text = "y" }
highlight.highlight_dialog = nil
hold_returns = false
Assert.is_false(ReaderHighlight.onHold(highlight))
Assert.is_nil(highlight.highlight_dialog, "没选上文字不弹菜单")
hold_returns = true

-- 松手不重复弹：起手弹的那个还开着，不吃原生的查词典 / 默认动作。
highlight.highlight_dialog = "menu"
ReaderHighlight.onHoldRelease(highlight)
Assert.eq(release_calls, 0, "菜单开着：松手归菜单自理，不再走原生")

-- 标题：折行压平，超长截断。
highlight.highlight_dialog = nil
highlight._getDialogAnchor = function() return nil end
highlight.selected_text = { text = "  第一行\n\n  第二行  " }
ReaderHighlight.onShowHighlightMenu(highlight)
Assert.eq(highlight.highlight_dialog.title, "第一行 第二行")
highlight.selected_text = { text = ("长"):rep(200) }
ReaderHighlight.onShowHighlightMenu(highlight)
-- truncateUtf8 按字节不切断字符：118 字节 = 39 个中文字，加省略号约 40 字，
-- 一行放得下墨屏菜单（x_smalltfont 一行约 55 字）。
Assert.eq(highlight.highlight_dialog.title, ("长"):rep(39) .. "…", "标题限长，超长加省略号")

-- 关掉按住即弹：起手只选词不弹菜单，回到原生松手才弹的节奏。
settings.reader_popup_on_hold = false
highlight.highlight_dialog = nil
Assert.is_false(HighlightMenu.onHoldEnabled())
ReaderHighlight.onHold(highlight)
Assert.is_nil(highlight.highlight_dialog, "关掉后按住不弹菜单")

-- 已有标注的菜单仍带标题（划过的段落点出来一样看得到原文）。
highlight.selected_text = { text = "标注原文" }
highlight.ui = { annotation = { annotations = { { text = "旧标注" } } } }
ReaderHighlight.onShowHighlightMenu(highlight, 1)
Assert.eq(highlight.highlight_dialog.title, "旧标注")
highlight.ui = nil

table.insert(settings.reader_popup_button_order, 2, empty)
