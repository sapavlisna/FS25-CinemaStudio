-- Předměty na ose: skupina řádků „Předměty“ (sbalitelná, přetahuje se za název jako ostatní řádky), výběr předmětu ve
-- scéně (vozidlo / nářadí / paleta, balík, hromada pod kurzorem), jejich menu a postavení na místo při resetu.

local E = CinemaEditorScreen
local S = CinemaShot
local W = CinemaWorld
local Pr = CinemaProps

local function t(key)
    return g_i18n:getText(key)
end

E.PROP_KINDS = { "vehicle", "bale", "heap", "field" }

function CinemaEditorScreen:props()
    self.shot.props = self.shot.props or {}
    return self.shot.props
end

-- Skupina předmětů je na ose, když nějaké jsou, nebo když si ji uživatel přidal.
function CinemaEditorScreen:hasPropsRow()
    return #self:props() > 0 or self.shot.propsRow == true
end

function CinemaEditorScreen:propsCollapsed()
    return self.shot.propsCollapsed == true or self:isCompact()
end

-- Výška skupiny: záhlaví a pod ním řádek každého předmětu (sbalená jen záhlaví).
function CinemaEditorScreen:getPropsGroupH()
    return E.ROW_H * (1 + (self:propsCollapsed() and 0 or #self:props()))
end

-- Spodek záhlaví skupiny a řádku předmětu k (pod záhlavím, první nejvýš); nil, když skupina není vidět.
function CinemaEditorScreen:getPropsHeaderY()
    local row = self:rowLayout().byKey.props
    return row ~= nil and row.y + row.h - E.ROW_H or nil
end

function CinemaEditorScreen:getPropRowY(k)
    local hy = self:getPropsHeaderY()
    return hy ~= nil and hy - k * E.ROW_H or nil
end

-- Zásah ve skupině předmětů: { kind = "propsCollapse" | "propsHeader" | "prop", index, rowKey }, nebo nil.
function CinemaEditorScreen:hitProps(x, y)
    local hy = self:getPropsHeaderY()
    if hy == nil then
        return nil
    end
    if y >= hy and y <= hy + E.ROW_H then
        if x >= E.ARROW_X0 and x < E.ARROW_X1 then
            return { kind = "propsCollapse" }
        end
        return { kind = "propsHeader", rowKey = x >= E.LABEL_X and x < E.TRACK_X0 and "props" or nil }
    end
    if self:propsCollapsed() then
        return nil
    end
    for k in ipairs(self:props()) do
        local ry = self:getPropRowY(k)
        if y >= ry and y < ry + E.ROW_H then
            return { kind = "prop", index = k }
        end
    end
    return nil
end

function CinemaEditorScreen:toggleProps()
    self.shot.propsCollapsed = not self.shot.propsCollapsed or nil
    self:markDirty()
end

local function fruitTitle(ft)
    local fill = ft ~= nil and ft.fillType or nil
    return fill ~= nil and (fill.title or fill.name) or (ft ~= nil and ft.name or t("cine_field_noFruit"))
end

-- Jak je plodina daleko: bez plodiny, zralá, posekaná, uschlá, jinak růst n.
function E.fieldGrowthLabel(p)
    local ft = CinemaProps.fruitOf(p)
    local g = p.growth or 0
    if ft == nil or g == 0 then
        return t("cine_field_noFruit")
    elseif ft.witheredState ~= nil and g == ft.witheredState then
        return t("cine_field_withered")
    elseif g == ft.cutState then
        return t("cine_field_cut")
    elseif g >= (ft.minHarvestingGrowthState or 99) and g <= (ft.maxHarvestingGrowthState or -1) then
        return t("cine_field_ready")
    end
    return string.format(t("cine_field_growing"), g)
end

local function groundTitle(value)
    for name, v in pairs(FieldGroundType or {}) do
        if v == value and type(name) == "string" then
            local key = "cine_ground_" .. name
            return g_i18n:hasText(key) and t(key) or name
        end
    end
    return "?"
end
E.fieldGroundTitle = groundTitle

-- Kolečko, které se točí, dokud se pole nastavuje: střed cx, cy.
function E.drawSpinner(cx, cy, color)
    local px, py = g_pixelSizeScaledX, g_pixelSizeScaledY
    local n = 10
    local head = math.floor((g_time or 0) / 80) % n
    for k = 0, n - 1 do
        local a = k / n * 2 * math.pi
        local strength = 1 - ((head - k) % n) / n
        E.gfx.line(cx + math.sin(a) * 4 * px, cy + math.cos(a) * 4 * py, cx + math.sin(a) * 8 * px, cy + math.cos(a) * 8 * py, 2,
            { color[1], color[2], color[3], 0.2 + 0.8 * strength })
    end
end

-- Text o průběhu nastavování pole p (nil, když se nenastavuje).
function E.fieldProgressText(p)
    local info = Pr.fieldProgress(p.field)
    if info == nil then
        return nil
    end
    local what = info.phase == "field" and t("cine_field_phaseField")
        or string.format(t("cine_field_phase_" .. info.phase), info.done, info.total)
    return string.format(t("cine_field_busy"), what, info.seconds)
end

-- Co o předmětu řádek říká: druh, kde je, co s ním reset udělá.
function CinemaEditorScreen:propStatus(p)
    if p.kind == "field" then
        local busy = E.fieldProgressText(p)
        if busy ~= nil then
            return busy
        end
        local ft = Pr.fruitOf(p)
        local text = string.format("%s · %s · %s", ft ~= nil and fruitTitle(ft) or t("cine_field_noFruit"), E.fieldGrowthLabel(p),
            groundTitle(p.ground))
        if p.zones ~= nil then
            local cut, standing = CinemaZones.summary(CinemaZones.decode(p.zones))
            text = text .. " · " .. string.format(t("cine_zone_status"), cut, standing)
        end
        if p.windrow ~= nil then
            text = text .. " · " .. string.format(t("cine_field_windrowStatus"), #Pr.decodeLines(p.windrowLines))
        end
        return self.shot.fieldsOn and text or text .. "  " .. t("cine_field_resetOff")
    end
    if p.kind == "heap" then
        return string.format(t("cine_prop_statusHeap"), p.radius or Pr.HEAP_RADIUS)
    end
    local x, y, z = Pr.position(p)
    local where = x ~= nil and string.format("%.0f / %.0f, %.1f m", x, z, y - W.terrainY(x, z)) or "?"
    if not Pr.exists(p) then
        return string.format(t(p.kind == "bale" and "cine_prop_statusRespawn" or "cine_prop_statusMissing"), where)
    end
    return string.format(t("cine_prop_statusOk"), where)
end

function CinemaEditorScreen:drawPropsGroup()
    local hy = self:getPropsHeaderY()
    if hy == nil then
        return
    end
    local gfx, ui = E.gfx, E.UI
    local props = self:props()
    self:drawRowBase(hy, E.ROW_H, false, string.format(t("cine_props_label"), #props), nil)
    if Pr.anyFieldProgress() then
        E.drawSpinner(E.TRACK_X0 - 0.012, hy + E.ROW_H * 0.5, E.UI.pickHover)
    end
    gfx.text(E.ARROW_X0 + 0.002, hy + E.ROW_H * 0.5 - E.TEXT_SIZE * 0.3, E.TEXT_SIZE * 0.75, self:propsCollapsed() and ">" or "v",
        #props > 0 and ui.text or ui.dim, RenderText.ALIGN_LEFT, true)
    gfx.text(E.TRACK_X0 + 0.006, hy + E.ROW_H * 0.5 - E.TEXT_SIZE * 0.28, E.TEXT_SIZE * 0.68,
        t(#props > 0 and "cine_props_hint" or "cine_props_empty"), ui.dim, RenderText.ALIGN_LEFT)
    if self:propsCollapsed() then
        return
    end
    for k, p in ipairs(props) do
        local ry = self:getPropRowY(k)
        local active = self.activeProp == k
        self:drawRowBase(ry, E.ROW_H, active, "  " .. (p.name or "?"), nil)
        if p.kind == "field" and Pr.fieldProgress(p.field) ~= nil then
            E.drawSpinner(E.TRACK_X0 - 0.012, ry + E.ROW_H * 0.5, E.UI.pickHover)
        end
        local c = Pr.exists(p) and ui.text or ui.cut
        gfx.text(E.TRACK_X0 + 0.006, ry + E.ROW_H * 0.5 - E.TEXT_SIZE * 0.28, E.TEXT_SIZE * 0.68,
            t("cine_prop_kind_" .. p.kind) .. "  ·  " .. self:propStatus(p), c, RenderText.ALIGN_LEFT)
    end
end

---------------------------------------------------------------------------------------------------
-- přidání: výběr ve scéně

function CinemaEditorScreen:pickProp(kind)
    self.pendingAction = { prop = kind }
    self.picking = true
    self:needCursor()
    self:showMessage(t("cine_msg_pickProp_" .. kind))
end

function CinemaEditorScreen:addProp(p)
    if p == nil then
        return
    end
    for _, other in ipairs(self:props()) do
        local same = (p.kind == "bale" and other.uid == p.uid) or (p.kind == "field" and other.field == p.field)
            or (p.kind == "vehicle" and other.start ~= nil and p.start.entries[1] ~= nil and other.start.entries[1] ~= nil
                and other.start.entries[1].uid == p.start.entries[1].uid)
        if p.kind == other.kind and same then
            self:showMessage(t("cine_msg_propAlready"))
            return
        end
    end
    self:pushUndo()
    local props = self:props()
    props[#props + 1] = p
    self.activeProp = #props
    self.shot.propsCollapsed = nil
    self:markDirty()
    self:showMessage(string.format(t("cine_msg_propAdded"), p.name or "?"))
    if p.kind == "field" and not self.shot.fieldsOn then
        self:confirmFieldsOn()
    end
end

-- Zapnutí vracení polí při resetu: reset mění skutečnou hru (stav pole se uloží se savegame), proto potvrzení.
function CinemaEditorScreen:confirmFieldsOn(x, y)
    x, y = x or self.mouseX or 0.5, y or self.mouseY or 0.5
    local function line(key)
        return E.menuItem(t(key), function() end, { disabled = true })
    end
    self:openMenu(t("cine_field_warnTitle"), {
        line("cine_field_warn1"),
        line("cine_field_warn2"),
        line("cine_field_warn3"),
        { text = "", separator = true, disabled = true },
        E.menuItem(t("cine_field_warnYes"), function(s)
            s:pushUndo()
            s.shot.fieldsOn = true
            s:markDirty()
            s:showMessage(t("cine_msg_fieldsOn"))
        end),
        E.menuItem(t("cine_field_warnNo"), function() end),
    }, x, y)
end

function CinemaEditorScreen:setFieldsOn(on, x, y)
    if on and not self.shot.fieldsOn then
        self:confirmFieldsOn(x, y)
        return
    end
    self:pushUndo()
    self.shot.fieldsOn = on or nil
    self:markDirty()
    self:showMessage(t(on and "cine_msg_fieldsOn" or "cine_msg_fieldsOff"))
end

-- Klik ve scéně při výběru předmětu (vozidla řeší pickAt přes obrysy). true, když se klik spotřeboval.
function CinemaEditorScreen:pickPropAt(kind, x, y)
    if kind == "bale" then
        local bale = Pr.baleAt(self.cam, x, y)
        if bale == nil then
            self:showMessage(t("cine_msg_noBale"))
            return true
        end
        self:addProp(Pr.fromBale(bale))
        return true
    elseif kind == "heap" or kind == "field" then
        local px, _, pz = W.pickTerrain(self.cam, x, y)
        local p = px ~= nil and (kind == "heap" and Pr.fromHeap(px, pz) or Pr.fromField(px, pz)) or nil
        if p == nil then
            self:showMessage(t(kind == "heap" and "cine_msg_noHeap" or "cine_msg_noField"))
            return true
        end
        self:addProp(p)
        return true
    end
    return false
end

-- Značky balíků při výběru balíku.
function CinemaEditorScreen:drawBalePick()
    local list = Pr.baleCandidates(self.cam, self.mouseX, self.mouseY)
    local hover = list[1] ~= nil and list[1].px <= Pr.BALE_PICK_PX and list[1] or nil
    for _, c in ipairs(list) do
        local isHover = c == hover
        local r = (isHover and 14 or 8) * g_pixelSizeScaledX
        local rh = (isHover and 14 or 8) * g_pixelSizeScaledY
        E.gfx.outline(c.sx - r, c.sy - rh, c.sx + r, c.sy + rh, isHover and 3 or 1.5, isHover and E.UI.pickHover or E.UI.pickBox)
        if isHover then
            E.gfx.text(c.sx, c.sy + rh + 0.006, E.TEXT_SIZE, Pr.baleName(c.bale), E.UI.pickHover, RenderText.ALIGN_CENTER, true)
        end
    end
end

---------------------------------------------------------------------------------------------------
-- reset

-- Postaví všechny předměty na zapamatované místo; vrací důvod prvního neúspěchu nebo nil.
function CinemaEditorScreen:resetProps()
    local failed, changed = nil, false
    for _, p in ipairs(self:props()) do
        local ok, info = true, nil
        if p.kind ~= "field" or self.shot.fieldsOn then
            ok, info = Pr.reset(p)
        end
        if not ok then
            failed = failed or info
        elseif info == true then
            changed = true
        end
    end
    if changed then
        -- vyrobený balík má nové číslo: uložit, ať ho příští reset najde
        S.touch(self.shot)
        self:markDirty()
    end
    return failed
end

---------------------------------------------------------------------------------------------------
-- menu

local function item(text, action, opts)
    local entry = { text = text, action = action }
    for k, v in pairs(opts or {}) do
        entry[k] = v
    end
    return entry
end

function CinemaEditorScreen:propAddItems()
    return {
        item(t("cine_prop_addVehicle"), function(s) s:pickProp("vehicle") end),
        item(t("cine_prop_addBale"), function(s) s:pickProp("bale") end),
        item(t("cine_prop_addHeap"), function(s) s:pickProp("heap") end),
        item(t("cine_prop_addField"), function(s) s:pickProp("field") end, { disabled = g_fieldManager == nil }),
    }
end

function CinemaEditorScreen:openPropsMenu(x, y)
    local items = self:propAddItems()
    items[#items + 1] = item(t(self.shot.fieldsOn and "cine_field_resetOnItem" or "cine_field_resetOffItem"),
        function(s) s:setFieldsOn(not s.shot.fieldsOn, x, y) end)
    items[#items + 1] = item(t("cine_prop_resetAll"), function(s)
        local failed = s:resetProps()
        s:showMessage(t(failed ~= nil and "cine_msg_propMissing" or "cine_msg_propsReset"))
    end, { disabled = #self:props() == 0 })
    items[#items + 1] = item(t(self:propsCollapsed() and "cine_props_expand" or "cine_props_collapse"),
        function(s) s:toggleProps() end, { disabled = #self:props() == 0 })
    items[#items + 1] = item(t("cine_props_hide"), function(s)
        s:pushUndo()
        s.shot.propsRow = nil
        s:markDirty()
    end, { disabled = #self:props() > 0 })
    self:openMenu(t("cine_props_title"), items, x, y)
end

local function maxOf(densityMap, fallback)
    local system = g_currentMission ~= nil and g_currentMission.fieldGroundSystem or nil
    if system ~= nil and FieldDensityMap ~= nil and FieldDensityMap[densityMap] ~= nil then
        local ok, value = pcall(system.getMaxValue, system, FieldDensityMap[densityMap])
        if ok and value ~= nil then
            return value
        end
    end
    return fallback
end

local function enumValues(enum)
    local list = {}
    for name, v in pairs(enum or {}) do
        if type(name) == "string" and type(v) == "number" and name:upper() == name then
            list[#list + 1] = v
        end
    end
    table.sort(list)
    return list
end

local function cycle(list, current, dir)
    local k = 0
    for j, v in ipairs(list) do
        if v == current then
            k = j
        end
    end
    return list[(k - 1 + dir) % #list + 1]
end

-- Položky stavu pole: plodina, růst, půda, hnojení, vápno, orba, válcování, podmítka, plevel, kameny, mazání řádků.
function CinemaEditorScreen:fieldStateItems(p, change)
    local fm = g_fieldManager
    local mission = g_currentMission
    local fruits = { 0 }
    for _, index in ipairs(fm ~= nil and fm.availableFruitTypeIndices or {}) do
        fruits[#fruits + 1] = index
    end
    local function fruitIndex()
        local ft = Pr.fruitOf(p)
        return ft ~= nil and ft.index or 0
    end
    local function setFruit(dir)
        local index = cycle(fruits, fruitIndex(), dir)
        local ft = index ~= 0 and g_fruitTypeManager:getFruitTypeByIndex(index) or nil
        p.fruit = ft ~= nil and ft.name or nil
        if ft ~= nil then
            p.growth = ft.minHarvestingGrowthState or p.growth
        else
            p.growth = 0
        end
    end
    local function growthMax()
        local ft = Pr.fruitOf(p)
        local top = 0
        for g in pairs(ft ~= nil and ft.growthStateToName or {}) do
            top = math.max(top, g)
        end
        return math.max(top, ft ~= nil and (ft.cutState or 0) or 0, ft ~= nil and (ft.witheredState or 0) or 0)
    end
    local function level(key, label, top)
        return E.stepItem(function() return string.format(t(label), p[key] or 0, top) end,
            function(s) change(s, function() p[key] = math.min((p[key] or 0) + 1, top) end) end,
            function(s) change(s, function() p[key] = math.max((p[key] or 0) - 1, 0) end) end, { disabled = top <= 0 })
    end
    local grounds = enumValues(FieldGroundType)
    local sprays = enumValues(FieldSprayType)
    return {
        E.stepItem(function()
            local ft = Pr.fruitOf(p)
            return string.format(t("cine_field_fruit"), ft ~= nil and fruitTitle(ft) or t("cine_field_noFruit"))
        end, function(s) change(s, function() setFruit(1) end) end, function(s) change(s, function() setFruit(-1) end) end),
        E.stepItem(function() return string.format(t("cine_field_growth"), E.fieldGrowthLabel(p), p.growth or 0) end,
            function(s) change(s, function() p.growth = math.min((p.growth or 0) + 1, growthMax()) end) end,
            function(s) change(s, function() p.growth = math.max((p.growth or 0) - 1, 0) end) end,
            { disabled = Pr.fruitOf(p) == nil }),
        E.stepItem(function() return string.format(t("cine_field_ground"), groundTitle(p.ground)) end,
            function(s) change(s, function() p.ground = cycle(grounds, p.ground, 1) end) end,
            function(s) change(s, function() p.ground = cycle(grounds, p.ground, -1) end) end, { disabled = #grounds == 0 }),
        E.stepItem(function()
            local name = "?"
            for n, v in pairs(FieldSprayType or {}) do
                if v == p.sprayType and type(n) == "string" then
                    name = g_i18n:hasText("cine_spray_" .. n) and t("cine_spray_" .. n) or n
                end
            end
            return string.format(t("cine_field_sprayType"), name)
        end, function(s) change(s, function() p.sprayType = cycle(sprays, p.sprayType, 1) end) end,
            function(s) change(s, function() p.sprayType = cycle(sprays, p.sprayType, -1) end) end, { disabled = #sprays == 0 }),
        level("sprayLevel", "cine_field_sprayLevel", fm ~= nil and fm.sprayLevelMaxValue or 0),
        level("lime", "cine_field_lime", fm ~= nil and fm.limeLevelMaxValue or 0),
        level("plow", "cine_field_plow", fm ~= nil and fm.plowLevelMaxValue or 0),
        level("roller", "cine_field_roller", maxOf("ROLLER_LEVEL", 1)),
        level("stubble", "cine_field_stubble", maxOf("STUBBLE_SHRED_LEVEL", 1)),
        level("weed", "cine_field_weed", mission ~= nil and mission.weedSystem ~= nil and mission.weedSystem.maxValue or 0),
        level("stone", "cine_field_stone", mission ~= nil and mission.stoneSystem ~= nil and mission.stoneSystem.maxValue or 0),
        item(t(p.clear ~= 0 and "cine_field_clearOn" or "cine_field_clearOff"),
            function(s) change(s, function() p.clear = p.clear ~= 0 and 0 or 1 end) end, { keepOpen = true }),
        item(function() return t(p.fast and "cine_field_fastOn" or "cine_field_fastOff") end,
            function(s) change(s, function() p.fast = not p.fast or nil end) end, { keepOpen = true }),
        item(t("cine_field_zones"), function(s) s:openZoneMenu(p, change) end, { submenu = true }),
        item(t("cine_field_windrows"), function(s) s:openWindrowMenu(p, change) end, { submenu = true }),
    }
end

-- Řádky slámy, trávy nebo sena, které reset nasype po nastavení pole.
function CinemaEditorScreen:openWindrowMenu(p, change)
    local types = Pr.windrowTypes()
    local names = { "" }
    for _, wt in ipairs(types) do
        names[#names + 1] = wt.name
    end
    local function title()
        for _, wt in ipairs(types) do
            if wt.name == p.windrow then
                return wt.title
            end
        end
        return t("cine_field_windrowNone")
    end
    local function cycleType(dir)
        local name = cycle(names, p.windrow or "", dir)
        p.windrow = name ~= "" and name or nil
        p.windrowAmount = p.windrowAmount or Pr.WINDROW_AMOUNT
        if p.windrow ~= nil and p.windrowLines == nil then
            local zoned = #CinemaZones.cutLines(CinemaZones.decode(p.zones)) > 0
            self:makeWindrowLines(p, zoned and "zone" or "cp", true)
        end
    end
    local function count()
        return #Pr.decodeLines(p.windrowLines)
    end
    local items = {
        E.stepItem(function() return string.format(t("cine_field_windrowType"), title()) end,
            function(s) change(s, function() cycleType(1) end) end, function(s) change(s, function() cycleType(-1) end) end),
        E.stepItem(function() return string.format(t("cine_field_windrowAmount"), p.windrowAmount or Pr.WINDROW_AMOUNT) end,
            function(s) change(s, function()
                p.windrowAmount = math.min((p.windrowAmount or Pr.WINDROW_AMOUNT) + Pr.WINDROW_AMOUNT_STEP, Pr.WINDROW_AMOUNT_MAX)
            end) end,
            function(s) change(s, function()
                p.windrowAmount = math.max((p.windrowAmount or Pr.WINDROW_AMOUNT) - Pr.WINDROW_AMOUNT_STEP, Pr.WINDROW_AMOUNT_STEP)
            end) end, { disabled = p.windrow == nil }),
        E.menuItem(function()
            local key = ({ cp = "cine_field_windrowFromCp", zone = "cine_field_windrowFromZone" })[p.windrowSource]
            return string.format(t(key or "cine_field_windrowCount"), count())
        end, function() end, { disabled = true }),
        E.menuItem(t("cine_field_windrowLoadCp"), function(s) change(s, function() s:makeWindrowLines(p, "cp") end) end,
            { keepOpen = true }),
        E.stepItem(function() return string.format(t("cine_field_windrowSpacing"), p.windrowSpacing or Pr.WINDROW_SPACING) end,
            function(s) change(s, function()
                p.windrowSpacing = math.min((p.windrowSpacing or Pr.WINDROW_SPACING) + 1, Pr.WINDROW_SPACING_MAX)
                s:makeWindrowLines(p, "parallel")
            end) end,
            function(s) change(s, function()
                p.windrowSpacing = math.max((p.windrowSpacing or Pr.WINDROW_SPACING) - 1, Pr.WINDROW_SPACING_MIN)
                s:makeWindrowLines(p, "parallel")
            end) end),
    }
    self:openMenu(string.format(t("cine_field_windrowTitle"), p.name or "?"), items, self.mouseX or 0.5, self.mouseY or 0.5)
end

-- Čáry řádků: z kurzu Courseplay načteného ve stroji (source = "cp"), jinak rovnoběžně po rozestupu. quiet = bez hlášky
-- o kurzu (při první volbě materiálu se tiše vezmou rovnoběžné, když kurz není).
function CinemaEditorScreen:makeWindrowLines(p, source, quiet)
    local field = Pr.findField(p.field)
    if field == nil then
        return
    end
    if source == "zone" then
        local lines = CinemaZones.cutLines(CinemaZones.decode(p.zones))
        if #lines > 0 then
            p.windrowLines, p.windrowSource = Pr.encodeLines(lines), "zone"
            if not quiet then
                self:showMessage(string.format(t("cine_msg_windrowZone"), #lines))
            end
            return
        end
    end
    if source == "cp" then
        local lines, name, width = Pr.courseLines(field)
        if lines ~= nil and #lines > 0 then
            p.windrowLines, p.windrowSource = Pr.encodeLines(lines), "cp"
            if width ~= nil and width > 0 then
                p.windrowSpacing = math.floor(width + 0.5)
            end
            self:showMessage(string.format(t("cine_msg_windrowCp"), #lines, name or "?"))
            return
        end
        if not quiet then
            self:showMessage(t("cine_msg_windrowNoCp"))
        end
    end
    local lines = Pr.parallelLines(Pr.fieldPolygon(field), p.windrowSpacing or Pr.WINDROW_SPACING)
    p.windrowLines, p.windrowSource = Pr.encodeLines(lines), "parallel"
end

function CinemaEditorScreen:openPropMenu(k, x, y)
    local p = self:props()[k]
    if p == nil then
        return
    end
    self.activeProp = k
    local function change(s, fn)
        s:pushUndo()
        fn()
        s:markDirty()
    end
    local items = {
        item(t("cine_prop_recapture"), function(s)
            s:pushUndo()
            if Pr.recapture(p) then
                s:markDirty()
                s:showMessage(string.format(t("cine_msg_propRecaptured"), p.name or "?"))
            else
                table.remove(s.undoStack)
                s:showMessage(t("cine_msg_propMissing"))
            end
        end),
        item(t(p.kind == "field" and "cine_field_applyNow" or "cine_prop_placeNow"), function(s)
            local ok = Pr.reset(p)
            s:showMessage(ok and string.format(t("cine_msg_propPlaced"), p.name or "?") or t("cine_msg_propMissing"))
        end),
    }
    if p.kind == "field" then
        for _, entry in ipairs(self:fieldStateItems(p, change)) do
            items[#items + 1] = entry
        end
    else
        items[#items + 1] = E.stepItem(function() return string.format(t("cine_prop_up"), select(2, Pr.position(p)) or 0) end,
            function(s) change(s, function() Pr.raise(p, 0.25) end) end,
            function(s) change(s, function() Pr.raise(p, -0.25) end) end, { disabled = p.kind == "heap" })
    end
    if p.kind == "heap" then
        items[#items + 1] = E.stepItem(function() return string.format(t("cine_prop_radiusUp"), p.radius or Pr.HEAP_RADIUS) end,
            function(s) change(s, function() p.radius = math.min((p.radius or Pr.HEAP_RADIUS) + 1, Pr.HEAP_RADIUS_MAX) end) end,
            function(s) change(s, function() p.radius = math.max((p.radius or Pr.HEAP_RADIUS) - 1, Pr.HEAP_RADIUS_MIN) end) end)
    end
    items[#items + 1] = { text = "", separator = true, disabled = true }
    items[#items + 1] = item(t("cine_prop_delete"), function(s)
        change(s, function() table.remove(s:props(), k) end)
        s.activeProp = nil
    end)
    self:openMenu(string.format(t("cine_prop_title"), p.name or "?"), items, x, y)
end
