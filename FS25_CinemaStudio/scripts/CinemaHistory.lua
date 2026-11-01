-- Historie úprav záběru: záznam = { time, snap }, kde snap je stav záběru před krokem a time čas kroku (vteřiny podle hodin
-- počítače). Stav po kroku je snap dalšího záznamu, u posledního současný stav. Záznamy se pamatují týden (i po restartu hry,
-- ukládá je CinemaStorage), nejvýš MAX_ENTRIES. Čistá logika bez herních API: popis kroku podle rozdílu dvou stavů, stáří, ořez.

CinemaHistory = CinemaHistory or {}
local H = CinemaHistory

H.MAX_AGE = 7 * 24 * 3600
H.MAX_ENTRIES = 200

-- Dny od 1. 1. 1970 pro datum (občanský kalendář).
local function daysFromCivil(y, m, d)
    if m <= 2 then
        y = y - 1
    end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

function H.toSeconds(y, mo, d, h, mi, s)
    return daysFromCivil(y, mo, d) * 86400 + h * 3600 + mi * 60 + s
end

-- Čas teď ve vteřinách (místní čas počítače); hra dává datum přes getDate.
function H.now()
    if getDate ~= nil then
        local y, mo, d, h, mi, s = string.match(getDate("%Y/%m/%d %H:%M:%S"), "(%d+)/(%d+)/(%d+) (%d+):(%d+):(%d+)")
        if y ~= nil then
            return H.toSeconds(tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi), tonumber(s))
        end
    end
    if os ~= nil and os.time ~= nil then
        return os.time()
    end
    return 0
end

-- Stáří jako klíč textu a číslo: { "cine_hist_agoNow" }, { "cine_hist_agoMin", 5 }, hodiny, dny.
function H.age(seconds)
    if seconds < 60 then
        return "cine_hist_agoNow", 0
    elseif seconds < 3600 then
        return "cine_hist_agoMin", math.floor(seconds / 60)
    elseif seconds < 86400 then
        return "cine_hist_agoHour", math.floor(seconds / 3600)
    end
    return "cine_hist_agoDay", math.floor(seconds / 86400)
end

-- Záznamy novější než týden a nejvýš MAX_ENTRIES nejnovějších; vrací nový seznam.
function H.prune(entries, now)
    local list = {}
    for _, e in ipairs(entries) do
        if now - e.time <= H.MAX_AGE then
            list[#list + 1] = e
        end
    end
    while #list > H.MAX_ENTRIES do
        table.remove(list, 1)
    end
    return list
end

-- Hluboké porovnání bez stálých čísel věcí (uid se přidělují líně a stav tím nemění).
local function deepEqual(a, b)
    if type(a) ~= type(b) then
        return false
    end
    if type(a) ~= "table" then
        return a == b
    end
    for k, v in pairs(a) do
        if k ~= "uid" and not deepEqual(v, b[k]) then
            return false
        end
    end
    for k in pairs(b) do
        if k ~= "uid" and a[k] == nil then
            return false
        end
    end
    return true
end
H.equal = deepEqual

-- Odstraní záznamy, jejichž krok nic nezměnil (stav před ním je stejný jako po něm); current je současný stav.
function H.compact(entries, current)
    local after = current
    for i = #entries, 1, -1 do
        if deepEqual(entries[i].snap, after) then
            table.remove(entries, i)
        else
            after = entries[i].snap
        end
    end
    return entries
end

-- K-framy všech bloků kamery (K-framy Letu i značky režimů) a bloky bez nich.
local function split(segments)
    local keys, blocks = {}, {}
    for _, seg in ipairs(segments or {}) do
        local bare = {}
        for k, v in pairs(seg.track) do
            if k ~= "keys" and k ~= "marks" then
                bare[k] = v
            end
        end
        blocks[#blocks + 1] = { id = seg.id, t = seg.t, track = bare }
        for _, k in ipairs(seg.track.keys or seg.track.marks or {}) do
            keys[#keys + 1] = k
        end
    end
    return keys, blocks
end

-- Popis kroku z a do stavu b: klíč textu a počet dalších změn; nil, když jsou stavy stejné.
function H.describe(a, b)
    local found = {}
    local function compare(x, y, added, removed, changed)
        if #x < #y then
            found[#found + 1] = added
        elseif #x > #y then
            found[#found + 1] = removed
        elseif not deepEqual(x, y) then
            found[#found + 1] = changed
        end
    end
    if #a.cameras ~= #b.cameras then
        found[#found + 1] = "cine_hist_cameras"
    else
        for i = 1, #a.cameras do
            local x, y = a.cameras[i], b.cameras[i]
            local xKeys, xBlocks = split(x.segments)
            local yKeys, yBlocks = split(y.segments)
            -- K-frame přidaný na konec Letu blok prodlouží: krok je přidání K-framu, ne úprava bloku
            if #xBlocks == #yBlocks then
                compare(xKeys, yKeys, "cine_hist_keyAdded", "cine_hist_keyRemoved", "cine_hist_keys")
            end
            compare(xBlocks, yBlocks, "cine_hist_blockAdded", "cine_hist_blockRemoved", "cine_hist_blocks")
            compare(x.focus or {}, y.focus or {}, "cine_hist_focusAdded", "cine_hist_focusRemoved", "cine_hist_focus")
            if not deepEqual(x.curves, y.curves) then
                found[#found + 1] = "cine_hist_curves"
            end
            if x.name ~= y.name or x.camColor ~= y.camColor or x.camHidden ~= y.camHidden then
                found[#found + 1] = "cine_hist_camera"
            end
        end
    end
    compare(a.actors or {}, b.actors or {}, "cine_hist_actorAdded", "cine_hist_actorRemoved", "cine_hist_actors")
    if not deepEqual(a.env, b.env) then
        found[#found + 1] = "cine_hist_env"
    end
    if a.preroll ~= b.preroll or a.shake ~= b.shake or a.bank ~= b.bank or a.name ~= b.name then
        found[#found + 1] = "cine_hist_settings"
    end
    if #found == 0 then
        return nil
    end
    return found[1], #found - 1
end
