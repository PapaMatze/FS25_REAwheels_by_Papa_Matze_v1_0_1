-- ===========================================================
-- REA Wheels – Enhanced FS25 Physics Edition (v1.0.5)
-- by Papa_Matze – Final patched version for FS25
-- ===========================================================

REA_WHEELS = {}
local modName = "REAwheels"

-- ============================================
-- Global Settings (Realism+)
-- ============================================
REA_WHEELS.SINK_SCALE          = 2.5   -- Tiefes Einsinken
REA_WHEELS.SLIP_SINK_SCALE     = 2.8   -- Zusätzlicher Sinkfaktor bei Wheel-Slip
REA_WHEELS.MAX_SINK_BOOST      = 2.6   -- Extremfall
REA_WHEELS.ROLL_RESISTANCE     = 2.0   -- Rollwiderstand
REA_WHEELS.WEIGHT_INFLUENCE    = 2.0   -- Gewichtsübertragung
REA_WHEELS.WETNESS_MULTIPLIER  = 1.5   -- Mud/Wet Boost
REA_WHEELS.DEBUG_ENABLED       = false -- Wird via F9 gesteuert
REA_WHEELS.DEBUG_TIMER         = 0

-- ============================================
-- F9 Debug Toggle (oben rechts anzeigen)
-- ============================================
function REA_WHEELS:keyEvent(unicode, sym, modifier, isDown)
    if sym == Input.KEY_f9 and not isDown then
        REA_WHEELS.DEBUG_ENABLED = not REA_WHEELS.DEBUG_ENABLED
        REA_WHEELS.DEBUG_TIMER = 5000
        print("REA Wheels Debug = " .. tostring(REA_WHEELS.DEBUG_ENABLED))
    end
end

-- ============================================
-- Bodenfarbe übernehmen (Dynamic Dirt FS25)
-- ============================================
function REA_WHEELS:applyGroundColor(vehicle, wheel, groundType)
    if wheel == nil or vehicle == nil then return end

    local color = {1,1,1}

    if groundType == GroundType.SOIL then color = {0.25,0.20,0.15} end
    if groundType == GroundType.MUD then  color = {0.18,0.12,0.08} end
    if groundType == GroundType.GRASS then color = {0.10,0.25,0.10} end
    if groundType == GroundType.LIME then  color = {0.92,0.90,0.80} end
    if groundType == GroundType.ROAD then  color = {0.05,0.05,0.05} end
    if groundType == GroundType.SNOW then  color = {0.90,0.90,1.00} end

    setShaderParameter(wheel.node, "colorScale", color[1], color[2], color[3], 1, false)
end

-- ============================================
-- Update
-- ============================================
function REA_WHEELS:update(dt)
    if REA_WHEELS.DEBUG_ENABLED then
        REA_WHEELS.DEBUG_TIMER = REA_WHEELS.DEBUG_TIMER - dt
        if REA_WHEELS.DEBUG_TIMER <= 0 then
            REA_WHEELS.DEBUG_ENABLED = false
        end
    end

    -- Safety: abort if mission or vehicle list not ready yet
    if g_currentMission == nil or g_currentMission.vehicles == nil then
        return
    end

    for _, vehicle in pairs(g_currentMission.vehicles) do
        if vehicle.spec_wheels then
            REA_WHEELS:processVehicle(vehicle, dt)
        end
    end
end

-- ============================================
-- Fahrzeugverarbeitung
-- ============================================
function REA_WHEELS:processVehicle(vehicle, dt)
    local spec = vehicle.spec_wheels
    if not spec.wheels then return end

    for _, wheel in pairs(spec.wheels) do
        if wheel.wheelShapeCreated then
            REA_WHEELS:processWheel(vehicle, wheel, dt)
        end
    end
end

-- ============================================
-- Einzelradphysik
-- ============================================
function REA_WHEELS:processWheel(vehicle, wheel, dt)
    local vx, vy, vz = getWheelShapeVelocity(wheel.node, wheel.wheelShape)
    local speed = math.sqrt(vx*vx + vz*vz)

    -- Grip check
    local slip = math.max(0, wheel.slip or 0)

    -- Ground type
    local groundType = getWheelShapeGroundType(wheel.node, wheel.wheelShape) or GroundType.SOIL

    -- Farbübernahme
    REA_WHEELS:applyGroundColor(vehicle, wheel, groundType)

    -- Sink factor
    local sink = REA_WHEELS.SINK_SCALE
    sink = sink + slip * REA_WHEELS.SLIP_SINK_SCALE

    if speed < 0.8 then
        sink = sink * REA_WHEELS.MAX_SINK_BOOST
    end

    -- Wetness boost
    local wetFactor = g_currentMission.environment.weather:getGroundWetness() or 0
    sink = sink + (wetFactor * REA_WHEELS.WETNESS_MULTIPLIER)

    -- Apply sink
    wheel.sink = (wheel.sink or 0) + (sink * 0.0004)

    if wheel.sink > 0.25 then
        wheel.sink = 0.25 -- Limit
    end

    -- Weight influence
    wheel.load = (wheel.load or 0) * REA_WHEELS.WEIGHT_INFLUENCE

    -- Braking reduction (kein Motorbremsen beim Gas loslassen)
    if vehicle.spec_motorized then
        vehicle.spec_motorized.brakePedal = math.min(vehicle.spec_motorized.brakePedal * 0.4, 0.2)
    end

    -- Debug text oben rechts
    if REA_WHEELS.DEBUG_ENABLED then
        setTextAlignment(RenderText.ALIGN_RIGHT)
        renderText(0.98, 0.88, 0.018, string.format("REA Wheels v1.0.5"))
        renderText(0.98, 0.86, 0.018, string.format("Sink %.3f", wheel.sink))
        renderText(0.98, 0.84, 0.018, string.format("Slip %.3f", slip))
        renderText(0.98, 0.82, 0.018, string.format("Load %.3f", wheel.load or 0))
        renderText(0.98, 0.80, 0.018, "Ground: " .. tostring(groundType))
    end
end

-- ============================================
-- FS25 Registrierung
-- ============================================
function REA_WHEELS.prerequisitesPresent(specializations)
    return true
end

function REA_WHEELS.registerOverwrittenFunctions(vehicleType)
end

function REA_WHEELS.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "update", REA_WHEELS)
    SpecializationUtil.registerEventListener(vehicleType, "keyEvent", REA_WHEELS)
end

addModEventListener(REA_WHEELS)
