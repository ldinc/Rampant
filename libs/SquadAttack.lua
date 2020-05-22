if (squadAttackG) then
    return squadAttackG
end
local squadAttack = {}

-- imports

local constants = require("Constants")
local mapUtils = require("MapUtils")
local unitGroupUtils = require("UnitGroupUtils")
local movementUtils = require("MovementUtils")
local mathUtils = require("MathUtils")
local chunkPropertyUtils = require("ChunkPropertyUtils")
local chunkUtils = require("ChunkUtils")

-- constants

local PLAYER_PHEROMONE = constants.PLAYER_PHEROMONE
local MOVEMENT_PHEROMONE = constants.MOVEMENT_PHEROMONE
local BASE_PHEROMONE = constants.BASE_PHEROMONE
local RESOURCE_PHEROMONE = constants.RESOURCE_PHEROMONE

local ATTACK_SCORE_KAMIKAZE = constants.ATTACK_SCORE_KAMIKAZE

local DIVISOR_DEATH_TRAIL_TABLE = constants.DIVISOR_DEATH_TRAIL_TABLE

local BASE_CLEAN_DISTANCE = constants.BASE_CLEAN_DISTANCE

local SQUAD_BUILDING = constants.SQUAD_BUILDING

local SQUAD_RAIDING = constants.SQUAD_RAIDING
local SQUAD_SETTLING = constants.SQUAD_SETTLING
local SQUAD_GUARDING = constants.SQUAD_GUARDING
local SQUAD_RETREATING = constants.SQUAD_RETREATING

local AI_MAX_BITER_GROUP_SIZE = constants.AI_MAX_BITER_GROUP_SIZE

local ATTACK_QUEUE_SIZE = constants.ATTACK_QUEUE_SIZE

local AI_STATE_SIEGE = constants.AI_STATE_SIEGE

local PLAYER_PHEROMONE_MULTIPLER = constants.PLAYER_PHEROMONE_MULTIPLER

local DEFINES_GROUP_FINISHED = defines.group_state.finished
local DEFINES_GROUP_GATHERING = defines.group_state.gathering
local DEFINES_GROUP_MOVING = defines.group_state.moving
local DEFINES_DISTRACTION_NONE = defines.distraction.none
local DEFINES_DISTRACTION_BY_ENEMY = defines.distraction.by_enemy
local DEFINES_DISTRACTION_BY_ANYTHING = defines.distraction.by_anything

-- imported functions

local mRandom = math.random
local mMin = math.min
local tRemove = table.remove


local euclideanDistancePoints = mathUtils.euclideanDistancePoints

local findMovementPosition = movementUtils.findMovementPosition

local removeSquadFromChunk = chunkPropertyUtils.removeSquadFromChunk
local addDeathGenerator = chunkPropertyUtils.addDeathGenerator
local getDeathGenerator = chunkPropertyUtils.getDeathGenerator

local getNestCount = chunkPropertyUtils.getNestCount

local getNeighborChunks = mapUtils.getNeighborChunks
local addSquadToChunk = chunkPropertyUtils.addSquadToChunk
local getChunkByXY = mapUtils.getChunkByXY
local positionToChunkXY = mapUtils.positionToChunkXY
local addMovementPenalty = movementUtils.addMovementPenalty
local lookupMovementPenalty = movementUtils.lookupMovementPenalty
local calculateKamikazeThreshold = unitGroupUtils.calculateKamikazeThreshold
local positionFromDirectionAndChunk = mapUtils.positionFromDirectionAndChunk
local positionFromDirectionAndFlat = mapUtils.positionFromDirectionAndFlat

local createSquad = unitGroupUtils.createSquad

local euclideanDistanceNamed = mathUtils.euclideanDistanceNamed

local getPlayerBaseGenerator = chunkPropertyUtils.getPlayerBaseGenerator
local getResourceGenerator = chunkPropertyUtils.getResourceGenerator

local getChunkByPosition = mapUtils.getChunkByPosition

local scoreNeighborsForAttack = movementUtils.scoreNeighborsForAttack
local scoreNeighborsForSettling = movementUtils.scoreNeighborsForSettling

-- module code

local function scoreResourceLocation(squad, neighborChunk)
    local settle = neighborChunk[MOVEMENT_PHEROMONE] + neighborChunk[RESOURCE_PHEROMONE]
    return settle -- - lookupMovementPenalty(squad, neighborChunk)
        - (neighborChunk[PLAYER_PHEROMONE] * PLAYER_PHEROMONE_MULTIPLER)
end

local function scoreSiegeLocation(squad, neighborChunk)
    local settle = neighborChunk[MOVEMENT_PHEROMONE] + neighborChunk[BASE_PHEROMONE] + neighborChunk[RESOURCE_PHEROMONE] + (neighborChunk[PLAYER_PHEROMONE] * PLAYER_PHEROMONE_MULTIPLER)
    return settle -- - lookupMovementPenalty(squad, neighborChunk)
end

local function scoreAttackLocation(natives, squad, neighborChunk)
    local damage
    local movementPheromone = neighborChunk[MOVEMENT_PHEROMONE]

    if (movementPheromone >= 0) then
        damage = movementPheromone + (neighborChunk[BASE_PHEROMONE]) + (neighborChunk[PLAYER_PHEROMONE] * PLAYER_PHEROMONE_MULTIPLER)
    else
        damage = (neighborChunk[BASE_PHEROMONE] * (1 - (movementPheromone / -natives.retreatThreshold))) + (neighborChunk[PLAYER_PHEROMONE] * PLAYER_PHEROMONE_MULTIPLER) + (getPlayerBaseGenerator(natives.map, neighborChunk) * PLAYER_PHEROMONE_MULTIPLER)
    end

    return damage -- - lookupMovementPenalty(squad, neighborChunk)
end

local function scoreAttackKamikazeLocation(natives, squad, neighborChunk)
    local damage = neighborChunk[BASE_PHEROMONE] + (neighborChunk[PLAYER_PHEROMONE] * PLAYER_PHEROMONE_MULTIPLER) + (getPlayerBaseGenerator(natives.map, neighborChunk) * PLAYER_PHEROMONE_MULTIPLER)
    return damage -- - lookupMovementPenalty(squad, neighborChunk)
end


local function settleMove(map, squad, surface)
    local targetPosition = map.position
    local targetPosition2 = map.position2
    local group = squad.group

    local groupPosition = group.position
    local x, y = positionToChunkXY(groupPosition)
    local chunk = getChunkByXY(map, x, y)
    local scoreFunction = scoreResourceLocation
    local groupState = group.state
    local natives = map.natives
    if (natives.state == AI_STATE_SIEGE) then
        scoreFunction = scoreSiegeLocation
    end
    addMovementPenalty(squad, squad.chunk)
    addSquadToChunk(map, chunk, squad)
    local distance = euclideanDistancePoints(groupPosition.x,
                                             groupPosition.y,
                                             squad.originPosition.x,
                                             squad.originPosition.y)
    local cmd
    local position
    local position2

    if (distance >= squad.maxDistance) or ((getResourceGenerator(map, chunk) ~= 0) and (getNestCount(map, chunk) == 0))
    then
        position = findMovementPosition(surface, groupPosition)

        if not position then
            position = groupPosition
        end

        targetPosition.x = position.x
        targetPosition.y = position.y

        cmd = map.settleCommand
        if squad.kamikaze then
            cmd.distraction = DEFINES_DISTRACTION_NONE
        else
            cmd.distraction = DEFINES_DISTRACTION_BY_ENEMY
        end

        squad.status = SQUAD_BUILDING

        surface.create_entity(map.createBuildCloudQuery)

        if (euclideanDistanceNamed(targetPosition, group.position) > 200) then
            print("fuck")
        end

        group.set_command(cmd)
    else
        local attackChunk, attackDirection, nextAttackChunk, nextAttackDirection = scoreNeighborsForSettling(map,
                                                                                                             chunk,
                                                                                                             getNeighborChunks(map, x, y),
                                                                                                             scoreFunction,
                                                                                                             squad)


        if (attackChunk == -1) then
            cmd = map.wonderCommand
            group.set_command(cmd)
            return
        elseif (attackDirection ~= 0) then
            local attackPlayerThreshold = natives.attackPlayerThreshold

            if (nextAttackChunk ~= -1) then
                attackChunk = nextAttackChunk
                positionFromDirectionAndFlat(attackDirection, groupPosition, targetPosition)
                positionFromDirectionAndFlat(nextAttackDirection, targetPosition, targetPosition2)
                position = findMovementPosition(surface, targetPosition2)

                if position and (euclideanDistanceNamed(position, group.position) > 200) then
                    print("tp2", serpent.dump(targetPosition))
                    print("tp3", serpent.dump(targetPosition2))
                    print("tp", serpent.dump(position))
                    print("gp", serpent.dump(group.position))
                    print("fuck set2")
                end
            else
                positionFromDirectionAndFlat(attackDirection, groupPosition, targetPosition)
                position = findMovementPosition(surface, targetPosition)

                if position and (euclideanDistanceNamed(position, group.position) > 200) then
                    print("tp2", serpent.dump(targetPosition))                    
                    print("tp", serpent.dump(position))
                    print("gp", serpent.dump(group.position))
                    print("fuck set3")
                end

            end

            if position then
                targetPosition.x = position.x
                targetPosition.y = position.y
            else
                cmd = map.wonderCommand
                group.set_command(cmd)
                return
            end

            if (getPlayerBaseGenerator(map, attackChunk) ~= 0) or
                (attackChunk[PLAYER_PHEROMONE] >= attackPlayerThreshold)
            then
                cmd = map.attackCommand

                if not squad.rabid then
                    squad.frenzy = true
                    squad.frenzyPosition.x = groupPosition.x
                    squad.frenzyPosition.y = groupPosition.y
                end
            else
                cmd = map.moveCommand
                if squad.rabid or squad.kamikaze then
                    cmd.distraction = DEFINES_DISTRACTION_NONE
                else
                    cmd.distraction = DEFINES_DISTRACTION_BY_ENEMY
                end
            end
        else
            cmd = map.settleCommand
            cmd.destination.x = groupPosition.x
            cmd.destination.y = groupPosition.y
            
            if squad.kamikaze then
                cmd.distraction = DEFINES_DISTRACTION_NONE
            else
                cmd.distraction = DEFINES_DISTRACTION_BY_ENEMY
            end

            squad.status = SQUAD_BUILDING

            surface.create_entity(map.createBuildCloudQuery)
        end

        if (euclideanDistanceNamed(targetPosition, group.position) > 200) then
            print("tp", serpent.dump(targetPosition))
            print("gp", serpent.dump(group.position))
            print("fuck set")
        end

        group.set_command(cmd)
    end
end

local function attackMove(map, squad, surface)

    local targetPosition = map.position
    local targetPosition2 = map.position2

    local group = squad.group

    local position
    local groupPosition = group.position
    local x, y = positionToChunkXY(groupPosition)
    local chunk = getChunkByXY(map, x, y)
    local attackScorer = scoreAttackLocation
    if squad.kamikaze then
        attackScorer = scoreAttackKamikazeLocation
    end
    local squadChunk = squad.chunk
    addMovementPenalty(squad, squadChunk)
    addSquadToChunk(map, chunk, squad)
    squad.frenzy = (squad.frenzy and (euclideanDistanceNamed(groupPosition, squad.frenzyPosition) < 100))
    local attackChunk, attackDirection, nextAttackChunk, nextAttackDirection = scoreNeighborsForAttack(map,
                                                                                                       chunk,
                                                                                                       getNeighborChunks(map, x, y),
                                                                                                       attackScorer,
                                                                                                       squad)
    if (attackChunk == -1) then
        cmd = map.wonderCommand
        group.set_command(cmd)
        return
    elseif (nextAttackChunk ~= -1) then
        attackChunk = nextAttackChunk
        positionFromDirectionAndFlat(attackDirection, groupPosition, targetPosition)
        positionFromDirectionAndFlat(nextAttackDirection, targetPosition, targetPosition2)
        position = findMovementPosition(surface, targetPosition2)
    else
        positionFromDirectionAndFlat(attackDirection, groupPosition, targetPosition)
        position = findMovementPosition(surface, targetPosition)
    end

    if not position then
        cmd = map.wonderCommand
        group.set_command(cmd)
        return
    else
        targetPosition.x = position.x
        targetPosition.y = position.y
    end

    if (getPlayerBaseGenerator(map, attackChunk) ~= 0) and
        (attackChunk[PLAYER_PHEROMONE] >= map.natives.attackPlayerThreshold)
    then
        cmd = map.attackCommand

        if not squad.rabid then
            squad.frenzy = true
            squad.frenzyPosition.x = groupPosition.x
            squad.frenzyPosition.y = groupPosition.y
        end
    else
        cmd = map.moveCommand
        if squad.rabid or squad.frenzy then
            cmd.distraction = DEFINES_DISTRACTION_BY_ANYTHING
        else
            cmd.distraction = DEFINES_DISTRACTION_BY_ENEMY
        end
    end

    if (euclideanDistanceNamed(targetPosition, group.position) > 200) then
        print("tp", serpent.dump(targetPosition))
        print("gp", serpent.dump(group.position))
        print("fuck atk")
    end

    group.set_command(cmd)
end

local function buildMove(map, squad, surface)
    local group = squad.group
    local position = map.position
    local groupPosition = findMovementPosition(surface, group.position)

    if not groupPosition then
        groupPosition = group.position
    end

    position.x = groupPosition.x
    position.y = groupPosition.y

    group.set_command(map.compoundSettleCommand)
end

function squadAttack.squadDispatch(map, surface, squad)
    -- local profiler = game.create_profiler()
    local group = squad.group
    if group and group.valid then
        local status = squad.status
        if (status == SQUAD_RAIDING) then
            attackMove(map, squad, surface)
        elseif (status == SQUAD_SETTLING) then
            settleMove(map, squad, surface)
        elseif (status == SQUAD_RETREATING) then
            if squad.settlers then
                squad.status = SQUAD_SETTLING
                settleMove(map, squad, surface)
            else
                squad.status = SQUAD_RAIDING
                attackMove(map, squad, surface)
            end
        elseif (status == SQUAD_BUILDING) then
            removeSquadFromChunk(map, squad)
            buildMove(map, squad, surface)
        elseif (status == SQUAD_GUARDING) then
            if squad.settlers then
                squad.status = SQUAD_SETTLING
                settleMove(map, squad, surface)
            else
                squad.status = SQUAD_RAIDING
                attackMove(map, squad, surface)
            end
        end
    end
    -- game.print({"", "--dispatch4 ", profiler})
end

squadAttackG = squadAttack
return squadAttack
