-- Vstupní bod: klávesy pro otevření editoru a nahrávání jízdy pěšky i ve vozidle (globální akce hráče, vzor ScreenshotMode).

CinemaStudio = {}
CinemaStudio.api = CinemaApi

PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(PlayerInputComponent.registerGlobalPlayerActionEvents, function()
    local _, eventId = g_inputBinding:registerActionEvent(InputAction.CINE_OPEN, CinemaStudio, CinemaStudio.onOpenEditor, false, true, false, true)
    if eventId ~= nil then
        g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_VERY_LOW)
        g_inputBinding:setActionEventTextVisibility(eventId, false)
    end
    _, eventId = g_inputBinding:registerActionEvent(InputAction.CINE_RECORD, CinemaStudio, CinemaStudio.onToggleRecord, false, true, false, true)
    if eventId ~= nil then
        g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_VERY_LOW)
        g_inputBinding:setActionEventTextVisibility(eventId, false)
    end
end)

-- vývojový modul (scripts/dev/) si přidá svůj konzolový příkaz; ve vydaném módu není
function CinemaStudio:loadMap()
    if CinemaDev ~= nil then CinemaDev.loadMap() end
end

function CinemaStudio:onToggleRecord()
    CinemaRecorder.toggle()
end

function CinemaStudio:update(dt)
    CinemaRecorder.update(dt)
    if CinemaDev ~= nil and CinemaDev.update ~= nil then CinemaDev.update(dt) end
    if CinemaPerson.reopenEditor then
        CinemaPerson.reopenEditor = nil
        CinemaEditorScreen.show()
        local screen = CinemaEditorScreen.INSTANCE
        if screen ~= nil and screen.shot ~= nil then
            CinemaShot.touch(screen.shot)
            screen:markDirty()
        end
    end
end

function CinemaStudio:draw()
    CinemaRecorder.draw()
end

function CinemaStudio:onOpenEditor()
    CinemaRecorder.stop()
    CinemaEditorScreen.show()
end

-- Konec hry s otevřeným editorem (odpojení v MP): zavřít ho, dokud mise existuje — uloží se do správné mapy
-- a vstupní kontext se vrátí ve správném pořadí.
function CinemaStudio:deleteMap()
    if CinemaDev ~= nil then CinemaDev.deleteMap() end
    local screen = CinemaEditorScreen.INSTANCE
    if screen == nil then
        return
    end
    if screen:getIsOpen() then
        g_gui:showGui("")
    end
    if screen.cam.active then
        CinemaCamera.stop(screen.cam)
    end
end

addModEventListener(CinemaStudio)
