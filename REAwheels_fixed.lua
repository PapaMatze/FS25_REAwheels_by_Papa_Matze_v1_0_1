-- REAwheels_fixed.lua - safe neutral behavior
local function applyNeutral(vehicle)
    if vehicle and vehicle.wheels then
        for _, w in ipairs(vehicle.wheels) do
            if w.latStiffness then w.latStiffness = w.latStiffness * 1.03 end
            if w.longStiffness then w.longStiffness = w.longStiffness * 1.01 end
        end
    end
end

Vehicle.update = Utils.appendedFunction(Vehicle.update, function(self, dt)
    applyNeutral(self)
end)
