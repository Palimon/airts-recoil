local base, turret, muzzle1 = piece("base", "turret", "muzzle1")

function script.Create() end

function script.QueryWeapon(w)   return muzzle1 end
function script.AimFromWeapon(w) return turret end
function script.AimWeapon(w, heading, pitch)
  Turn(turret, y_axis, heading, math.rad(360))
  return true
end
function script.FireWeapon(w) end

function script.Killed(recentDamage, maxHealth) return 1 end
