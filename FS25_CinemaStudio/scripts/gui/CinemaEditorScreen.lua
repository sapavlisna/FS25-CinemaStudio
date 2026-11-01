-- Editor kamery: celoobrazovková průhledná obrazovka (vzor ConstructionScreen) s vlastním vstupním kontextem.
-- Kamera volně létá, K vloží K-frame do bloku pod playheadem, časová osa z bloků dole, přehrávání bez UI s předstihem.
-- Tady je životní cyklus, vstup, let a přehrávání; nástroje (výběr objektu, pohled shora, křivka, herci) jsou
-- v CinemaEditorTools.lua, menu v CinemaEditorMenu.lua a kreslení v CinemaEditorDraw.lua.

CinemaEditorScreen = CinemaEditorScreen or {}
CinemaEditorScreen.MOD_DIR = g_currentModDirectory
CinemaEditorScreen.GUI_NAME = "CinemaEditorScreen"
CinemaEditorScreen.INPUT_CONTEXT = "CINEMA_STUDIO"

CinemaEditorScreen.FLY_SPEED_DEFAULT = 8
CinemaEditorScreen.FLY_SPEED_MIN = 0.5
CinemaEditorScreen.FLY_SPEED_MAX = 250
CinemaEditorScreen.FLY_SPEED_STEP = 1.2
CinemaEditorScreen.FLY_DAMPING = 0.18 -- s; setrvačnost letu
CinemaEditorScreen.FOCAL_DAMPING = 0.08
CinemaEditorScreen.CHASE_STEP = 0.05 -- s; krok, po kterém se mimo přehrávání počítá tlumené sledování z plánu
-- K v bloku režimu: od jakého posunu (m) a natočení (rad) kamery proti bloku se mění kamera bloku, ne jen ohnisko
CinemaEditorScreen.MODE_MOVED = 0.05
CinemaEditorScreen.MODE_TURNED = 0.005
CinemaEditorScreen.MOUNT_RAY = 60 -- m; jak daleko kamera při připevnění hledá část vozidla, na kterou míří
CinemaEditorScreen.TARGET_DAMPING = 0.12 -- s; vyhlazení polohy sledovaného vozidla (fyzika škube)
CinemaEditorScreen.TARGET_HEADING_DAMPING = 0.6 -- s; směr jízdy (vozidlo při řízení po trase kmitá a kamera na kraji ramene by se houpala)
CinemaEditorScreen.TARGET_HEIGHT_DAMPING = 0.3 -- s; výška (nerovnosti terénu)
CinemaEditorScreen.TARGET_DISTANCE_REF = 12 -- m; od vzdálenosti kamery od cíle se vyhlazení úměrně prodlužuje (výchylka na dlouhém rameni se zesiluje)
CinemaEditorScreen.TARGET_DISTANCE_MAX = 6 -- největší násobek vyhlazení
CinemaEditorScreen.FAST = 4
CinemaEditorScreen.LOOK_MOUSE = 0.001 * 16.666 -- rad na jednotku osy myši, stejně jako PlayerInputComponent
CinemaEditorScreen.LOOK_STICK = 0.001 -- rad na jednotku osy a ms (páčka)
CinemaEditorScreen.LOOK_FOCAL_REF = 35 -- pro delší ohnisko se rozhlížení zpomalí, aby šlo mířit jemně
CinemaEditorScreen.PITCH_LIMIT = math.rad(89)
CinemaEditorScreen.SPEED_STEPS = { 1, 5, 10 } -- km/h; globální krok všech úprav rychlosti (menu, kolečko na úseku)
CinemaEditorScreen.BANK_STEPS = { 0, 5, 10, 15, 20, 30 } -- ° náklonu do zatáčky; 0 = vypnuto (horizont zůstává rovný)
CinemaEditorScreen.BANK_FULL_RATE = math.rad(20) -- rad/s otáčení, při kterém je náklon plný
CinemaEditorScreen.BANK_SMOOTH = 0.6 -- s; vyhlazení náklonu
CinemaEditorScreen.BANK_SIGN = 1 -- znaménko náklonu do zatáčky (ověřit ve hře, při opačném naklánění -1)
CinemaEditorScreen.GROUND_CLEARANCE = 0.3
CinemaEditorScreen.SCRUB_STEP = 1
CinemaEditorScreen.NUDGE_STEP = 0.5
CinemaEditorScreen.REPEAT_DELAY = 350
CinemaEditorScreen.REPEAT_INTERVAL = 60
CinemaEditorScreen.UNDO_LIMIT = 60
CinemaEditorScreen.MESSAGE_TIME = 2500

local M = CinemaMath
local S = CinemaShot
local Cam = CinemaCamera
local W = CinemaWorld
local Mo = CinemaModes
local Env = CinemaEnvironment
local E = CinemaEditorScreen

local CinemaEditorScreen_mt = Class(CinemaEditorScreen, ScreenElement)

function CinemaEditorScreen.new()
    local self = ScreenElement.new(nil, CinemaEditorScreen_mt)
    self.mission = g_currentMission
    self.cam = Cam.new()
    self.shot = nil
    self.index = nil
    self.playhead = 0
    self.sel = {}
    self.playing = false
    self.clean = false
    self.showHelp = false
    self.picking = false
    self.topdown = nil
    self.curves = false
    self.letterbox = false
    self.grid = false
    self.crosshair = false
    self.menu = nil
    self.palette = nil
    self.drivers = {}
    self.envSaved = {}
    self.snapOn, self.editMode = true, "overwrite"
    self.playheadAnywhere = false
    self.collapsed = {}
    self.targetFilters = {}
    self.activeTarget = 0
    self.actorRt = {}
    self.flySpeed = E.FLY_SPEED_DEFAULT
    self.targetFocal = 35
    self.vel = { 0, 0, 0 }
    self.moveForward, self.moveSide, self.moveUp = 0, 0, 0
    self.mouseX, self.mouseY = 0.5, 0.5
    self.drag = nil
    self.freeLook, self.autoCursor, self.cursorShown = true, false, nil
    self.undoStack, self.redoStack = {}, {}
    self.history, self.historyDirty, self.historyOpen, self.historyScroll = {}, false, false, 0
    self.held = {}
    self.rowKeys = {}
    self.message, self.messageTimer = nil, 0
    self.dirty = false
    return self
end

-- Obrazovka se načte jednou na hru; po přechodu do jiné hry se stará zahodí (vzor plánovače SprayDrone).
function CinemaEditorScreen.show()
    local old = E.INSTANCE
    if old ~= nil and old.mission ~= g_currentMission then
        old:delete()
        E.INSTANCE = nil
    end
    if E.INSTANCE == nil then
        local screen = E.new()
        g_gui:loadGui(E.MOD_DIR .. "gui/CinemaEditorScreen.xml", E.GUI_NAME, screen)
        E.INSTANCE = screen
    end
    if not E.INSTANCE:getIsOpen() then
        g_gui:showGui(E.GUI_NAME)
    end
end

function CinemaEditorScreen:delete()
    if self.cam.active then
        Cam.stop(self.cam)
    end
    if E.INSTANCE == self then
        E.INSTANCE = nil
    end
    CinemaEditorScreen:superClass().delete(self)
end

function CinemaEditorScreen:onOpen()
    CinemaEditorScreen:superClass().onOpen(self)
    CinemaActions.notify = function(text) self:showMessage(text) end
    g_inputBinding:setContext(E.INPUT_CONTEXT, true, false)
    self:registerActions()
    if self.shot == nil then
        self:loadShots()
    end
    Cam.start(self.cam)
    self.targetFocal = self.cam.focal
    self.vel = { 0, 0, 0 }
    self.playing, self.clean, self.drag, self.menu, self.picking, self.topdown = false, false, nil, nil, false, nil
    self.curves = false
    self.freeLook, self.autoCursor, self.cursorShown = true, false, nil
    self.altDown = nil
    self.playTimeline = false
    self.speedStep = self.speedStep or 5
    self:applyCursor()
    self:importRecording()
end

function CinemaEditorScreen:onClose()
    if self.playing then
        self:stopPlayback()
    end
    self:stopActors()
    self:clearDrivers()
    self:saveAll()
    Env.apply(nil, self.envSaved)
    self.envSaved = {}
    -- puštění držené klávesy po odregistrování akcí nepřijde
    self.held, self.rowKeys, self.nudging = {}, {}, false
    g_inputBinding:removeActionEventsByTarget(self)
    g_inputBinding:revertContext()
    Cam.stop(self.cam)
    self.topdown = nil
    CinemaEditorScreen:superClass().onClose(self)
end

---------------------------------------------------------------------------------------------------
-- záběry

function CinemaEditorScreen:loadShots()
    self.index = CinemaStorage.loadIndex()
    if #self.index.files == 0 then
        local file = CinemaStorage.newFileName(self.index)
        self.index.files[1] = file
        self.index.active = 1
    end
    self:openShot(self.index.active)
end

function CinemaEditorScreen:openShot(i)
    self.index.active = i
    local file = self.index.files[i]
    self.shot = CinemaStorage.load(file) or S.new(file)
    self.shot.file = file
    self.shot.name = string.format(g_i18n:getText("cine_shotName"), i)
    self.playhead = 0
    self:selClear()
    self.detail, self.detailKinds = nil, nil
    self.viewSpan, self.viewStart = nil, nil
    self.undoStack, self.redoStack = {}, {}
    self.history = CinemaHistory.prune(CinemaStorage.loadHistory(file), CinemaHistory.now())
    self.historyDirty, self.historyCache, self.historyScroll = false, nil, 0
    self:syncDrivers()
    self.activeTarget = 0
    self.actorRt = {}
    self.dirty = false
    self:applyEnvironment()
    self.envStart = Env.capture()
end

function CinemaEditorScreen:saveAll()
    if self.shot ~= nil and self.dirty then
        self:save(true)
    end
    self:saveHistory()
    if self.index ~= nil then
        CinemaStorage.saveIndex(self.index)
    end
end

function CinemaEditorScreen:switchShot(delta)
    local count = #self.index.files
    if count < 2 then
        self:showMessage(g_i18n:getText("cine_msg_onlyShot"))
        return
    end
    self:stopActors()
    self:saveAll()
    self:openShot((self.index.active - 1 + delta) % count + 1)
    self:showMessage(self.shot.name)
end

-- Po změně vybrané kamery se výběr zruší a kamera skočí na její pózu.
function CinemaEditorScreen:afterCameraChange()
    local shot = self.shot
    self:selClear()
    self.rangeTime = nil
    if self.topdown == nil and #shot.segments > 0 then
        self:applyShotPose(self.playhead)
    end
    self:setActiveTarget(0)
    self:showMessage(string.format(g_i18n:getText("cine_msg_camera"), shot.camIndex, #shot.cameras))
    self:markDirty()
end

function CinemaEditorScreen:switchCamera(delta)
    local shot = self.shot
    local count = #shot.cameras
    if count < 2 then
        self:showMessage(g_i18n:getText("cine_msg_onlyCamera"))
        return
    end
    S.setCamera(shot, (shot.camIndex - 1 + delta) % count + 1)
    self:afterCameraChange()
end

function CinemaEditorScreen:selectCamera(index)
    if S.setCamera(self.shot, index) then
        self:afterCameraChange()
    end
end

-- Nová prázdná kamera: dráha vozidel zůstává, kamera má vlastní bloky a body zájmu.
function CinemaEditorScreen:addCamera()
    self:pushUndo()
    S.addCamera(self.shot)
    self:afterCameraChange()
end

function CinemaEditorScreen:removeCamera()
    local shot = self.shot
    if #shot.cameras < 2 then
        self:showMessage(g_i18n:getText("cine_msg_onlyCamera"))
        return
    end
    self:pushUndo()
    S.removeCamera(shot, shot.camIndex)
    self:afterCameraChange()
end

function CinemaEditorScreen:newShot()
    self:stopActors()
    self:saveAll()
    local file = CinemaStorage.newFileName(self.index)
    table.insert(self.index.files, file)
    self:openShot(#self.index.files)
    self:markDirty()
    self:showMessage(self.shot.name)
end

-- Záběr zmizí ze seznamu; soubor zůstane na disku (pojistka proti omylu).
function CinemaEditorScreen:deleteShot()
    if #self.index.files < 2 then
        self:showMessage(g_i18n:getText("cine_msg_onlyShot"))
        return
    end
    self:stopActors()
    -- soubor záběru zůstane (pojistka proti omylu), jeho historie bez něj nemá smysl a je velká
    local file = self.index.files[self.index.active]
    if file ~= nil and deleteFile ~= nil then
        pcall(deleteFile, CinemaStorage.getHistoryPath(file))
    end
    table.remove(self.index.files, self.index.active)
    self.dirty = false
    self:openShot(math.min(self.index.active, #self.index.files))
    CinemaStorage.saveIndex(self.index)
    self:showMessage(g_i18n:getText("cine_msg_shotDeleted"))
end

---------------------------------------------------------------------------------------------------
-- vstup

local function addAction(self, action, callback, triggerUp, triggerDown, triggerAlways, state, disableConflicts)
    if action == nil then
        return
    end
    local _, eventId = g_inputBinding:registerActionEvent(action, self, callback, triggerUp, triggerDown, triggerAlways, true, state, disableConflicts)
    if eventId ~= nil then
        g_inputBinding:setActionEventTextVisibility(eventId, false)
    end
end

function CinemaEditorScreen:registerActions()
    local A = InputAction
    addAction(self, A.MENU_BACK, self.onActionBack, false, true, false)
    addAction(self, A.AXIS_MOVE_FORWARD_PLAYER, self.onActionMoveForward, false, false, true)
    addAction(self, A.AXIS_MOVE_SIDE_PLAYER, self.onActionMoveSide, false, false, true)
    addAction(self, A.CINE_UPDOWN, self.onActionUpDown, false, false, true)
    addAction(self, A.AXIS_LOOK_LEFTRIGHT_PLAYER, self.onActionLookX, false, false, true, nil, true)
    addAction(self, A.AXIS_LOOK_UPDOWN_PLAYER, self.onActionLookY, false, false, true, nil, true)
    addAction(self, A.CINE_CURSOR, self.onActionCursor, false, true, false)
    addAction(self, A.CINE_KEY_ADD, self.onActionKeyAdd, false, true, false)
    addAction(self, A.CINE_KEY_DELETE, self.onActionKeyDelete, false, true, false)
    addAction(self, A.CINE_KEY_BACKSPACE, self.onActionKeyBackspace, false, true, false)
    addAction(self, A.CINE_KEY_PREV, self.onActionKeyPrev, false, true, false)
    addAction(self, A.CINE_KEY_NEXT, self.onActionKeyNext, false, true, false)
    addAction(self, A.CINE_KEY_RAISE, self.onActionKeyRaise, true, true, false)
    addAction(self, A.CINE_KEY_LOWER, self.onActionKeyLower, true, true, false)
    addAction(self, A.CINE_PLAY, self.onActionPlay, false, true, false)
    addAction(self, A.CINE_PLAY_START, self.onActionPlayStart, false, true, false)
    addAction(self, A.CINE_HOME, self.onActionHome, false, true, false)
    addAction(self, A.CINE_END, self.onActionEnd, false, true, false)
    addAction(self, A.CINE_CLEAN, self.onActionClean, false, true, false)
    addAction(self, A.CINE_HELP, self.onActionHelp, false, true, false)
    addAction(self, A.CINE_UNDO, self.onActionUndo, false, true, false)
    addAction(self, A.CINE_REDO, self.onActionRedo, false, true, false)
    addAction(self, A.CINE_SAVE, self.onActionSave, false, true, false)
    addAction(self, A.CINE_PICK, self.onActionPick, false, true, false)
    addAction(self, A.CINE_TOPDOWN, self.onActionTopdown, false, true, false)
    addAction(self, A.CINE_RESET_ACTORS, self.onActionResetActors, false, true, false)
    addAction(self, A.CINE_RESET_HERE, self.onActionResetHere, false, true, false)
    addAction(self, A.CINE_DETAIL, self.onActionDetail, false, true, false)
    addAction(self, A.CINE_PLAY_TIMELINE, self.onActionPlayTimeline, false, true, false)
    addAction(self, A.CINE_CAMERA_NEXT, self.onActionCameraNext, false, true, false)
    addAction(self, A.CINE_SPEED_UP, self.onActionSpeedUp, false, true, false)
    addAction(self, A.CINE_SPEED_DOWN, self.onActionSpeedDown, false, true, false)
    addAction(self, A.CINE_CYCLE_TARGET, self.onActionCycleTarget, false, true, false)
    addAction(self, A.CINE_CURVES, self.onActionCurves, false, true, false)
    addAction(self, A.CINE_SHOT_NEW, self.onActionShotNew, false, true, false)
    addAction(self, A.CINE_SHOT_PREV, self.onActionShotPrev, false, true, false)
    addAction(self, A.CINE_SHOT_NEXT, self.onActionShotNext, false, true, false)
    addAction(self, A.CINE_LETTERBOX, self.onActionLetterbox, false, true, false)
    addAction(self, A.CINE_GRID, self.onActionGrid, false, true, false)
    addAction(self, A.CINE_DOCK, self.onActionDock, false, true, false)
    addAction(self, A.CINE_SNAP, self.onActionSnap, false, true, false)
    addAction(self, A.CINE_EDIT_MODE, self.onActionEditMode, false, true, false)
    addAction(self, A.CINE_SPLIT, self.onActionSplit, false, true, false)
    addAction(self, A.CINE_KEY_PASS, self.onActionKeyPass, false, true, false)
    addAction(self, A.CINE_COPY, self.onActionCopy, false, true, false)
    addAction(self, A.CINE_PASTE, self.onActionPaste, false, true, false)
    for i = 1, #M.FOCAL_PRESETS do
        addAction(self, A["CINE_LENS_" .. i], self.onActionLens, false, true, false, i)
    end
end

local function isShift()
    return Input.isKeyPressed(Input.KEY_lshift) or Input.isKeyPressed(Input.KEY_rshift)
end

local function isAlt()
    return Input.isKeyPressed(Input.KEY_lalt) or Input.isKeyPressed(Input.KEY_ralt)
end

local function isCtrl()
    return Input.isKeyPressed(Input.KEY_lctrl) or Input.isKeyPressed(Input.KEY_rctrl)
end
E.isShift, E.isAlt, E.isCtrl = isShift, isAlt, isCtrl

-- Verzálky i s diakritikou (tlačítka a nadpisy jako ve hře).
function E.upper(s)
    if utf8ToUpper ~= nil then
        return utf8ToUpper(s)
    end
    return string.upper(s)
end

-- Násobek kroku podle modifikátoru: Shift hrubě.
function E.stepFactor()
    if isShift() then
        return E.FAST
    end
    return 1
end

-- Akce, které nedávají smysl během přehrávání nebo s otevřeným menu.
function CinemaEditorScreen:isBusy()
    return self.playing or self.menu ~= nil or self.palette ~= nil or self.drag ~= nil
end

function CinemaEditorScreen:onActionBack()
    if self.playing then
        self:stopPlayback()
    elseif self.menu ~= nil then
        self.menu = nil
    elseif self.palette ~= nil then
        self.palette = nil
    elseif self.showHelp then
        self.showHelp = false
    elseif self.boxPlacing ~= nil then
        self.boxPlacing = nil
    elseif self.picking then
        self.picking = false
        self.pendingAction = nil
    elseif self.topdown ~= nil then
        self:exitTopdown()
    elseif self.clean then
        self:setClean(false)
    else
        g_gui:showGui("")
    end
end

-- osy se sčítají (víc vazeb na jednu osu) a v update se nulují, jako v PlayerInputComponent
function CinemaEditorScreen:onActionMoveForward(_, value)
    self.moveForward = self.moveForward - value
end

function CinemaEditorScreen:onActionMoveSide(_, value)
    self.moveSide = self.moveSide + value
end

function CinemaEditorScreen:onActionUpDown(_, value)
    self.moveUp = self.moveUp + value
end

function CinemaEditorScreen:onActionKeyAdd()
    if self:isBusy() then
        return
    end
    if self.topdown ~= nil then
        -- shora K nebere pózu kamery nad mapou, ale vloží bod do dráhy v čase playheadu
        self:insertAtPlayhead()
        return
    end
    self:addKeyHere()
end

-- Delete smaže vybrané a zavře mezeru po bloku, Backspace ji nechá (kamera v ní stojí), jako ve střihovém programu.
function CinemaEditorScreen:onActionKeyDelete()
    self:deleteCommand(true)
end

function CinemaEditorScreen:onActionKeyBackspace()
    self:deleteCommand(false)
end

function CinemaEditorScreen:deleteCommand(ripple)
    if self:isBusy() then
        return
    end
    local cp = self.chPoint
    if self.curves and cp ~= nil then
        local desc = self:channelByKey(cp.key)
        if desc ~= nil and self:channelOf(desc, false) ~= nil and self:channelOf(desc, false).points[cp.index] ~= nil then
            self:removeChannelPoint(desc, cp.index)
            return
        end
        self.chPoint = nil
    end
    if self.topdown ~= nil and self.activeTarget > 0 then
        self:deleteRoutePoint(self.topdown.point)
        return
    end
    if self:deleteSelectedSpans() then
        return
    end
    if self:selCount() > 0 then
        self:deleteSelection(ripple)
        return
    end
    -- z pohledu kamery s vybraným hercem: bez výběru smaže poslední bod trasy (opraví špatně položený bod z pravého tlačítka)
    local actor = self.shot.actors[self.activeTarget]
    if actor ~= nil and #(actor.points or {}) > 1 then
        self:deleteRoutePoint({ actor = self.activeTarget, index = #actor.points })
    end
end

function CinemaEditorScreen:onActionSnap()
    if not self:isBusy() then
        self:toggleSnap()
    end
end

function CinemaEditorScreen:onActionEditMode()
    if not self:isBusy() then
        self:toggleEditMode()
    end
end

function CinemaEditorScreen:onActionCopy()
    if not self:isBusy() then
        self:copySelection()
    end
end

function CinemaEditorScreen:onActionPaste()
    if not self:isBusy() and self.topdown == nil then
        self:pasteClipboard()
    end
end

-- Rozdělí blok pod playheadem na dva.
function CinemaEditorScreen:onActionSplit()
    if not self:isBusy() and self.topdown == nil then
        local span = self:selPrimary("span")
        if span ~= nil then
            local i, e = self:spanFromObject("span", span)
            if i ~= nil and self.playhead > e.t0 and self.playhead < e.t1 then
                self:pushUndo()
                self:splitSpanAt(i, self.playhead)
            else
                self:showMessage(g_i18n:getText("cine_msg_spanSplitOutside"))
            end
        elseif self:selPrimary("focus") ~= nil then
            self:splitFocusHere(nil)
        else
            self:splitBlock()
        end
    end
end

-- K-frame, kterého se týká přepnutí průjezdu: vybraný, jinak ten na ukazateli.
function CinemaEditorScreen:passKey()
    local seg, index = self:selectedKey()
    if seg ~= nil and index ~= nil then
        return seg, index
    end
    seg = S.segmentAt(self.shot, self.playhead)
    if seg ~= nil and S.hasKeys(seg.track) then
        index = S.flightKeyAt(seg.track, self.playhead - seg.t)
        if index ~= nil then
            return seg, index
        end
    end
    return nil, nil
end

-- Průjezd K-framem dokola: Plynule → Zastavit → Roh.
function CinemaEditorScreen:onActionKeyPass()
    -- výchozí Y se kryje s Ctrl + Y (znovu)
    if self:isBusy() or isCtrl() then
        return
    end
    local seg, index = self:passKey()
    if seg == nil then
        self:showMessage(g_i18n:getText("cine_msg_passNoKey"))
        return
    end
    self:pushUndo()
    local pass = S.cyclePass(self.shot, seg.track.keys[index])
    self:markDirty()
    self:showMessage(string.format(g_i18n:getText("cine_msg_pass"), g_i18n:getText("cine_pass_" .. pass)))
end

-- Šipky vlevo / vpravo posouvají ukazatel po celých sekundách, se Shiftem skáčou po K-framech (stepKframe).
function CinemaEditorScreen:onActionKeyPrev()
    if self:isBusy() then
        return
    end
    if isShift() then
        self:stepKframe(-1)
        return
    end
    self:setPlayhead(math.max(math.ceil(self.playhead / E.SCRUB_STEP - 1e-6) - 1, 0) * E.SCRUB_STEP, true)
end

-- Šipky skáčou po K-framech všech bloků kamery (K-frame Letu i značka režimu se vyberou) a po začátcích a koncích bloků;
-- s vybraným hercem navíc po jeho bodech trasy, akcích a začátku a konci jízdy.
function CinemaEditorScreen:stepKframe(direction)
    local best, bestTime
    local function consider(t, entry)
        if t == nil then
            return
        end
        if (direction > 0 and t > self.playhead + S.KEY_SNAP and (bestTime == nil or t < bestTime - 1e-9))
            or (direction < 0 and t < self.playhead - S.KEY_SNAP and (bestTime == nil or t > bestTime + 1e-9)) then
            best, bestTime = entry, t
        end
    end
    local actor = self.shot.actors[self.activeTarget]
    if actor ~= nil then
        for j = 1, #actor.points do
            consider(self:routePointTime(self.activeTarget, j), { kind = "point", index = j })
        end
        for _, action in ipairs(actor.actions or {}) do
            consider((actor.delay or 0) + action.t, { kind = "actor" })
            consider((actor.delay or 0) + CinemaActions.endTime(action), { kind = "actor" })
        end
        consider(actor.delay or 0, { kind = "actor" })
        consider(self:actorEnd(self.activeTarget), { kind = "actor" })
    end
    for _, seg in ipairs(self.shot.segments) do
        local d = seg.track.duration or 0
        for i, k in ipairs(seg.track.keys or {}) do
            consider(seg.t + k.t, { kind = "key", seg = seg, index = i })
        end
        for _, m in ipairs(seg.track.marks or {}) do
            consider(seg.t + m.u * d, { kind = "mark", obj = m })
        end
        consider(seg.t, { kind = "block" })
        consider(S.segmentEnd(seg), { kind = "block" })
    end
    if best == nil then
        return
    end
    if best.kind == "key" then
        self:selectKey(best.seg, best.index)
        return
    end
    if best.kind == "mark" then
        self:selSet("mark", best.obj)
    elseif best.kind == "point" and self.topdown ~= nil then
        self.topdown.point = { actor = self.activeTarget, index = best.index }
    end
    self:setPlayhead(bestTime, self.topdown == nil)
end

function CinemaEditorScreen:onActionKeyNext()
    if self:isBusy() then
        return
    end
    if isShift() then
        self:stepKframe(1)
        return
    end
    self:setPlayhead((math.floor(self.playhead / E.SCRUB_STEP + 1e-6) + 1) * E.SCRUB_STEP, true)
end

-- Šipky nahoru / dolů přepínají ovládaný řádek osy (i při letu, kdy není kurzor). S Ctrl zvedají / snižují vybraný
-- K-frame nebo stojící kameru: stisk = jeden krok, držení opakuje (update).
function CinemaEditorScreen:onActionKeyRaise(_, value)
    self:rowOrNudge("raise", value, 1)
end

function CinemaEditorScreen:onActionKeyLower(_, value)
    self:rowOrNudge("lower", value, -1)
end

function CinemaEditorScreen:rowOrNudge(name, value, direction)
    if self.rowKeys[name] then
        self.rowKeys[name] = value > 0 or nil
        return
    end
    if value > 0 and self.held[name] == nil and not isCtrl() then
        self.rowKeys[name] = true
        if not self:isBusy() then
            self:stepActiveRow(direction)
        end
        return
    end
    self:setHeld(name, value > 0, direction)
end

-- Ovládaný řádek o jeden výš (vozidla nad kamerou) nebo níž; vozidla skrytá detailem se přeskočí, posunutá mimo okno
-- řádků se do něj vrátí.
function CinemaEditorScreen:stepActiveRow(direction)
    local rows = { 0 }
    for i = 1, #self.shot.actors do
        if self:isActorListed(i) then
            rows[#rows + 1] = i
        end
    end
    local current = 1
    for j, target in ipairs(rows) do
        if target == self.activeTarget then
            current = j
        end
    end
    local nextRow = rows[math.max(1, math.min(#rows, current + direction))]
    if nextRow ~= self.activeTarget then
        self:setActiveTarget(nextRow)
    end
end

function CinemaEditorScreen:setHeld(name, down, direction)
    if down then
        if self.held[name] == nil then
            self.held[name] = { next = g_time + E.REPEAT_DELAY, direction = direction }
            self:nudgeSelected(direction)
        end
    else
        self.held[name] = nil
    end
end

function CinemaEditorScreen:nudgeSelected(direction)
    if self:isBusy() then
        return
    end
    local seg, index, key = self:selectedKey()
    local block = key == nil and self:selPrimary("block") or nil
    if key == nil and not (block ~= nil and Mo.STANDS[block.track.mode]) then
        if block ~= nil or self:selPrimary("mark") ~= nil then
            self:showMessage(g_i18n:getText("cine_msg_modePosition"))
        end
        return
    end
    if not self.nudging then
        -- celé držení klávesy je jeden krok zpět
        self:pushUndo()
        self.nudging = true
    end
    local step = direction * E.NUDGE_STEP * E.stepFactor()
    if key ~= nil then
        S.nudgeKey(self.shot, key, 0, step, 0)
    else
        block.track.camY = block.track.camY + step
        S.touch(self.shot)
    end
    self:markDirty()
    if self.topdown == nil then
        if key ~= nil then
            self:jumpToKey(seg, index)
        else
            self:applyShotPose(self.playhead)
        end
    end
end

function CinemaEditorScreen:onActionPlay()
    if self.menu ~= nil then
        return
    end
    if self.playing then
        self:stopPlayback()
        return
    end
    local start = self.playhead
    if start >= S.duration(self.shot) - S.KEY_SNAP then
        start = 0
    end
    self:startPlayback(start)
end

function CinemaEditorScreen:onActionPlayStart()
    if self.menu ~= nil then
        return
    end
    if self.playing then
        self:stopPlayback()
    end
    self:startPlayback(0)
end

function CinemaEditorScreen:onActionHome()
    if not self:isBusy() then
        self:setPlayhead(0, self.topdown == nil)
    end
end

function CinemaEditorScreen:onActionEnd()
    if not self:isBusy() then
        self:setPlayhead(S.duration(self.shot), self.topdown == nil)
    end
end

-- Kurzor zůstává vidět: rozhlížení tažením myši čte polohu kurzoru a se skrytým kurzorem ji hra nedává.
function CinemaEditorScreen:setClean(clean)
    self.clean = clean
end

function CinemaEditorScreen:onActionSpeedUp()
    self:changeBlockSpeed(1)
end

function CinemaEditorScreen:onActionSpeedDown()
    self:changeBlockSpeed(-1)
end

-- Při přehrávání jde zapnout časová osa dole (jen pro sledování, nic se tím nemění).
function CinemaEditorScreen:onActionPlayTimeline()
    if not self.playing then
        return
    end
    self.playTimeline = not self.playTimeline
    self:showMessage(g_i18n:getText(self.playTimeline and "cine_msg_playTimelineOn" or "cine_msg_playTimelineOff"))
end

function CinemaEditorScreen:onActionClean()
    if not self:isBusy() and self.topdown == nil then
        self:setClean(not self.clean)
    end
end

function CinemaEditorScreen:onActionHelp()
    self.showHelp = not self.showHelp
end

function CinemaEditorScreen:onActionUndo()
    if self:isBusy() or #self.undoStack == 0 then
        return
    end
    table.insert(self.redoStack, S.clone(self.shot))
    S.restore(self.shot, table.remove(self.undoStack))
    self:afterHistory()
end

function CinemaEditorScreen:onActionRedo()
    if self:isBusy() or #self.redoStack == 0 then
        return
    end
    table.insert(self.undoStack, S.clone(self.shot))
    S.restore(self.shot, table.remove(self.redoStack))
    self:afterHistory()
end

function CinemaEditorScreen:onActionSave()
    self:save(false)
    CinemaStorage.saveIndex(self.index)
end

function CinemaEditorScreen:onActionLens(_, _, presetIndex)
    if self:isBusy() then
        return
    end
    self:setFocal(M.FOCAL_PRESETS[presetIndex])
end

function CinemaEditorScreen:onActionPick()
    if self:isBusy() then
        return
    end
    self.picking = not self.picking
    self.pendingAction = nil
    self.boxPlacing = nil
    if self.picking then
        self:setClean(false)
        self:needCursor()
        self:showMessage(g_i18n:getText("cine_msg_pick"))
    end
end

function CinemaEditorScreen:onActionTopdown()
    if self:isBusy() then
        return
    end
    if self.topdown ~= nil then
        self:exitTopdown()
    else
        self:enterTopdown()
    end
end

function CinemaEditorScreen:onActionResetActors()
    if not self:isBusy() then
        self:resetActors(true)
        -- po vrácení vozidel na start se i časová osa a kamera vrátí na začátek
        self:setPlayhead(0, self.topdown == nil)
        self:showActorStates(0)
    end
end

-- Vozidla na pozici podle plánu v čase playheadu (R je vrátí na start).
function CinemaEditorScreen:onActionResetHere()
    if not self:isBusy() then
        self:resetActorsAt(self.playhead, true)
    end
end

-- Detail aktivního vozidla (nebo prvního): zapne a vypne.
function CinemaEditorScreen:onActionDetail()
    if self:isBusy() then
        return
    end
    if self:getDetail() ~= nil then
        self:setDetail(nil)
        self:showMessage(g_i18n:getText("cine_msg_detailOff"))
        return
    end
    local i = self.activeTarget > 0 and self.activeTarget or (#self.shot.actors > 0 and 1 or nil)
    if i == nil then
        self:showMessage(g_i18n:getText("cine_msg_detailNone"))
        return
    end
    self:setDetail(i)
    self:showMessage(string.format(g_i18n:getText("cine_msg_detailOn"), self.shot.actors[i].name or "?"))
end

function CinemaEditorScreen:onActionCycleTarget()
    if self:isBusy() then
        return
    end
    local count = #self.shot.actors
    self:setActiveTarget((self.activeTarget + 1) % (count + 1))
end

-- Co se právě ovládá: 0 = kamera, jinak číslo vozidla. Zvýrazní se řádek na ose a dráha ve 3D.
function CinemaEditorScreen:setActiveTarget(target)
    local changed = self.activeTarget ~= target
    self.activeTarget = target
    self.objectFocus = nil
    -- v detailu se řádky přepnou za vozidlem, které se právě ovládá
    if target > 0 and self.detail ~= nil and self.detail ~= target and self.shot.actors[target] ~= nil then
        self.detail = target
        self.detailKinds = CinemaActions.laneKinds(self.shot.actors[target], true)
    end
    if target > 0 then
        self:revealActor(target)
    end
    if changed then
        self:showMessage(self:getActiveTargetText())
    end
end

function CinemaEditorScreen:onActionCurves()
    if not self:isBusy() then
        self.curves = not self.curves
        if self.curves then
            self:needCursor()
        end
    end
end

function CinemaEditorScreen:onActionShotNew()
    if not self:isBusy() then
        self:newShot()
    end
end

function CinemaEditorScreen:onActionShotPrev()
    if not self:isBusy() then
        self:switchShot(-1)
    end
end

function CinemaEditorScreen:onActionShotNext()
    if not self:isBusy() then
        self:switchShot(1)
    end
end

function CinemaEditorScreen:onActionCameraNext()
    if not self:isBusy() then
        self:switchCamera(1)
    end
end

function CinemaEditorScreen:onActionLetterbox()
    self.letterbox = not self.letterbox
end

function CinemaEditorScreen:onActionGrid()
    self.grid = not self.grid
end

function CinemaEditorScreen:toggleCrosshair()
    self.crosshair = not self.crosshair
end

function CinemaEditorScreen:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    self.mouseX, self.mouseY = posX, posY
    if self.playing then
        return true
    end
    if self.palette ~= nil then
        self:paletteMouseEvent(posX, posY, isDown, button)
        return true
    end
    if self.showHelp then
        if isDown then
            self.showHelp = false
        end
        return true
    end
    if self.menu ~= nil then
        self:menuMouseEvent(posX, posY, isDown, isUp, button)
        return true
    end
    -- rozjeté tažení dojede i nad panelem historie nebo dokem
    if self.drag ~= nil and self.topdown == nil and not isDown then
        if isUp and (button == Input.MOUSE_BUTTON_LEFT or button == Input.MOUSE_BUTTON_MIDDLE) then
            self:finishDrag()
        elseif not isUp then
            self:onPanelsDrag(posX, posY)
        end
        return true
    end
    if self:historyMouseEvent(posX, posY, isDown, button) then
        return true
    end
    if self:dockMouseEvent(posX, posY, isDown, button) then
        return true
    end
    if self:boxMouseEvent(posX, posY, isDown, button) then
        return true
    end
    local wheel = isDown and (button == Input.MOUSE_BUTTON_WHEEL_UP or button == Input.MOUSE_BUTTON_WHEEL_DOWN)
    if wheel then
        self:onWheel(button == Input.MOUSE_BUTTON_WHEEL_UP and 1 or -1)
        return true
    end
    if self.topdown ~= nil then
        self:topdownMouseEvent(posX, posY, isDown, isUp, button)
        return true
    end
    if isDown and button == Input.MOUSE_BUTTON_RIGHT then
        if self.drag ~= nil then
            return true
        end
        -- s kurzorem na panelu menu, jinak pravé tlačítko ukládá keyframe jako K
        if not self.freeLook and not self.clean and self:isOverPanels(posX, posY) then
            self:openContextMenu(posX, posY)
        elseif not self:addRoutePointFromView(posX, posY) then
            self:onActionKeyAdd()
        end
        return true
    end
    if isDown and button == Input.MOUSE_BUTTON_LEFT and not self.clean and not self.freeLook then
        if self.picking then
            self:pickAt(posX, posY)
        else
            self:onPanelsDown(posX, posY)
        end
        return true
    end
    if isDown and button == Input.MOUSE_BUTTON_MIDDLE and not self.clean and not self.freeLook then
        self:onPanelsMiddle(posX, posY)
        return true
    end
    if isUp and self.drag ~= nil and (button == Input.MOUSE_BUTTON_LEFT or button == Input.MOUSE_BUTTON_MIDDLE) then
        self:finishDrag()
        return true
    end
    if self.drag ~= nil then
        self:onPanelsDrag(posX, posY)
    end
    return true
end

-- Kolečko (letecký i pohled shora): Alt přiblíží osu, Ctrl změní rychlost bloku (kamery nebo vozidla), Shift přiblíží kameru,
-- bez modifikátoru rychlost letu (shora výška pohledu), Ctrl + Shift výška nových bodů shora.
function CinemaEditorScreen:onWheel(steps)
    if self:isOverChannelList() then
        self:chScrollBy(steps)
        return
    end
    if self:isOverActorRows() and not isAlt() and not isCtrl() and not isShift() then
        self:scrollRowsBy(steps)
        return
    end
    if isAlt() then
        if self.altToggled then
            self.altToggled = false
            self:onActionCursor()
        end
        self:wheelTimeline(steps)
        return
    end
    if self.topdown ~= nil and isCtrl() and isShift() then
        self:topdownWheel(steps)
        return
    end
    if isCtrl() then
        self:wheelSpeed(steps)
        return
    end
    if isShift() then
        self:wheelZoom(steps)
        return
    end
    if self.topdown ~= nil then
        self:topdownWheel(steps)
        return
    end
    self.flySpeed = M.clamp(self.flySpeed * E.FLY_SPEED_STEP ^ steps, E.FLY_SPEED_MIN, E.FLY_SPEED_MAX)
    self:showMessage(string.format(g_i18n:getText("cine_msg_flySpeed"), self.flySpeed))
end

-- Rozhlížení bez držení tlačítka: myš je v režimu rozhlížení skrytá a její pohyb chodí jako osa (stejně jako u hráče).
function CinemaEditorScreen:getLookStep(value, isMouse)
    if not self.freeLook or self.playing or self.menu ~= nil or self.topdown ~= nil then
        return 0
    end
    local scale = isMouse and E.LOOK_MOUSE or E.LOOK_STICK * g_currentDt
    local zoom = M.clamp(M.focalToFov(self.targetFocal) / M.focalToFov(E.LOOK_FOCAL_REF), 0.15, 1.5)
    return value * scale * g_gameSettings:getValue(GameSettings.SETTING.CAMERA_SENSITIVITY) * zoom
end

function CinemaEditorScreen:onActionLookX(_, value, _, _, isMouse)
    self.cam.yaw = self.cam.yaw - self:getLookStep(value, isMouse)
end

-- osa myši Y: kladná hodnota je pohyb dolů, kladný pitch je pohled dolů
function CinemaEditorScreen:onActionLookY(_, value, _, _, isMouse)
    if g_gameSettings:getValue(GameSettings.SETTING.INVERT_Y_LOOK) then
        value = -value
    end
    self.cam.pitch = M.clamp(self.cam.pitch + self:getLookStep(value, isMouse), -E.PITCH_LIMIT, E.PITCH_LIMIT)
end

-- Kurzor je vidět jen mimo rozhlížení a mimo přehrávání.
function CinemaEditorScreen:applyCursor()
    local show = not (self.freeLook or self.playing)
    if show == self.cursorShown then
        return
    end
    self.cursorShown = show
    g_inputBinding:setShowMouseCursor(show)
    if show then
        wrapMousePosition(0.5, 0.5)
    end
end

function CinemaEditorScreen:setFreeLook(on)
    self.freeLook = on
    self.drag = nil
    self:applyCursor()
end

-- Nástroje, které potřebují kurzor (výběr objektu, pohled shora, křivka), ho zapnou samy a po skončení vrátí rozhlížení.
function CinemaEditorScreen:needCursor()
    if self.freeLook then
        self.autoCursor = true
        self:setFreeLook(false)
    end
end

function CinemaEditorScreen:releaseCursor()
    if self.autoCursor and not self.picking and self.menu == nil and self.topdown == nil and not self.curves then
        self.autoCursor = false
        self:setFreeLook(true)
    end
end

-- Alt přepíná kurzor stejně jako F: za letu jde pak klikat na osu a do menu, dalším Altem se vrátí rozhlížení myší.
function CinemaEditorScreen:updateAltCursor()
    local down = E.isAlt()
    if self.altDown == nil then
        self.altDown = down -- Alt držený při otevření editoru (Alt+C) nic nepřepne
        return
    end
    if down and not self.altDown and not self.playing and self.topdown == nil and self.menu == nil then
        self.altAnchor = self.cursorShown and self.mouseX or nil
        self.altToggled = true
        self:onActionCursor()
    elseif not down then
        self.altAnchor, self.altToggled = nil, false
    end
    self.altDown = down
end

-- Boční panel s nabídkou vybraného řádku: vypnutý → vlevo → vpravo → vypnutý.
function CinemaEditorScreen:onActionDock()
    if self.playing then
        return
    end
    self.dock = self.dock == nil and "left" or (self.dock == "left" and "right" or nil)
    self:showMessage(g_i18n:getText("cine_msg_dock_" .. (self.dock or "off")))
end

function CinemaEditorScreen:onActionCursor()
    if self.playing or self.topdown ~= nil then
        return
    end
    self.autoCursor = false
    self:setFreeLook(not self.freeLook)
    self:showMessage(g_i18n:getText(self.freeLook and "cine_msg_lookOn" or "cine_msg_lookOff"))
end

---------------------------------------------------------------------------------------------------
-- stav

function CinemaEditorScreen:showMessage(text)
    self.message = text
    self.messageTimer = E.MESSAGE_TIME
end

function CinemaEditorScreen:markDirty()
    self.dirty = true
end

-- Akce a křivky efektů herce jsou při změně rychlosti přišpendlené k místu na trase, ne k času (kromě připnutých akcí):
-- před změnou se zapamatuje, kde na trase každá je (vzdálenost s a čas navíc, když tam herec stojí), po ní dostane čas,
-- kdy tam herec podle nového plánu jízdy bude.
function CinemaEditorScreen:keepOnRoute(actor, fn)
    local plan = actor ~= nil and not actor.pinActions and CinemaRoute.plan(actor) or nil
    if plan == nil then
        fn()
        return
    end
    local items = {}
    local function pin(item)
        if item.t > 0 then
            local _, _, s = CinemaRoute.positionAtTime(plan, item.t)
            items[#items + 1] = { item = item, s = s, extra = item.t - CinemaRoute.timeAtS(plan, s) }
        end
    end
    for _, action in ipairs(actor.actions or {}) do
        pin(action)
    end
    -- křivka rychlosti plán jízdy dělá, ta se nepřepočítává
    for id, ch in pairs(actor.curves or {}) do
        if id ~= "speed" then
            for _, pt in ipairs(ch.points or {}) do
                pin(pt)
            end
        end
    end
    fn()
    local after = CinemaRoute.plan(actor)
    if after == nil or after == plan then
        return
    end
    for _, a in ipairs(items) do
        a.item.t = math.max(CinemaRoute.timeAtS(after, a.s) + a.extra, 0)
    end
    CinemaActions.sortByTime(actor)
    for id, ch in pairs(actor.curves or {}) do
        if id ~= "speed" and ch.points ~= nil then
            table.sort(ch.points, function(p, q) return p.t < q.t end)
        end
    end
end

function CinemaEditorScreen:pushUndo()
    local snapshot = S.clone(self.shot)
    table.insert(self.undoStack, snapshot)
    if #self.undoStack > E.UNDO_LIMIT then
        table.remove(self.undoStack, 1)
    end
    self.redoStack = {}
    table.insert(self.history, { time = CinemaHistory.now(), snap = snapshot })
    if #self.history > CinemaHistory.MAX_ENTRIES then
        table.remove(self.history, 1)
    end
    self.historyDirty = true
end

function CinemaEditorScreen:afterHistory()
    if self.activeTarget > #self.shot.actors then
        self.activeTarget = 0
    end
    self.actorRt = {}
    self:syncDrivers()
    self:applyEnvironment()
    self:markDirty()
end

-- Prostředí podle záběru (čas, období, počasí); co záběr nenastavuje, se vrátí na původní hodnotu.
function CinemaEditorScreen:applyEnvironment(force)
    Env.apply(self.shot.env, self.envSaved, force)
end

-- Řidiči ve vozidlech podle záběru (actor.driver = jméno pomocníka); při úpravách a po zavření editoru se srovnají.
-- Do vozidla, kam nastupuje postava, se řidič nesází: sedí v něm až postava, a jen od nástupu do výstupu.
function CinemaEditorScreen:syncDrivers()
    local seated = {}
    for _, a in ipairs(self.shot.actors) do
        for _, action in ipairs(CinemaPerson.isPerson(a) and a.actions or {}) do
            if action.kind == "seat" and action.vehicle ~= nil then
                seated[action.vehicle] = true
            end
        end
    end
    local wanted = {}
    for _, a in ipairs(self.shot.actors) do
        local first = a.start ~= nil and a.start.entries[1] or nil
        if first ~= nil and a.driver ~= nil and not seated[first.uid] then
            wanted[first.uid] = a.driver
        end
    end
    for uid, name in pairs(self.drivers) do
        if wanted[uid] ~= name then
            local v = W.find(uid)
            if v ~= nil then
                W.setDriver(v, nil)
            end
            self.drivers[uid] = nil
        end
    end
    for uid, name in pairs(wanted) do
        if self.drivers[uid] ~= name then
            local v = W.find(uid)
            if v ~= nil and W.setDriver(v, name) then
                self.drivers[uid] = name
            end
        end
    end
end

function CinemaEditorScreen:clearDrivers()
    for uid in pairs(self.drivers) do
        local v = W.find(uid)
        if v ~= nil then
            W.setDriver(v, nil)
        end
    end
    self.drivers = {}
end

-- Záznamy historie se uloží (bez kroků, které nic nezměnily, a starších než týden).
function CinemaEditorScreen:saveHistory()
    if self.shot == nil or not self.historyDirty then
        return
    end
    local entries = CinemaHistory.prune(self.history, CinemaHistory.now())
    CinemaHistory.compact(entries, S.clone(self.shot))
    self.history = entries
    if CinemaStorage.saveHistory(self.shot.file or self.shot.name, entries) then
        self.historyDirty = false
    end
end

function CinemaEditorScreen:save(silent)
    local ok = CinemaStorage.save(self.shot)
    if ok then
        self.dirty = false
    end
    self:saveHistory()
    if not silent then
        self:showMessage(g_i18n:getText(ok and "cine_msg_saved" or "cine_msg_saveFailed"))
    end
end

function CinemaEditorScreen:setFocal(mm)
    self.targetFocal = M.clampFocal(mm)
    self:showMessage(string.format(g_i18n:getText("cine_msg_focal"), self.targetFocal))
end

function CinemaEditorScreen:selectKey(seg, index)
    self:setSelectedKey(seg, index)
    if self.topdown == nil then
        self:jumpToKey(seg, index)
    else
        self.playhead = seg.t + seg.track.keys[index].t
    end
end

-- Kamera skočí na pózu K-framu, playhead na jeho čas.
function CinemaEditorScreen:jumpToKey(seg, index)
    local k = seg ~= nil and seg.track.keys[index] or nil
    if k == nil then
        return
    end
    self.playhead = seg.t + k.t
    self:applyShotPose(self.playhead)
end

function CinemaEditorScreen:setPlayhead(t, moveCamera)
    self.playhead = math.max(0, t)
    if moveCamera then
        self:applyShotPose(self.playhead)
    end
    if not self.playing then
        self:applyTools(self.playhead)
    end
end

-- Póza záběru v čase t podle bloků (blocksPose), plus křivka zoomu, náklon a třes.
-- dt ~= nil = přehrávání: poloha vozidel se vyhlazuje podle skutečné jízdy; při náhledu se bere plánovaná poloha.
-- Kamera drží horizont: interpolace mezi keyframy (i fokus na objekt) jinak natáčí i kolem osy pohledu, takže se při
-- pohybu naklání. Bez náklonu se naklánění odstraní; s náklonem (shot.bank) se při otáčení naklání do zatáčky,
-- plynule podle rychlosti otáčení (jen při přehrávání, kde je znám čas kroku).
function CinemaEditorScreen:levelPose(q, t, dt)
    local yaw, pitch = M.quatToYawPitchRoll(q)
    local max = math.rad(self.shot.bank or 0)
    if max <= 0 or dt == nil or dt <= 0 then
        self.bankYaw, self.bankRoll = nil, nil
        return M.quatFromYawPitchRoll(yaw, pitch, 0)
    end
    local sec = dt * 0.001
    local rate = self.bankYaw ~= nil and M.angleDiff(self.bankYaw, yaw) / sec or 0
    self.bankYaw = yaw
    local target = M.clamp(rate / E.BANK_FULL_RATE, -1, 1) * max * E.BANK_SIGN
    self.bankRoll = M.damp(self.bankRoll or 0, target, E.BANK_SMOOTH, sec)
    return M.quatFromYawPitchRoll(yaw, pitch, self.bankRoll)
end

-- Póza bloku v čase t (bez navázání): Let podle K-framů s míření na body zájmu, sledování z bodu podle K-framů s natočením
-- na cíl, jinak podle režimu.
function CinemaEditorScreen:blockPose(seg, t, dt)
    local track = seg.track
    if S.hasKeys(track) then
        local x, y, z, q, focal = S.flightEvaluate(self.shot, track, t - seg.t)
        if x == nil then
            return nil
        end
        if track.mode == S.FLIGHT then
            return x, y, z, self:applyFocus(t, dt, x, y, z, q, focal), focal
        end
        return self:aimAtTarget(track, t, dt, x, y, z, q, focal, t - seg.t)
    end
    return self:modePose(seg, t, dt)
end

-- Kamera v x, y, z míří na cíl bloku, s odchylkou směru z K-framů (rel = čas v bloku); s automatickým zoomem drží jeho
-- velikost v obraze (ohnisko úměrné vzdálenosti). Bez cíle zůstane natočení z K-framu.
function CinemaEditorScreen:aimAtTarget(track, t, dt, x, y, z, q, focal, rel)
    local st = self:targetState(track.target, t, dt)
    if st == nil then
        return x, y, z, q, focal
    end
    local ly = st.y + (track.lookHeight or Mo.LOOK_HEIGHT)
    local yaw, pitch = M.yawPitchFromDirection(st.x - x, ly - y, st.z - z)
    local distance = math.sqrt((st.x - x) ^ 2 + (st.y - y) ^ 2 + (st.z - z) ^ 2)
    if dt ~= nil and self.targetFilters[track.target] ~= nil then
        self.targetFilters[track.target].distance = distance
    end
    if track.autoZoom and track.dist0 ~= nil then
        focal = M.clamp(focal * distance / track.dist0, M.FOCAL_MIN, M.FOCAL_MAX)
    end
    local aimYaw, aimPitch = S.keyAim(track, rel)
    return x, y, z, M.quatFromYawPitchRoll(yaw + aimYaw, pitch + aimPitch, 0), focal
end

-- Póza, na které blok skončil: při přehrávání ta, která se opravdu ukázala (vozidla jedou podle fyziky), jinak plánovaná.
function CinemaEditorScreen:blockEndPose(seg, dt)
    local held = dt ~= nil and self.heldPoses ~= nil and self.heldPoses[seg.id] or nil
    if held ~= nil then
        return held[1], held[2], held[3], held[4], held[5]
    end
    return self:blockPose(seg, S.segmentEnd(seg), nil)
end

-- Póza kamery v čase t podle bloků: v bloku jeho póza (s plynulým navázáním na předchozí blok, má-li ho), v mezeře poslední
-- póza předchozího bloku, před prvním blokem jeho první póza.
function CinemaEditorScreen:blocksPose(t, dt)
    local shot = self.shot
    local seg = S.segmentAt(shot, t)
    if seg == nil then
        local before = S.blockBefore(shot, t)
        if before ~= nil then
            return self:blockEndPose(before, dt)
        end
        local first = S.blockAfter(shot, t)
        if first == nil then
            return nil
        end
        return self:blockPose(first, first.t, dt)
    end
    local x, y, z, q, focal = self:blockPose(seg, t, dt)
    if x == nil then
        return nil
    end
    if dt ~= nil then
        self.heldPoses = self.heldPoses or {}
        self.heldPoses[seg.id] = { x, y, z, q, focal }
    end
    if seg.track.smooth then
        local blend = math.min(seg.track.blend or S.SMOOTH_BLEND, (seg.track.duration or 1) * 0.5)
        local w = blend > 1e-6 and M.smoothstep((t - seg.t) / blend) or 1
        local before = w < 1 and S.blockBefore(shot, seg.t) or nil
        local bx, by, bz, bq, bf
        if before ~= nil then
            bx, by, bz, bq, bf = self:blockEndPose(before, dt)
        end
        if bx ~= nil then
            x, y, z = bx + (x - bx) * w, by + (y - by) * w, bz + (z - bz) * w
            q = M.quatNlerp(bq, q, w)
            focal = bf * (focal / bf) ^ w
        end
    end
    return x, y, z, q, focal
end

function CinemaEditorScreen:evaluatePose(t, dt)
    local shot = self.shot
    if dt ~= nil then
        self:updateTargets(t, dt)
    end
    local x, y, z, q, focal = self:blocksPose(t, dt)
    if x == nil then
        return nil
    end
    local zoom = shot.curves ~= nil and shot.curves.zoom or nil
    if CinemaChannels.isActive(zoom, t) then
        focal = M.clampFocal(CinemaChannels.valueAt(zoom, t))
    end
    q = self:levelPose(q, t, dt)
    local seg = S.segmentAt(shot, t)
    local shake = seg ~= nil and seg.track.shake or shot.shake or 0
    if shake > 0 then
        local dyaw, dpitch, dx, dy, dz = S.shakeOffset(shake, t)
        local yaw, pitch, roll = M.quatToYawPitchRoll(q)
        q = M.quatFromYawPitchRoll(yaw + dyaw, pitch + dpitch, roll)
        x, y, z = x + dx, y + dy, z + dz
    end
    return x, y, z, q, focal
end

-- Filtry všech sledovaných objektů běží pořád (i mimo jejich úsek), aby po přepnutí nezaostávaly.
function CinemaEditorScreen:updateTargets(t, dt)
    for _, f in ipairs(self.shot.focus) do
        if f.target ~= nil then
            self:targetState(f.target, t, dt)
        end
    end
    for _, seg in ipairs(self.shot.segments) do
        if seg.track.target ~= nil then
            self:targetState(seg.track.target, t, dt)
        end
        if seg.track.target2 ~= nil then
            self:targetState(seg.track.target2, t, dt)
        end
    end
end

-- Místo cíle v obraze (0 = střed, ±1 = kraj) v čase t: z křivek kamery, jinak podle bodu zájmu f.
function CinemaEditorScreen:focusFraming(f, t)
    local curves = self.shot.curves
    local ox, oy = f.ox or 0, f.oy or 0
    if curves ~= nil and CinemaChannels.isActive(curves.aimX, t) then
        ox = CinemaChannels.valueAt(curves.aimX, t)
    end
    if curves ~= nil and CinemaChannels.isActive(curves.aimY, t) then
        oy = CinemaChannels.valueAt(curves.aimY, t)
    end
    return M.clamp(ox, -1, 1), M.clamp(oy, -1, 1)
end

-- Natočení podle bodů zájmu: kamera míří na aktuální objekt (na jeho místo v obraze), při přepnutí se plynule přetočí
-- z předchozího. Bez bodu zájmu (nebo s volným) platí natočení z K-framů.
function CinemaEditorScreen:applyFocus(t, dt, x, y, z, keyQ, focal)
    local focus = self.shot.focus
    if #focus == 0 then
        return keyQ
    end
    local zoom = self.shot.curves ~= nil and self.shot.curves.zoom or nil
    local lensFocal = CinemaChannels.isActive(zoom, t) and M.clampFocal(CinemaChannels.valueAt(zoom, t)) or focal or 35
    local states = {}
    for _, f in ipairs(focus) do
        if f.target ~= nil and states[f.target] == nil then
            states[f.target] = self:targetState(f.target, t, dt)
        end
    end
    local function aimAt(f)
        local st = f ~= nil and f.target ~= nil and states[f.target] or nil
        if st == nil then
            return keyQ
        end
        local ox, oy = self:focusFraming(f, t)
        local yaw, pitch = M.yawPitchFraming(st.x - x, st.y + (f.height or S.FOCUS_HEIGHT) - y, st.z - z, ox, oy,
            M.focalToFov(lensFocal), g_screenAspectRatio)
        return M.quatFromYawPitchRoll(yaw, pitch, 0)
    end
    local previous, current, u = S.focusAt(self.shot, t)
    if current == nil then
        return keyQ
    end
    if u >= 1 then
        return aimAt(current)
    end
    return M.quatNlerp(aimAt(previous), aimAt(current), u)
end

-- Poloha sledovaného objektu; při přehrávání vyhlazená, jinak přesná.
function CinemaEditorScreen:filterTarget(st, dt, uid)
    if dt == nil then
        return st
    end
    local f = self.targetFilters[uid]
    if f == nil then
        f = { x = st.x, y = st.y, z = st.z, heading = st.heading, time = g_time }
        self.targetFilters[uid] = f
        return f
    end
    if f.time == g_time then
        return f
    end
    f.time = g_time
    local sec = dt * 0.001
    local k = M.clamp((f.distance or 0) / E.TARGET_DISTANCE_REF, 1, E.TARGET_DISTANCE_MAX)
    f.x = M.damp(f.x, st.x, E.TARGET_DAMPING * k, sec)
    f.y = M.damp(f.y, st.y, E.TARGET_HEIGHT_DAMPING * k, sec)
    f.z = M.damp(f.z, st.z, E.TARGET_DAMPING * k, sec)
    f.heading = f.heading + M.angleDiff(f.heading, st.heading) * (1 - math.exp(-sec / (E.TARGET_HEADING_DAMPING * k)))
    return f
end

function CinemaEditorScreen:applyShotPose(t)
    local x, y, z, q, focal = self:evaluatePose(t, nil)
    if x == nil then
        return
    end
    self.vel = { 0, 0, 0 }
    self.targetFocal = focal
    Cam.setPose(self.cam, x, y, z, q, focal)
end

function CinemaEditorScreen:canPlay()
    for _, seg in ipairs(self.shot.segments) do
        if (seg.track.target ~= nil and self:targetName(seg.track.target) == nil)
            or (seg.track.target2 ~= nil and self:targetName(seg.track.target2) == nil) then
            return false, "cine_msg_targetMissing"
        end
    end
    if #self.shot.segments == 0 then
        return false, "cine_msg_needBlock"
    end
    local key, name, why = self:getActorBlocker()
    if key ~= nil then
        return false, key, name, why
    end
    return true
end

-- Text důvodu, proč se záběr nedá přehrát; nil, když jde.
function CinemaEditorScreen:getPlayBlockText()
    local ok, reason, name, why = self:canPlay()
    if ok then
        return nil
    end
    local text = g_i18n:getText(reason)
    if name ~= nil then
        text = why ~= nil and string.format(text, name, g_i18n:getText(why)) or string.format(text, name)
    end
    return text
end

function CinemaEditorScreen:startPlayback(t)
    local blocked = self:getPlayBlockText()
    if blocked ~= nil then
        self:showMessage(blocked)
        return
    end
    if self.topdown ~= nil then
        self:exitTopdown()
    end
    self.picking = false
    self:applyEnvironment(true)
    self.playing = true
    self.playTime = t
    self.playEnd = self:getPlaybackEnd()
    -- konec záběru platí jen pro přehrání, které začne před ním
    self.stopAt = self.shot.endMark ~= nil and t < self.shot.endMark - S.KEY_SNAP and self.shot.endMark or nil
    self.prerollLeft = self.shot.preroll
    self.bankYaw, self.bankRoll = nil, nil
    self.drag = nil
    self.targetFilters = {}
    self.heldPoses = {}
    self:applyCursor()
    -- vozidla se vrací na start jen při přehrání od začátku; od playheadu jedou odtamtud, kde stojí
    if t <= S.KEY_SNAP then
        self:resetActors(false)
    end
    self.fieldsWait = CinemaProps.fieldsBusy() or nil
    if self.fieldsWait then
        self:showMessage(g_i18n:getText("cine_status_fieldsWait"))
    end
    self:prepareActors(t)
    self:applyShotPose(t)
end

-- Všechny záběry za sebou od prvního (nebo od záběru first); další záběr naváže střihem, bez předstihu.
function CinemaEditorScreen:playAllShots(first)
    self:stopActors()
    self:saveAll()
    self.sequence = true
    self:openShot(first or 1)
    self:startPlayback(0)
    if not self.playing then
        self:advanceSequence()
    end
end

-- Další přehratelný záběr; nepřehratelné se přeskočí a editor zůstane na posledním přehraném.
function CinemaEditorScreen:advanceSequence()
    if not self.sequence then
        return false
    end
    for i = self.index.active + 1, #self.index.files do
        local candidate = CinemaStorage.load(self.index.files[i])
        if candidate ~= nil and #candidate.segments > 0 then
            local previous = self.index.active
            self:stopActors()
            self:openShot(i)
            if self:canPlay() then
                self:startPlayback(0)
                self.prerollLeft = 0
                return true
            end
            self:openShot(previous)
        end
    end
    self.sequence = nil
    return false
end

function CinemaEditorScreen:stopPlayback()
    self.sequence = nil
    self.playing = false
    self.fieldsWait = nil
    self.playhead = self.playTime or self.playhead
    self:stopActors()
    self:applyCursor()
end

-- Přehrávání běží do konce záběru, nebo dokud nedojede kamera i poslední vozidlo; kamera po svém konci drží poslední pózu.
function CinemaEditorScreen:getPlaybackEnd()
    if self.shot.endMark ~= nil then
        return self.shot.endMark
    end
    local finish = S.duration(self.shot)
    for i = 1, #self.shot.actors do
        finish = math.max(finish, self:actorEnd(i))
    end
    return finish
end

---------------------------------------------------------------------------------------------------
-- průběh

function CinemaEditorScreen:hasPersonActor()
    for _, a in ipairs(self.shot ~= nil and self.shot.actors or {}) do
        if a.person == CinemaPerson.PLAYER then
            return true
        end
    end
    return false
end

function CinemaEditorScreen:update(dt)
    CinemaEditorScreen:superClass().update(self, dt)
    if not self.cam.active then
        return
    end
    CinemaProps.updateFields()
    Env.hold(self.envSaved)
    if self.messageTimer > 0 then
        self.messageTimer = self.messageTimer - dt
    end
    self:updateAltCursor()
    self:releaseCursor()
    if self:hasPersonActor() then
        CinemaPerson.keepVisible()
        CinemaPerson.keepCamera(self.cam)
    end
    if not self.playing and self.shot ~= nil then
        self:syncVehiclesToPlayhead()
        self:syncDrivers()
        if CinemaPerson.syncExitPoints(self.shot.actors) then
            self:markDirty()
        end
    end
    CinemaPerson.syncHelpers(self.shot ~= nil and self.shot.actors or {}, self.playing and self.playTime or self.playhead, dt, self.playing)
    CinemaPerson.syncCarry(self.shot ~= nil and self.shot.actors or {}, self.playing and self.playTime or self.playhead)
    if CinemaDev ~= nil then CinemaDev.walk(self.shot ~= nil and self.shot.actors or {}, self.playTime or 0, self.playing) end
    if self.playing then
        self:updatePlayback(dt)
    elseif self.topdown ~= nil then
        self:updateHeld()
        self:updateTopdown(dt)
    else
        self:updateHeld()
        self:updateFlight(dt)
    end
    self.moveForward, self.moveSide, self.moveUp = 0, 0, 0
end

function CinemaEditorScreen:updatePlayback(dt)
    local dtSec = dt * 0.001
    self.playhead = self.playTime
    -- pole se nastavuje po snímcích: dokud úloha běží, kamera stojí na začátku a předstih ani čas neběží
    if self.fieldsWait then
        self.fieldsWait = CinemaProps.fieldsBusy() or nil
        return
    end
    if self.prerollLeft > 0 then
        self.prerollLeft = self.prerollLeft - dtSec
        local x, y, z, q, focal = self:evaluatePose(self.playTime, dt)
        if x ~= nil then
            Cam.setPose(self.cam, x, y, z, q, focal)
        end
        return
    end
    self.playTime = self.playTime + dtSec
    self.playhead = self.playTime
    self:updateActors(dt, self.playTime)
    if not self.sequence and self.stopAt ~= nil and self.playTime >= self.stopAt then
        self.playTime = self.stopAt
        self:stopPlayback()
        return
    end
    -- jeden záběr bez konce běží i za koncem kamery (drží poslední pózu), aby šlo počkat třeba na rozložení stroje
    -- a zastavit mezerníkem; přehrávání záběrů za sebou na konci střihne na další
    if self.sequence and self.playTime >= (self.playEnd or S.duration(self.shot)) then
        self.playTime = math.min(self.playTime, S.duration(self.shot))
        if not self:advanceSequence() then
            self:stopPlayback()
        end
        return
    end
    local x, y, z, q, focal = self:evaluatePose(math.min(self.playTime, S.duration(self.shot)), dt)
    if x == nil then
        self:stopPlayback()
        self:showMessage(g_i18n:getText("cine_msg_targetMissing"))
        return
    end
    Cam.setPose(self.cam, x, y, z, q, focal)
    self.targetFocal = focal
end

function CinemaEditorScreen:updateHeld()
    local anyHeld = false
    for _, h in pairs(self.held) do
        anyHeld = true
        if g_time >= h.next then
            h.next = g_time + E.REPEAT_INTERVAL
            self:nudgeSelected(h.direction)
        end
    end
    if not anyHeld then
        self.nudging = false
    end
end

function CinemaEditorScreen:updateFlight(dt)
    local cam = self.cam
    local dtSec = dt * 0.001
    local fwd, side, up = self.moveForward, self.moveSide, self.moveUp
    if isCtrl() or self.menu ~= nil then
        -- Ctrl+S / Ctrl+Z nemají kameru posunout
        fwd, side, up = 0, 0, 0
    end
    local speed = self.flySpeed * E.stepFactor()
    local fx, _, fz = M.forwardFromYawPitch(cam.yaw, 0)
    local rx, _, rz = M.rightFromYaw(cam.yaw)
    local length = math.sqrt(fwd * fwd + side * side)
    if length > 1 then
        fwd, side = fwd / length, side / length
    end
    local tx = (fx * fwd + rx * side) * speed
    local tz = (fz * fwd + rz * side) * speed
    local ty = M.clamp(up, -1, 1) * speed
    local v = self.vel
    v[1] = M.damp(v[1], tx, E.FLY_DAMPING, dtSec)
    v[2] = M.damp(v[2], ty, E.FLY_DAMPING, dtSec)
    v[3] = M.damp(v[3], tz, E.FLY_DAMPING, dtSec)
    local x, y, z = cam.x + v[1] * dtSec, cam.y + v[2] * dtSec, cam.z + v[3] * dtSec
    local ground = W.terrainY(x, z) + E.GROUND_CLEARANCE
    if y < ground then
        y = ground
        v[2] = math.max(v[2], 0)
    end
    local focal = math.exp(M.damp(math.log(cam.focal), math.log(self.targetFocal), E.FOCAL_DAMPING, dtSec))
    if math.abs(focal - self.targetFocal) < 0.01 then
        focal = self.targetFocal
    end
    Cam.setPose(cam, x, y, z, M.quatFromYawPitchRoll(cam.yaw, cam.pitch, cam.roll), focal)
end

function CinemaEditorScreen:draw()
    CinemaEditorScreen:superClass().draw(self)
    if not self.cam.active then
        return
    end
    if self.playing then
        if self.playTimeline then
            self:drawPlaybackTimeline()
        end
        return
    end
    -- během kreslení se rozvržení řádků nemění: spočítá se jednou
    self.layoutFrozen = nil
    self.layoutFrozen = self:rowLayout()
    self:drawEditor()
    self.layoutFrozen = nil
end
