--[[
    REAwheels_fixed.lua – FS25 REA Wheels Physik
    by Papa_Matze

    Funktionen:
      - tiefere Spuren (gefühlt „einsinken“)
      - höherer Rollwiderstand
      - stärkerer Gewichtseinfluss
      - Helfer-Physik (AI spürt Gewicht und Boden)
      - DynamicDirt-Unterstützung
      - Debug-Overlay (F9, 5 Sekunden sichtbar)
]]

REAwheels = {}
REAwheels.version = "1.0.7"

--------------------------------------------------------------------
-- Globale Tuning-Werte
--------------------------------------------------------------------
-- Spurtiefe / Einsinken (Einfluss auf Grip/Trägheit)
REAwheels.WheelSinkScale          = 2.5   -- Standard: 1.0

-- Rollwiderstand
REAwheels.RollingResistanceScale  = 2.0   -- Standard: 1.0

-- Gewichtseinfluss
REAwheels.WeightEffectScale       = 2.0   -- Standard: 1.0

-- Einfluss Bodenfeuchte (Dynamic Dirt / Wetter)
REAwheels.WetnessInfluence        = 1.5   -- 0..2 – je höher, desto mehr Matsch-Effekt

-- Helfer-Physik
REAwheels.HelperPhysicsFactor     = 1.0   -- 0 = aus, 1 = wie Spieler, >1 = stärker

-- Debug Overlay
REAwheels.debugActive             = false
REAwheels.debugHideTimer          = 0
REAwheels.debugHideDelayMs        = 5000  -- 5 Sekunden nach Loslassen von F9

--------------------------------------------------------------------
-- Hilfsfunktionen
--------------------------------------------------------------------

local function REA_clamp(v, minV, maxV)
    if v < minV then return minV end
    if v > maxV then return maxV end
    return v
end

local function REA_isHelper(vehicle)
    if vehicle ~= nil and vehicle.getIsAIActive ~= nil then
        return vehicle:getIsAIActive()
    end
    return false
end

--------------------------------------------------------------------
-- Initialisierung / Map-Events
--------------------------------------------------------------------

function REAwheels:loadMap(name)
    print(string.format("REA Wheels v%s geladen (FS25)", REAwheels.version))

    REAwheels.LastUpdateTime       = 0
    REAwheels.GroundWetnessFactor  = 0
    REAwheels.DynamicDirtFound     = false
    REAwheels.DynamicDirtNotFound  = false
    REAwheels.DynamicDirtActivated = false
    REAwheels.DynamicDirtMaxTimer  = 5000

    REAwheels.DebugForce           = false
    REAwheels.DebugFrictionCoeff   = false
    REAwheels.DebugGroundType      = false
    REAwheels.DebugWetness         = false

    REAwheels:SetGlobalParameters()
end

function REAwheels:deleteMap()
end

function REAwheels:mouseEvent(posX, posY, isDown, isUp, button)
end

function REAwheels:keyEvent(unicode, sym, modifier, isDown)
    -- F9 → Debug-Overlay
    if sym == Input.KEY_f9 then
        if isDown then
            REAwheels.debugActive = true
            REAwheels.debugHideTimer = REAwheels.debugHideDelayMs
        else
            -- Timer läuft, bis Overlay verschwindet
            REAwheels.debugHideTimer = REAwheels.debugHideDelayMs
        end
    end
end

--------------------------------------------------------------------
-- Haupt-Update
--------------------------------------------------------------------

function REAwheels:update(dt)
    ----------------------------------------------------------------
    -- Timer für Debug HUD
    ----------------------------------------------------------------
    if REAwheels.debugHideTimer > 0 then
        REAwheels.debugHideTimer = REAwheels.debugHideTimer - dt
        if REAwheels.debugHideTimer <= 0 then
            REAwheels.debugActive = false
        end
    end

    ----------------------------------------------------------------
    -- Dynamic Dirt koppeln
    ----------------------------------------------------------------
    REAwheels:GetIsDynamicDirtActivated(dt)

    ----------------------------------------------------------------
    -- Bodenfeuchte aktualisieren
    ----------------------------------------------------------------
    REAwheels:UpdateGroundWetness(dt)

    ----------------------------------------------------------------
    -- REA für alle Fahrzeuge / Anhänger / Drescher / Güllefässer
    ----------------------------------------------------------------
    if g_currentMission == nil or g_currentMission.vehicles == nil then
        return
    end

    for _, vehicle in pairs(g_currentMission.vehicles) do
        if vehicle ~= nil and vehicle.spec_wheels ~= nil and vehicle.isAddedToPhysics then
            if REAwheels:GetIsActive(vehicle, dt) then
                local MotorizedVehicle =
                       vehicle.spec_motorized ~= nil
                    or vehicle.spec_combine ~= nil
                    or vehicle.spec_sprayer ~= nil
                    or vehicle.spec_manureTanker ~= nil

                local isTrailer =
                       (vehicle.spec_motorized == nil
                    and vehicle.spec_combine == nil
                    and vehicle.spec_sprayer == nil
                    and vehicle.spec_manureTanker == nil)

                local PowerConsumerActivated = false
                if vehicle.spec_powerConsumer ~= nil and vehicle.spec_powerConsumer.forceNode ~= nil then
                    if vehicle.doCheckSpeedLimit ~= nil then
                        PowerConsumerActivated = vehicle:doCheckSpeedLimit()
                    end
                end

                REAwheels:UpdateWheels(vehicle, vehicle.spec_wheels, vehicle.spec_crawlers,
                                       MotorizedVehicle, PowerConsumerActivated, isTrailer, dt)
            end
        end
    end
end

--------------------------------------------------------------------
-- Debug HUD
--------------------------------------------------------------------

function REAwheels:draw()
    if not REAwheels.debugActive then
        return
    end

    local x = 0.80
    local y = 0.95
    local s = 0.018

    local wet = REAwheels:GetGroundWetness() or 0

    setTextColor(1, 1, 1, 1)
    renderText(x, y,      s, string.format("REA Wheels v%s", REAwheels.version))
    renderText(x, y-0.03, s, string.format("Spurtiefe: %.2f", REAwheels.WheelSinkScale))
    renderText(x, y-0.06, s, string.format("Rollwiderstand: %.2f", REAwheels.RollingResistanceScale))
    renderText(x, y-0.09, s, string.format("Gewichtseinfluss: %.2f", REAwheels.WeightEffectScale))
    renderText(x, y-0.12, s, string.format("Bodenfeuchte: %.2f", wet))
end

--------------------------------------------------------------------
-- DynamicDirt erkennen
--------------------------------------------------------------------

function REAwheels:isDynamicDirtLoaded()
    local names = { "FS22_READynamicDirt", "READynamicDirt", "FS25_READynamicDirt", "FS23_READynamicDirt" }
    for _, n in ipairs(names) do
        if g_modIsLoaded ~= nil and g_modIsLoaded[n] ~= nil then
            return true, n
        end
    end
    return false, nil
end

function REAwheels:GetIsDynamicDirtActivated(dt)
    if REAwheels.DynamicDirtActivated == nil then
        REAwheels.DynamicDirtFound = false
        REAwheels.DynamicDirtNotFound = false
        REAwheels.DynamicDirtMaxTimer = 5000
        REAwheels.DynamicDirtActivated = false
    end

    if not REAwheels.DynamicDirtActivated and not REAwheels.DynamicDirtNotFound then
        if not REAwheels.DynamicDirtFound then
            local loaded, modName = REAwheels:isDynamicDirtLoaded()
            if loaded then
                print("REA Wheels: REA DynamicDirt gefunden (" .. tostring(modName) .. ")")
                REAwheels.DynamicDirtFound = true
            end
        end

        if REAwheels.DynamicDirtFound then
            if WheelsUtil ~= nil and WheelsUtil.LowspotScanCompleted ~= nil and WheelsUtil.LowspotScanCompleted then
                print("REA Wheels: REA DynamicDirt Scan abgeschlossen")
                REAwheels.DynamicDirtActivated = true
            end
        end
    end

    if not REAwheels.DynamicDirtFound and not REAwheels.DynamicDirtNotFound then
        if REAwheels.DynamicDirtMaxTimer > 0 then
            REAwheels.DynamicDirtMaxTimer = REAwheels.DynamicDirtMaxTimer - dt
        else
            REAwheels.DynamicDirtNotFound = true
            print("REA Wheels: REA DynamicDirt nicht gefunden (Zeitüberschreitung)")
        end
    end
end

--------------------------------------------------------------------
-- Fahrzeug aktiv?
--------------------------------------------------------------------

function REAwheels:GetIsActive(vehicle, dt)
    if vehicle.REAWheelsKeepActive == nil then
        vehicle.REAWheelsKeepActive = false
        vehicle.REAWheelsKeepActiveTime = 1000
    end

    local MinSpeedToActivate = 0.5
    local VehicleActive = false

    if vehicle.getIsActive ~= nil then
        VehicleActive = vehicle:getIsActive()
    end

    if vehicle.lastSpeed ~= nil then
        VehicleActive = VehicleActive or (vehicle.lastSpeed * 3600 > MinSpeedToActivate)
    end

    if VehicleActive then
        vehicle.REAWheelsKeepActive = true
        vehicle.REAWheelsKeepActiveTime = 1000
    end

    if vehicle.REAWheelsKeepActive and not VehicleActive then
        vehicle.REAWheelsKeepActiveTime = vehicle.REAWheelsKeepActiveTime - dt
        if vehicle.REAWheelsKeepActiveTime < 0 then
            vehicle.REAWheelsKeepActive = false
        end
    end

    return vehicle.REAWheelsKeepActive
end

--------------------------------------------------------------------
-- Globale Parameter (Friction-Tabellen etc.)
--------------------------------------------------------------------

function REAwheels:SetFrictionCoeff(TireType, Groundtype, CoeffDry, CoeffFactorWet, CoeffFactorSnow)
    local TireTypeName   = {"MUD","OFFROAD","STREET","CRAWLERS"}
    local GroundTypeName = {"ROAD","HARD TERRAIN","SOFT TERRAIN","FIELD"}

    if REAwheels.DebugFrictionCoeff then
        print("REAwheels: Original friction coefficient for tiretype '" ..
            TireTypeName[TireType] .. "' on groundtype '" ..
            GroundTypeName[Groundtype] .. "' Dry=" ..
            tostring(WheelsUtil.tireTypes[TireType].frictionCoeffs[Groundtype]) ..
            ", Wet=" .. tostring(WheelsUtil.tireTypes[TireType].frictionCoeffsWet[Groundtype]) ..
            ", Snow=" .. tostring(WheelsUtil.tireTypes[TireType].frictionCoeffsSnow[Groundtype]))
    end

    WheelsUtil.tireTypes[TireType].frictionCoeffs[Groundtype]      = CoeffDry
    WheelsUtil.tireTypes[TireType].frictionCoeffsWet[Groundtype]   = CoeffDry * CoeffFactorWet
    WheelsUtil.tireTypes[TireType].frictionCoeffsSnow[Groundtype]  = CoeffDry * CoeffFactorSnow

    if REAwheels.DebugFrictionCoeff then
        print("REAwheels: Edited friction coefficient for tiretype '" ..
            TireTypeName[TireType] .. "' on groundtype '" ..
            GroundTypeName[Groundtype] .. "' Dry=" ..
            tostring(WheelsUtil.tireTypes[TireType].frictionCoeffs[Groundtype]) ..
            ", Wet=" .. tostring(WheelsUtil.tireTypes[TireType].frictionCoeffsWet[Groundtype]) ..
            ", Snow=" .. tostring(WheelsUtil.tireTypes[TireType].frictionCoeffsSnow[Groundtype]))
    end
end

function REAwheels:SetGlobalParameters()
    local TireTypeMUD      = 1
    local TireTypeOFFROAD  = 2
    local TireTypeSTREET   = 3
    local TireTypeCRAWLER  = 4

    local ROAD          = WheelsUtil.GROUND_ROAD
    local HARD_TERRAIN  = WheelsUtil.GROUND_HARD_TERRAIN
    local SOFT_TERRAIN  = WheelsUtil.GROUND_SOFT_TERRAIN
    local FIELD         = WheelsUtil.GROUND_FIELD

    REAwheels.TireTypeMaxSinkFrictionReduced   = {1,1,1,1}
    REAwheels.TireTypeSinkStuckLevel           = {1,1,1,1}
    REAwheels.TireTypeMinRollingCoeff          = {1,1,1,1}
    REAwheels.TireTypeSinkPerMeterSpinning     = {0.1,0.1,0.1,0.1}

    REAwheels.MinWheelRadius                   = 0.15
    REAwheels.WheelRadiusMaxSinkFactor         = 0.5

    REAwheels.TireTypeMaxSinkFrictionReducedLowSpot = 100
    REAwheels.TireTypeSinkStuckLevelLowSpot         = 75

    local SnowCoeffFactor = 1

    -- MUD
    SnowCoeffFactor = 0.5
    REAwheels:SetFrictionCoeff(TireTypeMUD, ROAD,         0.85, 0.95, SnowCoeffFactor)
    REAwheels:SetFrictionCoeff(TireTypeMUD, HARD_TERRAIN, 0.76, 0.90, SnowCoeffFactor)
    REAwheels:SetFrictionCoeff(TireTypeMUD, SOFT_TERRAIN, 0.84, 0.85, SnowCoeffFactor)
    REAwheels:SetFrictionCoeff(TireTypeMUD, FIELD,        0.80, 0.85, SnowCoeffFactor)
    REAwheels.TireTypeMaxSinkFrictionReduced[TireTypeMUD]        = 35
    REAwheels.TireTypeSinkStuckLevel[TireTypeMUD]                = 95
    REAwheels.TireTypeSinkPerMeterSpinning[TireTypeMUD]          = 0.04
    REAwheels.TireTypeMinRollingCoeff[TireTypeMUD]               = 0.04

    -- OFFROAD
    SnowCoeffFactor = 0.7
    REAwheels:SetFrictionCoeff(TireTypeOFFROAD, ROAD,         1.19, 0.95, SnowCoeffFactor)
    REAwheels:SetFrictionCoeff(TireTypeOFFROAD, HARD_TERRAIN, 0.85, 0.85, SnowCoeffFactor)
    REAwheels:SetFrictionCoeff(TireTypeOFFROAD, SOFT_TERRAIN, 0.84, 0.80, SnowCoeffFactor)
    REAwheels:SetFrictionCoeff(TireTypeOFFROAD, FIELD,        0.80, 0.75, SnowCoeffFactor)
    REAwheels.TireTypeMaxSinkFrictionReduced[TireTypeOFFROAD]    = 40
    REAwheels.TireTypeSinkStuckLevel[TireTypeOFFROAD]            = 90
    REAwheels.TireTypeSinkPerMeterSpinning[TireTypeOFFROAD]      = 0.03
    REAwheels.TireTypeMinRollingCoeff[TireTypeOFFROAD]           = 0.03

    -- STREET
    SnowCoeffFactor = 0.5
    REAwheels:SetFrictionCoeff(TireTypeSTREET, ROAD,         1.44, 0.95, SnowCoeffFactor)
    REAwheels:SetFrictionCoeff(TireTypeSTREET, HARD_TERRAIN, 0.66, 0.80, SnowCoeffFactor)
    REAwheels:SetFrictionCoeff(TireTypeSTREET, SOFT_TERRAIN, 0.68, 0.75, SnowCoeffFactor)
    REAwheels:SetFrictionCoeff(TireTypeSTREET, FIELD,        0.69, 0.60, SnowCoeffFactor)
    REAwheels.TireTypeMaxSinkFrictionReduced[TireTypeSTREET]     = 50
    REAwheels.TireTypeSinkStuckLevel[TireTypeSTREET]             = 80
    REAwheels.TireTypeSinkPerMeterSpinning[TireTypeSTREET]       = 0.02
    REAwheels.TireTypeMinRollingCoeff[TireTypeSTREET]            = 0.02

    -- CRAWLER
    SnowCoeffFactor = 0.6
    REAwheels:SetFrictionCoeff(TireTypeCRAWLER, ROAD,         0.85, 0.85, SnowCoeffFactor)
    REAwheels:SetFrictionCoeff(TireTypeCRAWLER, HARD_TERRAIN, 0.95, 0.85, SnowCoeffFactor)
    REAwheels:SetFrictionCoeff(TireTypeCRAWLER, SOFT_TERRAIN, 0.95, 0.80, SnowCoeffFactor)
    REAwheels:SetFrictionCoeff(TireTypeCRAWLER, FIELD,        0.92, 0.75, SnowCoeffFactor)
    REAwheels.TireTypeMaxSinkFrictionReduced[TireTypeCRAWLER]    = 40
    REAwheels.TireTypeSinkStuckLevel[TireTypeCRAWLER]            = 95
    REAwheels.TireTypeSinkPerMeterSpinning[TireTypeCRAWLER]      = 0.03
    REAwheels.TireTypeMinRollingCoeff[TireTypeCRAWLER]           = 0.10

    REAwheels.GlobalValuesSet = true
    print("Global REA Wheels Parameter geladen")
end

--------------------------------------------------------------------
-- Bodenfeuchte (vereinfachte Variante, basiert auf Wetter)
--------------------------------------------------------------------

function REAwheels:GetGroundWetness()
    if g_currentMission ~= nil
       and g_currentMission.environment ~= nil
       and g_currentMission.environment.weather ~= nil then
        local w = g_currentMission.environment.weather:getGroundWetness() or 0
        return REA_clamp(w * REAwheels.WetnessInfluence, 0, 1)
    end
    return 0
end

function REAwheels:UpdateGroundWetness(dt)
    -- hier einfach die Engine-Wetness benutzen, damit Server/Client gleich sind
    REAwheels.GroundWetnessFactor = REAwheels:GetGroundWetness()
end

--------------------------------------------------------------------
-- GetGroundType Safe
--------------------------------------------------------------------

function REAwheels:GetGroundType(wheel)
    if wheel == nil then
        return WheelsUtil.GROUND_HARD_TERRAIN
    end

    if wheel.contact == Wheels.WHEEL_NO_CONTACT then
        return WheelsUtil.GROUND_HARD_TERRAIN
    end

    if wheel.lastTerrainMaterial ~= nil then
        return wheel.lastTerrainMaterial
    end

    if wheel.lastContactTerrainType ~= nil then
        return wheel.lastContactTerrainType
    end

    return WheelsUtil.GROUND_HARD_TERRAIN
end

--------------------------------------------------------------------
-- Hauptphysik: UpdateWheels
--------------------------------------------------------------------

function REAwheels:UpdateWheels(vehicle, spec_wheels, spec_crawlers,
                                MotorizedVehicle, PowerConsumerActivated,
                                isTrailer, dt)

    if spec_wheels == nil or spec_wheels.wheels == nil then
        return
    end

    local wet = REAwheels:GetGroundWetness()
    local numWheels = #spec_wheels.wheels

    for i = 1, numWheels do
        local wheel = spec_wheels.wheels[i]
        if wheel.wheelShapeCreated then

            local ActWheelWidth  = wheel.width or 0.3
            local ActWheelRadius = wheel.radiusOriginal or wheel.radius or 0.5

            if wheel.WheelToSmall == nil then
                wheel.WheelToSmall = ActWheelRadius < REAwheels.MinWheelRadius
            end

            local MinWheelSink = 0.001
            local ActWheelSink = MinWheelSink
            if wheel.sink ~= nil then
                ActWheelSink = math.abs(math.max(wheel.sink, MinWheelSink))
            end

            local speed = math.abs(wheel.lastSpeed or 0)

            ----------------------------------------------------------------
            -- 1) Friction / Grip
            ----------------------------------------------------------------
            if MotorizedVehicle or isTrailer then
                if wheel.OrgFrictionScale == nil then
                    wheel.OrgFrictionScale = wheel.frictionScale
                end

                if speed > 0.05 then
                    local TireFriction = 0
                    if wheel.CrawlerTrackLength == nil then
                        TireFriction = (ActWheelWidth * 2) + (ActWheelRadius / 2)
                        if wheel.additionalWheels ~= nil then
                            local numAdditionalWheels = #wheel.additionalWheels
                            TireFriction = TireFriction + (numAdditionalWheels * (TireFriction * 0.5))
                        end
                    else
                        TireFriction = (ActWheelWidth * 1.33) + (wheel.CrawlerTrackLength / 2)
                    end

                    local ActWheelSinkPercentage =
                        (ActWheelSink / (REAwheels.WheelRadiusMaxSinkFactor * ActWheelRadius)) * 100

                    local tireTypeIndex = wheel.tireType or 1
                    local MaxSinkReduced   = REAwheels.TireTypeMaxSinkFrictionReduced[tireTypeIndex] or 30
                    local StuckLevel       = REAwheels.TireTypeSinkStuckLevel[tireTypeIndex] or 90

                    local FrictionFactorBySink = 1.0

                    if ActWheelSinkPercentage < StuckLevel then
                        FrictionFactorBySink = 1 - ((MaxSinkReduced * (ActWheelSinkPercentage / 100)) / 100)
                    else
                        FrictionFactorBySink = 0.05
                    end

                    -- Wetness senkt Grip
                    local wetGripFactor = 1 - (wet * 0.5)
                    FrictionFactorBySink = FrictionFactorBySink * wetGripFactor

                    -- globale Skalierung
                    FrictionFactorBySink = FrictionFactorBySink * REAwheels.WeightEffectScale

                    -- Helfer: Gewicht stärker spürbar
                    if REA_isHelper(vehicle) then
                        FrictionFactorBySink = FrictionFactorBySink * REAwheels.HelperPhysicsFactor
                    end

                    wheel.frictionScale = TireFriction * FrictionFactorBySink

                    if wheel.WheelToSmall == true then
                        wheel.frictionScale = wheel.frictionScale * 2.0
                    end
                else
                    wheel.frictionScale = wheel.OrgFrictionScale or wheel.frictionScale
                end
            end

            ----------------------------------------------------------------
            -- 2) Einfacher Rollwiderstand über „fiktiven Sink“-Faktor
            ----------------------------------------------------------------
            if wheel.node ~= nil and wheel.wheelShape ~= nil then
                local load = 0.0
                if getWheelShapeContactForce ~= nil and wheel.contact ~= Wheels.WHEEL_NO_CONTACT then
                    load = math.max(getWheelShapeContactForce(wheel.node, wheel.wheelShape), load)
                end

                local sinkStrength = ActWheelSink * REAwheels.WheelSinkScale
                local baseRR = sinkStrength * REAwheels.RollingResistanceScale * 0.02

                if load > 0 and baseRR > 0 and speed > 0.05 then
                    if wheel.OrgFrictionScale ~= nil then
                        wheel.frictionScale = wheel.frictionScale + baseRR
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------
-- Registrierung als Mod Event
--------------------------------------------------------------------

addModEventListener(REAwheels)
