-- Lišty editoru: horní (celý záběr: záběry, přehrávání, vozidla, pohledy, uložení) a lišta osy (úpravy osy a přidání na ukazatel),
-- nápověda k věci pod kurzorem a zvuky menu. Všechno na lištách jde i klávesou; klávesa je u tlačítka v zeleném čtverečku.

local E = CinemaEditorScreen
local S = CinemaShot
local Env = CinemaEnvironment
local rect, text, outline = E.gfx.rect, E.gfx.text, E.gfx.outline

E.TOOLBAR_H = 0.034
E.TOPBAR_H = 0.04
E.TOP_LIMIT = 1 - E.TOPBAR_H - 0.006 -- horní mez menu a panelů: pod horní lištou
E.TOOL_PAD = 0.007
E.TOOL_GAP = 0.004
E.TOOL_GROUP_GAP = 0.012
E.KBD_PAD = 0.003
E.BAR_X0 = 0.008
E.BAR_X1 = 0.992

local function t(key)
    return g_i18n:getText(key)
end

-- Zvuk herního menu (HOVER, CLICK…); chybějící vzorek nebo služba nic neudělá.
function E.playSound(name)
    local gui = g_gui
    if gui == nil or gui.soundPlayer == nil or GuiSoundPlayer == nil or GuiSoundPlayer.SOUND_SAMPLES == nil then
        return
    end
    local sample = GuiSoundPlayer.SOUND_SAMPLES[name]
    if sample ~= nil then
        pcall(gui.soundPlayer.playSample, gui.soundPlayer, sample)
    end
end

-- Položka lišty: label (klíč textu, s raw doslovný text, nebo funkce), hint, run(s, x, y), volitelně kbd (klávesa),
-- active / disabled / hidden (funkce), primary (zelená výplň), flat (bez dlaždice), kind = "text" (jen popisek).
-- Skupina s right = true se řadí od pravého okraje, tight = bez mezer mezi položkami.

local function noActors(s)
    return #s.shot.actors == 0
end

local function oneShot(s)
    return #s.index.files < 2
end

local function topbarGroups()
    return {
        { { kind = "text", raw = true, label = "CINEMA STUDIO", bold = true, color = E.UI.accent } },
        {
            tight = true,
            { raw = true, label = "<", hint = "cine_top_prev_h", flat = true, disabled = oneShot, run = function(s) s:switchShot(-1) end },
            { label = function(s) return string.format("%s  %d/%d", s.shot.name, s.index.active, #s.index.files) end, hint = "cine_top_shot_h",
                flat = true, run = function(s, x, y) s:openShotMenu(x, y) end },
            { raw = true, label = ">", hint = "cine_top_next_h", flat = true, disabled = oneShot, run = function(s) s:switchShot(1) end },
            { raw = true, label = "+", hint = "cine_top_new_h", flat = true, run = function(s) s:newShot() end },
        },
        {
            { label = "cine_tb_play", hint = "cine_tb_play_h", primary = true, run = function(s) s:onActionPlay() end },
            { label = "cine_tb_playStart", hint = "cine_tb_playStart_h", run = function(s) s:onActionPlayStart() end },
            { label = "cine_tb_playAll", hint = "cine_tb_playAll_h", disabled = oneShot, run = function(s) s:playAllShots() end },
        },
        {
            { label = "cine_top_reset", hint = "cine_top_reset_h", kbd = "R", disabled = noActors, run = function(s) s:onActionResetActors() end },
            { label = "cine_top_vehAt", hint = "cine_top_vehAt_h", kbd = "B", disabled = noActors, run = function(s) s:onActionResetHere() end },
            { label = "cine_top_follow", hint = "cine_top_follow_h", disabled = noActors, active = function(s) return s.vehiclesFollow == true end,
                run = function(s) s:toggleVehiclesFollow() end },
        },
        {
            { label = "cine_top_topdown", hint = "cine_top_topdown_h", kbd = "M", active = function(s) return s.topdown ~= nil end,
                run = function(s) s:onActionTopdown() end },
            { label = "cine_top_pick", hint = "cine_top_pick_h", kbd = "T", active = function(s) return s.picking end, run = function(s) s:onActionPick() end },
            { label = function(s) return s:boxLabel() end, hint = "cine_box_tb_h",
                active = function(s) return s.boxPlacing ~= nil or (s.picking and s.pendingAction ~= nil and s.pendingAction.box == true) end,
                run = function(s, x, y) s:openBoxMenu(x, y) end },
            { label = "cine_top_cross", hint = "cine_top_cross_h", active = function(s) return s.crosshair == true end,
                run = function(s) s:toggleCrosshair() end },
            { label = "cine_top_clean", hint = "cine_top_clean_h", kbd = "H", run = function(s) s:onActionClean() end },
            { label = "cine_top_env", hint = "cine_top_env_h", disabled = function() return not Env.available() end,
                active = function(s) return s.shot.env ~= nil end, run = function(s, x, y) s:openEnvironmentMenu(x, y) end },
            { label = function(s) return string.format(t("cine_top_camera"), s.shot.camIndex, #s.shot.cameras) end, hint = "cine_top_camera_h",
                kbd = "C", run = function(s, x, y) s:openCameraMenu(x, y) end },
        },
        {
            right = true,
            { kind = "text", bold = true, label = function(s) return string.format(t("cine_top_time"), s.playhead, S.duration(s.shot)) end,
                hint = "cine_top_time_h" },
            { label = "cine_top_save", hint = "cine_top_save_h", run = function(s) s:onActionSave() end },
            { raw = true, label = "?", hint = "cine_top_help_h", kbd = "F1", run = function(s) s:onActionHelp() end },
            { raw = true, label = "X", hint = "cine_top_close_h", run = function() g_gui:showGui("") end },
        },
    }
end

-- Akce, kterou lišta nabídne znovu jedním klikem (naposledy přidaná z panelu Přidat), jen na řádku kamery.
local function againHidden(s)
    return s.lastAction == nil or s.activeTarget ~= 0
end

E.ADD_HINTS = { camera = "cine_tb_action_h", vehicle = "cine_tb_actionVeh_h", person = "cine_tb_actionPerson_h", object = "cine_tb_actionObj_h" }

local function toolbarGroups()
    return {
        {
            { label = "cine_tb_undo", hint = "cine_tb_undo_h", disabled = function(s) return #s.undoStack == 0 end, run = function(s) s:onActionUndo() end },
            { label = "cine_tb_redo", hint = "cine_tb_redo_h", disabled = function(s) return #s.redoStack == 0 end, run = function(s) s:onActionRedo() end },
        },
        {
            { label = "cine_tb_snap", hint = "cine_tb_snap_h", run = function(s) s:onActionSnap() end, active = function(s) return s.snapOn ~= false end },
            { label = function(s) return t("cine_tb_mode_" .. s.editMode) end, hint = "cine_tb_mode_h", run = function(s) s:onActionEditMode() end,
                active = function(s) return s.editMode == "insert" end },
            { label = "cine_tb_split", hint = "cine_tb_split_h", run = function(s) s:onActionSplit() end },
            { label = "cine_tb_delete", hint = "cine_tb_delete_h", run = function(s) s:onActionKeyDelete() end },
        },
        {
            { raw = true, label = "-", hint = "cine_tb_zoomOut_h", run = function(s) s:zoomTimeline(-1, s:xAtTime(s.playhead)) end },
            { raw = true, label = "+", hint = "cine_tb_zoomIn_h", run = function(s) s:zoomTimeline(1, s:xAtTime(s.playhead)) end },
            { label = "cine_tb_all", hint = "cine_tb_zoomAll_h", run = function(s) s.viewSpan, s.viewStart = nil, nil end },
            { label = "cine_tb_curves", hint = "cine_tb_curves_h", run = function(s) s:onActionCurves() end, active = function(s) return s.curves end },
            { label = "cine_tb_big", hint = "cine_tb_big_h", run = function(s) s:toggleRowsBig() end, active = function(s) return s.rowsBig == true end },
            { label = "cine_tb_more", hint = "cine_tb_more_h", run = function(s, x, y) s:openMoreMenu(x, y) end,
                active = function(s) return s.dock ~= nil or s.historyOpen end },
            { label = "cine_tb_info", hint = "cine_tb_info_h", run = function(s, x, y) s:openInfoMenu(x, y) end },
        },
        {
            right = true,
            tight = true,
            { label = function(s)
                return s.keyAdvance and string.format(t("cine_tb_advance_on"), E.formatStep(s.keyStep or E.KEY_STEP_DEFAULT)) or t("cine_tb_advance_off")
            end, hint = "cine_tb_advance_h", active = function(s) return s.keyAdvance == true end, run = function(s) s:toggleKeyAdvance() end },
            { raw = true, label = "v", hint = "cine_tb_advanceStep_h", run = function(s, x, y) s:openKeyStepMenu(x, y) end },
        },
        {
            right = true,
            { label = function(s) return "+ " .. t(E.addTileName(s.lastAction.mode)) end, hint = "cine_tb_again_h", hidden = againHidden,
                run = function(s) s:repeatLastAction() end },
            { key = "cine_tb_action", label = function(s) return t(s:addRowKind() == "camera" and "cine_tb_addCamera" or "cine_tb_action") end,
                widthOf = { "cine_tb_action", "cine_tb_addCamera" },
                hint = function(s) return t(E.ADD_HINTS[s:addRowKind()]) end,
                active = function(s) return s.menu ~= nil and s.menu.panel == "add" end,
                run = function(s, x, y, entry) s:onAddButton(x, y, entry) end },
        },
    }
end

local function textOf(self, value, raw)
    if type(value) == "function" then
        return value(self)
    end
    return raw and value or t(value)
end

local function labelOf(self, item)
    local s = textOf(self, item.label, item.raw)
    return item.kind == "text" and s or E.upper(s)
end

local function isDisabled(self, item)
    return item.disabled ~= nil and item.disabled(self)
end

local function itemWidth(self, item, size)
    local w = getTextWidth(size, labelOf(self, item))
    -- tlačítko s popiskem podle řádku má šířku nejdelšího z nich, ať lišta neskáče
    for _, key in ipairs(item.widthOf or {}) do
        w = math.max(w, getTextWidth(size, E.upper(t(key))))
    end
    if item.kind == "text" then
        return w + E.TOOL_PAD
    end
    if item.kbd ~= nil then
        w = w + E.TOOL_PAD + getTextWidth(size * 0.8, item.kbd) + 2 * E.KBD_PAD
    end
    return w + 2 * E.TOOL_PAD
end

-- Plochý seznam { button, x, w, size }: levé skupiny od x0, pravé od x1; když se nevejdou, text se zmenší.
local function layoutBar(self, groups, x0, x1)
    local visible = {}
    for _, group in ipairs(groups) do
        local items = {}
        for _, item in ipairs(group) do
            if item.hidden == nil or not item.hidden(self) then
                items[#items + 1] = item
            end
        end
        if #items > 0 then
            visible[#visible + 1] = { items = items, right = group.right, gap = group.tight and 0 or E.TOOL_GAP }
        end
    end
    local function groupWidth(group, size)
        local w = 0
        for k, item in ipairs(group.items) do
            w = w + itemWidth(self, item, size) + (k > 1 and group.gap or 0)
        end
        return w
    end
    local size = E.TEXT_SIZE * 0.8
    for _ = 1, 3 do
        local need = (#visible - 1) * E.TOOL_GROUP_GAP
        for _, group in ipairs(visible) do
            need = need + groupWidth(group, size)
        end
        if need <= x1 - x0 then
            break
        end
        size = size * (x1 - x0) / need * 0.98
    end
    local list = {}
    local function place(group, x)
        for k, item in ipairs(group.items) do
            if k > 1 then
                x = x + group.gap
            end
            local w = itemWidth(self, item, size)
            list[#list + 1] = { button = item, x = x, w = w, size = size, right = group.right }
            x = x + w
        end
        return x
    end
    local x = x0
    local rights = {}
    for _, group in ipairs(visible) do
        if group.right then
            rights[#rights + 1] = group
        else
            x = place(group, x) + E.TOOL_GROUP_GAP
        end
    end
    local rx = x1
    for i = #rights, 1, -1 do
        rx = rx - groupWidth(rights[i], size)
        place(rights[i], rx)
        rx = rx - E.TOOL_GROUP_GAP
    end
    return list
end

local function barAt(list, x)
    for i, entry in ipairs(list) do
        if entry.button.kind ~= "text" and x >= entry.x and x <= entry.x + entry.w then
            return i
        end
    end
    return nil
end

function CinemaEditorScreen:toolbarLayout()
    return layoutBar(self, toolbarGroups(), E.BAR_X0, E.BAR_X1)
end

function CinemaEditorScreen:topbarLayout()
    return layoutBar(self, topbarGroups(), E.BAR_X0, E.BAR_X1)
end

function CinemaEditorScreen:toolbarY()
    return self:getPanelTop() - E.TOOLBAR_H
end

function CinemaEditorScreen:topbarY()
    return 1 - E.TOPBAR_H
end

-- Tlačítko lišty osy pod kurzorem: index v seznamu toolbarLayout, nebo nil.
function CinemaEditorScreen:toolAt(x, y)
    local y0 = self:toolbarY()
    if y < y0 or y > y0 + E.TOOLBAR_H then
        return nil
    end
    return barAt(self:toolbarLayout(), x)
end

function CinemaEditorScreen:topbarAt(x, y)
    if y < self:topbarY() then
        return nil
    end
    return barAt(self:topbarLayout(), x)
end

local function clickEntry(self, entry, y)
    if entry == nil or isDisabled(self, entry.button) then
        return
    end
    E.playSound("CLICK")
    entry.button.run(self, entry.x, y, entry)
end

function CinemaEditorScreen:toolbarClick(index)
    clickEntry(self, self:toolbarLayout()[index], self:toolbarY())
end

-- Menu z horní lišty se otevírají pod ní.
function CinemaEditorScreen:topbarClick(index)
    clickEntry(self, self:topbarLayout()[index], self:topbarY() - 0.004)
end

-- Tlačítka jako ve hře: tmavá dlaždice, zapnutý přepínač a hlavní tlačítko zelenou výplní, najetí zeleným textem a spodní linkou;
-- klávesa v tmavě zeleném čtverečku.
local function drawBar(self, list, y0, h, hover)
    local ui = E.UI
    local py = g_pixelSizeScaledY
    local ry, rh = y0 + h * 0.12, h * 0.76
    for i, entry in ipairs(list) do
        local b = entry.button
        local size = entry.size
        local label = labelOf(self, b)
        local ty = ry + rh * 0.5 - size * 0.35
        if b.kind == "text" then
            text(entry.x, ty, size, label, b.color or ui.text, RenderText.ALIGN_LEFT, b.bold)
        else
            local filled = b.primary or (b.active ~= nil and b.active(self))
            local disabled = isDisabled(self, b)
            local hovered = i == hover and not disabled
            rect(entry.x, ry, entry.w, rh, filled and ui.highlight or (b.flat and ui.row or ui.button))
            if hovered then
                rect(entry.x, ry, entry.w, 2 * py, filled and ui.text or ui.accent)
            end
            local tc = ui.text
            if disabled then
                tc = ui.dim
            elseif hovered and not filled then
                tc = ui.accent
            end
            if b.kbd == nil then
                text(entry.x + entry.w * 0.5, ty, size, label, tc, RenderText.ALIGN_CENTER, true)
            else
                text(entry.x + E.TOOL_PAD, ty, size, label, tc, RenderText.ALIGN_LEFT, true)
                local ks = size * 0.8
                local kw = getTextWidth(ks, b.kbd) + 2 * E.KBD_PAD
                local kh = rh * 0.62
                local kx = entry.x + entry.w - E.TOOL_PAD - kw
                local lit = filled or hovered
                rect(kx, ry + (rh - kh) * 0.5, kw, kh, lit and ui.kbdLit or ui.kbd)
                text(kx + kw * 0.5, ry + rh * 0.5 - ks * 0.35, ks, b.kbd, (lit or disabled) and tc or ui.accent, RenderText.ALIGN_CENTER, true)
            end
        end
    end
end

function CinemaEditorScreen:barHover()
    if self.drag ~= nil or self.menu ~= nil or self.freeLook then
        return nil, nil
    end
    local i = self:topbarAt(self.mouseX, self.mouseY)
    if i ~= nil then
        return "top", i
    end
    i = self:toolAt(self.mouseX, self.mouseY)
    if i ~= nil then
        return "tool", i
    end
    return nil, nil
end

function CinemaEditorScreen:drawToolbar()
    local ui = E.UI
    local bar, index = self:barHover()
    local key = bar ~= nil and (bar .. index) or nil
    if key ~= self.toolHover then
        self.toolHover = key
        if key ~= nil then
            E.playSound("HOVER")
        end
    end
    local y0 = self:toolbarY()
    rect(0, y0, 1, g_pixelSizeScaledY, ui.separator)
    drawBar(self, self:toolbarLayout(), y0, E.TOOLBAR_H, bar == "tool" and index or nil)
    local top = self:topbarY()
    rect(0, top, 1, E.TOPBAR_H, ui.topbar)
    rect(0, top, 1, g_pixelSizeScaledY, ui.separator)
    drawBar(self, self:topbarLayout(), top, E.TOPBAR_H, bar == "top" and index or nil)
end

-- Nápověda k tomu, co je pod kurzorem: co dělají tlačítka myši a modifikátory (nil, když kurzor není vidět).
local HINTS = {
    key = "cine_hint_key", segment = "cine_hint_block", mark = "cine_hint_mark", edge = "cine_hint_edge", focus = "cine_hint_focus",
    curveKey = "cine_hint_curveKey", curveHandle = "cine_hint_curveHandle",
    actorAction = "cine_hint_action", routePoint = "cine_hint_routePoint", lane = "cine_hint_empty", timeline = "cine_hint_empty",
    ruler = "cine_hint_ruler", playheadMode = "cine_hint_playheadMode", collapse = "cine_hint_collapse", eye = "cine_hint_eye",
    compact = "cine_hint_compact", rowScroll = "cine_hint_rowScroll", addActor = "cine_hint_addActor",
    expandAll = "cine_hint_expandAll", collapseAll = "cine_hint_collapseAll",
    propsHeader = "cine_hint_props", propsCollapse = "cine_hint_props", prop = "cine_hint_prop",
    objectsHeader = "cine_hint_objects", objectsCollapse = "cine_hint_objects", object = "cine_hint_object", objAction = "cine_hint_objAction",
}

function CinemaEditorScreen:hoverHint()
    if self.freeLook or self.playing or self.menu ~= nil then
        return nil
    end
    local index = self:topbarAt(self.mouseX, self.mouseY)
    local list = index ~= nil and self:topbarLayout() or nil
    if index == nil then
        index = self:toolAt(self.mouseX, self.mouseY)
        list = index ~= nil and self:toolbarLayout() or nil
    end
    if index ~= nil then
        local hint = list[index].button.hint
        return hint ~= nil and textOf(self, hint) or nil
    end
    local hit = self:hitPanels(self.mouseX, self.mouseY)
    if hit == nil then
        return nil
    end
    local key = HINTS[hit.kind]
    if hit.kind == "actor" then
        key = hit.onBlock and "cine_hint_drive" or "cine_hint_empty"
    end
    if hit.rowKey ~= nil then
        key = "cine_hint_rowDrag"
    end
    return key ~= nil and t(key) or nil
end

-- Obrys věci pod kurzorem: je vidět, co se chytí (blok, jízda vozidla).
function CinemaEditorScreen:drawHover()
    if self.drag ~= nil or self.menu ~= nil or self.freeLook then
        return
    end
    local hit = self:hitPanels(self.mouseX, self.mouseY)
    if hit == nil then
        return
    end
    local c = { 1, 1, 1, 0.6 }
    E.gfx.clipTrack()
    if hit.kind == "segment" then
        local seg = self.shot.segments[hit.index]
        local y, h = self:getCamRowY() + E.TRACK_H * 0.1, E.TRACK_H * 0.8
        outline(self:xAtTime(seg.t), y, self:xAtTime(CinemaShot.segmentEnd(seg)), y + h, 1, c)
    elseif hit.kind == "edge" then
        -- kraj bloku, který se tažením ořízne
        local x = self:xAtTime(hit.edge == "start" and hit.seg.t or CinemaShot.segmentEnd(hit.seg))
        E.gfx.rect(x - 2 * g_pixelSizeScaledX, self:getCamRowY(), 4 * g_pixelSizeScaledX, E.TRACK_H, E.UI.keySelected)
    elseif hit.kind == "actor" and hit.onBlock then
        local a = self.shot.actors[hit.index]
        local ry = self:getActorRowY(hit.index)
        local y, h = ry + E.ROW_H * 0.14, E.ROW_H * 0.72
        local x0 = self:xAtTime(a.delay or 0)
        outline(x0, y, math.max(self:xAtTime(self:actorEnd(hit.index)), x0 + 0.01), y + h, 1, c)
    end
    E.gfx.setClip(nil)
end
