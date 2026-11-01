-- Panel s historií úprav záběru: seznam kroků od nejnovějšího, u každého popis a stáří. Klik na krok vrátí záběr do stavu po něm
-- (jde vrátit zpět jako každá úprava), kolečko listuje. Záznamy drží CinemaHistory, ukládá je CinemaStorage.

local E = CinemaEditorScreen
local S = CinemaShot
local H = CinemaHistory
local M = CinemaMath

E.HISTORY_W = 0.27

local function t(key)
    return g_i18n:getText(key)
end

-- Řádky panelu od nejnovějšího: { label, extra, time, snap, current, origin }. Krok, který nic nezměnil, se vynechá.
-- Stav po kroku je snímek dalšího záznamu (u posledního současný stav). Řádky se přepočítají jen po změně záběru nebo historie.
function CinemaEditorScreen:historyRows()
    local key = string.format("%d:%d", #self.history, self.shot.version)
    if self.historyCache ~= nil and (self.historyCache.key == key or self.drag ~= nil) then
        return self.historyCache.rows
    end
    local rows = {}
    local after = S.clone(self.shot)
    for i = #self.history, 1, -1 do
        local entry = self.history[i]
        local described = entry.described
        if described == nil or described.after ~= after then
            local label, extra = H.describe(entry.snap, after)
            described = { after = after, label = label, extra = extra }
            entry.described = described
        end
        local label, extra = described.label, described.extra
        if label ~= nil then
            rows[#rows + 1] = { label = label, extra = extra, time = entry.time, snap = after }
        end
        after = entry.snap
    end
    if #rows > 0 then
        rows[1].current = true
        rows[#rows + 1] = { origin = true, time = self.history[1].time, snap = after }
    end
    self.historyCache = { key = key, rows = rows }
    return rows
end

function CinemaEditorScreen:toggleHistory()
    self.historyOpen = not self.historyOpen
    self.historyScroll, self.historyHover = 0, nil
end

-- Rámeček panelu: u okraje opačného než boční panel, mezi horní mezí a spodní mezí nad osou; řádků se vejde cap.
function CinemaEditorScreen:getHistoryLayout()
    local floor = self:getMenuFloor()
    local cap = math.max(math.floor((E.DOCK_TOP - floor - E.MENU_PAD) / E.MENU_LINE) - 1, 3)
    local rows = self:historyRows()
    local shown = math.max(math.min(#rows, cap), 1)
    local h = (shown + 1) * E.MENU_LINE + E.MENU_PAD
    local x = self.dock == "right" and E.DOCK_MARGIN or 1 - E.DOCK_MARGIN - E.HISTORY_W
    return x, E.DOCK_TOP - h, E.HISTORY_W, h, shown, rows
end

local function rowLabel(row)
    if row.origin then
        return t("cine_hist_origin")
    end
    local text = t(row.label)
    if row.extra > 0 then
        text = string.format(t("cine_hist_more"), text, row.extra)
    end
    return text
end

local function ageText(seconds)
    local key, n = H.age(math.max(seconds, 0))
    if n == 0 then
        return t(key)
    end
    return string.format(t(key), n)
end

function CinemaEditorScreen:drawHistory()
    local ui = E.UI
    local x, y, w, h, shown, rows = self:getHistoryLayout()
    local alpha = self.freeLook and 0.8 or 1
    drawFilledRect(x - 0.002, y - 0.003, w + 0.004, h + 0.006, 0, 0, 0, alpha)
    drawFilledRect(x, y, w, h, ui.panel[1], ui.panel[2], ui.panel[3], alpha)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(true)
    setTextColor(ui.keySelected[1], ui.keySelected[2], ui.keySelected[3], 1)
    renderText(x + E.MENU_PAD, y + h - E.MENU_LINE + E.MENU_PAD * 0.6, E.MENU_TEXT * 1.05, string.format(t("cine_hist_title"), #rows))
    setTextBold(false)
    if #rows == 0 then
        setTextColor(ui.dim[1], ui.dim[2], ui.dim[3], ui.dim[4] or 1)
        renderText(x + E.MENU_PAD, y + h - 2 * E.MENU_LINE + E.MENU_PAD * 0.9, E.MENU_TEXT, t("cine_hist_empty"))
        setTextColor(1, 1, 1, 1)
        return
    end
    local now = H.now()
    local first = M.clamp(self.historyScroll, 0, math.max(#rows - shown, 0))
    self.historyScroll = first
    for k = 1, shown do
        local row = rows[first + k]
        local rowY = y + h - (k + 1) * E.MENU_LINE
        if not self.freeLook and self.historyHover == k then
            drawFilledRect(x, rowY, w, E.MENU_LINE, ui.track[1] + 0.12, ui.track[2] + 0.12, ui.track[3] + 0.14, 1)
        end
        local c = row.current and ui.keySelected or ui.text
        setTextColor(c[1], c[2], c[3], c[4] or 1)
        setTextAlignment(RenderText.ALIGN_LEFT)
        renderText(x + E.MENU_PAD, rowY + E.MENU_PAD * 0.9, E.MENU_TEXT, rowLabel(row))
        setTextColor(ui.dim[1], ui.dim[2], ui.dim[3], ui.dim[4] or 1)
        setTextAlignment(RenderText.ALIGN_RIGHT)
        renderText(x + w - E.MENU_PAD, rowY + E.MENU_PAD * 0.9, E.MENU_TEXT * 0.85, row.current and t("cine_hist_current") or ageText(now - row.time))
    end
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
end

-- Záběr se vrátí do stavu po kroku row (krok zpět ho zase vrátí).
function CinemaEditorScreen:restoreHistory(row)
    if row == nil or row.current then
        return
    end
    self:pushUndo()
    S.restore(self.shot, row.snap)
    self:afterHistory()
    self:showMessage(string.format(t("cine_msg_historyRestored"), rowLabel(row)))
end

-- Myš nad panelem: najetí zvýrazní řádek, kolečko listuje, klik vrací záběr. Vrací true, když událost patřila panelu.
function CinemaEditorScreen:historyMouseEvent(px, py, isDown, button)
    if not self.historyOpen or self.freeLook or self.clean then
        return false
    end
    local x, y, w, h, shown, rows = self:getHistoryLayout()
    if px < x or px > x + w or py < y or py > y + h then
        self.historyHover = nil
        return false
    end
    local k = math.floor((y + h - py) / E.MENU_LINE)
    self.historyHover = (k >= 1 and k <= shown) and k or nil
    if isDown and (button == Input.MOUSE_BUTTON_WHEEL_UP or button == Input.MOUSE_BUTTON_WHEEL_DOWN) then
        local delta = button == Input.MOUSE_BUTTON_WHEEL_UP and -1 or 1
        self.historyScroll = M.clamp(self.historyScroll + delta * 2, 0, math.max(#rows - shown, 0))
    elseif isDown and button == Input.MOUSE_BUTTON_LEFT and self.historyHover ~= nil then
        E.playSound("CLICK")
        self:restoreHistory(rows[M.clamp(self.historyScroll, 0, math.max(#rows - shown, 0)) + self.historyHover])
    end
    return true
end
