-- Copyright (C) 2022  veden

-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.

-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.

-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.


if playerUtilsG then
    return playerUtilsG
end
local playerUtils = {}

-- imports

-- imported functions

-- module code

function playerUtils.validPlayer(player)
    if player and player.valid then
        local char = player.character
        return char and char.valid
    end
    return false
end

playerUtilsG = playerUtils
return playerUtils
