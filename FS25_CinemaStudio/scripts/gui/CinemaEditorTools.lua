-- Nástroje editoru: zásahy myší do panelů (časová osa, řádky vozidel, křivka rychlosti), výběr objektu (T),
-- pohled shora pro klikání dráhy a tras (M) a herci (vozidla, která se s přehráváním rozjedou).

local E = CinemaEditorScreen
local M = CinemaMath
local S = CinemaShot
local W = CinemaWorld
local R = CinemaRoute
local Mo = CinemaModes
local Cam = CinemaCamera
local A = CinemaActions
local Pe = CinemaPerson

E.TOPDOWN_PITCH = math.rad(89.5)
E.TOPDOWN_FOCAL = 28
E.TOPDOWN_HEIGHT = 160
E.TOPDOWN_HEIGHT_MIN = 15
E.TOPDOWN_HEIGHT_MAX = 2500
E.TOPDOWN_ROTATE = 1.2 -- rad/s
E.PLAN_HEIGHT_DEFAULT = 15 -- m nad terénem pro K-framy naklikané shora
E.PLAN_PITCH = math.rad(12)
E.ACTOR_SPEED_DEFAULT = 15
E.POINT_GRAB_PX = 14 -- jak blízko bodu musí být kurzor, aby ho klik chytil
E.ROUTE_GRAB_PX = 9 -- jak blízko čáře trasy musí být kurzor, aby klik vložil bod
E.POINT_SLOP_PX = 5 -- o kolik se musí kurzor pohnout, aby se z kliknutí na bod stalo tažení
E.POINT_MIN_GAP = 3 -- m; blíž k existujícímu bodu trasy se nový nevkládá
E.EDGE_HIT_PX = 6 -- jak blízko kraji bloku musí být kurzor, aby tažení blok ořezávalo
E.KEY_BAND = 0.3 -- K-framy se chytají jen ve středním pásu řádku (díl výšky od středu); nad a pod ním se chytá kraj bloku

---------------------------------------------------------------------------------------------------
-- panely: co je pod kurzorem

-- Vrací { kind = "key" | "mark" | "edge" | "segment" | "actor" | "curveKey" | "curve" | "timeline" | "panel", … } nebo nil mimo panely.
function CinemaEditorScreen:hitPanels(x, y)
    if y >= self:topbarY() then
        local i = self:topbarAt(x, y)
        return i ~= nil and { kind = "top", index = i } or { kind = "topbar" }
    end
    local top = self:getPanelTop()
    if self.curves and y > top and y <= top + E.CURVE_HEIGHT then
        return self:hitChannelPanel(x, y)
    end
    if y > top then
        return nil
    end
    if y >= self:toolbarY() then
        local tool = self:toolAt(x, y)
        return tool ~= nil and { kind = "tool", index = tool } or { kind = "toolbar" }
    end
    local buttons = self:getBottomButtons()
    for name, kind in pairs({ add = "addActor", expand = "expandAll", collapse = "collapseAll" }) do
        local b = buttons[name]
        if x >= b[1] and x <= b[1] + b[3] and y >= b[2] and y <= b[2] + b[4] then
            return { kind = kind }
        end
    end
    local eye = self:eyeAt(x, y)
    if eye ~= nil then
        return { kind = "eye", target = eye }
    end
    local swatch = self:swatchAt(x, y)
    if swatch ~= nil then
        return { kind = "swatch", target = swatch }
    end
    local camY = self:getCamRowY()
    if y >= camY and y <= camY + E.TRACK_H and x >= E.ARROW_X0 and x < E.ARROW_X1 then
        return { kind = "compact" }
    end
    if y >= camY and y <= camY + E.TRACK_H and x >= E.LABEL_X and x < E.TRACK_X0 then
        return { kind = "camLabel", rowKey = "cam" }
    end
    if self:hasRowScroll() then
        local sx, sy, sw, sh = self:getRowScrollRect()
        if x >= sx - 0.003 and x <= sx + sw + 0.003 and y >= sy and y <= sy + sh then
            return { kind = "rowScroll" }
        end
    end
    -- levý sloupec s názvy řádků patří řádkům, ne obsahu osy (ten může být posunutý pod něj)
    local inTrack = x >= E.TRACK_X0
    if self:isFocusRowShown() then
        local fy = self:getFocusRowY()
        if y >= fy and y <= fy + E.ROW_H then
            if not inTrack and x >= E.LABEL_X then
                return { kind = "focusLabel", focusRow = true, rowKey = "focus" }
            end
            local i = inTrack and self:focusAtScreen(x) or nil
            if i ~= nil then
                return { kind = "focus", index = i }
            end
            -- tělo úseku patří bodu, kterým začíná
            i = inTrack and S.focusIndexAt(self.shot, self:timeAtX(x)) or nil
            if i ~= nil then
                return { kind = "focus", index = i, body = true }
            end
            return { kind = "timeline", focusRow = true }
        end
    end
    local propHit = self:hitProps(x, y) or self:hitObjects(x, y)
    if propHit ~= nil then
        return propHit
    end
    for i = 1, #self.shot.actors do
        local ry = self:getActorRowY(i)
        if self:isActorShown(i) and y >= ry and y <= ry + self:getActorBlockH(i) then
            if y < ry + E.ROW_H and x >= E.ARROW_X0 and x < E.ARROW_X1 then
                return { kind = "collapse", index = i }
            end
            if y >= ry + E.ROW_H then
                local lane = self:laneAtScreen(i, y)
                if lane ~= nil then
                    local action, part
                    if inTrack then
                        action, part = self:actionAtScreen(i, x, lane)
                    end
                    if action ~= nil then
                        return { kind = "actorAction", index = i, action = action, part = part }
                    end
                    return { kind = "lane", index = i, lane = lane }
                end
            end
            local point = inTrack and self:routePointAtScreen(i, x) or nil
            if point ~= nil and y < ry + E.ROW_H and self:selectedSpanEndAt(i, x) ~= nil then
                point = nil
            end
            if point ~= nil then
                return { kind = "routePoint", index = i, point = point }
            end
            return { kind = "actor", index = i, onBlock = inTrack and self:isOnActorBlock(i, x),
                rowKey = not inTrack and x >= E.LABEL_X and y < ry + E.ROW_H and self:actorRowKey(i) or nil }
        end
    end
    if y >= camY - 0.012 and y <= camY + E.TRACK_H + 0.012 then
        if not inTrack then
            return { kind = "panel" }
        end
        local key = self:keyAtScreen(x, y)
        if key ~= nil then
            return { kind = "key", seg = key.seg, index = key.index }
        end
        local mark = self:markAtScreen(x, y)
        if mark ~= nil then
            return { kind = "mark", seg = mark.seg, index = mark.index }
        end
        local edgeSeg, edge = self:blockEdgeAtScreen(x)
        if edgeSeg ~= nil then
            return { kind = "edge", seg = edgeSeg, edge = edge }
        end
        local seg, segIndex = S.segmentAt(self.shot, self:timeAtX(x))
        if seg ~= nil then
            return { kind = "segment", index = segIndex }
        end
        return { kind = "timeline" }
    end
    if y <= E.SCROLL_Y + E.SCROLL_H then
        return { kind = "scroll" }
    end
    -- pravítko dole (i štítek s časem): tažením se posouvá playhead, aktivní řádek se nemění; vlevo přepínač, kde playhead reaguje
    if y < E.TRACK_Y - 0.012 then
        return { kind = x < E.TRACK_X0 and "playheadMode" or "ruler" }
    end
    return { kind = "panel" }
end

-- Je kurzor ve středním pásu řádku kamery, kde se chytají K-framy?
local function inKeyBand(self, y)
    return math.abs(y - (self:getCamRowY() + E.TRACK_H * 0.5)) <= E.TRACK_H * E.KEY_BAND
end

-- K-frame režimu (značka) pod kurzorem: { seg = číslo bloku, index }, nebo nil.
function CinemaEditorScreen:markAtScreen(x, y)
    if not inKeyBand(self, y) then
        return nil
    end
    local best, bestDist = nil, E.KEY_PX * 0.8 * g_pixelSizeScaledX
    for si, seg in ipairs(self.shot.segments) do
        local duration = seg.track.duration or 0
        for i, m in ipairs(seg.track.marks or {}) do
            local dist = math.abs(self:xAtTime(seg.t + m.u * duration) - x)
            if dist <= bestDist then
                best, bestDist = { seg = si, index = i }, dist
            end
        end
    end
    return best
end

-- K-frame Letu pod kurzorem: { seg, index }, nebo nil.
function CinemaEditorScreen:keyAtScreen(x, y)
    if not inKeyBand(self, y) then
        return nil
    end
    local best, bestDist = nil, E.KEY_HIT_PX * g_pixelSizeScaledX
    for _, seg in ipairs(self.shot.segments) do
        for i, k in ipairs(seg.track.keys or {}) do
            local dist = math.abs(self:xAtTime(seg.t + k.t) - x)
            if dist <= bestDist then
                best, bestDist = { seg = seg, index = i }, dist
            end
        end
    end
    return best
end

-- Kraj bloku pod kurzorem: blok a "start" / "end", nebo nil.
function CinemaEditorScreen:blockEdgeAtScreen(x)
    local best, bestEdge, bestDist = nil, nil, E.EDGE_HIT_PX * g_pixelSizeScaledX
    for _, seg in ipairs(self.shot.segments) do
        for _, edge in ipairs({ "start", "end" }) do
            local dist = math.abs(self:xAtTime(edge == "start" and seg.t or S.segmentEnd(seg)) - x)
            if dist <= bestDist then
                best, bestEdge, bestDist = seg, edge, dist
            end
        end
    end
    return best, bestEdge
end

-- Přidá K-frame do režimu pod playheadem s ohniskem focal (bez něj s tím, které tam režim má, takže se tvar nezmění) a vybere
-- ho. Na krajích bloku se místo K-framu mění ohnisko začátku nebo konce.
function CinemaEditorScreen:addModeMark(seg, focal, undoPushed)
    local track = seg.track
    local d = math.max(track.duration or 1, 0.1)
    local u = M.clamp((self.playhead - seg.t) / d, 0, 1)
    local gap = Mo.markGap(track)
    if not undoPushed then
        self:pushUndo()
    end
    if focal ~= nil and (u < gap or u > 1 - gap) then
        track[u < gap and "focal" or "focal2"] = focal
        S.touch(self.shot)
        self:markDirty()
        self:showMessage(string.format(g_i18n:getText("cine_msg_blockFocal"), focal))
        return
    end
    local index, added = Mo.addMark(track, u, self.targetFocal)
    if focal ~= nil and not track.autoZoom then
        added = added or math.abs(track.marks[index].focal - focal) > 0.01
        track.marks[index].focal = focal
    end
    if not added and not undoPushed then
        table.remove(self.undoStack)
    end
    self:setSelectedMark(seg, index)
    S.touch(self.shot)
    self:markDirty()
    local at = seg.t + track.marks[index].u * d
    self:showMessage(string.format(g_i18n:getText(added and "cine_msg_markAdded" or "cine_msg_markExists"), at))
end

-- K-frame Letu v čase t mimo bloky: prodlouží Let, který před t skončil jako poslední, a K-frame dá na jeho konec; jinak
-- založí nový Let. Vrací blok a index K-framu, nebo nil, když se nový blok před další nevejde.
function CinemaEditorScreen:keyInGap(t, key)
    local shot = self.shot
    local before = S.blockBefore(shot, t)
    if before ~= nil and before.track.mode == S.FLIGHT then
        before.track.duration = t - before.t
        key.t = t - before.t
        return before, S.flightSetKey(shot, before.track, key)
    end
    local nextSeg = S.blockAfter(shot, t)
    local room = nextSeg ~= nil and nextSeg.t - S.MIN_GAP - t or math.huge
    if room < S.MIN_GAP then
        return nil
    end
    local seg = { id = S.nextSegmentId(shot), t = t, track = S.newFlight(key, math.min(S.MIN_SEGMENT, room)) }
    S.addSegment(shot, seg)
    return seg, 1
end

-- K: K-frame do bloku pod playheadem a nikdy blok nerozdělí. V Letu póza a ohnisko kamery (přepíše K-frame ve stejném čase),
-- v režimu jen ohnisko (polohu určuje režim), ve statické kameře póza celého bloku a ohnisko, v mezeře viz keyInGap.
function CinemaEditorScreen:addKeyHere()
    local shot = self.shot
    local cam = self.cam
    local t = self.playhead
    local seg = S.segmentAt(shot, t)
    if seg ~= nil and not S.isFlight(seg) and t >= S.segmentEnd(seg) - S.KEY_SNAP then
        -- na konci statické kamery nebo režimu začne za ním nový Let (K-frame by jen přepsal ohnisko bloku)
        t = S.segmentEnd(seg)
        seg = nil
        local nextSeg = S.segmentAt(shot, t + 1e-6)
        if nextSeg ~= nil and nextSeg.t > t - 1e-9 then
            seg = nextSeg
        end
    end
    if seg ~= nil and not S.hasKeys(seg.track) then
        self:addModeKey(seg)
        return
    end
    self:pushUndo()
    local key = S.newKey(0, cam.x, cam.y, cam.z, M.quatFromYawPitchRoll(cam.yaw, cam.pitch, cam.roll), self.targetFocal)
    local index, existed
    if seg ~= nil then
        key.t = t - seg.t
        existed = S.flightKeyAt(seg.track, key.t) ~= nil
        index = S.flightSetKey(shot, seg.track, key)
    else
        seg, index = self:keyInGap(t, key)
        if seg == nil then
            table.remove(self.undoStack)
            self:showMessage(g_i18n:getText("cine_msg_noRoom"))
            return
        end
    end
    if seg.track.mode == "spotlight" then
        -- K-frame sledování z bodu nese i směr kamery: jako odchylku od směru na cíl
        local k = seg.track.keys[index]
        local st = self:targetState(seg.track.target, seg.t + k.t)
        if st ~= nil then
            local yaw, pitch = M.yawPitchFromDirection(st.x - k.x, st.y + (seg.track.lookHeight or Mo.LOOK_HEIGHT) - k.y, st.z - k.z)
            k.aimYaw, k.aimPitch = M.angleDiff(yaw, cam.yaw), cam.pitch - pitch
        end
    end
    self:setSelectedKey(seg, index)
    self:advanceAfterKey(seg)
    self:markDirty()
    if existed then
        self:showMessage(g_i18n:getText("cine_msg_keyOverwritten"))
        return
    end
    self:showMessage(g_i18n:getText("cine_msg_keyAdded"))
end

E.KEY_STEPS = { 0.5, 1, 2, 3, 5, 10 }
E.KEY_STEP_DEFAULT = 2
E.KEY_STEP_MIN = 0.1
E.KEY_STEP_MAX = 60

function E.formatStep(step)
    return step == math.floor(step) and string.format("%d", step) or string.format("%.1f", step)
end

-- Posun po K (přepínač na liště osy): playhead skočí o krok dál, Let s novým K-framem se k němu prodlouží a bloky, které by
-- překážely, se odsunou o totéž. Kamera zůstane, kde je, ať se z ní letí k dalšímu K-framu. Patří do kroku zpět s K.
function CinemaEditorScreen:advanceAfterKey(seg)
    if not self.keyAdvance then
        return
    end
    local shot = self.shot
    local t = self.playhead + (self.keyStep or E.KEY_STEP_DEFAULT)
    local oldEnd = S.segmentEnd(seg)
    if S.isFlight(seg) and oldEnd < t then
        local nextSeg = S.blockAfter(shot, oldEnd)
        if nextSeg ~= nil and nextSeg ~= seg and nextSeg.t < t + S.MIN_GAP then
            S.shiftAfter(shot, nextSeg.t, math.max(t - oldEnd, t + S.MIN_GAP - nextSeg.t), { segs = { [seg.id] = true } })
        end
        seg.track.duration = t - seg.t
        S.touch(shot)
    end
    self:setPlayhead(t, false)
    local v0, span = self:getViewStart(), self:getViewSpan()
    if self.viewSpan ~= nil and (t < v0 or t > v0 + span) then
        self.viewStart = t - span * 0.8
    end
end

function CinemaEditorScreen:toggleKeyAdvance()
    self.keyAdvance = not self.keyAdvance or nil
    self:showMessage(self.keyAdvance and string.format(g_i18n:getText("cine_msg_advanceOn"), E.formatStep(self.keyStep or E.KEY_STEP_DEFAULT))
        or g_i18n:getText("cine_msg_advanceOff"))
end

-- Krok posunu nastaví i zapne posun.
function CinemaEditorScreen:setKeyStep(step)
    self.keyStep = math.max(E.KEY_STEP_MIN, math.min(E.KEY_STEP_MAX, step))
    self.keyAdvance = true
    self:showMessage(string.format(g_i18n:getText("cine_msg_advanceOn"), E.formatStep(self.keyStep)))
end

function CinemaEditorScreen:openKeyStepMenu(x, y)
    local t = function(key) return g_i18n:getText(key) end
    local current = self.keyStep or E.KEY_STEP_DEFAULT
    local items = {
        { text = function() return (self.keyAdvance and "> " or "") .. t("cine_adv_on") end, action = function(s) s:toggleKeyAdvance() end,
            keepOpen = true },
    }
    for _, step in ipairs(E.KEY_STEPS) do
        items[#items + 1] = { text = function()
            local on = self.keyAdvance and math.abs((self.keyStep or E.KEY_STEP_DEFAULT) - step) < 1e-6
            return (on and "> " or "") .. string.format(t("cine_adv_step"), E.formatStep(step))
        end, action = function(s) s:setKeyStep(step) end, keepOpen = true }
    end
    items[#items + 1] = { text = t("cine_adv_custom"), action = function(s)
        TextInputDialog.show(function(target, text, clickOk)
            local value = clickOk and tonumber(((text or ""):gsub(",", "."):gsub("[^%d%.]", ""))) or nil
            if value ~= nil and value > 0 then
                target:setKeyStep(value)
            elseif clickOk then
                target:showMessage(t("cine_msg_advanceBad"))
            end
        end, s, E.formatStep(current), t("cine_adv_prompt"), t("cine_adv_custom"), 6, t("button_ok"))
    end }
    self:openMenu(t("cine_adv_title"), items, x, y)
end

-- K v bloku režimu: polohu kamery určuje režim, takže K přidá K-frame jen s ohniskem kamery; když kamera odletěla jinam,
-- řekne to. Stojící kamera (statická, sledování z bodu) se přesune na místo kamery, statická i s natočením (celý blok).
-- K v bloku bez K-framů Letu: když se kamera od pózy bloku na ukazateli posunula nebo natočila, převezme blok polohu, směr
-- i ohnisko kamery po celé své délce (statická = stanoviště, připevněná = nové připevnění, sledování z bodu = stanoviště
-- a natočení, ostatní režimy = posun a natočení vůči kameře režimu); jinak přidá K-frame ohniska.
function CinemaEditorScreen:addModeKey(seg)
    local track = seg.track
    local cam = self.cam
    local t = self.playhead
    local x, y, z, q = self:modePose(seg, t, nil)
    local moved, turned = false, false
    if x ~= nil then
        local yaw, pitch = M.quatToYawPitchRoll(q)
        moved = (cam.x - x) ^ 2 + (cam.y - y) ^ 2 + (cam.z - z) ^ 2 > E.MODE_MOVED ^ 2
        turned = math.abs(M.angleDiff(yaw, cam.yaw)) > E.MODE_TURNED or math.abs(pitch - cam.pitch) > E.MODE_TURNED
    end
    if not moved and not turned then
        self:addModeMark(seg, self.targetFocal)
        return
    end
    if track.mode == "mount" and W.find(track.target) == nil then
        return
    end
    self:pushUndo()
    if track.mode == "static" then
        track.camX, track.camY, track.camZ, track.yaw, track.pitch = cam.x, cam.y, cam.z, cam.yaw, cam.pitch
    elseif track.mode == "mount" then
        track.camIndex = nil
        self:mountHere(track, W.find(track.target))
    else
        if track.mode == "spotlight" then
            track.camX, track.camY, track.camZ = cam.x, cam.y, cam.z
        end
        local bx, by, bz, bq = self:modePose(seg, t, nil, true)
        if bx ~= nil then
            Mo.shiftFromCamera(track, bx, by, bz, bq, cam.x, cam.y, cam.z, cam.yaw, cam.pitch)
        end
    end
    -- bez K-framů režimu ohnisko celého bloku (jako poloha), s nimi K-frame u ukazatele
    if track.marks ~= nil and #track.marks > 0 then
        self:addModeMark(seg, self.targetFocal, true)
    else
        if not track.autoZoom then
            track.focal, track.focal2 = self.targetFocal, nil
        end
        S.touch(self.shot)
        self:setSelectedBlock(seg)
        self:markDirty()
    end
    self:showMessage(g_i18n:getText("cine_msg_staticMoved"))
end

-- Klik a tažení věcí na ose posouvá playhead jen v režimu „všude“ (přepínač vlevo pod osou); jinak jen pravítko.
function CinemaEditorScreen:followPlayhead(t)
    if self.playheadAnywhere then
        self:setPlayhead(t, self.topdown == nil)
    end
end

-- Playhead z pravítka; přichytí se ke krajům a K-framům jako tažené věci.
function CinemaEditorScreen:scrubTo(x)
    self:setPlayhead(self:snapTime(self:timeAtX(x), self:snapTargets(nil, true)), self.topdown == nil)
end

function CinemaEditorScreen:isOverPanels(x, y)
    return self:hitPanels(x, y) ~= nil
end

function CinemaEditorScreen:onPanelsDown(x, y)
    local hit = self:hitPanels(x, y)
    if hit == nil then
        return
    end
    local kind = hit.kind
    local toggle = E.isShift()
    local shot = self.shot
    if kind == "key" or kind == "segment" or kind == "timeline" or kind == "edge" or kind == "mark" then
        self:setActiveTarget(0)
    end
    if kind == "mark" then
        local seg = shot.segments[hit.seg]
        local mark = seg.track.marks[hit.index]
        if toggle then
            self:selToggle("mark", mark)
        else
            self:selSet("mark", mark)
        end
        self.drag = { kind = "mark", seg = hit.seg, index = hit.index }
        self:followPlayhead(seg.t + mark.u * (seg.track.duration or 1))
    elseif kind == "scroll" then
        self:scrollTo(x)
        self.drag = { kind = "scrollDrag" }
    elseif kind == "key" then
        -- K-frame Letu: vybere se a tažením se posouvá v čase uvnitř svého bloku
        local seg, k = hit.seg, hit.seg.track.keys[hit.index]
        if toggle then
            self:selToggle("key", k)
        else
            self:selSet("key", k)
            if self.playheadAnywhere then
                if self.topdown == nil then
                    self:jumpToKey(seg, hit.index)
                else
                    self.playhead = seg.t + k.t
                end
            end
        end
        self.drag = { kind = "keyTime", seg = seg, key = k, x0 = x }
    elseif kind == "edge" then
        -- kraj bloku: tažením se blok ořezává (druhý konec stojí)
        self:setSelectedBlock(hit.seg)
        self:beginTrim(x, hit.seg, hit.edge)
    elseif kind == "segment" then
        local seg = shot.segments[hit.index]
        local grabKind, grabObj, reduce = self:segmentClick(seg, self:timeAtX(x), toggle)
        self:followPlayhead(self:timeAtX(x))
        self:beginClipDrag(x, grabKind, grabObj, reduce)
    elseif kind == "lane" then
        self:setActiveTarget(hit.index)
        self:beginMarquee(x, y, toggle)
    elseif kind == "timeline" then
        self:beginMarquee(x, y, toggle)
    elseif kind == "ruler" then
        self.drag = { kind = "scrub" }
        self:scrubTo(x)
    elseif kind == "playheadMode" then
        E.playSound("CLICK")
        self.playheadAnywhere = not self.playheadAnywhere
    elseif kind == "routePoint" then
        self:setActiveTarget(hit.index)
        if self.topdown ~= nil then
            self.topdown.point = { actor = hit.index, index = hit.point }
        end
        self:followPlayhead(self:routePointTime(hit.index, hit.point))
    elseif kind == "actorAction" then
        self:setActiveTarget(hit.index)
        local actor = shot.actors[hit.index]
        local action = actor.actions[hit.action]
        -- ve výběru víc věcí tah za akci posouvá celou skupinu, i když míří na úchyt délky
        local inGroup = self:selHas("action", action) and self:selCount() > 1
        if hit.part == "end" and not toggle and not inGroup then
            self:selSet("action", action)
            self.drag = { kind = "actionEnd", actor = hit.index, index = hit.action }
            self:followPlayhead((actor.delay or 0) + CinemaActions.endTime(action))
        else
            local reduce = self:clickSelect("action", action, toggle)
            self:followPlayhead((actor.delay or 0) + action.t)
            self:beginClipDrag(x, "action", action, reduce)
        end
    elseif hit.rowKey ~= nil and kind ~= "camLabel" then
        if kind == "actor" then
            self:setActiveTarget(hit.index)
        end
        self.drag = { kind = "row", key = hit.rowKey, y0 = y }
    elseif kind == "actor" then
        self:setActiveTarget(hit.index)
        if hit.onBlock and self:spanMouseDown(hit.index, x, toggle) then
            -- úsek, pauza nebo stání: vybere se sám (CinemaEditorSpans)
            return
        elseif hit.onBlock then
            local actor = shot.actors[hit.index]
            self:beginClipDrag(x, "drive", actor, self:clickSelect("drive", actor, toggle))
        else
            self:beginMarquee(x, y, toggle)
        end
    elseif kind == "tool" then
        self:toolbarClick(hit.index)
    elseif kind == "top" then
        self:topbarClick(hit.index)
    elseif kind == "collapse" then
        E.playSound("CLICK")
        self:toggleActorCollapsed(hit.index)
    elseif kind == "propsCollapse" then
        E.playSound("CLICK")
        self:toggleProps()
    elseif kind == "prop" then
        self.activeProp = hit.index
    elseif kind == "objectsCollapse" then
        E.playSound("CLICK")
        self:toggleObjects()
    elseif kind == "object" then
        self.activeObject, self.selObjAction, self.objectFocus = hit.index, nil, true
    elseif kind == "objAction" then
        self:beginObjectActionDrag(hit.index, hit.action, x)
    elseif kind == "compact" then
        E.playSound("CLICK")
        self:toggleCompact()
    elseif kind == "expandAll" or kind == "collapseAll" then
        E.playSound("CLICK")
        self:setAllRowsCollapsed(kind == "collapseAll")
    elseif kind == "addActor" then
        E.playSound("CLICK")
        local ax, ay, aw, ah = self:getAddActorRect()
        self:openAddActorMenu(ax + aw, ay + ah)
    elseif kind == "rowScroll" then
        self:rowScrollTo(y)
        self.drag = { kind = "rowScrollDrag" }
    elseif kind == "eye" then
        self:toggleRoute(hit.target)
    elseif kind == "camLabel" then
        self:setActiveTarget(0)
        self.drag = { kind = "row", key = "cam", y0 = y, click = function(s) s:switchCamera(1) end }
    elseif kind == "swatch" then
        self:setActiveTarget(hit.target == "cam" and 0 or hit.target)
        self:openPalette(hit.target, x, y)
    elseif kind == "focus" then
        local f = shot.focus[hit.index]
        self:beginClipDrag(x, "focus", f, self:clickSelect("focus", f, toggle))
    elseif kind == "chEye" or kind == "chRow" or kind == "chPoint" or kind == "chGraph" then
        self:chPanelDown(hit, x, y)
    elseif kind == "curveKey" then
        -- bod K-framu na křivce rychlosti: tažením nahoru a dolů se mění rychlost kamery v K-framu
        local seg, k = hit.seg, hit.seg.track.keys[hit.index]
        self:selSet("key", k)
        self:setPlayhead(seg.t + k.t, self.topdown == nil)
        local _, _, vmax = self:getCurveScale()
        self.drag = { kind = "curveKey", seg = seg, key = k, vmax = vmax }
    elseif kind == "curveHandle" then
        self.drag = { kind = "curveHandle", seg = hit.seg, key = hit.seg.track.keys[hit.index], side = hit.side }
    end
end

-- Tažení táhla vlivu na křivce rychlosti: jak dlouho trvá rozjezd / dojezd (díl úseku k sousednímu K-framu);
-- Shift nastaví obě strany stejně.
function CinemaEditorScreen:dragCurveHandle(x)
    local drag = self.drag
    local keys = drag.seg.track.keys
    local index
    for i, k in ipairs(keys) do
        if k == drag.key then
            index = i
        end
    end
    local key = drag.key
    local otherIndex = index ~= nil and S.anchorNeighbor(self.shot, drag.seg.track, index, drag.side == "in" and -1 or 1) or nil
    local other = otherIndex ~= nil and keys[otherIndex] or nil
    if other == nil then
        return
    end
    local rel = self:timeAtX(x) - drag.seg.t
    local span = math.abs(other.t - key.t)
    if span < 1e-6 then
        return
    end
    local value = M.clamp(math.abs(rel - key.t) / span, M.INFLUENCE_MIN, M.INFLUENCE_MAX)
    value = math.floor(value * 100 + 0.5) / 100
    if not drag.moved then
        self:pushUndo()
        drag.moved = true
    end
    S.setKeyInfluence(self.shot, key, E.isShift() and nil or drag.side, value)
    self.curveShown = { key = key, time = g_time, influence = value }
    self:markDirty()
end

-- Střední tlačítko na bloku režimu s pohybem: tažením se mění rozjezd (levá půlka bloku) nebo dojezd (pravá půlka).
function CinemaEditorScreen:onPanelsMiddle(x, y)
    local hit = self:hitPanels(x, y)
    if hit ~= nil and (hit.kind == "ruler" or hit.kind == "scroll") then
        self.drag = { kind = "pan", x = x }
        return
    end
    if hit == nil or hit.kind ~= "segment" then
        return
    end
    local seg = self.shot.segments[hit.index]
    if not Mo.MOVING[seg.track.mode] then
        return
    end
    local t = self:timeAtX(x)
    self:setActiveTarget(0)
    self.drag = { kind = "ease", index = hit.index, side = t < seg.t + (seg.track.duration or 0) * 0.5 and "in" or "out" }
    self:dragEase(x)
end

-- Tažení K-framu Letu v čase: nepřeskočí sousední K-framy ani kraje bloku.
function CinemaEditorScreen:dragKeyTime(x)
    local drag = self.drag
    local track = drag.seg.track
    local index
    for i, k in ipairs(track.keys) do
        if k == drag.key then
            index = i
        end
    end
    if index == nil then
        return
    end
    if not drag.moved then
        if math.abs(x - drag.x0) < E.DRAG_SLOP_PX * g_pixelSizeScaledX then
            return
        end
        if S.keyIsFree(self.shot, track, index) then
            if not drag.warned then
                drag.warned = true
                self:showMessage(g_i18n:getText("cine_msg_keyFree"))
            end
            return
        end
        self:pushUndo()
        drag.moved = true
    end
    local t = self:timeAtX(x)
    if not E.isShift() then
        t = math.floor(t * 10 + 0.5) / 10
    end
    local rel = S.flightMoveKey(self.shot, track, index, t - drag.seg.t)
    if self.playheadAnywhere then
        self.playhead = drag.seg.t + rel
    end
    if self.topdown == nil then
        self:applyShotPose(self.playhead)
    end
    self:markDirty()
end

-- Tažení bodu K-framu na křivce rychlosti: rychlost kamery v K-framu (m/s; Shift jemně, jinak po desetinách).
function CinemaEditorScreen:dragCurveKey(y)
    local drag = self.drag
    local track = drag.seg.track
    local index
    for i, k in ipairs(track.keys) do
        if k == drag.key then
            index = i
        end
    end
    if index == nil then
        return
    end
    if S.keyIsFree(self.shot, track, index) then
        if not drag.warned then
            drag.warned = true
            self:showMessage(g_i18n:getText("cine_msg_keyFree"))
        end
        return
    end
    local y0, h = self:getCurveScale()
    local v = math.max((y - y0) / h * drag.vmax, 0)
    v = E.isShift() and v or math.floor(v * 10 + 0.5) / 10
    if not drag.moved then
        self:pushUndo()
        drag.moved = true
    end
    S.setKeySpeed(self.shot, track, index, v)
    self.curveShown = { key = drag.key, time = g_time }
    self:markDirty()
end

function CinemaEditorScreen:dragEase(x)
    local drag = self.drag
    local seg = self.shot.segments[drag.index]
    if seg == nil then
        return
    end
    local t = self:timeAtX(x)
    local value = drag.side == "in" and t - seg.t or S.segmentEnd(seg) - t
    if not E.isShift() then
        value = math.floor(value * 10 + 0.5) / 10
    end
    local a1, a2, d = Mo.easeTimes(seg.track)
    local other = drag.side == "in" and a2 or a1
    value = M.clamp(value, 0, math.max(d - other, 0))
    local key = drag.side == "in" and "easeIn" or "easeOut"
    if Mo.value(seg.track, key) == value then
        return
    end
    if not drag.moved then
        self:pushUndo()
        drag.moved = true
    end
    seg.track.easeIn, seg.track.easeOut = a1, a2
    seg.track[key] = value
    self.easeShown = { index = drag.index, side = drag.side, value = value, time = g_time }
    S.touch(self.shot)
    self:markDirty()
end

function CinemaEditorScreen:onPanelsDrag(x, y)
    local drag = self.drag
    if drag.kind == "clip" then
        self:dragClip(x)
    elseif drag.kind == "trim" then
        self:dragTrim(x)
    elseif drag.kind == "marquee" then
        self:dragMarquee(x, y)
    elseif drag.kind == "ease" then
        self:dragEase(x)
    elseif drag.kind == "keyTime" then
        self:dragKeyTime(x)
    elseif drag.kind == "curveKey" then
        self:dragCurveKey(y)
    elseif drag.kind == "curveHandle" then
        self:dragCurveHandle(x)
    elseif drag.kind == "scrollDrag" then
        self:scrollTo(x)
    elseif drag.kind == "rowScrollDrag" then
        self:rowScrollTo(y)
    elseif drag.kind == "row" then
        self:dragRow(y)
    elseif drag.kind == "objAction" then
        self:dragObjectAction(x)
    elseif drag.kind == "pan" then
        self:panTimelineBy(x - drag.x)
        drag.x = x
    elseif drag.kind == "span" then
        self:dragSpan(drag, x)
    elseif drag.kind == "actionEnd" then
        local actor = self.shot.actors[drag.actor]
        local action = actor ~= nil and actor.actions[drag.index] or nil
        if action == nil then
            return
        end
        local dur = self:timeAtX(x) - (actor.delay or 0) - action.t
        if not E.isShift() then
            dur = math.floor(dur * 10 + 0.5) / 10
            if CinemaActions.isBlink(action) then
                -- tažení blikání přidává a ubírá celá bliknutí
                local P = CinemaActions.BLINK_PERIOD
                dur = math.max(1, math.floor(dur / P + 0.5)) * P
            end
        end
        if not drag.moved then
            if math.abs(dur - (CinemaActions.endTime(action) - action.t)) < 0.05 then
                return
            end
            self:pushUndo()
            drag.moved = true
        end
        CinemaActions.setDuration(action, dur >= CinemaActions.MIN_DURATION * 0.5 and dur or nil)
        if self.playheadAnywhere then
            self.playhead = (actor.delay or 0) + CinemaActions.endTime(action)
        end
        S.touch(self.shot)
        self:markDirty()
    elseif drag.kind == "scrub" then
        self:scrubTo(x)
    elseif drag.kind == "mark" then
        local seg = self.shot.segments[drag.seg]
        if seg == nil or seg.track.marks == nil or seg.track.marks[drag.index] == nil then
            return
        end
        local d = math.max(seg.track.duration or 1, 0.1)
        local t = self:timeAtX(x)
        if not E.isShift() then
            t = math.floor(t * 10 + 0.5) / 10
        end
        if not drag.moved then
            self:pushUndo()
            drag.moved = true
        end
        local u = Mo.moveMark(seg.track, drag.index, (t - seg.t) / d)
        if self.playheadAnywhere then
            self.playhead = seg.t + u * d
        end
        S.touch(self.shot)
        if self.topdown == nil then
            self:applyShotPose(self.playhead)
        end
        self:markDirty()
    elseif drag.kind == "chPoint" then
        self:chPanelDrag(x, y)
    elseif drag.kind == "aim" then
        if drag.handle and not drag.moved then
            self:pushUndo()
            drag.moved = true
        end
        self:topdownAim(x, y)
    elseif drag.kind == "face" then
        self:topdownFace(x, y)
    elseif drag.kind == "point" or drag.kind == "keyPos" or drag.kind == "standPos" or drag.kind == "pathHandle" then
        self:topdownMove(x, y)
    end
end

---------------------------------------------------------------------------------------------------
-- výběr objektu

local REASONS = { noStart = "cine_msg_actorNoStart", missing = "cine_msg_actorMissing", notDrivable = "cine_msg_notDrivable",
    notServer = "cine_msg_actorNotServer", occupied = "cine_msg_actorOccupied", aiActive = "cine_msg_actorAi",
    cannotReverse = "cine_msg_cannotReverse" }

E.PERSON_PICK_SIZE = { 0.35, 1.85 }

E.DRONE_PICK_SIZE = { 0.9, 0.6 }

-- Obrys kvádru (půl šířky half, výška height od y) kolem bodu na obrazovce: x0, y0, x1, y1 a vzdálenost, nebo nil.
function CinemaEditorScreen:pickBox(st, half, height, base)
    local d = math.sqrt((st.x - self.cam.x) ^ 2 + (st.y - self.cam.y) ^ 2 + (st.z - self.cam.z) ^ 2)
    if d > W.PICK_DISTANCE then
        return nil
    end
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, c in ipairs({ { -1, 0, -1 }, { 1, 0, -1 }, { -1, 0, 1 }, { 1, 0, 1 }, { -1, 1, -1 }, { 1, 1, -1 }, { -1, 1, 1 }, { 1, 1, 1 } }) do
        local sx, sy = CinemaCamera.worldToScreen(self.cam, st.x + c[1] * half, st.y + base + c[2] * height, st.z + c[3] * half)
        if sx == nil then
            return nil
        end
        x0, y0, x1, y1 = math.min(x0, sx), math.min(y0, sy), math.max(x1, sx), math.max(y1, sy)
    end
    if x1 < 0 or y1 < 0 or x0 > 1 or y0 > 1 then
        return nil
    end
    return { x0, y0, x1, y1 }, d
end

-- Kandidáti výběru T: vozidla, postavy herců (obrys kolem postavy v plánované poloze na ukazateli) a drony vleků v záběru.
function CinemaEditorScreen:pickList()
    local list = W.candidates(self.cam)
    local pending = self.pendingAction
    if pending ~= nil and (pending.box or pending.carry ~= nil or pending.prop ~= nil or pending.object or pending.actor) then
        return list
    end
    for _, c in ipairs({ unpack(list) }) do
        for _, d in ipairs(W.drones(c.vehicle)) do
            local target = W.droneTarget(c.vehicle, d.k)
            local box, dist = self:pickBox(W.nodeState(d.node), E.DRONE_PICK_SIZE[1], E.DRONE_PICK_SIZE[2], -E.DRONE_PICK_SIZE[2] * 0.5)
            if box ~= nil then
                list[#list + 1] = { target = target, label = self:targetName(target), dist = dist, box = box }
            end
        end
    end
    local half, height = E.PERSON_PICK_SIZE[1], E.PERSON_PICK_SIZE[2]
    for i, a in ipairs(self.shot.actors) do
        if Pe.isPerson(a) then
            local target = S.personTarget(self.shot, a)
            local st = self:targetState(target, self.playhead)
            local box, dist = nil, nil
            if st ~= nil then
                box, dist = self:pickBox(st, half, height, 0)
            end
            if box ~= nil then
                list[#list + 1] = { person = i, target = target, label = a.name or "?", dist = dist, box = box }
            end
        end
    end
    return list
end

-- Klik na postavu herce nebo dron při výběru: stejné dokončení jako u vozidla, jen cílem je postava / dron.
function CinemaEditorScreen:pickPerson(c, pending, x, y)
    self.addTarget = c.target
    if pending == nil then
        self:openTargetMenu(c.target, c.person, x, y)
        return
    end
    self.picking = false
    if pending.target then
        self:openAddPanel()
    elseif pending.retarget ~= nil then
        for _, seg in ipairs(self.shot.segments) do
            if seg.id == pending.retarget then
                self:retargetBlock(seg, c.target)
            end
        end
    elseif pending.focus then
        self:setFocusHere(c.target)
    elseif pending.focusTarget ~= nil then
        self:changeFocusTarget(pending.focusTarget, pending.from, nil, c.target)
    elseif pending.mode == "mount" or pending.mode == "vehicleCam" then
        self:showMessage(g_i18n:getText("cine_msg_needVehicle"))
    elseif pending.mode == "pair" then
        self:openPairMenu(c.target, x, y)
    elseif pending.mode ~= nil then
        self:createTrackOn(pending.mode, c.target, pending.side)
    end
end

function CinemaEditorScreen:pickAt(x, y)
    if self:isOverPanels(x, y) then
        self:onPanelsDown(x, y)
        return
    end
    if self.pendingAction ~= nil and self.pendingAction.box then
        self:boxPickAt(x, y)
        return
    end
    if self.pendingAction ~= nil and self.pendingAction.carry ~= nil then
        self:carryPickAt(x, y, self.pendingAction.carry)
        return
    end
    local propKind = self.pendingAction ~= nil and self.pendingAction.prop or nil
    if propKind ~= nil and propKind ~= "vehicle" then
        self.pendingAction = nil
        self.picking = false
        self:pickPropAt(propKind, x, y)
        return
    end
    local pending = self.pendingAction
    -- brána nebo budova (bod pod kurzorem) má přednost před obrysem vozidla, ve kterém může ležet
    if (pending == nil or pending.object) and self:pickObjectAt(x, y, pending) then
        return
    end
    local list = self.pickCandidates or self:pickList()
    local c = W.candidateAt(list, x, y)
    if c ~= nil and c.vehicle == nil then
        self.pendingAction = nil
        self:pickPerson(c, pending, x, y)
        return
    end
    if c == nil then
        self.picking = false
        self.pendingAction = nil
        if pending ~= nil and pending.object then
            self:showMessage(g_i18n:getText("cine_msg_noObject"))
        end
        return
    end
    self.pendingAction = nil
    -- vybraný objekt je od teď cílem akcí z panelu Přidat
    self.addTarget = W.uid(c.vehicle)
    if pending ~= nil then
        self.picking = false
        if pending.actor then
            self:addActor(c.vehicle)
        elseif pending.target then
            self:openAddPanel()
        elseif pending.retarget ~= nil then
            for _, seg in ipairs(self.shot.segments) do
                if seg.id == pending.retarget then
                    self:retargetBlock(seg, W.uid(c.vehicle))
                end
            end
        elseif pending.focus then
            self:setFocusHere(c.vehicle)
        elseif pending.focusTarget ~= nil then
            self:changeFocusTarget(pending.focusTarget, pending.from, c.vehicle)
        elseif pending.prop == "vehicle" then
            self:addProp(CinemaProps.fromVehicle(c.vehicle))
        elseif pending.object then
            self:addObject(CinemaObjects.fromVehicle(c.vehicle))
        elseif pending.mode == "mount" then
            self:createMountTrack(c.vehicle)
        elseif pending.mode == "vehicleCam" then
            self:openVehicleCamMenu(c.vehicle, x, y)
        elseif pending.mode == "pair" then
            self:openPairMenu(W.uid(c.vehicle), x, y)
        else
            self:createTrack(pending.mode, c.vehicle, pending.side)
        end
        return
    end
    self:openObjectMenu(c.vehicle, x, y)
end

-- Název režimu; sledování se jménem strany, ze které se natáčí.
function CinemaEditorScreen.trackLabel(track)
    local label = g_i18n:getText("cine_mode_" .. track.mode)
    local side = track.mode == "follow" and Mo.followSide(track) or nil
    if side ~= nil then
        label = string.format("%s - %s", label, g_i18n:getText("cine_follow_" .. side))
    end
    if track.mode == "pov" then
        label = string.format("%s - %s", label, g_i18n:getText("cine_pov_" .. (track.variant or "eyes")))
    elseif track.mode == "mount" and track.camIndex ~= nil then
        label = string.format("%s - %s", label, string.format(g_i18n:getText("cine_vehicleCam"), track.camIndex))
    end
    return label
end

-- Kamera, ze které se režim odvozuje: volná kamera editoru (v pohledu shora její uložená póza).
function CinemaEditorScreen:getFreeCamera()
    return self.topdown ~= nil and self.topdown.save or self.cam
end

-- Nový blok v živém režimu od času playheadu. Začíná tam, kde stojí volná kamera vůči vozidlu.
function CinemaEditorScreen:createTrack(mode, vehicle, side)
    self:createTrackOn(mode, W.uid(vehicle), side)
end

-- Nový režim na cíl target (vozidlo nebo postava herce) podle polohy cíle v čase playheadu.
function CinemaEditorScreen:createTrackOn(mode, target, side)
    local st = self:targetState(target, self.playhead)
    if st == nil then
        return
    end
    local cam = self:getFreeCamera()
    self:placeTrack(Mo.init(mode, target, cam.x, cam.y, cam.z, st.x, st.y, st.z, st.heading, side))
end

-- Vzdálenost kamery bloku od jeho cíle v čase t (pro automatický zoom), nil bez cíle.
function CinemaEditorScreen:blockTargetDistance(seg, t)
    local x, y, z = self:modePose(seg, t, nil)
    local st = seg.track.target ~= nil and self:targetState(seg.track.target, t) or nil
    if x == nil or st == nil then
        return nil
    end
    return math.max(math.sqrt((st.x - x) ^ 2 + (st.y - y) ^ 2 + (st.z - z) ^ 2), 1)
end

-- Dva cíle v záběru: kamera kolmo na jejich spojnici ze strany, kde je teď, a tak daleko, aby se vešly oba.
function CinemaEditorScreen:createPairTrack(target, target2)
    local st, st2 = self:targetState(target, self.playhead), self:targetState(target2, self.playhead)
    if st == nil or st2 == nil then
        return
    end
    local cam = self:getFreeCamera()
    local mx, my, mz = (st.x + st2.x) * 0.5, (st.y + st2.y) * 0.5, (st.z + st2.z) * 0.5
    local track = Mo.init("pair", target, cam.x, cam.y, cam.z, mx, my, mz, st.heading)
    track.target2 = target2
    self:placeTrack(track)
end

-- Pohled postavy herce i: očima nebo přes rameno (variant z Mo.POV_VARIANTS).
function CinemaEditorScreen:createPovTrack(i, variant)
    local actor = self.shot.actors[i]
    if actor == nil or not CinemaPerson.isPerson(actor) then
        return
    end
    local track = Mo.init("pov", S.personTarget(self.shot, actor), 0, 0, 0, 0, 0, 0, 0)
    track.variant = variant
    self:placeTrack(track)
end

-- Kamera připevněná na vozidlo: s kamerou vozidla index camIndex na jejím místě a s jejím objektivem, jinak tam, kde je
-- teď volná kamera, na části vozidla, na kterou míří (rameno, lišta…), nebo na kostře.
function CinemaEditorScreen:createMountTrack(vehicle, camIndex)
    local track = Mo.init("mount", W.uid(vehicle), 0, 0, 0, 0, 0, 0, 0)
    if camIndex ~= nil then
        local camera = W.vehicleCameras(vehicle)[camIndex]
        if camera == nil then
            self:showMessage(g_i18n:getText("cine_msg_noVehicleCameras"))
            return
        end
        track.camIndex = camIndex
        self:placeTrack(track)
        -- objektiv kamery vozidla (placeTrack dá bloku ohnisko editoru)
        track.focal = M.clampFocal(M.fovToFocal(getFovY(camera.node)))
        S.touch(self.shot)
        self:applyShotPose(self.playhead)
        return
    end
    self:mountHere(track, vehicle)
    self:placeTrack(track)
end

-- Uloží do bloku připevnění podle současné volné kamery (část vozidla pod středem obrazu, jinak kostra).
function CinemaEditorScreen:mountHere(track, vehicle)
    local cam = self:getFreeCamera()
    local fx, fy, fz = M.forwardFromYawPitch(cam.yaw, cam.pitch)
    local shape = W.raycastVehicle(vehicle, cam.x, cam.y, cam.z, fx, fy, fz, E.MOUNT_RAY)
    local node = shape ~= nil and shape or vehicle.rootNode
    track.mountPath = W.nodePath(vehicle, node)
    if track.mountPath == nil then
        node = vehicle.rootNode
        track.mountPath = W.nodePath(vehicle, node)
    end
    Mo.mountFromCamera(track, W.frame(node), cam.x, cam.y, cam.z, cam.yaw, cam.pitch)
end

-- Statická kamera od playheadu: stojí tam, kde je volná kamera, a drží její natočení; nepotřebuje cíl.
function CinemaEditorScreen:createStaticTrack()
    local cam = self:getFreeCamera()
    self:placeTrack(Mo.initStatic(cam.x, cam.y, cam.z, cam.yaw, cam.pitch))
end

-- Nový blok od playheadu (uvnitř jiného bloku hned za jeho koncem). Do mezery před dalším blokem se vmáčkne (zkrátí se);
-- když se ani tak nevejde, přepíše začátek následujícího. Mezi bloky je střih, plynulé navázání se zapne v nastavení bloku.
function CinemaEditorScreen:placeTrack(track)
    local shot = self.shot
    track.focal = self.targetFocal
    local seg = { id = S.nextSegmentId(shot), t = self.playhead, track = track }
    self.picking = false
    local current = S.segmentAt(shot, seg.t)
    if current ~= nil then
        seg.t = S.segmentEnd(current) + S.MIN_GAP
    end
    S.standToKeys(track)
    local squeezed, overwritten = false, false
    local nextSeg = S.blockAfter(shot, seg.t + 1e-6)
    if nextSeg ~= nil and S.segmentEnd(seg) > nextSeg.t - S.MIN_GAP then
        local gap = nextSeg.t - S.MIN_GAP - seg.t
        if gap >= S.MIN_SEGMENT then
            seg.track.duration = gap
            squeezed = true
        else
            overwritten = true
        end
    end
    self:pushUndo()
    self:clearSpanForNewBlock(seg)
    if S.segmentOverlaps(shot, seg) then
        table.remove(self.undoStack)
        self:showMessage(g_i18n:getText("cine_msg_segmentBusy"))
        return
    end
    S.addSegment(shot, seg)
    self:setSelectedBlock(seg)
    self.playhead = seg.t
    self:markDirty()
    self:applyShotPose(self.playhead)
    self:showMessage(string.format(g_i18n:getText("cine_msg_segmentSet"), E.trackLabel(track), seg.t, S.segmentEnd(seg)))
    if squeezed then
        self:showMessage(g_i18n:getText("cine_msg_segmentSqueezed"))
    elseif overwritten then
        self:showMessage(g_i18n:getText("cine_msg_segmentOverwrote"))
    end
end

function CinemaEditorScreen:restartTrackHere(seg)
    local track = seg.track
    if track.mode == "mount" then
        local v = W.find(track.target)
        if v ~= nil and track.camIndex == nil then
            self:pushUndo()
            self:mountHere(track, v)
            S.touch(self.shot)
            self:markDirty()
            self:applyShotPose(self.playhead)
        end
        return
    end
    if track.mode == "pov" or track.mode == "pair" then
        return
    end
    if track.mode == "static" then
        local cam = self:getFreeCamera()
        self:pushUndo()
        track.camX, track.camY, track.camZ, track.yaw, track.pitch = cam.x, cam.y, cam.z, cam.yaw, cam.pitch
        S.touch(self.shot)
        self:markDirty()
        return
    end
    local st = self:targetState(track.target, self.playhead)
    if st == nil then
        return
    end
    self:pushUndo()
    local cam = self:getFreeCamera()
    local fresh = Mo.init(track.mode, track.target, cam.x, cam.y, cam.z, st.x, st.y, st.z, st.heading, track.mode == "follow" and "camera" or nil)
    fresh.duration, fresh.focal = track.duration, self.targetFocal
    fresh.smooth, fresh.blend = track.smooth, track.blend
    S.standToKeys(fresh)
    seg.track = fresh
    S.touch(self.shot)
    self:markDirty()
    self:applyShotPose(self.playhead)
end

---------------------------------------------------------------------------------------------------
-- bloky v živém režimu: póza a plánovaná poloha cíle

-- Kde bude vozidlo za t sekund od začátku záběru. Vozidlo s trasou je podle plánu (vozidla v editoru stojí na startu),
-- ostatní stojí tam, kde jsou. Souprava se posune a pootočí jako celek podle prvního vozidla.
function CinemaEditorScreen:predictedState(v, t)
    local live = W.state(v)
    local uid = W.uid(v)
    for _, actor in ipairs(self.shot.actors) do
        local entries = actor.start ~= nil and actor.start.entries or {}
        for _, entry in ipairs(entries) do
            if entry.uid == uid then
                local x, y, z, heading = self:entryPoseAt(actor, entry, t)
                if x == nil then
                    return live
                end
                return { x = x, y = y, z = z, heading = heading or live.heading }
            end
        end
    end
    return live
end

-- Směr (yaw) uloženého článku: getWorldRotation u vozidla otočeného zády vrací (π, π − yaw, π), samotné ry pak neplatí.
local function yawOf(entry)
    local ry = entry.ry or 0
    if math.abs(entry.rx or 0) > math.pi * 0.5 and math.abs(entry.rz or 0) > math.pi * 0.5 then
        return math.pi - ry
    end
    return ry
end

-- Poloha a směr článku soupravy herce v čase t (s od začátku záběru) podle plánu trasy: souprava se posune a pootočí
-- jako celek podle prvního vozidla. nil bez trasy.
function CinemaEditorScreen:entryPoseAt(actor, entry, t)
    local root = actor.start ~= nil and actor.start.entries[1] or nil
    local plan = R.plan(actor)
    if plan == nil or root == nil then
        return nil
    end
    local rx, rz, _, heading = R.positionAtTime(plan, t - (actor.delay or 0))
    if t <= (actor.delay or 0) then
        heading = yawOf(root)
    end
    -- kořen soupravy míří po směru jízdy (ne natočený jako na startu), ostatní články si drží úhel vůči němu
    local delta = heading - yawOf(root)
    local c, sn = math.cos(delta), math.sin(delta)
    local ox, oz = entry.x - root.x, entry.z - root.z
    local x, z = rx + ox * c + oz * sn, rz - ox * sn + oz * c
    local y = W.terrainY(x, z) + (entry.y - W.terrainY(entry.x, entry.z))
    return x, y, z, entry.ry ~= nil and yawOf(entry) + delta or nil
end

-- Stav cíle v čase t: při přehrávání skutečný vyhlazený, jinak plánovaný.
function CinemaEditorScreen:targetState(uid, t, dt)
    local _, droneNode = W.droneOf(uid)
    if droneNode ~= nil then
        -- dron létá podle svého skriptu, plán nemá: vždy tam, kde je
        local st = W.nodeState(droneNode)
        return dt ~= nil and self:filterTarget(st, dt, uid) or st
    end
    local person = S.personOfTarget(self.shot, uid)
    if person ~= nil then
        -- postava podle plánu trasy (i při přehrávání jde po něm)
        local x, z, yaw, y = CinemaPerson.poseAt(person, t)
        if x == nil then
            return nil
        end
        local st = { x = x, y = y or W.terrainY(x, z), z = z, heading = yaw or 0 }
        return dt ~= nil and self:filterTarget(st, dt, uid) or st
    end
    local v = W.find(uid)
    if v == nil then
        return nil
    end
    if dt ~= nil then
        return self:filterTarget(W.state(v), dt, uid)
    end
    return self:predictedState(v, t)
end

-- Rám uzlu, na který je blok připevněný. Při přehrávání skutečný (náklon i houpání vozidla), jinak v plánované poloze
-- vozidla v čase t: rám se otočí kolem kořene vozidla o rozdíl směru a posune s ním.
function CinemaEditorScreen:mountFrame(track, t, live)
    local v = W.find(track.target)
    if v == nil then
        return nil
    end
    local node
    if track.camIndex ~= nil then
        local camera = W.vehicleCameras(v)[track.camIndex]
        node = camera ~= nil and camera.node or nil
    else
        node = W.nodeAt(v, track.mountPath or "c1")
    end
    if node == nil then
        return nil
    end
    local frame = W.frame(node)
    if live then
        return frame
    end
    local root, st = W.state(v), self:predictedState(v, t)
    local d = M.angleDiff(root.heading, st.heading)
    local c, s = math.cos(d), math.sin(d)
    local function turn(vec)
        return { vec[1] * c + vec[3] * s, vec[2], -vec[1] * s + vec[3] * c }
    end
    local rel = turn({ frame.x - root.x, frame.y - root.y, frame.z - root.z })
    return { x = st.x + rel[1], y = st.y + rel[2], z = st.z + rel[3], ax = turn(frame.ax), ay = turn(frame.ay), az = turn(frame.az) }
end

-- Sledování s tlumením: kamera jde za polohou, kterou by měla mít, s časovou konstantou track.lag (v zatáčce vybočí ven,
-- při rozjezdu zůstane vzadu). Mimo přehrávání se tlumení spočítá z plánu od začátku bloku, při přehrávání běží filtr
-- (začne tam, kde by byl podle plánu).
function CinemaEditorScreen:chasePosition(seg, t, dt, x, y, z)
    local track = seg.track
    local lag = track.lag or 0
    if lag <= 0 then
        return x, y, z
    end
    local chase = self.chase
    if dt ~= nil and chase ~= nil and chase.seg == seg.id then
        if chase.time ~= g_time then
            chase.time = g_time
            local sec = dt * 0.001
            chase.x, chase.y, chase.z = M.damp(chase.x, x, lag, sec), M.damp(chase.y, y, lag, sec), M.damp(chase.z, z, lag, sec)
        end
        return chase.x, chase.y, chase.z
    end
    local from = math.max(seg.t, t - lag * 5)
    local step = math.max(E.CHASE_STEP, lag / 10)
    local px, py, pz
    local tau = from
    while true do
        local st = self:targetState(track.target, tau)
        local cx, cy, cz = nil, nil, nil
        if st ~= nil then
            cx, cy, cz = Mo.evaluate(track, tau - seg.t, st)
        end
        if cx ~= nil then
            if px == nil then
                px, py, pz = cx, cy, cz
            else
                local k = 1 - math.exp(-step / lag)
                px, py, pz = px + (cx - px) * k, py + (cy - py) * k, pz + (cz - pz) * k
            end
        end
        if tau >= t then
            break
        end
        tau = math.min(tau + step, t)
    end
    px, py, pz = px or x, py or y, pz or z
    if dt ~= nil then
        self.chase = { seg = seg.id, x = px, y = py, z = pz, time = g_time }
    end
    return px, py, pz
end

-- Póza živého režimu v čase t: x, y, z, q, focal (nil, když cíl chybí).
function CinemaEditorScreen:modePose(seg, t, dt, raw)
    local track = seg.track
    if not raw and track.mode ~= "static" and track.mode ~= "mount" then
        local x, y, z, q, focal = self:modePose(seg, t, dt, true)
        if x == nil then
            return nil
        end
        x, y, z, q = Mo.applyShift(track, x, y, z, q)
        return x, y, z, q, focal
    end
    if track.mode == "static" then
        return track.camX, track.camY, track.camZ, M.quatFromYawPitchRoll(track.yaw or 0, track.pitch or 0, 0),
            Mo.focalAt(track, t - seg.t, nil, self.targetFocal)
    end
    if track.mode == "mount" then
        local frame = self:mountFrame(track, t, dt ~= nil)
        if frame == nil then
            return nil
        end
        local x, y, z, q = Mo.mountPose(track, frame)
        return x, y, z, q, Mo.focalAt(track, t - seg.t, nil, self.targetFocal)
    end
    if track.mode == "pov" then
        -- postava jde po plánu i při přehrávání, takže bez vyhlazení (kamera v hlavě nesmí zaostávat)
        local st = self:targetState(track.target, t)
        local person = S.personOfTarget(self.shot, track.target)
        if st == nil or person == nil then
            return nil
        end
        local x, y, z, q = Mo.povPose(track, st, t - seg.t, CinemaPerson.speedAt(person, t))
        return x, y, z, q, Mo.focalAt(track, t - seg.t, nil, self.targetFocal)
    end
    local st = self:targetState(track.target, t, dt)
    if st == nil then
        return nil
    end
    local extra
    if track.mode == "pass" then
        extra = { pass = self:targetState(track.target, seg.t + (track.passAt or 0)) }
    elseif track.mode == "pair" then
        extra = { second = track.target2 ~= nil and self:targetState(track.target2, t, dt) or nil }
        if extra.second == nil then
            return nil
        end
    end
    local x, y, z, lx, ly, lz, q = Mo.evaluate(track, t - seg.t, st, extra)
    if x == nil then
        return nil
    end
    if Mo.GROUND_HEIGHT[track.mode] then
        y = W.terrainY(x, z) + track.height
    end
    if track.mode == "follow" then
        x, y, z = self:chasePosition(seg, t, dt, x, y, z)
    end
    y = math.max(y, W.terrainY(x, z) + (Mo.CLEARANCE[track.mode] or 0.5))
    if q ~= nil then
        return x, y, z, q, Mo.focalAt(track, t - seg.t, math.abs(y - st.y), self.targetFocal)
    end
    local yaw, pitch = M.yawPitchFromDirection(lx - x, ly - y, lz - z)
    local distance = math.sqrt((st.x - x) ^ 2 + (st.y - y) ^ 2 + (st.z - z) ^ 2)
    if dt ~= nil and self.targetFilters[track.target] ~= nil then
        self.targetFilters[track.target].distance = distance
    end
    return x, y, z, M.quatFromYawPitchRoll(yaw, pitch, 0), Mo.focalAt(track, t - seg.t, distance, self.targetFocal)
end

-- Od času playheadu míří kamera v Letu na vozidlo; bez vozidla se vrací k natočení z K-framů.
-- vehicle může být i cíl (uid nebo postava herce).
function CinemaEditorScreen:setFocusHere(vehicle)
    local target = type(vehicle) == "string" and vehicle or (vehicle ~= nil and W.uid(vehicle) or nil)
    self:pushUndo()
    S.addFocusBlock(self.shot, self.playhead, target)
    self.picking = false
    self:markDirty()
    if target ~= nil then
        self:showMessage(string.format(g_i18n:getText("cine_msg_focusSet"), self.playhead, self:targetName(target) or "?"))
    else
        self:showMessage(string.format(g_i18n:getText("cine_msg_focusFree"), self.playhead))
    end
end

-- Název cíle bodu zájmu: vozidlo, postava herce, nebo nil (chybí).
function CinemaEditorScreen:targetName(target)
    local droneVehicle, _, k = W.droneOf(target)
    if droneVehicle ~= nil then
        return string.format(g_i18n:getText("cine_target_drone"), W.name(droneVehicle), k)
    end
    local person = S.personOfTarget(self.shot, target)
    if person ~= nil then
        return person.name or "?"
    end
    local v = target ~= nil and W.find(target) or nil
    return v ~= nil and W.name(v) or nil
end

-- Cíle bodu zájmu ze seznamu řádků osy: vozidla herců (i zapřažená) a postavy. { target, label }.
function CinemaEditorScreen:focusCandidates()
    local list, seen = {}, {}
    for _, a in ipairs(self.shot.actors) do
        if CinemaPerson.isPerson(a) then
            list[#list + 1] = { target = S.personTarget(self.shot, a), label = a.name or "?" }
        end
        for _, entry in ipairs(a.start ~= nil and a.start.entries or {}) do
            local v = W.find(entry.uid)
            if v ~= nil and not seen[entry.uid] then
                seen[entry.uid] = true
                list[#list + 1] = { target = entry.uid, label = W.name(v) }
                for _, d in ipairs(W.drones(v)) do
                    local target = W.droneTarget(v, d.k)
                    list[#list + 1] = { target = target, label = self:targetName(target) }
                end
            end
        end
    end
    return list
end

-- Bod zájmu f míří na vozidlo (nebo cíl target): celý (from nil), nebo jen od času from (úsek se tam rozdělí).
function CinemaEditorScreen:changeFocusTarget(f, from, vehicle, target)
    local shot = self.shot
    local uid = target or W.uid(vehicle)
    self:pushUndo()
    if from ~= nil then
        local index = S.splitFocus(shot, from, uid)
        if index == nil then
            table.remove(self.undoStack)
            self:showMessage(g_i18n:getText("cine_msg_focusSplitNot"))
            return
        end
        self:selSet("focus", shot.focus[index])
    else
        f.target = uid
        S.touch(shot)
    end
    self:markDirty()
    self:showMessage(string.format(g_i18n:getText("cine_msg_focusSet"), from or f.t, self:targetName(uid) or "?"))
end

-- Tažení řádku za název: po odtržení se ukazuje, kam řádek padne.
function CinemaEditorScreen:dragRow(y)
    local drag = self.drag
    if not drag.moved then
        if math.abs(y - drag.y0) < E.DRAG_SLOP_PX * g_pixelSizeScaledY then
            return
        end
        drag.moved = true
    end
    drag.y = y
    drag.drop = self:rowDropAt(drag.key, y)
end

-- Kam padne řádek key puštěný ve výšce y: { before = klíč } (pod ten řádek… tedy před něj odspodu), nebo { after = klíč }
-- nad nejvyšší viditelný; y čáry, kterou to ukazuje.
function CinemaEditorScreen:rowDropAt(key, y)
    local rows = self:rowLayout().rows
    local last
    for _, row in ipairs(rows) do
        if row.key ~= key then
            if y < row.y + row.h * 0.5 then
                return { before = row.key, y = row.y }
            end
            last = row
        end
    end
    return last ~= nil and { after = last.key, y = last.y + last.h } or nil
end

-- Přesune řádek key podle drop (rowDropAt); pořadí se uloží se záběrem.
function CinemaEditorScreen:moveRow(key, drop)
    local order = self:rowOrder()
    local list = {}
    for _, other in ipairs(order) do
        if other ~= key then
            list[#list + 1] = other
        end
    end
    local at = #list + 1
    for k, other in ipairs(list) do
        if other == drop.before then
            at = k
        elseif other == drop.after then
            at = k + 1
        end
    end
    table.insert(list, at, key)
    local same = true
    for k, other in ipairs(order) do
        same = same and list[k] == other
    end
    if same then
        return false
    end
    self:pushUndo()
    self.shot.rowOrder = list
    self:markDirty()
    return true
end

function CinemaEditorScreen:toggleRowsBig()
    self.rowsBig = not self.rowsBig or nil
    self:revealActor(self.activeTarget)
    self:showMessage(g_i18n:getText(self.rowsBig and "cine_msg_rowsBig" or "cine_msg_rowsSmall"))
end

-- Řádek bodů zájmu na ose i bez bodů; body se pak přidávají pravým tlačítkem na řádku nebo přes T.
function CinemaEditorScreen:addFocusRow()
    self:pushUndo()
    self.shot.focusRow = true
    self:markDirty()
    self:showMessage(g_i18n:getText("cine_msg_focusRow"))
end

-- Nový bod zájmu na ukazateli s cílem target (nil = volný pohled).
function CinemaEditorScreen:addFocusTarget(target)
    self:pushUndo()
    local index = S.addFocusBlock(self.shot, self.playhead, target)
    self:selSet("focus", self.shot.focus[index])
    self:markDirty()
    self:showMessage(string.format(g_i18n:getText("cine_msg_focusSet"), self.playhead, self:targetName(target) or g_i18n:getText("cine_focus_free")))
end

-- Rozdělí úsek bodu zájmu na ukazateli; with = false utne míření (dál volný pohled).
function CinemaEditorScreen:splitFocusHere(with)
    self:pushUndo()
    local index = S.splitFocus(self.shot, self.playhead, with)
    if index == nil then
        table.remove(self.undoStack)
        self:showMessage(g_i18n:getText("cine_msg_focusSplitNot"))
        return false
    end
    self:selSet("focus", self.shot.focus[index])
    self:markDirty()
    self:showMessage(g_i18n:getText(with == false and "cine_msg_focusCut" or "cine_msg_split"))
    return true
end

---------------------------------------------------------------------------------------------------
-- pohled shora

function CinemaEditorScreen:enterTopdown()
    local cam = self.cam
    self.picking = false
    self:setClean(false)
    self:needCursor()
    self.topdown = {
        save = { x = cam.x, y = cam.y, z = cam.z, yaw = cam.yaw, pitch = cam.pitch, focal = cam.focal },
        x = cam.x, z = cam.z, yaw = cam.yaw, height = E.TOPDOWN_HEIGHT,
    }
    self.planHeight = self.planHeight or E.PLAN_HEIGHT_DEFAULT
    self:applyTopdownPose()
    self:showMessage(self:getActiveTargetText())
end

function CinemaEditorScreen:exitTopdown()
    local td = self.topdown
    if td == nil then
        return
    end
    self.placingHelper = nil
    self.topdown = nil
    self.drag = nil
    local s = td.save
    self.targetFocal = s.focal
    Cam.setPose(self.cam, s.x, s.y, s.z, M.quatFromYawPitchRoll(s.yaw, s.pitch, 0), s.focal)
end

function CinemaEditorScreen:applyTopdownPose()
    local td = self.topdown
    local y = W.terrainY(td.x, td.z) + td.height
    Cam.setPose(self.cam, td.x, y, td.z, M.quatFromYawPitchRoll(td.yaw, E.TOPDOWN_PITCH, 0), E.TOPDOWN_FOCAL)
end

function CinemaEditorScreen:updateTopdown(dt)
    local td = self.topdown
    local dtSec = dt * 0.001
    local fwd, side, rot = self.moveForward, self.moveSide, self.moveUp
    if E.isCtrl() or self.menu ~= nil then
        fwd, side, rot = 0, 0, 0
    end
    local speed = td.height * 0.9 * E.stepFactor()
    local fx, _, fz = M.forwardFromYawPitch(td.yaw, 0)
    local rx, _, rz = M.rightFromYaw(td.yaw)
    td.x = td.x + (fx * fwd + rx * side) * speed * dtSec
    td.z = td.z + (fz * fwd + rz * side) * speed * dtSec
    td.yaw = td.yaw + M.clamp(rot, -1, 1) * E.TOPDOWN_ROTATE * dtSec
    self:applyTopdownPose()
end

function CinemaEditorScreen:topdownWheel(steps)
    local td = self.topdown
    if E.isCtrl() and E.isShift() then
        self.planHeight = M.clamp(self.planHeight * 1.15 ^ steps, 1, 500)
        self:showMessage(string.format(g_i18n:getText("cine_msg_planHeight"), self.planHeight))
        return
    end
    td.height = M.clamp(td.height * 1.2 ^ (-steps), E.TOPDOWN_HEIGHT_MIN, E.TOPDOWN_HEIGHT_MAX)
end

function CinemaEditorScreen:topdownMouseEvent(posX, posY, isDown, isUp, button)
    if isDown and button == Input.MOUSE_BUTTON_RIGHT then
        if self:isOverPanels(posX, posY) then
            self:openContextMenu(posX, posY)
        else
            local hit = self:topdownHitAt(posX, posY)
            if hit == nil then
                self:onActionKeyAdd()
            elseif hit.kind == "point" then
                self:deleteRoutePoint({ actor = self.activeTarget, index = hit.index })
            elseif hit.kind == "pathHandle" then
                -- táhlo zpět na automatický oblouk (obě strany, ať nezůstane zlom)
                local k = hit.seg.track.keys[hit.index]
                self:pushUndo()
                k.hin, k.hout = nil, nil
                S.touch(self.shot)
                self:markDirty()
            elseif hit.kind == "stand" then
                local _, index = S.segmentById(self.shot, hit.seg.id)
                self:setSelectedBlock(hit.seg)
                self:openTrackMenu(index, posX, posY)
            else
                self:setSelectedKey(hit.seg, hit.index)
                self:onActionKeyDelete()
            end
        end
        return
    end
    if isDown and button == Input.MOUSE_BUTTON_MIDDLE then
        self:onPanelsMiddle(posX, posY)
        return
    end
    if isUp and button == Input.MOUSE_BUTTON_MIDDLE then
        self.drag = nil
        return
    end
    if isDown and button == Input.MOUSE_BUTTON_LEFT then
        if self.picking then
            self:pickAt(posX, posY)
        elseif self:isOverPanels(posX, posY) then
            self:onPanelsDown(posX, posY)
        else
            self:topdownClick(posX, posY)
        end
        return
    end
    if isUp and button == Input.MOUSE_BUTTON_LEFT then
        local drag = self.drag
        if drag ~= nil and (drag.kind == "clip" or drag.kind == "marquee" or drag.kind == "row") then
            self:finishDrag()
        end
        self.drag = nil
        -- klik na bod bez tažení otevře jeho menu
        if drag ~= nil and not drag.moved and not drag.inserted then
            if drag.kind == "point" or drag.kind == "startPoint" then
                self:openPointMenu(self.activeTarget, drag.index, posX, posY)
            elseif drag.kind == "keyPos" then
                self:openKeyMenu(drag.seg, drag.index, posX, posY)
            end
        end
        return
    end
    if self.drag ~= nil then
        self:onPanelsDrag(posX, posY)
    end
end

-- Bod trasy vybraného vozidla, nebo K-frame Letu těsně pod kurzorem: klik ho chytí k posunu místo založení nového.
function CinemaEditorScreen:topdownHitAt(x, y)
    local cam = self.cam
    local best, bestDist = nil, E.POINT_GRAB_PX * g_pixelSizeScaledX
    local function consider(kind, index, wx, wy, wz, seg, side)
        local sx, sy = Cam.worldToScreen(cam, wx, wy, wz)
        if sx ~= nil then
            local dist = math.sqrt((sx - x) ^ 2 + ((sy - y) / g_screenAspectRatio) ^ 2)
            if dist <= bestDist then
                best, bestDist = { kind = kind, index = index, seg = seg, side = side }, dist
            end
        end
    end
    if not self:isRouteShown(self.activeTarget) then
        return nil
    end
    if self.activeTarget == 0 then
        for _, hnd in ipairs(self:pathHandleTips()) do
            consider("pathHandle", hnd.index, hnd.x, hnd.y, hnd.z, hnd.seg, hnd.side)
        end
        if best ~= nil then
            return best
        end
    end
    if self.activeTarget > 0 then
        local actor = self.shot.actors[self.activeTarget]
        -- konec šipky natočení postavy má přednost před bodem (bod je blízko); šipku mají jen body se zadaným natočením
        if Pe.isPerson(actor) then
            for i, p in ipairs(actor.points) do
                if p[6] ~= nil then
                    local tx, ty, tz = self:faceTip(actor, i)
                    consider("face", i, tx, ty, tz)
                end
            end
            if best ~= nil then
                return best
            end
        end
        for i, p in ipairs(actor ~= nil and actor.points or {}) do
            consider("point", i, p[1], self:routePointY(actor, p) + 0.3, p[2])
        end
    else
        -- koncový bod čárky směru pohledu K-framu: tažením se kamera natáčí
        local keys = S.allKeys(self.shot)
        for _, e in ipairs(keys) do
            if e.seg.track.mode == S.FLIGHT then
                local tx, ty, tz = self:keyAimTip(e.key)
                consider("aim", e.index, tx, ty, tz, e.seg)
            end
        end
        if best ~= nil then
            return best
        end
        for _, e in ipairs(keys) do
            consider("key", e.index, e.key.x, e.key.y, e.key.z, e.seg)
        end
        for _, seg in ipairs(self.shot.segments) do
            local track = seg.track
            if Mo.STANDS[track.mode] and track.camX ~= nil then
                consider("stand", nil, track.camX, track.camY, track.camZ, seg)
            end
        end
    end
    return best
end

-- Konce táhel dráhy vybraného K-framu Letu ve světě: { seg, index, side, x, y, z }; nulová táhla (roh) se nekreslí.
function CinemaEditorScreen:pathHandleTips()
    local seg, index, k = self:selectedKey()
    if seg == nil or k == nil or seg.track.mode ~= S.FLIGHT or #seg.track.keys < 2 then
        return {}
    end
    local hin, hout = S.keyHandles(self.shot, seg.track, index)
    local out = {}
    for side, h in pairs({ ["in"] = hin, out = hout }) do
        if h[1] * h[1] + h[2] * h[2] + h[3] * h[3] > 1e-4 then
            out[#out + 1] = { seg = seg, index = index, side = side, x = k.x + h[1], y = k.y + h[2], z = k.z + h[3] }
        end
    end
    return out
end

E.FACE_SNAP = 15 -- °; natočení postavy tažením se přichytává po tolika stupních (Shift volně)

-- Konec šipky natočení postavy v bodě k (shora): x, y, z. Délka roste s výškou kamery, ať je šipka pořád k chycení.
function CinemaEditorScreen:faceTip(actor, k)
    local p = actor.points[k]
    local yaw = Pe.pointFacing(actor, k)
    local y = self:routePointY(actor, p) + 0.3
    local len = math.max(2, (self.cam.y - y) * 0.05)
    return p[1] + math.sin(yaw) * len, y, p[2] + math.cos(yaw) * len
end

-- Tažení konce šipky: postava se v bodě dívá ke kurzoru (azimut po E.FACE_SNAP stupních, se Shiftem volně).
function CinemaEditorScreen:topdownFace(x, y)
    local drag = self.drag
    local actor = self.shot.actors[self.activeTarget]
    local p = actor ~= nil and actor.points[drag.index] or nil
    local px, _, pz = W.pickTerrain(self.cam, x, y)
    if p == nil or px == nil then
        return
    end
    local dx, dz = px - p[1], pz - p[2]
    if dx * dx + dz * dz < 0.25 then
        return
    end
    local az = Pe.azimuth(math.atan2(dx, dz))
    if not E.isShift() then
        az = (math.floor(az / E.FACE_SNAP + 0.5) * E.FACE_SNAP) % 360
    end
    if not drag.moved then
        self:pushUndo()
        drag.moved = true
    end
    p[6] = Pe.yawOfAzimuth(az)
    self.actorRt = {}
    self:markDirty()
    self:showMessage(string.format(g_i18n:getText("cine_msg_faceAzimuth"), drag.index, az))
end

-- Kam míří čárka směru pohledu K-framu (stejná délka, jakou kreslí drawPath).
function CinemaEditorScreen:keyAimTip(k)
    local yaw, pitch = M.quatToYawPitchRoll(k.q)
    local dx, dy, dz = M.forwardFromYawPitch(yaw, pitch)
    local cam = self.cam
    local dist = math.sqrt((k.x - cam.x) ^ 2 + (k.y - cam.y) ^ 2 + (k.z - cam.z) ^ 2)
    local len = math.max(1.5, dist * 0.08)
    return k.x + dx * len, k.y + dy * len, k.z + dz * len
end

function CinemaEditorScreen:topdownGrab(hit, x, y)
    local td = self.topdown
    if hit.kind == "pathHandle" then
        -- táhlo dráhy: tažení po terénu ohne dráhu, výška táhla nad K-framem zůstane
        local k = hit.seg.track.keys[hit.index]
        local hin, hout = S.keyHandles(self.shot, hit.seg.track, hit.index)
        local h = hit.side == "in" and hin or hout
        local ox, oz = self:grabOffset(x, y, k.x + h[1], k.z + h[3])
        self.drag = { kind = "pathHandle", seg = hit.seg, index = hit.index, side = hit.side, dy = h[2], x = x, y = y, ox = ox, oz = oz }
    elseif hit.kind == "face" then
        td.point = { actor = self.activeTarget, index = hit.index }
        self.drag = { kind = "face", index = hit.index, x = x, y = y }
    elseif hit.kind == "aim" then
        self:setSelectedKey(hit.seg, hit.index)
        self.playhead = hit.seg.t + hit.seg.track.keys[hit.index].t
        self.drag = { kind = "aim", seg = hit.seg, index = hit.index, handle = true }
    elseif hit.kind == "point" then
        td.point = { actor = self.activeTarget, index = hit.index }
        -- první bod je poloha vozidla: dá se jen vybrat, posouvá se přes Zapamatovat start; bod výstupu z vozidla drží
        -- vozidlo, taky se jen vybere (s ruční polohou z menu bodu se táhne)
        local p = self.shot.actors[self.activeTarget].points[hit.index]
        local ox, oz = self:grabOffset(x, y, p[1], p[2])
        local fixed = hit.index == 1 or (p[7] and not p[8])
        self.drag = { kind = fixed and "startPoint" or "point", index = hit.index, x = x, y = y, ox = ox, oz = oz }
    elseif hit.kind == "stand" then
        -- stanoviště stojící kamery (statická, sledování z bodu): tažením se přesune po terénu ve stejné výšce nad ním
        local track = hit.seg.track
        self:setSelectedBlock(hit.seg)
        local ox, oz = self:grabOffset(x, y, track.camX, track.camZ)
        self.drag = { kind = "standPos", seg = hit.seg, above = track.camY - W.terrainY(track.camX, track.camZ), x = x, y = y, ox = ox, oz = oz }
    else
        local k = hit.seg.track.keys[hit.index]
        self:setSelectedKey(hit.seg, hit.index)
        self.playhead = hit.seg.t + k.t
        local ox, oz = self:grabOffset(x, y, k.x, k.z)
        self.drag = { kind = "keyPos", seg = hit.seg, index = hit.index, above = k.y - W.terrainY(k.x, k.z), x = x, y = y, ox = ox, oz = oz }
    end
end

-- Rozdíl mezi uchopeným bodem a místem na terénu pod kurzorem: tažení pak drží bod tam, kde byl, a neskáče do strany.
function CinemaEditorScreen:grabOffset(x, y, wx, wz)
    local px, _, pz = W.pickTerrain(self.cam, x, y)
    if px == nil then
        return 0, 0
    end
    return wx - px, wz - pz
end

-- Tažení bodu po terénu; krok zpět se uloží až při prvním pohybu, prosté kliknutí nic nemění.
function CinemaEditorScreen:topdownMove(x, y)
    local drag = self.drag
    if not drag.moved and math.sqrt((x - drag.x) ^ 2 + ((y - drag.y) / g_screenAspectRatio) ^ 2) < E.POINT_SLOP_PX * g_pixelSizeScaledX then
        return
    end
    local px, _, pz = W.pickTerrain(self.cam, x, y)
    if px == nil then
        return
    end
    px, pz = px + (drag.ox or 0), pz + (drag.oz or 0)
    if not drag.moved then
        self:pushUndo()
        drag.moved = true
    end
    if drag.kind == "point" then
        local actor = self.shot.actors[self.activeTarget]
        if actor == nil or actor.points[drag.index] == nil then
            return
        end
        local p = actor.points[drag.index]
        p[1], p[2] = px, pz
        self.actorRt = {}
    elseif drag.kind == "standPos" then
        local track = drag.seg.track
        track.camX, track.camZ = px, pz
        track.camY = W.terrainY(px, pz) + drag.above
        S.touch(self.shot)
    elseif drag.kind == "pathHandle" then
        -- Ctrl táhla rozpojí (vznikne zlom), jinak druhé táhlo míří opačně a oblouk zůstane hladký
        local k = drag.seg.track.keys[drag.index]
        if k == nil then
            return
        end
        S.setKeyHandle(self.shot, drag.seg.track, drag.index, drag.side, { px - k.x, drag.dy, pz - k.z }, not E.isCtrl())
    else
        local k = drag.seg.track.keys[drag.index]
        if k == nil then
            return
        end
        k.x, k.z = px, pz
        k.y = W.terrainY(px, pz) + drag.above
        S.touch(self.shot)
    end
    self:markDirty()
end

-- K / pravé tlačítko shora: vloží bod do dráhy v čase playheadu, tedy tam, kde se právě ukazuje tečka kamery
-- nebo aktivního vozidla. Dráha se tím nezmění, bod se pak dá chytit a posunout nebo otevřít jeho menu.
function CinemaEditorScreen:insertAtPlayhead()
    if self.activeTarget > 0 then
        self:insertRoutePoint()
        return
    end
    local seg = S.segmentAt(self.shot, self.playhead)
    if seg == nil then
        self:showMessage(g_i18n:getText("cine_msg_noBlockAtPlayhead"))
        return
    end
    if not S.hasKeys(seg.track) then
        self:addModeMark(seg)
        return
    end
    self:insertCamKeyAt(self.playhead)
end

-- Části trasy herce: { plan, offset (index bodu před částí), start (s od začátku záběru) }; vozidlo má jednu, postava
-- jednu na každou část, která se jde.
function CinemaEditorScreen:routeParts(actor)
    local parts = {}
    if CinemaPerson.isPerson(actor) then
        for _, leg in ipairs(CinemaPerson.legs(actor)) do
            local plan = leg.start ~= nil and R.plan(leg.actor) or nil
            if plan ~= nil then
                parts[#parts + 1] = { plan = plan, offset = leg.from - 1, start = leg.start }
            end
        end
    else
        local plan = R.plan(actor)
        if plan ~= nil then
            parts[1] = { plan = plan, offset = 0, start = actor.delay or 0 }
        end
    end
    return parts
end

-- Nový bod trasy herce i (výchozí aktivní) v místě, kde je v čase tm (výchozí ukazatel); jízda se tím nezmění.
function CinemaEditorScreen:insertRoutePoint(i, tm)
    i, tm = i or self.activeTarget, tm or self.playhead
    local actor = self.shot.actors[i]
    local part = nil
    for _, p in ipairs(actor ~= nil and self:routeParts(actor) or {}) do
        if part == nil or (tm >= p.start - 1e-6 and (p.start > part.start or tm < part.start)) then
            part = p
        end
    end
    if part == nil then
        return
    end
    local plan = part.plan
    local x, z, s = R.positionAtTime(plan, tm - part.start)
    local after = R.insertIndex(plan.route, s, E.POINT_MIN_GAP)
    if after == nil then
        self:showMessage(g_i18n:getText("cine_msg_pointHere"))
        return
    end
    self:pushUndo()
    -- rychlost nového bodu = rychlost trasy v tom místě, takže se jízda nezmění
    local index = part.offset + after + 1
    local p = { x, z, R.cruiseAt(plan.route, s), nil, actor.points[index][5] }
    if CinemaPerson.isPerson(actor) then
        -- chůze úseku zůstane chůzí (rychlost bodu = chůze předchozího bodu), na patře bod drží výšku podlahy
        p[3] = actor.points[index - 1] ~= nil and actor.points[index - 1][3] or nil
        local _, _, _, y = CinemaPerson.poseAt(actor, tm)
        if y ~= nil and y > W.terrainY(x, z) + CinemaPerson.FLOOR_MIN then
            p[9] = y
        end
    end
    table.insert(actor.points, index, p)
    if self.topdown ~= nil then
        self.topdown.point = { actor = i, index = index }
    end
    self.actorRt = {}
    self:markDirty()
end

function CinemaEditorScreen:deleteRoutePoint(ref)
    local actor = self.shot.actors[self.activeTarget]
    if actor == nil or ref == nil or ref.actor ~= self.activeTarget or actor.points[ref.index] == nil then
        self:showMessage(g_i18n:getText("cine_msg_pickPoint"))
        return
    end
    if ref.index == 1 then
        self:showMessage(g_i18n:getText("cine_msg_startPoint"))
        return
    end
    -- bod výstupu z vozidla patří k výstupu na ose; bez něj by se další část trasy napojila na nástup. Když výstup na ose už
    -- není, smaže se celá jeho část trasy.
    local orphan = CinemaPerson.isOrphanExit(actor, ref.index)
    if orphan == false then
        self:showMessage(g_i18n:getText("cine_msg_exitPoint"))
        return
    end
    self:pushUndo()
    if orphan then
        CinemaPerson.removeOrphanLeg(actor, ref.index)
    else
        table.remove(actor.points, ref.index)
    end
    if self.topdown ~= nil then
        self.topdown.point = nil
    end
    self.actorRt = {}
    self:markDirty()
end

-- Výška bodu trasy herce: postava podlaha bodu, jinak terén.
function CinemaEditorScreen:routePointY(actor, p)
    return CinemaPerson.isPerson(actor) and CinemaPerson.pointY(p) or W.terrainY(p[1], p[2])
end

-- Místo na čáře trasy aktivního vozidla pod kurzorem: vzdálenost po trase a část trasy (routeParts), nebo nil.
function CinemaEditorScreen:topdownRouteAt(x, y)
    local actor = self.activeTarget > 0 and self.shot.actors[self.activeTarget] or nil
    if actor == nil or not self:isRouteShown(self.activeTarget) then
        return nil
    end
    local bestS, bestPart, bestDist = nil, nil, E.ROUTE_GRAB_PX * g_pixelSizeScaledX
    for _, part in ipairs(self:routeParts(actor)) do
        local route = part.plan.route
        for i = 1, #route.xs do
            local sx, sy = Cam.worldToScreen(self.cam, route.xs[i], W.terrainY(route.xs[i], route.zs[i]) + 0.3, route.zs[i])
            if sx ~= nil then
                local dist = math.sqrt((sx - x) ^ 2 + ((sy - y) / g_screenAspectRatio) ^ 2)
                if dist <= bestDist then
                    bestS, bestPart, bestDist = route.ss[i], part, dist
                end
            end
        end
    end
    return bestS, bestPart
end

-- Klik na čáru trasy vloží bod přesně na ni (mezi sousední body); hned se dá chytit a posunout.
function CinemaEditorScreen:insertRoutePointAtLine(s, part, x, y)
    local route = part.plan.route
    local after = R.insertIndex(route, s, E.POINT_MIN_GAP)
    if after == nil then
        return
    end
    local actor = self.shot.actors[self.activeTarget]
    local px, pz = R.pointAt(route, s)
    local index = part.offset + after + 1
    self:pushUndo()
    table.insert(actor.points, index, { px, pz, R.cruiseAt(route, s), nil, actor.points[index][5] })
    self.topdown.point = { actor = self.activeTarget, index = index }
    self.actorRt = {}
    self:markDirty()
    self.drag = { kind = "point", index = index, x = x, y = y, inserted = true }
end

-- Čas nejbližšího místa dráhy Letu pod kurzorem; nil mimo čáru.
function CinemaEditorScreen:topdownCamLineAt(x, y)
    local shot = self.shot
    if not self:isRouteShown(0) then
        return nil
    end
    local bestT, bestDist = nil, E.ROUTE_GRAB_PX * g_pixelSizeScaledX
    for _, seg in ipairs(shot.segments) do
        local keys = S.hasKeys(seg.track) and seg.track.keys or {}
        if #keys >= 2 then
            local t0, t1 = keys[1].t, keys[#keys].t
            local steps = math.min(200, math.max(30, math.floor((t1 - t0) * 6)))
            for k = 0, steps do
                local rel = t0 + (t1 - t0) * k / steps
                local px, py, pz = S.flightEvaluate(shot, seg.track, rel)
                local sx, sy = Cam.worldToScreen(self.cam, px, py, pz)
                if sx ~= nil then
                    local dist = math.sqrt((sx - x) ^ 2 + ((sy - y) / g_screenAspectRatio) ^ 2)
                    if dist <= bestDist then
                        bestT, bestDist = seg.t + rel, dist
                    end
                end
            end
        end
    end
    return bestT
end

-- K-frame na dráze Letu v čase t (zaokrouhleno na desetiny) s pózou, kterou tam kamera má, takže se pohyb nezmění;
-- je-li tam už K-frame, jen se vybere.
function CinemaEditorScreen:insertCamKeyAt(t)
    local shot = self.shot
    local seg = S.segmentAt(shot, t)
    if seg == nil or not S.hasKeys(seg.track) then
        return
    end
    local rel = M.clamp(math.floor((t - seg.t) * 10 + 0.5) / 10, 0, seg.track.duration)
    local existing = S.flightKeyAt(seg.track, rel)
    if existing ~= nil then
        self:setSelectedKey(seg, existing)
        self.playhead = seg.t + seg.track.keys[existing].t
        return
    end
    local x, y, z, q, focal = S.flightEvaluate(shot, seg.track, rel)
    local key = S.newKey(rel, x, y, z, q, focal)
    key.speed = S.flightSpeedAt(shot, seg.track, rel)
    self:pushUndo()
    self:setSelectedKey(seg, S.flightSetKey(shot, seg.track, key))
    self.playhead = seg.t + rel
    self:markDirty()
    self:showMessage(g_i18n:getText("cine_msg_keyAdded"))
end

-- Bod trasy vybraného herce v místě px, pz (shora i z pohledu kamery). Právě přidaný pomocník: první bod určí, kde stojí.
-- py = výška plochy, na kterou bod padl (podlaha, schod); u postavy si ji bod pamatuje, když je nad terénem.
function CinemaEditorScreen:addRoutePointAt(px, pz, py)
    local actor = self.shot.actors[self.activeTarget]
    if actor == nil then
        return
    end
    self:pushUndo()
    local floor = nil
    if py ~= nil and CinemaPerson.isPerson(actor) and py > W.terrainY(px, pz) + CinemaPerson.FLOOR_MIN then
        floor = py
    end
    if actor == self.placingHelper and #actor.points == 1 then
        actor.points[1] = { px, pz }
        actor.points[1][9] = floor
        local ps = actor.start.person
        ps.x, ps.y, ps.z = px, floor or W.terrainY(px, pz), pz
        self.placingHelper = nil
        self.actorRt = {}
        self:markDirty()
        self:showMessage(g_i18n:getText("cine_msg_helperPlaced"))
        return
    end
    table.insert(actor.points, { px, pz })
    actor.points[#actor.points][9] = floor
    if self.topdown ~= nil then
        self.topdown.point = { actor = self.activeTarget, index = #actor.points }
    end
    self.actorRt = {}
    self:markDirty()
end

-- Pravé tlačítko ve scéně z pohledu kamery s vybraným hercem: bod trasy tam, kam míří kurzor (při rozhlížení střed
-- obrazu), na podlahu i v budově. true, když se bod přidal.
function CinemaEditorScreen:addRoutePointFromView(x, y)
    if self.activeTarget <= 0 or self.shot.actors[self.activeTarget] == nil then
        return false
    end
    if self.freeLook then
        x, y = 0.5, 0.5
    end
    local px, py, pz = W.pickGround(self.cam, x, y)
    if px == nil then
        return false
    end
    self:addRoutePointAt(px, pz, py)
    self:showMessage(string.format(g_i18n:getText("cine_msg_routePointAdded"), #self.shot.actors[self.activeTarget].points))
    return true
end

function CinemaEditorScreen:topdownClick(x, y)
    local hit = self:topdownHitAt(x, y)
    if hit ~= nil then
        self:topdownGrab(hit, x, y)
        return
    end
    if self.topdown ~= nil then
        self.topdown.point = nil
    end
    local lineS, part = self:topdownRouteAt(x, y)
    if lineS ~= nil then
        self:insertRoutePointAtLine(lineS, part, x, y)
        return
    end
    if self.activeTarget == 0 then
        local t = self:topdownCamLineAt(x, y)
        if t ~= nil then
            self:insertCamKeyAt(t)
            return
        end
    end
    local px, _, pz = W.pickTerrain(self.cam, x, y)
    if px == nil then
        return
    end
    if self.activeTarget > 0 then
        self:addRoutePointAt(px, pz)
        return
    end
    -- nový K-frame za koncem záběru: čas podle vzdálenosti od konce posledního bloku a rychlosti letu; prodlouží poslední Let
    local shot = self.shot
    local py = W.terrainY(px, pz) + self.planHeight
    local t, yaw = 0, self.topdown.yaw
    local last = shot.segments[#shot.segments]
    if last ~= nil then
        local lx, ly, lz = self:blockEndPose(last, nil)
        t = S.segmentEnd(last) + S.MIN_SEGMENT
        if lx ~= nil then
            local dx, dy, dz = px - lx, py - ly, pz - lz
            t = S.segmentEnd(last) + math.max(1, math.sqrt(dx * dx + dy * dy + dz * dz) / self.flySpeed)
            if dx * dx + dz * dz > 0.01 then
                yaw = math.atan2(dx, dz)
            end
        end
    end
    self:pushUndo()
    local key = S.newKey(0, px, py, pz, M.quatFromYawPitchRoll(yaw, E.PLAN_PITCH, 0), self.topdown.save.focal)
    local seg, index = self:keyInGap(t, key)
    if seg == nil then
        table.remove(self.undoStack)
        return
    end
    self:setSelectedKey(seg, index)
    self.playhead = t
    self.drag = { kind = "aim", seg = seg, index = index }
    self:markDirty()
end

-- Tažením od nově položeného bodu se míří: kamera bude hledět na místo terénu pod kurzorem.
function CinemaEditorScreen:topdownAim(x, y)
    local k = self.drag.seg.track.keys[self.drag.index]
    if k == nil then
        return
    end
    local px, py, pz = W.pickTerrain(self.cam, x, y)
    if px == nil then
        return
    end
    local dx, dz = px - k.x, pz - k.z
    if dx * dx + dz * dz < 4 then
        return
    end
    local yaw, pitch = M.yawPitchFromDirection(dx, py - k.y, dz)
    k.q = M.quatFromYawPitchRoll(yaw, pitch, 0)
    S.touch(self.shot)
    self:markDirty()
end

function CinemaEditorScreen:getActiveTargetText()
    if self.activeTarget > 0 then
        local actor = self.shot.actors[self.activeTarget]
        if actor ~= nil then
            return string.format(g_i18n:getText("cine_target_actor"), actor.name or "?")
        end
    end
    return g_i18n:getText("cine_target_camera")
end

---------------------------------------------------------------------------------------------------
-- herci

-- Číslo herce, jehož souprava začíná tímto vozidlem, nebo nil.
function CinemaEditorScreen:findActor(vehicle)
    local uid = W.uid(W.rootOf(vehicle))
    for i, a in ipairs(self.shot.actors) do
        if a.start ~= nil and a.start.entries[1] ~= nil and a.start.entries[1].uid == uid then
            return i
        end
    end
    return nil
end

-- Nahrávka ruční jízdy (CinemaRecorder) se vloží do záběru jako nové vozidlo; jízda začíná na playheadu.
function CinemaEditorScreen:importRecording()
    local rec = CinemaRecorder.pending
    if rec == nil or self.shot == nil then
        return
    end
    CinemaRecorder.pending = nil
    self:pushUndo()
    local actor = { name = rec.name, speed = E.ACTOR_SPEED_DEFAULT, delay = self.playhead, points = rec.points, start = rec.start,
        curves = rec.curves, actions = {} }
    for _, action in ipairs(rec.actions) do
        A.add(actor, action)
    end
    local root = rec.start.entries[1] ~= nil and W.find(rec.start.entries[1].uid) or nil
    local helper = W.hasDriverSeat(root) and W.helperList()[1] or nil
    if helper ~= nil then
        actor.driver = helper.name
    end
    table.insert(self.shot.actors, actor)
    self:syncDrivers()
    self.activeTarget = #self.shot.actors
    self.actorRt = {}
    self:markDirty()
    self:showMessage(string.format(g_i18n:getText("cine_msg_recImported"), actor.name, rec.duration, #actor.points, #actor.actions))
end

-- Herec z vozidla (celé soupravy): start a stavy podle toho, jak stojí teď, vozidlo s místem pro řidiče dostane pomocníka.
function CinemaEditorScreen.newVehicleActor(vehicle)
    local root = W.rootOf(vehicle)
    local x, _, z = getWorldTranslation(root.rootNode)
    local actor = { name = W.name(root), speed = E.ACTOR_SPEED_DEFAULT, delay = 0, points = { { x, z } }, start = W.captureStart(root) }
    local helper = W.hasDriverSeat(root) and W.helperList()[1] or nil
    if helper ~= nil then
        actor.driver = helper.name
    end
    return actor
end

function CinemaEditorScreen:addActor(vehicle)
    local root = W.rootOf(vehicle)
    local existing = self:findActor(root)
    if existing ~= nil then
        self.activeTarget = existing
        self.picking = false
        if self.topdown == nil then
            self:enterTopdown()
        end
        self:showMessage(self:getActiveTargetText())
        return
    end
    self:pushUndo()
    local actor = E.newVehicleActor(vehicle)
    table.insert(self.shot.actors, actor)
    self:syncDrivers()
    self.activeTarget = #self.shot.actors
    self.picking = false
    self.actorRt = {}
    self:markDirty()
    if self.topdown == nil then
        self:enterTopdown()
    end
    self:showMessage(string.format(g_i18n:getText(root.spec_drivable ~= nil and "cine_msg_actorAdded" or "cine_msg_actorAddedStatic"), actor.name))
end

-- Postava: hráč sám jako herec (jedna na záběr); start je tam, kde teď stojí.
function CinemaEditorScreen:addPersonActor()
    for i, a in ipairs(self.shot.actors) do
        if a.person == Pe.PLAYER then
            self.activeTarget = i
            if self.topdown == nil then
                self:enterTopdown()
            end
            self:showMessage(self:getActiveTargetText())
            return
        end
    end
    self:pushUndo()
    local actor = Pe.newActor(g_i18n:getText("cine_person_me"))
    table.insert(self.shot.actors, actor)
    self.activeTarget = #self.shot.actors
    self.actorRt = {}
    self:markDirty()
    if self.topdown == nil then
        self:enterTopdown()
    end
    self:showMessage(g_i18n:getText("cine_msg_personAdded"))
end

-- Pomocník jako postava: stojí na terénu uprostřed obrazu (jinak u hráče), čelem ke kameře.
function CinemaEditorScreen:addHelperActor(helperName)
    local helper = nil
    for _, choice in ipairs(Pe.helperChoices()) do
        if choice.name == helperName then
            helper = choice
        end
    end
    if helper == nil then
        return
    end
    local x, _, z = W.pickTerrain(self.cam, 0.5, 0.5)
    if x == nil then
        x, _, z = Pe.playerPos()
    end
    local cx, _, cz = getWorldTranslation(self.cam.node)
    self:pushUndo()
    local actor = Pe.newHelperActor(helper, x, z, math.atan2(cx - x, cz - z))
    table.insert(self.shot.actors, actor)
    self.activeTarget = #self.shot.actors
    self:revealActor(self.activeTarget)
    self.actorRt = {}
    self:markDirty()
    if self.topdown == nil then
        self:enterTopdown()
    end
    self.placingHelper = actor
    self:showMessage(string.format(g_i18n:getText("cine_msg_helperAdded"), actor.name))
end

-- Vozidlo do záběru se vybere klikem ve scéně.
function CinemaEditorScreen:pickActorVehicle()
    self.pendingAction = { actor = true }
    self.picking = true
    self:needCursor()
    self:showMessage(g_i18n:getText("cine_msg_pickActor"))
end

-- Nabídka tlačítka + Herec nad řádky osy.
function CinemaEditorScreen:openAddActorMenu(x, y)
    local t = function(key) return g_i18n:getText(key) end
    local helpers = {}
    for _, helper in ipairs(Pe.helperChoices()) do
        helpers[#helpers + 1] = { text = helper.title, action = function(s) s:addHelperActor(helper.name) end }
    end
    local items = {
        { text = t("cine_actor_addVehicle"), action = function(s) s:pickActorVehicle() end },
        { text = t("cine_actor_addMe"), action = function(s) s:addPersonActor() end },
        { text = t("cine_actor_addFocusRow"), action = function(s) s:addFocusRow() end, disabled = self:hasFocusRow() },
        { text = t("cine_actor_addProps"), submenu = true, action = function(s) s:openMenu(t("cine_actor_addProps"), s:propAddItems(), x, y) end },
        { text = t("cine_actor_addObject"), action = function(s) s:pickObject() end },
    }
    if #helpers > 0 then
        items[#items + 1] = { text = t("cine_actor_addHelper"), submenu = true,
            action = function(s) s:openMenu(t("cine_actor_addHelper"), helpers, x, y) end }
    end
    self:openMenu(t("cine_actor_addTitle"), items, x, y)
end

-- Název řádku herce zadaný v herním dialogu; prázdný název vrátí výchozí (vozidlo, pomocník).
function CinemaEditorScreen:openRenameActor(i)
    local actor = self.shot.actors[i]
    if actor == nil then
        return
    end
    TextInputDialog.show(function(s, text, clickOk)
        if not clickOk or s.shot.actors[i] ~= actor then
            return
        end
        text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if text == "" then
            text = s:defaultActorName(actor)
        end
        if text ~= actor.name then
            s:pushUndo()
            actor.name = text
            s:markDirty()
        end
    end, self, actor.name or "", g_i18n:getText("cine_rename_prompt"), g_i18n:getText("cine_menu_rename"), 40,
        g_i18n:getText("button_ok"))
end

function CinemaEditorScreen:defaultActorName(actor)
    if Pe.isHelper(actor) then
        return Pe.helperTitle(actor.helper)
    elseif actor.person == Pe.PLAYER then
        return g_i18n:getText("cine_person_me")
    end
    local first = actor.start ~= nil and actor.start.entries[1] or nil
    local v = first ~= nil and W.find(first.uid) or nil
    return v ~= nil and W.name(v) or (actor.name or "?")
end

function CinemaEditorScreen:removeActor(i)
    self:pushUndo()
    table.remove(self.shot.actors, i)
    self:syncDrivers()
    -- smazaný aktivní → zpět na kameru, ne na trasu jiného vozidla
    if self.activeTarget == i then
        self.activeTarget = 0
    elseif self.activeTarget > i then
        self.activeTarget = self.activeTarget - 1
    end
    self.actorRt = {}
    self:markDirty()
end

function CinemaEditorScreen:actorEnd(i)
    local a = self.shot.actors[i]
    if Pe.isPerson(a) then
        return math.max(Pe.walkEnd(a), (a.delay or 0) + A.lastTime(a))
    end
    local plan = R.plan(a)
    return (a.delay or 0) + math.max(plan ~= nil and plan.total or 0, A.lastTime(a))
end

-- Co brání přehrání kvůli vozidlům herců: v soupravě sedí hráč (přehrání by vozidlo vracelo na start i s ním) nebo
-- vozidlo s trasou nejde řídit. Vrací klíč hlášky, jméno herce a případně klíč důvodu; nil, když nic nebrání.
-- Hráč, který je sám hercem, ve vozidle sedí podle osy (akce nástupu), takže nebrání.
function CinemaEditorScreen:getActorBlocker()
    local playerActor = self:hasPersonActor()
    local player = g_localPlayer
    local current = not playerActor and player ~= nil and player.getCurrentVehicle ~= nil and player:getCurrentVehicle() or nil
    local currentRoot = current ~= nil and W.rootOf(current) or nil
    for _, a in ipairs(self.shot.actors) do
        local first = a.start ~= nil and a.start.entries[1] or nil
        local v = first ~= nil and W.find(first.uid) or nil
        if v ~= nil then
            if currentRoot ~= nil and W.rootOf(v) == currentRoot then
                return "cine_msg_playOccupied", a.name or "?"
            end
            if R.plan(a) ~= nil then
                local ok, why = W.canDrive(v, playerActor)
                if not ok then
                    return "cine_msg_playBlocked", a.name or "?", REASONS[why] or "cine_msg_actorMissing"
                end
            end
        end
    end
    return nil
end

function CinemaEditorScreen:resetActors(showMessage)
    self:stopActors()
    self:clearActorStates()
    CinemaEnvironment.restart(self.shot.env, self.envStart, self.envSaved)
    local failed = self:resetProps()
    for _, a in ipairs(self.shot.actors) do
        local ok, why
        if Pe.isPerson(a) then
            ok, why = Pe.place(a, 0, self.cam)
        else
            ok, why = W.resetStart(a.start)
        end
        if not ok then
            failed = why
        else
            A.applyStates(a)
            A.applyAt(a, 0)
        end
    end
    for _, obj in ipairs(self:objects()) do
        A.applyAt(CinemaObjects.actor(obj), 0)
    end
    if failed ~= nil then
        self:showMessage(g_i18n:getText(REASONS[failed] or "cine_msg_actorMissing"))
    elseif showMessage and #self.shot.actors > 0 then
        self:showMessage(g_i18n:getText("cine_msg_actorsReset"))
    end
end

E.FOLLOW_INTERVAL = 200 -- ms; jak často vozidla při posunu ukazatele dojedou za ním

-- Přepínač „Vozidla s osou“: mimo přehrávání stojí vozidla herců tam, kde je plán chce mít v čase ukazatele (jako B,
-- jen bez předmětů a stavů), aby šlo osou listovat a vidět je. Postavy pomocníků jdou s osou vždy.
function CinemaEditorScreen:toggleVehiclesFollow()
    self.vehiclesFollow = not self.vehiclesFollow or nil
    self.followAt = nil
    self:showMessage(g_i18n:getText(self.vehiclesFollow and "cine_msg_followOn" or "cine_msg_followOff"))
end

function CinemaEditorScreen:syncVehiclesToPlayhead()
    if not self.vehiclesFollow or self.playing or self.shot == nil or self.followAt == self.playhead
        or g_time < (self.followNext or 0) then
        return
    end
    local t = self.playhead
    self.followAt, self.followNext = t, g_time + E.FOLLOW_INTERVAL
    for _, a in ipairs(self.shot.actors) do
        if not Pe.isPerson(a) and a.start ~= nil then
            local placement = nil
            if R.plan(a) ~= nil and t > (a.delay or 0) then
                placement = function(entry)
                    local x, y, z, ry = self:entryPoseAt(a, entry, t)
                    return x, y, z, 0, ry or entry.ry, 0
                end
            end
            W.resetStart(a.start, placement)
        end
    end
end

-- Vrátí vozidla herců tam, kde mají podle plánu trasy být v čase t (s od začátku záběru); herec bez trasy nebo před svým
-- startem stojí na startu.
function CinemaEditorScreen:resetActorsAt(t, showMessage)
    self:stopActors()
    self:clearActorStates()
    local failed = self:resetProps()
    for _, a in ipairs(self.shot.actors) do
        local placement = nil
        if R.plan(a) ~= nil and t > (a.delay or 0) then
            placement = function(entry)
                local x, y, z, ry = self:entryPoseAt(a, entry, t)
                return x, y, z, 0, ry or entry.ry, 0
            end
        end
        local ok, why
        if Pe.isPerson(a) then
            ok, why = Pe.place(a, t, self.cam)
        else
            ok, why = W.resetStart(a.start, placement)
        end
        if not ok then
            failed = why
        else
            A.applyStates(a)
        end
    end
    if failed ~= nil then
        self:showMessage(g_i18n:getText(REASONS[failed] or "cine_msg_actorMissing"))
    elseif showMessage and #self.shot.actors > 0 then
        self:showMessage(string.format(g_i18n:getText("cine_msg_actorsResetHere"), t))
    end
    self:showActorStates(t)
end

-- Detail vozidla: na ose zůstane jen kamera a toto vozidlo se všemi lajnami akcí, které umí (i prázdnými).
function CinemaEditorScreen:setDetail(i)
    if i ~= nil and self.shot.actors[i] ~= nil then
        self.detail = i
        self.detailKinds = A.laneKinds(self.shot.actors[i], true)
        self:setActiveTarget(i)
    else
        self.detail, self.detailKinds = nil, nil
    end
end

function CinemaEditorScreen:prepareActors(t)
    self.actorRt = {}
    for i, a in ipairs(self.shot.actors) do
        local rt = Pe.isPerson(a) and Pe.newRuntime(a) or W.newRuntime(a)
        A.prepare(rt, a, t)
        if rt.person then
            rt.state = "walking"
        elseif rt.route == nil then
            rt.state = "done"
        else
            local ok, why = W.canDrive(rt.vehicle, self:hasPersonActor())
            if ok and rt.route.hasReverse and not W.canReverse(rt.vehicle) then
                ok, why = false, "cannotReverse"
            end
            if not ok then
                rt.state = "done"
                self:showMessage(g_i18n:getText(REASONS[why] or "cine_msg_actorMissing"))
            end
        end
        self.actorRt[i] = rt
    end
    self:prepareObjects(t)
end

function CinemaEditorScreen:updateActors(dt, t)
    self:applyTools(t)
    for i, a in ipairs(self.shot.actors) do
        local rt = self.actorRt[i]
        if rt ~= nil and rt.person then
            if rt.state == "walking" then
                Pe.update(rt, a, t, dt)
            end
            A.update(rt, a, t - (a.delay or 0), dt)
        elseif rt ~= nil then
            if rt.state == "waiting" and t >= (a.delay or 0) then
                rt.state = "driving"
                rt.elapsed = math.max(t - (a.delay or 0), 0)
            end
            if rt.state == "driving" then
                W.driveActor(rt, a, dt)
            end
            A.update(rt, a, t - (a.delay or 0), dt)
            -- vozidlo, které dojelo, drží motor, dokud ho akce nevypne
            if rt.parked and rt.vehicle ~= nil and rt.act ~= nil and rt.act.motorWanted[W.uid(rt.vehicle)] ~= false then
                W.keepMotorAlive(rt.vehicle)
            end
        end
    end
    self:updateObjects(dt, t)
end

function CinemaEditorScreen:stopActors()
    for _, rt in pairs(self.actorRt) do
        if rt.person then
            Pe.stop()
        else
            W.stopActor(rt)
        end
        A.finish(rt)
    end
    self:stopObjects()
    self:restoreTools()
    self.actorRt = {}
    self:clearActorStates()
end

-- Stav vozidel (světla, složení, nářadí…) odpovídající času t podle akcí, aby po R nebo B vypadala vozidla tak, jak mají
-- být. Při přehrávání nebo návratu se původní stav vrátí.
function CinemaEditorScreen:showActorStates(t)
    self:clearActorStates()
    self.actState = {}
    for i, a in ipairs(self.shot.actors) do
        local rt = {}
        A.prepare(rt, a, t)
        rt.act.preview = true
        A.update(rt, a, t - (a.delay or 0), 0)
        self.actState[i] = rt
    end
    self:showObjectStates(t)
end

function CinemaEditorScreen:clearActorStates()
    for _, rt in pairs(self.actState or {}) do
        A.finish(rt)
    end
    self.actState = nil
    self:clearObjectStates()
end

---------------------------------------------------------------------------------------------------
-- kolečko na ose: Ctrl rychlost bloku (u vozidla úseku trasy), Shift přiblížení kamery, Alt přiblížení časové osy

E.BLOCK_ZOOM_STEP = 1.15 -- násobek ohniska za jedno cvaknutí kolečka
E.BLOCK_SPEED_STEP = 1.25 -- násobek rychlosti za jedno cvaknutí kolečka

-- Pauza v bodě j herce i (s, nil = bez pauzy). Akce a body křivek herce po konci pauzy se posunou s ní, ať nastoupení,
-- dveře nebo nesení zůstanou na stejném místě trasy (jinak by postava nasedla do vozidla uprostřed cesty). Bez kroku zpět.
-- Tažení pauzy a úseků na ose je v CinemaEditorSpans.lua.
function CinemaEditorScreen:setPointWait(i, j, wait)
    local actor = self.shot.actors[i]
    local p = actor ~= nil and actor.points[j] or nil
    if p == nil then
        return
    end
    local old = p[4] or 0
    local delta = (wait or 0) - old
    local arrival, nextOld = self:routePointTime(i, j), self:routePointTime(i, j + 1)
    p[4] = wait
    self.actorRt = {}
    if arrival == nil or math.abs(delta) < 1e-9 then
        return
    end
    -- o kolik se doopravdy posune příjezd do dalšího bodu (vozidlo kvůli pauze i brzdí a rozjíždí se)
    local nextNew = self:routePointTime(i, j + 1)
    local shift = nextOld ~= nil and nextNew ~= nil and nextNew - nextOld or delta
    self:rippleActor(i, arrival - (actor.delay or 0) + old, shift, true)
end

-- Rychlost úseku trasy vozidla i v čase t změní o delta km/h (oba krajní body); vrací číslo úseku, nebo nil bez úseku.
function CinemaEditorScreen:changeRouteSpan(i, t, delta)
    local result
    self:keepOnRoute(self.shot.actors[i], function() result = self:changeRouteSpanNow(i, t, delta) end)
    return result
end

function CinemaEditorScreen:changeRouteSpanNow(i, t, delta)
    local actor = self.shot.actors[i]
    local span = actor ~= nil and self:routeSpanAtTime(i, t) or nil
    if span == nil then
        return nil
    end
    local p1, p2 = actor.points[span], actor.points[span + 1]
    if CinemaPerson.isPerson(actor) then
        -- postava: + rychlejší chůze úseku, − pomalejší (bez přetočení dokola)
        local index = CinemaPerson.gaitIndex(p1[3])
        if (delta > 0 and index == #CinemaPerson.GAITS) or (delta < 0 and index == 1) then
            return span
        end
        self:pushUndo()
        CinemaPerson.stepGait(p1, delta > 0 and 1 or -1)
        self.actorRt = {}
        S.touch(self.shot)
        self:markDirty()
        self:showMessage(string.format(g_i18n:getText("cine_msg_gaitSpan"), span, span + 1,
            CinemaPerson.gaitTitle(p1[3])))
        return span
    end
    local from, to = self:routePointTime(i, span), self:routePointTime(i, span + 1)
    if self:shiftSpeedCurve(i, from - (actor.delay or 0), to - (actor.delay or 0), delta) then
        self:showMessage(string.format(g_i18n:getText("cine_msg_routeSpeed"), span, span + 1, self:channelValueAt({ kind = "speed", owner = i }, (from + to) * 0.5)))
        return span
    end
    self:pushUndo()
    p1[3] = M.clamp(self:routePointKmh(i, span) + delta, 0, 80)
    p2[3] = M.clamp(self:routePointKmh(i, span + 1) + delta, 0, 80)
    self.actorRt = {}
    S.touch(self.shot)
    self:markDirty()
    self:showMessage(string.format(g_i18n:getText("cine_msg_routeSpeed"), span, span + 1,
        math.max(self:routePointKmh(i, span), self:routePointKmh(i, span + 1))))
    return span
end

-- Rychlost bloku pod playheadem: úsek kamery (rychlost mezi keyframy) nebo režim (délka). Krok je podle globálního kroku:
-- 1 km/h = +5 %, 5 km/h = +25 %, 10 km/h = +50 %. Klávesou + zrychlí, - zpomalí.
function CinemaEditorScreen:changeBlockSpeed(direction)
    if self:isBusy() then
        return
    end
    local shot = self.shot
    if self.activeTarget > 0 and shot.actors[self.activeTarget] ~= nil
        and self:changeRouteSpan(self.activeTarget, self.playhead, direction * self.speedStep) ~= nil then
        return
    end
    local factor = 1 + self.speedStep * 0.05
    if direction < 0 then
        factor = 1 / factor
    end
    local seg = S.segmentAt(shot, self.playhead)
    if seg == nil then
        self:showMessage(g_i18n:getText("cine_msg_noBlockAtPlayhead"))
        return
    end
    self:pushUndo()
    self:showMessage(string.format(g_i18n:getText("cine_msg_blockLength"), S.scaleSegment(shot, seg, factor)))
    self:markDirty()
end

-- Globální krok rychlosti (km/h) přes všechny úpravy rychlosti; přepíná se v nabídce záběru.
function CinemaEditorScreen:cycleSpeedStep()
    local index = 1
    for i, value in ipairs(E.SPEED_STEPS) do
        if value == self.speedStep then
            index = i
        end
    end
    self.speedStep = E.SPEED_STEPS[index % #E.SPEED_STEPS + 1]
    self:showMessage(string.format(g_i18n:getText("cine_msg_speedStep"), self.speedStep))
end

-- Krok pro texty v nabídce (bez instance, např. při sestavení položek).
function E.speedStepOf()
    local screen = E.INSTANCE
    return screen ~= nil and screen.speedStep or 5
end

-- Věc, na kterou kolečko míří: pod kurzorem (je-li vidět na ose), jinak blok pod playheadem aktivního řádku.
-- { kind = "key" | "mark" | "segment", … } u kamery, { kind = "actor", index, t } u vozidla; nil, když tam nic není.
function CinemaEditorScreen:wheelTarget(cursorOnly)
    local shot = self.shot
    if self.cursorShown and self.mouseX ~= nil then
        local hit = self:hitPanels(self.mouseX, self.mouseY)
        if hit ~= nil and (hit.kind == "key" or hit.kind == "segment" or hit.kind == "mark") then
            return hit
        end
        if hit ~= nil and hit.kind == "edge" then
            local _, index = S.segmentById(shot, hit.seg.id)
            return { kind = "segment", index = index }
        end
        if hit ~= nil and hit.kind == "actor" and hit.onBlock then
            return { kind = "actor", index = hit.index, t = self:timeAtX(self.mouseX) }
        end
    end
    if cursorOnly then
        return nil
    end
    if self.activeTarget > 0 and shot.actors[self.activeTarget] ~= nil then
        return { kind = "actor", index = self.activeTarget, t = self.playhead }
    end
    local seg, segIndex = S.segmentAt(shot, self.playhead)
    if seg ~= nil then
        return { kind = "segment", index = segIndex }
    end
    return nil
end

-- Ctrl + kolečko: rychlost K-framu Letu, K-framu režimu, délka bloku kamery, nebo rychlost úseku trasy vozidla.
function CinemaEditorScreen:wheelSpeed(steps)
    local shot = self.shot
    local target = self:wheelTarget()
    if target == nil then
        self:showMessage(g_i18n:getText("cine_msg_noBlockAtPlayhead"))
        return
    end
    if target.kind == "key" then
        local track = target.seg.track
        if S.keyIsFree(shot, track, target.index) then
            self:showMessage(g_i18n:getText("cine_msg_keyFree"))
            return
        end
        local v = S.keySpeed(shot, track, target.index)
        self:pushUndo()
        S.setKeySpeed(shot, track, target.index, v <= 1e-3 and steps > 0 and 0.5 or v * E.BLOCK_SPEED_STEP ^ steps)
        self:setSelectedKey(target.seg, target.index)
        self:showMessage(string.format(g_i18n:getText("cine_msg_keySpeed"), (S.keySpeed(shot, track, target.index))))
    elseif target.kind == "mark" then
        local seg = shot.segments[target.seg]
        if not Mo.MOVING[seg.track.mode] then
            self:showMessage(g_i18n:getText("cine_msg_markNoSpeed"))
            return
        end
        self:pushUndo()
        Mo.adjustMark(seg.track, target.index, "speed", steps)
        self:setSelectedMark(seg, target.index)
        self:showMessage(string.format(g_i18n:getText("cine_msg_markSpeed"), seg.track.marks[target.index].speed))
    elseif target.kind == "segment" then
        local seg = shot.segments[target.index]
        self:pushUndo()
        self:showMessage(string.format(g_i18n:getText("cine_msg_blockLength"), S.scaleSegment(shot, seg, E.BLOCK_SPEED_STEP ^ steps)))
    else
        if self:changeRouteSpan(target.index, target.t, steps * self.speedStep) == nil then
            self:showMessage(g_i18n:getText("cine_msg_noBlockAtPlayhead"))
            return
        end
    end
    S.touch(shot)
    self:markDirty()
end

-- Shift + kolečko: přiblížení kamery. Nad K-framem jeho ohnisko, nad blokem zoom celého bloku, jinak ohnisko kamery.
function CinemaEditorScreen:wheelZoom(steps)
    local shot = self.shot
    local target = self:wheelTarget(true)
    if target ~= nil and target.kind == "mark" then
        local seg = shot.segments[target.seg]
        self:pushUndo()
        Mo.adjustMark(seg.track, target.index, "focal", steps)
        self:setSelectedMark(seg, target.index)
        S.touch(shot)
        self:markDirty()
        return
    end
    if target ~= nil and target.kind == "key" then
        local k = target.seg.track.keys[target.index]
        self:pushUndo()
        k.focal = M.stepFocal(k.focal, steps, E.BLOCK_ZOOM_STEP)
        self.targetFocal = k.focal
        S.touch(shot)
        self:markDirty()
        return
    end
    local seg = target ~= nil and target.kind == "segment" and shot.segments[target.index] or nil
    if seg ~= nil then
        self:pushUndo()
        local track = seg.track
        if S.hasKeys(track) then
            for _, k in ipairs(track.keys) do
                k.focal = M.stepFocal(k.focal, steps, E.BLOCK_ZOOM_STEP)
            end
        else
            track.focal = M.stepFocal(track.focal or self.targetFocal, steps, E.BLOCK_ZOOM_STEP)
            track.focal2 = M.stepFocal(Mo.value(track, "focal2"), steps, E.BLOCK_ZOOM_STEP)
            self.targetFocal = track.focal
        end
        S.touch(shot)
        self:markDirty()
        return
    end
    self:setFocal(M.stepFocal(self.targetFocal, steps, E.BLOCK_ZOOM_STEP))
end

-- Alt + kolečko: přiblíží nebo oddálí časovou osu kolem místa pod kurzorem (bez kurzoru kolem playheadu).
function CinemaEditorScreen:wheelTimeline(steps)
    local x = self.altAnchor or (self.cursorShown and self.mouseX) or self:xAtTime(self.playhead)
    self:zoomTimeline(steps, x)
end
