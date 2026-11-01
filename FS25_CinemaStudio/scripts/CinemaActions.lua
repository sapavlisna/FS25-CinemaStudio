-- Akce vozidel na časové ose: světla, blinkry, motor, rozložení, nářadí dolů a zapnuto, korba, výsyp, houkačka a
-- ovládání dronů ze SprayDrone. Akce je { t, kind, value, entry, dur? }: t jsou sekundy od startu herce (posun bloku
-- vozidla posouvá i akce), entry 0 = celá souprava, jinak číslo článku soupravy; dur (jen u akcí, které jdou vypnout)
-- je doba, po které se zapnutý stav sám vypne (blinkr, světla, nářadí dole…). Každý druh má na ose vlastní řádek (lajnu).
-- Při přehrávání se akce provedou ve svém čase a po něm se vozidla vrátí do stavu před první akcí.

CinemaActions = CinemaActions or {}
local A = CinemaActions

local function log(level, ...)
    if Logging ~= nil and Logging[level] ~= nil then
        Logging[level](...)
    end
end

local function hasBit(mask, n)
    return math.floor(mask / 2 ^ n) % 2 == 1
end

local function withBit(mask, n, on)
    local has = hasBit(mask, n)
    if on and not has then
        return mask + 2 ^ n
    elseif not on and has then
        return mask - 2 ^ n
    end
    return mask
end

---------------------------------------------------------------------------------------------------
-- co vozidlo umí

local function lightsOf(v)
    local spec = v.spec_lights
    if spec ~= nil and (spec.numLightTypes or 0) > 0 and v.setLightsTypesMask ~= nil then
        return spec
    end
    return nil
end

local function setLightTypes(v, names, on)
    local spec = lightsOf(v)
    local mask = spec.lightsTypesMask or 0
    for _, name in ipairs(names) do
        if Lights[name] ~= nil then
            mask = withBit(mask, Lights[name], on)
        end
    end
    v:setLightsTypesMask(mask)
end

-- Spoje, na kterých jde nářadí spustit dolů: vozidlo samo (je-li zapřažené) a nářadí, které nese.
local function jointsOf(v)
    local list = {}
    local function add(attacher, index)
        local spec = attacher.spec_attacherJoints
        local desc = spec ~= nil and spec.attacherJoints[index] or nil
        if desc ~= nil and desc.allowsLowering then
            list[#list + 1] = { attacher = attacher, index = index }
        end
    end
    if v.getAttacherVehicle ~= nil then
        local attacher = v:getAttacherVehicle()
        if attacher ~= nil and attacher.getImplementByObject ~= nil then
            local implement = attacher:getImplementByObject(v)
            if implement ~= nil then
                add(attacher, implement.jointDescIndex)
            end
        end
    end
    if v.getAttachedImplements ~= nil then
        for _, implement in ipairs(v:getAttachedImplements()) do
            add(v, implement.jointDescIndex)
        end
    end
    return list
end

-- Nářadí, které jde zapnout: vozidlo samo i vše, co nese.
local function toolsOf(v)
    local list = {}
    local function visit(x)
        local spec = x.spec_turnOnVehicle
        if spec ~= nil and x.setIsTurnedOn ~= nil and not spec.isAlwaysTurnedOn then
            list[#list + 1] = x
        end
        if x.getAttachedImplements ~= nil then
            for _, implement in ipairs(x:getAttachedImplements()) do
                if implement.object ~= nil then
                    visit(implement.object)
                end
            end
        end
    end
    visit(v)
    return list
end

local DRONE_SPEC = "spec_FS25_SprayDroneTrailer.sprayDroneStation"

-- Hláška pro uživatele (editor si sem dosadí showMessage); nil = jen do logu.
A.notify = nil

-- Text klíče cizího módu: jeho texty zná jen jeho vlastní g_i18n.
local function modText(env, key)
    local i18n = env ~= nil and env.g_i18n or nil
    if i18n ~= nil and i18n.getText ~= nil then
        return i18n:getText(key)
    end
    return g_i18n ~= nil and g_i18n:getText(key) or tostring(key)
end

local function droneEnv(v)
    local env = _G["FS25_SprayDroneTrailer"]
    if env ~= nil and env.SprayDroneStation ~= nil and env.SprayDroneCommandEvent ~= nil
        and v[DRONE_SPEC] ~= nil and v.sprayDroneCommand ~= nil then
        return env
    end
    return nil
end

local function foldable(v)
    local spec = v.spec_foldable
    return spec ~= nil and spec.hasFoldingParts and v.setFoldState ~= nil
end

-- Složení / rozložení bez animace, rovnou do koncové polohy (jako hra při načtení uložené polohy).
local function foldNow(v, direction)
    local spec = v.spec_foldable
    for _, part in pairs(spec.foldingParts or {}) do
        if part.animationName ~= nil and v.stopAnimation ~= nil then
            v:stopAnimation(part.animationName, true)
        end
    end
    if Foldable ~= nil and Foldable.setAnimTime ~= nil then
        Foldable.setAnimTime(v, direction > 0 and 1 or 0, true)
    end
end

local function tippable(v)
    local spec = v.spec_trailer
    return spec ~= nil and (spec.tipSideCount or 0) > 0 and v.startTipping ~= nil
end

local function dischargeable(v)
    return v.spec_trailer ~= nil and v.spec_dischargeable ~= nil and v.setDischargeState ~= nil
end

local function pipeOf(v)
    local spec = v.spec_pipe
    return spec ~= nil and (spec.numStates or 0) >= 2 and v.setPipeState ~= nil
end

-- Courseplay: vozidlo, kterému hráč v Courseplay přiřadil trasu na poli (job se spouští a zastavuje jako klávesou CP).
-- Volání cizího módu jsou v pcall: jiná verze Courseplay nesmí shodit editor.
local function courseplayOf(v)
    local ok, result = pcall(function()
        return v.spec_motorized ~= nil and v.cpStartStopDriver ~= nil and v.hasCpCourse ~= nil and v.getIsAIActive ~= nil
            and v.stopCurrentAIJob ~= nil and v:hasCpCourse() and v.getCanStartCp ~= nil
    end)
    return ok and result == true
end

local function courseplayActive(v)
    local ok, result = pcall(function() return v.getIsCpActive ~= nil and v:getIsCpActive() == true end)
    return ok and result
end

local function motorOf(v)
    return v.spec_motorized ~= nil and v.startMotor ~= nil and v.stopMotor ~= nil and v.getIsMotorStarted ~= nil
end

local function uidOf(v)
    return CinemaWorld.uid(v)
end

local function attacherOf(v)
    local spec = v.spec_attacherJoints
    return spec ~= nil and spec.attacherJoints ~= nil and #spec.attacherJoints > 0 and v.attachImplement ~= nil
        and v.detachImplementByObject ~= nil
end

local function washableOf(v)
    local spec = v.spec_washable
    return spec ~= nil and spec.washableNodes ~= nil and #spec.washableNodes > 0 and v.setNodeDirtAmount ~= nil
end

local function wearableOf(v)
    local spec = v.spec_wearable
    if spec == nil then
        return false
    end
    return (spec.wearableNodes ~= nil and #spec.wearableNodes > 0 and v.setNodeWearAmount ~= nil) or v.setDamageAmount ~= nil
end

local function clamp01(value)
    return math.max(0, math.min(1, value))
end

-- Jednotky nádrží vozidla, které mají kapacitu: čísla fill unitů.
local function fillUnitsOf(v)
    local list = {}
    if v.spec_fillUnit == nil or v.getFillUnits == nil or v.getFillUnitCapacity == nil then
        return list
    end
    for i, unit in ipairs(v:getFillUnits()) do
        local index = unit.fillUnitIndex or i
        if (v:getFillUnitCapacity(index) or 0) > 0 then
            list[#list + 1] = index
        end
    end
    return list
end

A.fillUnits = fillUnitsOf

-- Druhy, které jednotka unit vozidla v pojme, seřazené podle názvu: { index, name, title }.
function A.fillTypesOf(v, unit)
    local list = {}
    local supported = v.getFillUnitSupportedFillTypes ~= nil and v:getFillUnitSupportedFillTypes(unit) or {}
    for index, ok in pairs(supported) do
        local ft = ok and g_fillTypeManager:getFillTypeByIndex(index) or nil
        if ft ~= nil then
            list[#list + 1] = { index = index, name = ft.name, title = ft.title or ft.name }
        end
    end
    table.sort(list, function(a, b) return a.title < b.title end)
    return list
end

local function fillTypeName(index)
    return index ~= nil and g_fillTypeManager:getFillTypeNameByIndex(index) or "UNKNOWN"
end

-- Obsah jednotky jako text "<DRUH>@<litry>" (hodnota stavu fill).
function A.formatFill(name, liters)
    return string.format("%s@%.1f", name or "UNKNOWN", liters or 0)
end

-- "<DRUH>@<litry>" → druh, litry; nil při vadném zápisu.
function A.parseFill(text)
    if type(text) ~= "string" then
        return nil
    end
    local name, liters = text:match("^%s*([%w_]+)%s*@%s*([%d%.]+)%s*$")
    if name == nil or tonumber(liters) == nil then
        return nil
    end
    return name:upper(), tonumber(liters)
end

-- Nastaví obsah jednotky na druh a litry. Vozidlo, které se při vyprázdnění odstraní (kanystr), se na dobu změny pojistí.
local function setFillUnit(v, index, name, liters)
    local spec = v.spec_fillUnit
    local target = name ~= "UNKNOWN" and g_fillTypeManager:getFillTypeIndexByName(name) or nil
    local farmId = v:getOwnerFarmId()
    local oldRemove = spec.removeVehicleIfEmpty
    spec.removeVehicleIfEmpty = false
    local ok, err = pcall(function()
        local level, current = v:getFillUnitFillLevel(index), v:getFillUnitFillType(index)
        if level > 0.001 and (target == nil or current ~= target or liters <= 0.001) then
            v:addFillUnitFillLevel(farmId, index, -level, current, ToolType.UNDEFINED, nil)
            level = 0
        end
        if target ~= nil and liters > 0.001 and v:getFillUnitSupportsFillType(index, target) then
            v:addFillUnitFillLevel(farmId, index, liters - level, target, ToolType.UNDEFINED, nil)
        end
    end)
    spec.removeVehicleIfEmpty = oldRemove
    if not ok then
        error(err, 0)
    end
end

local function averageNodes(nodes, field)
    local sum = 0
    for _, node in ipairs(nodes) do
        sum = sum + (node[field] or 0)
    end
    return #nodes > 0 and sum / #nodes or 0
end

-- Bedna s kanystry na vleku SprayDrone: sloty { fillType, liters } přímo ve stavu vozidla.
A.CANISTER_TYPES = {
    SDT_CONCENTRATE_FERTILIZER = "SDT_CONCENTRATE_FERTILIZER", FERTILIZER = "SDT_CONCENTRATE_FERTILIZER",
    LIQUIDFERTILIZER = "SDT_CONCENTRATE_FERTILIZER", SDT_CONCENTRATE_HERBICIDE = "SDT_CONCENTRATE_HERBICIDE",
    HERBICIDE = "SDT_CONCENTRATE_HERBICIDE", DIESEL = "DIESEL", UNKNOWN = "UNKNOWN",
}
A.CANISTER_LITERS = 20

-- "DRUH@litry;DRUH@litry" (litry bez @ = plný kanystr, UNKNOWN = prázdný slot) → seznam { fillType, liters } po slotech;
-- nil a důvod při neznámém druhu.
function A.parseCanisters(text)
    local list = {}
    for item in (text or ""):gmatch("[^;,]+") do
        local name, liters = item:match("^%s*([%w_]+)%s*@?%s*([%d%.]*)%s*$")
        local canonical = name ~= nil and A.CANISTER_TYPES[name:upper()] or nil
        if canonical == nil then
            return nil, "unknownType:" .. item
        end
        list[#list + 1] = { fillType = canonical, liters = tonumber(liters) or A.CANISTER_LITERS }
    end
    return list
end

-- Seznam zpět jako text; s trim bez prázdných slotů na konci.
function A.formatCanisters(list, trim)
    local parts = {}
    for _, c in ipairs(list) do
        parts[#parts + 1] = string.format("%s@%g", c.fillType, c.liters)
    end
    while trim and #list > 0 and #parts > 0 and list[#parts].fillType == "UNKNOWN" do
        parts[#parts] = nil
    end
    return table.concat(parts, ";")
end

-- Stručný popis obsahu: "2× Nafta, 1× Hnojivo" (název druhu z herního seznamu druhů, jinak jméno).
function A.canisterSummary(text)
    local list = A.parseCanisters(text)
    if list == nil or #list == 0 then
        return ""
    end
    local counts, order = {}, {}
    for _, c in ipairs(list) do
        if c.fillType ~= "UNKNOWN" then
            if counts[c.fillType] == nil then
                order[#order + 1] = c.fillType
                counts[c.fillType] = 0
            end
            counts[c.fillType] = counts[c.fillType] + 1
        end
    end
    local parts = {}
    for _, name in ipairs(order) do
        parts[#parts + 1] = string.format("%d× %s", counts[name], A.fillTitle(name))
    end
    return table.concat(parts, ", ")
end

-- Název druhu z herního seznamu druhů, jinak jméno.
function A.fillTitle(name)
    local index = FillType ~= nil and FillType[name] or nil
    if index ~= nil and g_fillTypeManager ~= nil and g_fillTypeManager.getFillTypeTitleByIndex ~= nil then
        return g_fillTypeManager:getFillTypeTitleByIndex(index) or name
    end
    return name
end

local function toolboxOf(v)
    local spec = v[DRONE_SPEC]
    local tb = spec ~= nil and spec.toolbox or nil
    if tb ~= nil and tb.canisters ~= nil and (tb.slots or 0) > 0 and FillType ~= nil and FillType.UNKNOWN ~= nil then
        return tb, spec
    end
    return nil
end

-- Skříň s kanystry vleku SprayDrone (vrata nebo víko ovládá jeho skript, ne animace z XML): { part, api } nebo nil.
local function toolboxDoorOf(v)
    local tb = toolboxOf(v)
    local env = _G["FS25_SprayDroneTrailer"]
    local api = env ~= nil and env.SprayDroneToolbox or nil
    if tb == nil or api == nil or api.setOpen == nil or tb.parts == nil or tb.parts[1] == nil then
        return nil
    end
    return tb.parts[1], api
end

local function setToolboxDoor(v, open, instant)
    local part, api = toolboxDoorOf(v)
    api.setOpen(v, open, part)
    if instant and api.applyLid ~= nil then
        part.lidT = open and 1 or 0
        api.applyLid(part)
    end
end

-- Motor přenosné pumpy (nebo násypky) SprayDrone: spec a API pumpy, nebo nil.
local function pumpOf(v)
    local env = _G["FS25_SprayDroneTrailer"]
    local api = env ~= nil and env.SprayDronePump or nil
    local spec = api ~= nil and v[api.SPEC_NAME] or nil
    if spec == nil or v.sprayDronePumpCommand == nil then
        return nil
    end
    return spec, api
end

local function setPump(v, on)
    local _, api = pumpOf(v)
    v:sprayDronePumpCommand(on and api.CMD_ENGINE_ON or api.CMD_ENGINE_OFF)
end

-- Počet slotů bedny vozidla, nebo nil, když ji nemá.
function A.toolboxSlots(v)
    local tb = toolboxOf(v)
    return tb ~= nil and tb.slots or nil
end

-- Zapíše sloty bedny: list = { { fillType = "DRUH", liters } }, další sloty se vyprázdní. Stav jde i klientům.
local function writeCanisters(v, list)
    local tb, spec = toolboxOf(v)
    for i = 1, tb.slots do
        local item, c = list[i], tb.canisters[i]
        local index = item ~= nil and FillType[item.fillType] or nil
        if index ~= nil then
            c.fillType, c.liters = index, math.min(item.liters, tb.slotLiters or A.CANISTER_LITERS)
        else
            c.fillType, c.liters = FillType.UNKNOWN, 0
        end
    end
    if v.raiseDirtyFlags ~= nil and spec.dirtyFlag ~= nil then
        v:raiseDirtyFlags(spec.dirtyFlag)
    end
    local env = droneEnv(v)
    if env ~= nil and env.SprayDroneToolbox ~= nil and env.SprayDroneToolbox.updateCanisterVisuals ~= nil then
        pcall(env.SprayDroneToolbox.updateCanisterVisuals, tb)
    end
    -- víko bedny je otevřené, jen když v ní něco je, aby kanystry byly vidět
    local open = #list > 0
    if env ~= nil and env.SprayDroneToolbox ~= nil and env.SprayDroneToolbox.setOpen ~= nil then
        for _, part in ipairs(tb.parts or {}) do
            pcall(env.SprayDroneToolbox.setOpen, v, open, part)
        end
    end
end

local function readCanisters(v)
    local tb = toolboxOf(v)
    local list = {}
    for i = 1, tb.slots do
        local c = tb.canisters[i]
        if c.fillType ~= FillType.UNKNOWN and (c.liters or 0) > 0.001 then
            list[i] = { fillType = fillTypeName(c.fillType), liters = c.liters }
        else
            list[i] = { fillType = "UNKNOWN", liters = 0 }
        end
    end
    return list
end

-- Zapřažený vlek s jeho spoji, aby šel po přehrávání vrátit: { uid, input, joint }.
local function jointOfImplement(attacher, object)
    for _, implement in ipairs(attacher:getAttachedImplements()) do
        if implement.object == object then
            return { uid = uidOf(object), input = object:getActiveInputAttacherJointDescIndex(), joint = implement.jointDescIndex }
        end
    end
    return nil
end

local function animationsOf(v)
    local spec = v.spec_animatedVehicle
    return spec ~= nil and spec.animations ~= nil and next(spec.animations) ~= nil and v.playAnimation ~= nil and v.setAnimationTime ~= nil
end

-- Animace vozidla, které jdou otevřít a zavřít (dveře, okna, zrcátka…), podle jména.
function A.animationNames(v)
    local list = {}
    if v ~= nil and animationsOf(v) then
        for name in pairs(v.spec_animatedVehicle.animations) do
            list[#list + 1] = name
        end
        table.sort(list)
    end
    return list
end

local function setAnimation(v, name, value, instant)
    if v.getAnimationExists ~= nil and not v:getAnimationExists(name) then
        return
    end
    if instant then
        v:setAnimationTime(name, value == 1 and 1 or 0, true)
    else
        v:playAnimation(name, value == 1 and 1 or -1, v:getAnimationTime(name), true)
    end
end

-- Druhy akcí v pořadí nabídky. group = stav, který se po přehrávání vrací; values = hodnoty (1 zap / 0 vyp, u blinkrů 0..3,
-- u druhů s blink = true hodnota A.BLINK = blikání: počet bliknutí určuje délka akce).
A.KINDS = {
    lights = { group = "lights", values = { 1, 0, 2 }, light = true, blink = true,
        available = lightsOf,
        apply = function(v, value) setLightTypes(v, { "LIGHT_TYPE_DEFAULT" }, value == 1) end },
    workLights = { group = "lights", values = { 1, 0, 2 }, light = true, blink = true,
        available = lightsOf,
        apply = function(v, value) setLightTypes(v, { "LIGHT_TYPE_WORK_FRONT", "LIGHT_TYPE_WORK_BACK" }, value == 1) end },
    highBeam = { group = "lights", values = { 1, 0, 2 }, light = true, blink = true,
        available = lightsOf,
        apply = function(v, value) setLightTypes(v, { "LIGHT_TYPE_HIGHBEAM" }, value == 1) end },
    beacon = { group = "lights", values = { 1, 0 }, light = true,
        available = function(v)
            local spec = lightsOf(v)
            return spec ~= nil and v.setBeaconLightsVisibility ~= nil and next(spec.beaconLights or {}) ~= nil
        end,
        apply = function(v, value) v:setBeaconLightsVisibility(value == 1) end },
    turn = { group = "lights", values = { 1, 2, 3, 0 }, light = true,
        available = function(v) return lightsOf(v) ~= nil and v.setTurnLightState ~= nil end,
        apply = function(v, value)
            local states = { [0] = Lights.TURNLIGHT_OFF, Lights.TURNLIGHT_LEFT, Lights.TURNLIGHT_RIGHT, Lights.TURNLIGHT_HAZARD }
            v:setTurnLightState(states[value])
        end },
    motor = { group = "motor", values = { 1, 0 },
        available = motorOf,
        apply = function(v, value, ctx)
            if value == 1 then
                if not v:getIsMotorStarted() then
                    v:startMotor()
                end
            elseif v:getIsMotorStarted() then
                v:stopMotor()
            end
            ctx.motorWanted[uidOf(v)] = value == 1
        end },
    courseplay = { group = "courseplay", values = { 1, 0 }, noPreview = true,
        available = courseplayOf,
        apply = function(v, value)
            if value == 1 then
                if not v:getIsAIActive() then
                    v:cpStartStopDriver()
                end
            elseif courseplayActive(v) then
                v:stopCurrentAIJob(AIMessageSuccessStoppedByUser.new())
            end
        end },
    fold = { group = "fold", values = { 1, 0 },
        available = foldable,
        apply = function(v, value, ctx)
            local direction = (v.spec_foldable.turnOnFoldDirection or 1) * (value == 1 and 1 or -1)
            v:setFoldState(direction, false)
            if ctx ~= nil and ctx.instant then
                foldNow(v, direction)
            end
        end },
    lower = { group = "lower", values = { 1, 0 },
        available = function(v) return #jointsOf(v) > 0 end,
        apply = function(v, value)
            for _, j in ipairs(jointsOf(v)) do
                j.attacher:setJointMoveDown(j.index, value == 1)
            end
        end },
    turnOn = { group = "turnOn", values = { 1, 0 },
        available = function(v) return #toolsOf(v) > 0 end,
        apply = function(v, value)
            for _, tool in ipairs(toolsOf(v)) do
                if value ~= 1 then
                    tool:setIsTurnedOn(false)
                elseif tool.getCanBeTurnedOn == nil or tool:getCanBeTurnedOn() then
                    tool:setIsTurnedOn(true)
                end
            end
        end },
    tip = { group = "tip", values = { 1, 0 },
        available = tippable,
        apply = function(v, value)
            local open = v:getTipState() ~= Trailer.TIPSTATE_CLOSED
            if value == 1 and not open then
                v:startTipping()
            elseif value ~= 1 and open then
                v:stopTipping()
            end
        end },
    discharge = { group = "discharge", values = { 1, 0 },
        available = dischargeable,
        apply = function(v, value)
            v:setDischargeState(value == 1 and Dischargeable.DISCHARGE_STATE_GROUND or Dischargeable.DISCHARGE_STATE_OFF)
        end },
    pipe = { group = "pipe", values = { 1, 0 },
        available = pipeOf,
        apply = function(v, value) v:setPipeState(value == 1 and math.min(2, v.spec_pipe.numStates) or 1) end },
    honk = { group = "honk", values = { 1 },
        available = function(v) return v.spec_honk ~= nil and v.playHonk ~= nil end,
        apply = function(v, _, ctx)
            v:playHonk(true)
            ctx.timers[#ctx.timers + 1] = { left = 1, fn = function() v:playHonk(false) end }
        end },
    droneStart = { group = "drone", values = { 1 },
        available = function(v) return droneEnv(v) ~= nil end,
        apply = function(v)
            local env = droneEnv(v)
            -- záběr se točí pořád znovu: pole se vždy letí od začátku (paměť dronu, kde už postříkal, se smaže) a plán
            -- se přepočítá hned, ne až v dalších snímcích
            if env.SprayDroneCommandEvent.RESET_FIELD ~= nil then
                v:sprayDroneCommand(env.SprayDroneCommandEvent.RESET_FIELD, 0)
                if env.SprayDroneDrones ~= nil and env.SprayDroneStation.updateRoutePreview ~= nil then
                    env.SprayDroneDrones.forEach(v, env.SprayDroneStation.updateRoutePreview)
                end
            end
            local warning = env.SprayDroneStation.startFlight(v)
            if warning ~= nil then
                local text = modText(env, warning)
                log("warning", "CinemaStudio: drone did not start: %s", text)
                if A.notify ~= nil then
                    A.notify(text)
                end
            end
        end },
    droneHome = { group = "drone", values = { 1 },
        available = function(v) return droneEnv(v) ~= nil end,
        apply = function(v)
            local env = droneEnv(v)
            v:sprayDroneCommand(env.SprayDroneCommandEvent.RETURN_HOME, 0, nil, 0)
        end },
    droneGenerator = { group = "drone", values = { 1, 0 },
        available = function(v) return droneEnv(v) ~= nil end,
        apply = function(v, value)
            local env = droneEnv(v)
            v:sprayDroneCommand(env.SprayDroneCommandEvent.SET_GENERATOR, value)
        end },
    -- zapřažení vlek (payload = true: cíl je v action.vehicle, vybírá se z menu s cílem, ne obecnou nabídkou); vlek bez cíle
    -- při odpojení odpojí vše, co vozidlo nese
    attach = { group = "attach", values = { 1, 0 }, payload = true, noPreview = true,
        available = attacherOf,
        apply = function(v, value, ctx)
            local uid = ctx.action ~= nil and ctx.action.vehicle or nil
            local target = uid ~= nil and CinemaWorld.find(uid) or nil
            if value == 1 then
                if target == nil then
                    log("warning", "CinemaStudio: attach: trailer %s not found", tostring(uid))
                    return
                end
                local ok, why = CinemaWorld.attach(v, target)
                if not ok then
                    log("warning", "CinemaStudio: attach failed: %s", tostring(why))
                end
            else
                CinemaWorld.detach(v, target)
            end
        end },
    -- obsah bedny vleku SprayDrone (action.items = "DRUH@litry;…"); 0 bednu vyprázdní
    canisters = { group = "canisters", values = { 1, 0 }, payload = true,
        available = function(v) return toolboxOf(v) ~= nil end,
        apply = function(v, value, ctx)
            local list = value == 1 and A.parseCanisters(ctx.action ~= nil and ctx.action.items or "") or {}
            writeCanisters(v, list or {})
        end },
    -- motor pumpy SprayDrone: bez nafty v pumpě nenaskočí (stejně jako ve hře)
    pump = { group = "pump", values = { 1, 0 },
        available = function(v) return pumpOf(v) ~= nil end,
        apply = function(v, value) setPump(v, value == 1) end },
    toolboxDoor = { group = "toolboxDoor", values = { 1, 0 },
        available = function(v) return toolboxDoorOf(v) ~= nil end,
        apply = function(v, value, ctx) setToolboxDoor(v, value == 1, ctx ~= nil and ctx.instant) end },
    -- spojité stavy: jen se startem herce (A.STATE_ORDER), na ose nejsou; apply dostane v ctx.sub číslo jednotky
    dirt = { group = "dirt", values = {}, stateOnly = true,
        available = washableOf,
        apply = function(v, value)
            for _, node in ipairs(v.spec_washable.washableNodes) do
                v:setNodeDirtAmount(node, clamp01(value), true)
            end
        end },
    wear = { group = "wear", values = {}, stateOnly = true,
        available = wearableOf,
        apply = function(v, value)
            value = clamp01(value)
            if v.setDamageAmount ~= nil then
                v:setDamageAmount(value, true)
            end
            for _, node in ipairs(v.spec_wearable.wearableNodes or {}) do
                if v.setNodeWearAmount ~= nil then
                    v:setNodeWearAmount(node, value, true)
                end
            end
        end },
    fill = { group = "fill", values = {}, stateOnly = true,
        available = function(v) return #fillUnitsOf(v) > 0 end,
        apply = function(v, value, ctx)
            local name, liters = A.parseFill(value)
            if name ~= nil and ctx.sub ~= nil then
                setFillUnit(v, ctx.sub, name, liters)
            end
        end },
    toolbox = { group = "toolbox", values = {}, stateOnly = true,
        available = function(v) return toolboxOf(v) ~= nil end,
        apply = function(v, value) writeCanisters(v, A.parseCanisters(value) or {}) end },
    -- akce postavy (person = true): vozidlo nese akce v action.vehicle (uid), animace v action.anim; u pomocníka se
    -- nástup neprovádí tady, ale podle času v CinemaPerson.syncHelpers
    seat = { group = "seat", values = { 1, 0 }, person = true,
        available = function(v) return v.spec_enterable ~= nil end,
        apply = function(v, value)
            if value == 1 then
                CinemaPerson.enter(v)
            else
                CinemaPerson.leave()
            end
        end },
    door = { group = "door", values = { 1, 0 }, person = true,
        available = animationsOf,
        apply = function(v, value, ctx) setAnimation(v, ctx.action.anim, value, ctx.instant) end },
    -- postava nese předmět ze světa (action.carry) po dobu akce; drží ho CinemaPerson.syncCarry podle času
    carry = { group = "carry", values = { 1, 0 }, person = true, noVehicle = true,
        available = function() return true end, apply = function() end },
    -- akce objektů ve světě (world = true, CinemaObjects): cíl je obal { uniqueId, anim | placeable }, action.sub vybírá
    -- skupinu světel nebo výrobu budovy
    gate = { group = "gate", values = { 1, 0 }, world = true,
        available = function(t) return t.anim ~= nil end,
        apply = function(t, value, ctx) CinemaObjects.setAnimOpen(t.anim, value == 1, ctx ~= nil and ctx.instant) end },
    lamp = { group = "lamp", values = { 1, 0 }, world = true, sub = true,
        available = function(t) return t.placeable ~= nil and CinemaObjects.lightGroups(t.placeable) ~= nil end,
        apply = function(t, value, ctx) t.placeable:setGroupIsActive(ctx.action.sub, value == 1) end },
    -- vodní hadice SprayDrone (vlek, pumpa), jen u strojů mezi objekty: sub = číslo hadice, action.link = zapojení zapamatované
    -- při přidání akce (bez link hadici odpojí)
    hose = { group = "hose", values = { 1, 0 }, sub = true, objectOnly = true,
        available = function(v) return CinemaObjects.hoseSpec(v) ~= nil end,
        apply = function(v, value, ctx) CinemaObjects.applyHose(v, ctx.action.sub, value == 1 and ctx.action.link or nil) end },
    production = { group = "production", values = { 1, 0 }, world = true, sub = true,
        available = function(t) return t.placeable ~= nil and CinemaObjects.productionPoint(t.placeable) ~= nil end,
        apply = function(t, value, ctx)
            CinemaObjects.productionPoint(t.placeable):setProductionState(ctx.action.sub, value == 1)
        end },
}

A.ORDER = { "lights", "workLights", "highBeam", "beacon", "turn", "motor", "courseplay", "fold", "lower", "turnOn", "tip", "discharge",
    "pipe", "honk", "droneStart", "droneHome", "droneGenerator", "hose", "attach", "canisters", "toolboxDoor", "pump", "seat", "door", "carry", "gate", "lamp", "production" }

-- Spojité stavy herce (A.KINDS se stateOnly): čtou se jen při zapamatování startu, ne při nahrávání jízdy.
A.STATE_ORDER = { "dirt", "wear", "fill", "toolbox" }

-- Stav, který se před první akcí zapamatuje a po přehrávání vrátí: capture(v) → data, restore(v, data).
A.GROUPS = {
    lights = {
        capture = function(v)
            local spec = lightsOf(v)
            if spec == nil then
                return nil
            end
            return { mask = spec.lightsTypesMask or 0, turn = spec.turnLightState, beacon = spec.beaconLightsActive }
        end,
        restore = function(v, snap)
            if snap.turn ~= nil and v.setTurnLightState ~= nil then
                v:setTurnLightState(snap.turn)
            end
            if snap.beacon ~= nil and v.setBeaconLightsVisibility ~= nil then
                v:setBeaconLightsVisibility(snap.beacon)
            end
            v:setLightsTypesMask(snap.mask)
        end,
    },
    motor = {
        capture = function(v) return motorOf(v) and { on = v:getIsMotorStarted() } or nil end,
        restore = function(v, snap)
            if snap.on and not v:getIsMotorStarted() then
                v:startMotor()
            elseif not snap.on and v:getIsMotorStarted() then
                v:stopMotor()
            end
        end,
    },
    courseplay = {
        capture = function(v) return courseplayOf(v) and { active = courseplayActive(v) } or nil end,
        restore = function(v, snap)
            if not snap.active and courseplayActive(v) then
                v:stopCurrentAIJob(AIMessageSuccessStoppedByUser.new())
            end
        end,
    },
    fold = {
        capture = function(v) return foldable(v) and { unfolded = v:getIsUnfolded() } or nil end,
        restore = function(v, snap)
            if v:getIsUnfolded() ~= snap.unfolded then
                A.KINDS.fold.apply(v, snap.unfolded and 1 or 0, { instant = true })
            end
        end,
    },
    lower = {
        capture = function(v)
            local list = {}
            for _, j in ipairs(jointsOf(v)) do
                list[#list + 1] = { attacher = j.attacher, index = j.index, down = j.attacher:getJointMoveDown(j.index) }
            end
            return #list > 0 and list or nil
        end,
        restore = function(_, snap)
            for _, j in ipairs(snap) do
                j.attacher:setJointMoveDown(j.index, j.down)
            end
        end,
    },
    turnOn = {
        capture = function(v)
            local list = {}
            for _, tool in ipairs(toolsOf(v)) do
                list[#list + 1] = { tool = tool, on = tool:getIsTurnedOn() }
            end
            return #list > 0 and list or nil
        end,
        restore = function(_, snap)
            for _, s in ipairs(snap) do
                s.tool:setIsTurnedOn(s.on)
            end
        end,
    },
    tip = {
        capture = function(v) return tippable(v) and { open = v:getTipState() ~= Trailer.TIPSTATE_CLOSED } or nil end,
        restore = function(v, snap)
            if not snap.open and v:getTipState() ~= Trailer.TIPSTATE_CLOSED then
                v:stopTipping()
            end
        end,
    },
    discharge = {
        capture = function(v) return dischargeable(v) and { state = v:getDischargeState() } or nil end,
        restore = function(v, snap) v:setDischargeState(snap.state) end,
    },
    pipe = {
        capture = function(v) return pipeOf(v) and { state = v.spec_pipe.targetState } or nil end,
        restore = function(v, snap) v:setPipeState(snap.state) end,
    },
    honk = {
        capture = function() return nil end,
        restore = function() end,
    },
    drone = {
        capture = function(v)
            local env = droneEnv(v)
            if env == nil then
                return nil
            end
            return { generator = v[DRONE_SPEC].generatorEnabled, mission = env.SprayDroneStation.getAnyMissionActive(v) }
        end,
        restore = function(v, snap)
            local env = droneEnv(v)
            if env == nil then
                return
            end
            if v[DRONE_SPEC].generatorEnabled ~= snap.generator then
                v:sprayDroneCommand(env.SprayDroneCommandEvent.SET_GENERATOR, snap.generator and 1 or 0)
            end
            if not snap.mission and env.SprayDroneStation.getAnyMissionActive(v) then
                v:sprayDroneCommand(env.SprayDroneCommandEvent.RETURN_HOME, 0, nil, 0)
            end
        end,
    },
    attach = {
        capture = function(v, action)
            local target = action ~= nil and action.vehicle ~= nil and CinemaWorld.find(action.vehicle) or nil
            local snap = { joints = {}, target = target ~= nil and uidOf(target) or nil }
            for _, implement in ipairs(v:getAttachedImplements()) do
                snap.joints[#snap.joints + 1] = jointOfImplement(v, implement.object)
            end
            local other = target ~= nil and target:getAttacherVehicle() or nil
            if other ~= nil and other ~= v then
                snap.otherUid, snap.other = uidOf(other), jointOfImplement(other, target)
            end
            return snap
        end,
        restore = function(v, snap)
            local keep = {}
            for _, j in ipairs(snap.joints) do
                keep[j.uid] = true
            end
            local current = {}
            for _, implement in ipairs(v:getAttachedImplements()) do
                current[#current + 1] = implement.object
            end
            for _, object in ipairs(current) do
                if not keep[uidOf(object)] then
                    v:detachImplementByObject(object, true)
                end
            end
            local function reattach(attacher, j)
                local object = CinemaWorld.find(j.uid)
                if object ~= nil and object:getAttacherVehicle() == nil then
                    CinemaWorld.attach(attacher, object, j.joint, j.input)
                end
            end
            for _, j in ipairs(snap.joints) do
                reattach(v, j)
            end
            local other = snap.otherUid ~= nil and CinemaWorld.find(snap.otherUid) or nil
            if other ~= nil and snap.other ~= nil then
                reattach(other, snap.other)
            end
        end,
    },
    canisters = {
        capture = function(v) return { list = readCanisters(v) } end,
        restore = function(v, snap) writeCanisters(v, snap.list) end,
    },
    pump = {
        capture = function(v) return { on = pumpOf(v).engineOn == true } end,
        restore = function(v, snap) setPump(v, snap.on) end,
    },
    toolboxDoor = {
        capture = function(v) return { open = toolboxDoorOf(v).open == true } end,
        restore = function(v, snap) setToolboxDoor(v, snap.open, true) end,
    },
    -- v čem hráč seděl (uid kořene soupravy, nebo false venku)
    seat = {
        capture = function()
            local current = CinemaPerson.playerVehicle()
            return { inside = current ~= nil and uidOf(current) or false }
        end,
        restore = function(_, snap)
            local current = CinemaPerson.playerVehicle()
            if snap.inside == false then
                CinemaPerson.leave()
            elseif current == nil or uidOf(current) ~= snap.inside then
                local v = CinemaWorld.find(snap.inside)
                if v ~= nil then
                    CinemaPerson.enter(v)
                end
            end
        end,
    },
    door = {
        capture = function(v, action)
            return { anim = action.anim, time = v:getAnimationTime(action.anim) }
        end,
        restore = function(v, snap) v:setAnimationTime(snap.anim, snap.time, true) end,
    },
    hose = {
        capture = function(v, action) return { sub = action.sub, link = CinemaObjects.readHose(v, action.sub) or false } end,
        restore = function(v, snap) CinemaObjects.applyHose(v, snap.sub, snap.link or nil) end,
    },
    gate = {
        capture = function(t) return { time = t.anim.animation.time } end,
        restore = function(t, snap) CinemaObjects.setAnimTime(t.anim, snap.time) end,
    },
    lamp = {
        capture = function(t, action)
            local group = CinemaObjects.lightGroups(t.placeable)[action.sub]
            return group ~= nil and { sub = action.sub, on = group.isActive ~= false } or nil
        end,
        restore = function(t, snap) t.placeable:setGroupIsActive(snap.sub, snap.on) end,
    },
    production = {
        capture = function(t, action)
            return { sub = action.sub, on = CinemaObjects.productionEnabled(CinemaObjects.productionPoint(t.placeable), action.sub) }
        end,
        restore = function(t, snap) CinemaObjects.productionPoint(t.placeable):setProductionState(snap.sub, snap.on) end,
    },
}

-- Čtení stavu pro nahrávání jízdy: scope "root" = celá souprava, čte se z prvního vozidla, "entry" = každý článek soupravy zvlášť.
-- Hodnota je stejná jako hodnota akce daného druhu (1 zapnuto, 0 vypnuto, u blinkrů 0..3).
local function lightBit(v, name)
    local spec = lightsOf(v)
    return Lights[name] ~= nil and hasBit(spec.lightsTypesMask or 0, Lights[name]) and 1 or 0
end

A.READERS = {
    lights = { scope = "root", read = function(v) return lightBit(v, "LIGHT_TYPE_DEFAULT") end },
    workLights = { scope = "root", read = function(v)
        return math.max(lightBit(v, "LIGHT_TYPE_WORK_FRONT"), lightBit(v, "LIGHT_TYPE_WORK_BACK"))
    end },
    highBeam = { scope = "root", read = function(v) return lightBit(v, "LIGHT_TYPE_HIGHBEAM") end },
    beacon = { scope = "root", read = function(v) return lightsOf(v).beaconLightsActive and 1 or 0 end },
    turn = { scope = "root", read = function(v)
        local state = lightsOf(v).turnLightState
        if state == Lights.TURNLIGHT_LEFT then
            return 1
        elseif state == Lights.TURNLIGHT_RIGHT then
            return 2
        elseif state == Lights.TURNLIGHT_HAZARD then
            return 3
        end
        return 0
    end },
    lower = { scope = "root", read = function(v)
        for _, j in ipairs(jointsOf(v)) do
            if j.attacher:getJointMoveDown(j.index) then
                return 1
            end
        end
        return 0
    end },
    turnOn = { scope = "root", read = function(v)
        for _, tool in ipairs(toolsOf(v)) do
            if tool:getIsTurnedOn() then
                return 1
            end
        end
        return 0
    end },
    fold = { scope = "entry", read = function(v) return v:getIsUnfolded() and 1 or 0 end },
    tip = { scope = "entry", read = function(v) return v:getTipState() ~= Trailer.TIPSTATE_CLOSED and 1 or 0 end },
    discharge = { scope = "entry", read = function(v) return v:getDischargeState() ~= Dischargeable.DISCHARGE_STATE_OFF and 1 or 0 end },
    pipe = { scope = "entry", read = function(v) return v.spec_pipe.targetState >= 2 and 1 or 0 end },
    toolboxDoor = { scope = "entry", read = function(v) return toolboxDoorOf(v).open and 1 or 0 end },
    pump = { scope = "entry", read = function(v) return pumpOf(v).engineOn and 1 or 0 end },
}

-- Spojité stavy: špína a opotřebení 0..1 (průměr přes uzly), obsah jednotek nádrží "<DRUH>@<litry>" a obsah bedny SprayDrone
-- "DRUH@litry;…". Čtou se po článcích; units(v) rozdělí článek na víc klíčů (jednotky nádrží), tolerance je největší
-- rozdíl, který se ještě bere jako stejná hodnota.
A.READERS.dirt = { scope = "entry", tolerance = 0.01, read = function(v)
    return averageNodes(v.spec_washable.washableNodes, "dirtAmount")
end }
A.READERS.wear = { scope = "entry", tolerance = 0.01, read = function(v)
    if v.getWearTotalAmount ~= nil then
        return v:getWearTotalAmount()
    end
    return v.getDamageAmount ~= nil and v:getDamageAmount() or 0
end }
A.READERS.fill = { scope = "entry", units = fillUnitsOf, tolerance = 0.5, read = function(v, unit)
    return A.formatFill(fillTypeName(v:getFillUnitFillType(unit)), v:getFillUnitFillLevel(unit))
end }
A.READERS.toolbox = { scope = "entry", read = function(v) return A.formatCanisters(readCanisters(v), true) end }

local function sameState(reader, a, b)
    if type(a) == "number" and type(b) == "number" then
        return math.abs(a - b) <= (reader.tolerance or 0)
    end
    if reader == A.READERS.fill then
        local nameA, litersA = A.parseFill(a)
        local nameB, litersB = A.parseFill(b)
        if nameA == nil or nameB == nil then
            return a == b
        end
        local bothEmpty = litersA <= reader.tolerance and litersB <= reader.tolerance
        return (nameA == nameB or bothEmpty) and math.abs(litersA - litersB) <= reader.tolerance
    end
    return a == b
end

-- Stavy souprávy (vehicles[i] = i-tý článek, 1 = hlavní vozidlo) jako { ["druh:článek"] = hodnota }; článek 0 = celá souprava,
-- u jednotek nádrží "fill:článek:jednotka". Spojité stavy (A.STATE_ORDER) jen s full = true (start herce), do nahrávání jízdy ne.
function A.readStates(vehicles, full)
    local states = {}
    local order = {}
    for _, kind in ipairs(A.ORDER) do
        order[#order + 1] = kind
    end
    for _, kind in ipairs(full and A.STATE_ORDER or {}) do
        order[#order + 1] = kind
    end
    for _, kind in ipairs(order) do
        local reader, def = A.READERS[kind], A.KINDS[kind]
        if reader ~= nil then
            for entry, v in ipairs(vehicles) do
                if (reader.scope == "entry" or entry == 1) and def.available(v) then
                    local subs = reader.units ~= nil and reader.units(v) or { false }
                    for _, sub in ipairs(subs) do
                        local ok, value = pcall(reader.read, v, sub or nil)
                        if ok then
                            local key = string.format("%s:%d", kind, reader.scope == "root" and 0 or entry)
                            states[sub and string.format("%s:%d", key, sub) or key] = value
                        end
                    end
                end
            end
        end
    end
    return states
end

-- Vrátí soupravu herce do stavu zapamatovaného se startem; mění jen to, co se od něj liší.
function A.applyStates(actor)
    local states = actor.start ~= nil and actor.start.states or nil
    for key, value in pairs(states or {}) do
        local kind, entry, sub = key:match("^(%w+):(%d+):?(%d*)$")
        local def, reader = A.KINDS[kind], A.READERS[kind]
        if def ~= nil and reader ~= nil then
            local list = A.vehicles(actor, tonumber(entry))
            local root = A.vehicles(actor, 1)[1]
            local probe = reader.scope == "root" and root or list[1]
            local okRead, current = false, nil
            if probe ~= nil then
                okRead, current = pcall(reader.read, probe, tonumber(sub))
            end
            if not okRead or not sameState(reader, current, value) then
                for _, v in ipairs(list) do
                    local okAvailable, available = pcall(def.available, v)
                    if okAvailable and available then
                        local ok, err = pcall(def.apply, v, value, { motorWanted = {}, timers = {}, instant = true, sub = tonumber(sub) })
                        if not ok then
                            log("warning", "CinemaStudio: applying start state %s failed: %s", kind, tostring(err))
                        end
                    end
                end
            end
        end
    end
end

-- Barva značky na ose podle skupiny akce.
A.GROUP_COLORS = {
    lights = { 1, 0.9, 0.3 }, motor = { 1, 0.4, 0.35 }, courseplay = { 0.55, 0.85, 0.45 }, fold = { 0.4, 0.9, 1 }, lower = { 1, 0.65, 0.25 },
    turnOn = { 1, 0.65, 0.25 }, tip = { 0.75, 0.55, 0.35 }, discharge = { 0.75, 0.55, 0.35 }, pipe = { 0.75, 0.55, 0.35 },
    honk = { 1, 1, 1 }, drone = { 0.8, 0.6, 1 }, seat = { 0.45, 0.8, 1 }, door = { 0.95, 0.75, 0.5 },
    gate = { 0.95, 0.75, 0.5 }, lamp = { 1, 0.9, 0.3 }, production = { 0.55, 0.85, 0.45 }, hose = { 0.4, 0.7, 1 },
    attach = { 0.6, 0.85, 0.55 }, canisters = { 0.8, 0.6, 1 }, toolboxDoor = { 0.8, 0.6, 1 }, pump = { 1, 0.4, 0.35 }, carry = { 0.85, 0.7, 0.45 },
}

function A.color(action)
    local def = A.KINDS[action.kind]
    return A.GROUP_COLORS[def ~= nil and def.group or ""] or { 1, 1, 1 }
end

function A.label(action)
    local text = g_i18n:getText(string.format("cine_act_%s_%d", action.kind, action.value or 1))
    if A.isBlink(action) then
        return string.format("%s (%d×)", text, A.blinkCount(action))
    end
    if action.anim ~= nil then
        text = string.format("%s %s", text, action.anim)
    end
    if action.subLabel ~= nil then
        text = string.format("%s: %s", text, action.subLabel)
    end
    if action.vehicle ~= nil then
        text = string.format("%s – %s", text, CinemaWorld.name(CinemaWorld.find(action.vehicle)))
    end
    if action.kind == "canisters" and action.items ~= nil and (action.value or 1) == 1 then
        text = string.format("%s: %s", text, A.canisterSummary(action.items))
    end
    return text
end

function A.isPersonKind(kind)
    local def = A.KINDS[kind]
    return def ~= nil and def.person == true
end

---------------------------------------------------------------------------------------------------
-- akce herce: pořadí podle času

-- Vloží akci tak, aby zůstaly seřazené (stejný čas = za existující). Vrací její index.
function A.add(actor, action)
    actor.actions = actor.actions or {}
    local list = actor.actions
    local index = #list + 1
    for i, other in ipairs(list) do
        if other.t > action.t then
            index = i
            break
        end
    end
    table.insert(list, index, action)
    return index
end

function A.remove(actor, index)
    if actor.actions == nil or actor.actions[index] == nil then
        return false
    end
    table.remove(actor.actions, index)
    return true
end

-- Seřadí akce podle času (stejný čas zůstane v dosavadním pořadí).
function A.sortByTime(actor)
    local list = actor.actions or {}
    for i, action in ipairs(list) do
        action.order = i
    end
    table.sort(list, function(a, b)
        if a.t ~= b.t then
            return a.t < b.t
        end
        return a.order < b.order
    end)
    for _, action in ipairs(list) do
        action.order = nil
    end
end

-- Nejdřívější čas akce herce: akce smí být i před startem jízdy (záporný čas, vozidlo stojí na startu),
-- nejdřív ale na začátku záběru.
function A.minTime(actor)
    return -(actor.delay or 0)
end

-- Čas od startu herce, kdy začíná jeho nejdřívější akce (0, když žádná není před startem).
function A.earliest(actor)
    local first = 0
    for _, action in ipairs(actor.actions or {}) do
        first = math.min(first, action.t)
    end
    return first
end

-- Posune akci v čase; vrací její nový index.
function A.move(actor, index, t)
    local action = actor.actions[index]
    table.remove(actor.actions, index)
    action.t = math.max(A.minTime(actor), t)
    return A.add(actor, action)
end

-- Jde akci natáhnout na dobu? Jen zapnutý stav druhu, který má i hodnotu „vypnuto“ (jednorázové akce ne).
function A.canStretch(action)
    local def = A.KINDS[action.kind]
    if def == nil or (action.value or 1) == 0 then
        return false
    end
    for _, value in ipairs(def.values) do
        if value == 0 then
            return true
        end
    end
    return false
end

function A.endTime(action)
    if A.isBlink(action) then
        return action.t + A.blinkDuration(action)
    end
    return action.t + (A.canStretch(action) and action.dur or 0)
end

-- Blikání: světlo se rozsvítí a zhasne count-krát rovnoměrně přes délku akce (bez délky A.BLINK_DEFAULT bliknutí).
A.BLINK = 2
A.BLINK_PERIOD = 0.8 -- s na jedno bliknutí
A.BLINK_DEFAULT = 3

function A.isBlink(action)
    local def = A.KINDS[action.kind]
    return def ~= nil and def.blink == true and action.value == A.BLINK
end

function A.blinkDuration(action)
    return action.dur or A.BLINK_PERIOD * A.BLINK_DEFAULT
end

function A.blinkCount(action)
    return math.max(1, math.floor(A.blinkDuration(action) / A.BLINK_PERIOD + 0.5))
end

-- Nastaví dobu akce (nil nebo 0 = jednorázově, u blikání výchozí počet); vrací false, když akce natáhnout nejde.
function A.setDuration(action, dur)
    if A.isBlink(action) then
        action.dur = dur ~= nil and dur > 0 and math.max(dur, A.BLINK_PERIOD) or nil
        return true
    end
    if dur == nil or dur <= 0 then
        action.dur = nil
        return true
    end
    if not A.canStretch(action) then
        return false
    end
    action.dur = math.max(dur, A.MIN_DURATION)
    return true
end

A.MIN_DURATION = 0.5
A.DEFAULT_DURATION = 3

-- Čas konce poslední akce (s od startu herce), 0 bez akcí.
function A.lastTime(actor)
    local last = 0
    for _, action in ipairs(actor.actions or {}) do
        last = math.max(last, A.endTime(action))
    end
    return last
end

-- Druhy, které mají na osi vlastní řádek: s akcemi, nebo (v detailu) všechny, co vozidlo umí. V pořadí nabídky.
function A.laneKinds(actor, all)
    local used = {}
    for _, action in ipairs(actor.actions or {}) do
        used[action.kind] = true
    end
    local list = {}
    for _, kind in ipairs(A.ORDER) do
        if used[kind] or (all and #A.availableValues(actor, 0, kind) > 0) then
            list[#list + 1] = kind
        end
    end
    return list
end

---------------------------------------------------------------------------------------------------
-- vozidla soupravy a co z nabídky se na nich dá

-- Vozidla, na která akce míří: entry 0 = celá souprava, jinak jeden článek (podle pořadí při zapamatování startu).
-- Objekt ve světě (CinemaObjects.actor) dává své cíle sám.
function A.vehicles(actor, entry)
    if actor.targets ~= nil then
        return actor.targets()
    end
    local entries = actor.start ~= nil and actor.start.entries or {}
    local list = {}
    for i, e in ipairs(entries) do
        if entry == nil or entry == 0 or entry == i then
            local v = CinemaWorld.find(e.uid)
            if v ~= nil then
                list[#list + 1] = v
            end
        end
    end
    return list
end

-- Hodnoty druhu akce, které aspoň jedno vozidlo cíle umí (prázdné = druh se nenabízí).
function A.availableValues(actor, entry, kind)
    local def = A.KINDS[kind]
    -- postava má jen své akce a vozidlo k nim vybírá až nabídka; akce objektů ve světě mají jen objekty
    if (def.world == true) ~= (actor.world == true) or (def.person == true) ~= (actor.person ~= nil)
        or (def.objectOnly and actor.targets == nil) then
        return {}
    elseif def.person then
        return def.values
    end
    for _, v in ipairs(A.vehicles(actor, entry)) do
        if def.available(v) then
            return def.values
        end
    end
    return {}
end

---------------------------------------------------------------------------------------------------
-- přehrávání

-- Události v pořadí času: akce a konce akcí s dobou (hodnota 0). Při stejném času platí pořadí akcí.
function A.events(actor)
    local events = {}
    for _, action in ipairs(actor.actions or {}) do
        if A.isBlink(action) then
            local count = A.blinkCount(action)
            local step = A.blinkDuration(action) / count
            for k = 0, count - 1 do
                for _, phase in ipairs({ { 0, 1 }, { 0.5, 0 } }) do
                    local t = action.t + (k + phase[1]) * step
                    events[#events + 1] = { t = t, order = #events, action = { t = t, kind = action.kind, value = phase[2], entry = action.entry } }
                end
            end
        else
            events[#events + 1] = { t = action.t, order = #events, action = action }
        end
        if action.dur ~= nil and A.canStretch(action) and not A.isBlink(action) then
            events[#events + 1] = { t = action.t + action.dur, order = #events,
                action = { t = action.t + action.dur, kind = action.kind, value = 0, entry = action.entry, vehicle = action.vehicle,
                    anim = action.anim, leg = action.leg, sub = action.sub } }
        end
    end
    table.sort(events, function(a, b)
        if a.t ~= b.t then
            return a.t < b.t
        end
        return a.order < b.order
    end)
    local list = {}
    for i, e in ipairs(events) do
        list[i] = e.action
    end
    return list
end

-- Připraví běh akcí herce od času startTime. Akce před ním se přeskočí, ale stav, který nastavily (světla, nářadí dole…),
-- se provede hned na začátku, jako by už proběhly.
function A.prepare(rt, actor, startTime)
    local events = A.events(actor)
    local from = startTime - (actor.delay or 0)
    local index = 1
    local latest, order = {}, {}
    while events[index] ~= nil and events[index].t < from - 1e-6 do
        local e = events[index]
        local def = A.KINDS[e.kind]
        if def ~= nil and #def.values > 1 then
            local key = string.format("%s:%s:%s:%s", e.kind, tostring(e.entry or 0), e.kind == "door" and (tostring(e.vehicle) .. tostring(e.anim)) or "",
                tostring(e.sub or ""))
            if latest[key] == nil then
                order[#order + 1] = key
            end
            latest[key] = e
        end
        index = index + 1
    end
    local catchUp = {}
    for _, key in ipairs(order) do
        catchUp[#catchUp + 1] = latest[key]
    end
    rt.act = { events = events, index = index, catchUp = catchUp, snaps = {}, motorWanted = {}, timers = {} }
end

-- Stav se pamatuje jednou na vozidlo (u dveří na vozidlo a animaci, u objektu ve světě na objekt a skupinu světel / výrobu),
-- před první akcí, která ho mění. Objekt ve světě si drží rovnou (vozidlo se hledá podle uid, mohlo zmizet).
local function remember(state, group, v, action)
    local uid = uidOf(v)
    local extra = action ~= nil and (action.anim or action.sub) or nil
    local key = extra ~= nil and (uid .. ":" .. tostring(extra)) or uid
    state.snaps[group] = state.snaps[group] or {}
    if state.snaps[group][key] == nil then
        local ok, snap = pcall(A.GROUPS[group].capture, v, action)
        state.snaps[group][key] = { uid = uid, snap = ok and snap or false, target = v.world and v or nil }
    end
end

-- Akce postavy: vozidlo je v akci (výstup ho mít nemusí), nástup a výstup hraje jen hráč.
local function firePerson(state, actor, action, def)
    if def.noVehicle or (action.kind == "seat" and actor.person ~= CinemaPerson.PLAYER) then
        return
    end
    local v = action.vehicle ~= nil and CinemaWorld.find(action.vehicle) or nil
    if v == nil and (action.vehicle ~= nil or action.kind ~= "seat") then
        log("warning", "CinemaStudio: action %s: vehicle %s not found", action.kind, tostring(action.vehicle))
        return
    end
    if v ~= nil then
        local okAvailable, available = pcall(def.available, v)
        if not okAvailable or not available then
            return
        end
    end
    -- kde hráč seděl, je jeden stav bez ohledu na vozidlo
    remember(state, def.group, action.kind == "seat" and { uniqueId = "player" } or v, action)
    state.action = action
    local ok, err = pcall(def.apply, v, action.value or 1, state)
    state.action = nil
    if not ok then
        log("warning", "CinemaStudio: action %s failed: %s", action.kind, tostring(err))
    end
end

-- Druh, který nastavuje stav (má hodnotu vypnuto); jednorázové (houkačka, start dronu) se při náhledu nevykonávají.
function A.isStateful(kind)
    local def = A.KINDS[kind]
    if def == nil then
        return false
    end
    for _, value in ipairs(def.values) do
        if value == 0 then
            return true
        end
    end
    return false
end

function A.fire(state, actor, action)
    local def = A.KINDS[action.kind]
    if def == nil then
        return
    end
    if state.preview and (def.noPreview or not A.isStateful(action.kind)) then
        return
    end
    if def.person then
        if actor.person ~= nil then
            firePerson(state, actor, action, def)
        end
        return
    end
    local count = 0
    for _, v in ipairs(A.vehicles(actor, action.entry)) do
        local okAvailable, available = pcall(def.available, v)
        if okAvailable and available then
            remember(state, def.group, v, (def.world or def.sub or def.payload) and action or nil)
            state.action = action
            local ok, err = pcall(def.apply, v, action.value or 1, state)
            state.action = nil
            if ok then
                count = count + 1
            else
                log("warning", "CinemaStudio: action %s failed: %s", action.kind, tostring(err))
            end
        end
    end
    if CinemaDev ~= nil then CinemaDev.action(action, count) end
end

-- Provede akce, jejichž čas nastal (tLocal = s od startu herce), a odpočítá časovače (houkačka).
function A.update(rt, actor, tLocal, dt)
    local state = rt.act
    if state == nil then
        return
    end
    -- stav akcí před startem přehrávání nebo náhledu se nastaví hned, bez animací
    local instant = state.instant
    state.instant = true
    for _, action in ipairs(state.catchUp) do
        A.fire(state, actor, action)
    end
    state.instant = instant
    state.catchUp = {}
    local list = state.events
    while list[state.index] ~= nil and list[state.index].t <= tLocal + 1e-6 do
        A.fire(state, actor, list[state.index])
        state.index = state.index + 1
    end
    for i = #state.timers, 1, -1 do
        local timer = state.timers[i]
        timer.left = timer.left - dt * 0.001
        if timer.left <= 0 then
            pcall(timer.fn)
            table.remove(state.timers, i)
        end
    end
end

-- Natvrdo a hned (bez animací) nastaví stav, který akce herce nastavily do času t včetně (s od začátku záběru). Na rozdíl
-- od náhledu si nepamatuje předchozí stav, takže ho nic později nevrátí (reset na start / na ukazatel).
function A.applyAt(actor, t)
    local rt = {}
    A.prepare(rt, actor, t + 1e-3)
    rt.act.preview = true
    rt.act.instant = true
    for _, action in ipairs(rt.act.catchUp) do
        A.fire(rt.act, actor, action)
    end
end

-- Vrátí vozidla do stavu před první akcí.
function A.finish(rt)
    local state = rt.act
    if state == nil then
        return
    end
    for _, timer in ipairs(state.timers) do
        pcall(timer.fn)
    end
    for group, perVehicle in pairs(state.snaps) do
        for _, entry in pairs(perVehicle) do
            local v = entry.target or CinemaWorld.find(entry.uid)
            if (v ~= nil or group == "seat") and entry.snap ~= false then
                local ok, err = pcall(A.GROUPS[group].restore, v, entry.snap)
                if not ok then
                    log("warning", "CinemaStudio: restoring state %s failed: %s", group, tostring(err))
                end
            end
        end
    end
    rt.act = nil
end
