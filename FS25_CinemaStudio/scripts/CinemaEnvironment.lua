-- Prostředí scény záběru: denní doba, roční období a počasí. Mění je jen hostitel (server); klient v multiplayeru ne.
-- Postup je z dev módu SprayDroneCinema a z Easy Development Controls. Každé volání herního API je v pcall,
-- aby změna prostředí nikdy nesrazila editor. Co záběr nenastavuje, se nemění; co se změnilo, se po zavření vrátí.

CinemaEnvironment = CinemaEnvironment or {}
local Env = CinemaEnvironment

Env.HOUR_STEP = 0.25
Env.SEASONS = { "spring", "summer", "autumn", "winter" }
Env.SEASON_PERIOD = { spring = 2, summer = 5, autumn = 8, winter = 11 } -- období uprostřed ročního období
Env.HOUR_MS = 3600 * 1000

function Env.formatHour(hour)
    local minutes = math.floor((hour % 24) * 60 + 0.5) % (24 * 60)
    return string.format("%02d:%02d", math.floor(minutes / 60), minutes % 60)
end

-- Hodina posunutá o delta hodin, zaokrouhlená na čtvrthodiny, v rozsahu 0 až 24.
function Env.stepHour(hour, delta)
    local steps = math.floor(((hour + delta) / Env.HOUR_STEP) + 0.5)
    return (steps * Env.HOUR_STEP) % 24
end

local function environment()
    local mission = g_currentMission
    return mission ~= nil and mission.environment or nil
end

function Env.available()
    local mission = g_currentMission
    return mission ~= nil and mission.environment ~= nil and mission:getIsServer()
end

local function refresh(e)
    pcall(e.update, e, 1, true)
    if e.lighting ~= nil then
        pcall(e.lighting.update, e.lighting, 9999, true)
    end
end

-- Hodina dne (0 až 24) nebo nil.
function Env.hour()
    local e = environment()
    return e ~= nil and e.dayTime ~= nil and e.dayTime / Env.HOUR_MS or nil
end

-- Klíč ročního období podle hry (spring, summer, autumn, winter) nebo nil.
function Env.season()
    local e = environment()
    if e == nil or Season == nil then
        return nil
    end
    for _, key in ipairs(Env.SEASONS) do
        if Season[key:upper()] == e.currentSeason then
            return key
        end
    end
    return nil
end

-- Jméno aktuálního počasí (SUN, RAIN…) nebo nil.
function Env.weatherName()
    local e = environment()
    if e == nil or e.weather == nil then
        return nil
    end
    local ok, index = pcall(e.weather.getCurrentWeatherType, e.weather)
    if not ok or index == nil then
        return nil
    end
    local named, name = pcall(WeatherType.getName, index)
    return named and name or nil
end

-- Jména počasí, která hra v aktuálním ročním období umí.
function Env.weatherNames()
    local e = environment()
    local list = {}
    local byType = e ~= nil and e.weather ~= nil and e.weather.typeToWeatherObject or nil
    local season = byType ~= nil and byType[e.currentSeason] or nil
    for index in pairs(season or {}) do
        local ok, name = pcall(WeatherType.getName, index)
        if ok and name ~= nil then
            list[#list + 1] = name
        end
    end
    table.sort(list)
    return list
end

-- Nastaví hodinu dne; vrací milisekundy, na kterých se čas drží (Env.hold).
function Env.setHour(hour)
    local e = environment()
    if e == nil then
        return nil
    end
    local ms = math.floor((hour % 24) * Env.HOUR_MS)
    local ok = pcall(e.setEnvironmentTime, e, e.currentMonotonicDay, e.currentDay, ms, e.daysPerPeriod, false)
    if not ok then
        e.dayTime = ms
    end
    if e.lighting ~= nil and e.lighting.setDayTime ~= nil then
        pcall(e.lighting.setDayTime, e.lighting, e.dayTime, true)
    end
    if e.weather ~= nil then
        e.weather.cheatedTime = true
    end
    refresh(e)
    if g_server ~= nil and EnvironmentTimeEvent ~= nil then
        pcall(function()
            g_server:broadcastEvent(EnvironmentTimeEvent.new(e.currentMonotonicDay, e.currentDay, e.dayTime, e.daysPerPeriod))
        end)
    end
    return ms
end

function Env.setSeason(key)
    local e = environment()
    local period = Env.SEASON_PERIOD[key]
    if e == nil or period == nil then
        return false
    end
    local ok = pcall(e.setFixedPeriod, e, period)
    refresh(e)
    return ok
end

function Env.clearSeason()
    local e = environment()
    if e ~= nil then
        pcall(e.setFixedPeriod, e, nil)
        refresh(e)
    end
end

-- Počasí podle jména: nahradí předpověď jednou položkou a dopočítá zbytek (konzolový příkaz předpověď rozbíjí).
function Env.setWeather(name)
    local e = environment()
    local weather = e ~= nil and e.weather or nil
    if weather == nil then
        return false
    end
    local ok, done = pcall(function()
        local weatherType = WeatherType.getByName(name)
        local season = e.currentSeason
        local object = weatherType ~= nil and weather.typeToWeatherObject[season][weatherType] or nil
        if object == nil then
            return false
        end
        local current = weather.forecastItems[1]
        local currentObject = current ~= nil and weather:getWeatherObjectByIndex(current.season, current.objectIndex) or nil
        local variation = object:getVariationByIndex(object:getRandomVariationIndex())
        local duration = math.random(variation.minHours, variation.maxHours) * Env.HOUR_MS
        local startDay, startDayTime = e:getDayAndDayTime(e.dayTime, e.currentMonotonicDay)
        weather.forecastItems = { WeatherInstance.createInstance(object.index, variation.index, startDay, startDayTime, duration, season) }
        weather:fillWeatherForecast()
        if currentObject ~= nil then
            currentObject:deactivate(1)
            currentObject:update(99999999)
        end
        weather:init()
        return true
    end)
    if ok and done == true then
        return true
    end
    if not ok then
        Logging.warning("CinemaStudio weather %s: %s", tostring(name), tostring(done))
    end
    -- konzolový příkaz předpověď občas rozbije, ale ScreenshotMode i dev mód SprayDroneCinema ho s úspěchem používají
    local fallback = pcall(weather.consoleCommandWeatherSet, weather, name, 1)
    if fallback then
        refresh(e)
    end
    return fallback
end

-- Nastaví prostředí podle env (záběr; nil = nic) a v saved si pamatuje původní hodnoty změněných položek.
-- Položka, kterou záběr už nenastavuje a která se dřív změnila, se vrátí na původní hodnotu.
function Env.apply(env, saved, force)
    if not Env.available() then
        return
    end
    env = env or {}
    saved.done = saved.done or {}
    local done = saved.done
    local seasonChanged = false
    if env.season ~= nil then
        saved.season = true
        if force or done.season ~= env.season then
            Env.setSeason(env.season)
            done.season = env.season
            seasonChanged = true
        end
    elseif saved.season then
        Env.clearSeason()
        saved.season, done.season = nil, nil
        seasonChanged = true
    end
    -- počasí se losuje znovu jen při změně (a po změně období, které mění nabídku počasí), ne při každém kroku zpět
    if env.weather ~= nil then
        if saved.weather == nil then
            saved.weather = Env.weatherName() or false
        end
        if force or seasonChanged or done.weather ~= env.weather then
            Env.setWeather(env.weather)
            done.weather = env.weather
        end
    elseif saved.weather ~= nil then
        if saved.weather then
            Env.setWeather(saved.weather)
        end
        saved.weather, done.weather = nil, nil
    end
    if env.hour ~= nil then
        if saved.hour == nil then
            saved.hour = Env.hour() or false
        end
        if force or done.hour ~= env.hour then
            saved.lock = Env.setHour(env.hour)
            done.hour = env.hour
        end
    elseif saved.hour ~= nil then
        if saved.hour then
            Env.setHour(saved.hour)
        end
        saved.hour, saved.lock, done.hour = nil, nil, nil
    end
end

-- Denní doba a počasí teď (výchozí stav záběru pro Env.restart).
function Env.capture()
    return { hour = Env.hour(), weather = Env.weatherName() }
end

-- Prostředí na začátek záběru (R, přehrání od začátku): denní doba a počasí podle záběru, a co záběr nenastavuje, podle
-- start (Env.capture při otevření záběru). Počasí se losuje znovu jen, když je jiné, než má být.
function Env.restart(env, start, saved)
    if not Env.available() then
        return
    end
    env = env or {}
    Env.apply(env, saved)
    start = start or {}
    local hour = env.hour or start.hour
    if hour ~= nil then
        Env.setHour(hour)
    end
    local weather = env.weather or start.weather
    if weather ~= nil and Env.weatherName() ~= weather then
        Env.setWeather(weather)
    end
end

-- Drží nastavený čas každý snímek (hra jinak posouvá denní dobu dál).
function Env.hold(saved)
    local e = environment()
    if saved.lock ~= nil and e ~= nil then
        e.dayTime = saved.lock
    end
end

-- Čitelné shrnutí nastavení záběru pro stavový řádek a hlášky.
function Env.summary(env)
    local parts = {}
    if env ~= nil then
        if env.hour ~= nil then
            parts[#parts + 1] = Env.formatHour(env.hour)
        end
        if env.season ~= nil then
            parts[#parts + 1] = g_i18n:getText("cine_season_" .. env.season)
        end
        if env.weather ~= nil then
            parts[#parts + 1] = Env.weatherText(env.weather)
        end
    end
    return table.concat(parts, ", ")
end

function Env.weatherText(name)
    local key = "cine_weather_" .. name
    if g_i18n:hasText(key) then
        return g_i18n:getText(key)
    end
    return name
end
