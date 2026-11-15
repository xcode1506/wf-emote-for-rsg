--------------------------------------------------------------------------
-- WF-EMOTE (server)
-- Author: Hugo
-- Favourites & recent animations, saved per character (oxmysql).
--------------------------------------------------------------------------
local function started(name)
    local state = GetResourceState(name)
    return state == 'started' or state == 'starting'
end

local framework = (WF.Framework or 'auto'):lower()
if framework ~= 'rsg' and framework ~= 'vorp' then
    framework = started('rsg-core') and 'rsg' or started('vorp_core') and 'vorp' or 'none'
end

local RSGCore, VORPCore
if framework == 'rsg' then
    RSGCore = exports['rsg-core']:GetCoreObject()
elseif framework == 'vorp' then
    VORPCore = exports.vorp_core:GetCore()
end

local function characterId(src)
    if framework == 'rsg' then
        local Player = RSGCore.Functions.GetPlayer(src)
        return Player and Player.PlayerData.citizenid
    end
    if framework == 'vorp' then
        local user = VORPCore.getUser(src)
        local char = user and user.getUsedCharacter
        return char and char.charIdentifier and tostring(char.charIdentifier)
    end
    return GetPlayerIdentifierByType(src, 'license')
end

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `wf_emotes` (
            `identifier` VARCHAR(64) NOT NULL,
            `favorites`  LONGTEXT NOT NULL,
            `recent`     LONGTEXT NOT NULL,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
end)

local validId = {}
for _, anim in ipairs(WF.Animations) do validId[anim.Command] = true end

local function decode(str)
    local ok, data = pcall(json.decode, str or '[]')
    return ok and type(data) == 'table' and data or {}
end

local function cleanList(list, limit)
    local out, seen = {}, {}
    if type(list) ~= 'table' then return out end
    for _, id in ipairs(list) do
        if #out >= limit then break end
        if type(id) == 'string' and validId[id] and not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    return out
end

RegisterNetEvent('wf_emote:load', function()
    local src = source
    local id = characterId(src)
    if not id then
        -- character not ready yet: still answer so the client does not hit its
        -- 5 second timeout; it reloads once the framework fires the load event
        TriggerClientEvent('wf_emote:loaded', src, { favorites = {}, recent = {} })
        return
    end

    local ok, row = pcall(function()
        return MySQL.single.await('SELECT favorites, recent FROM wf_emotes WHERE identifier = ?', { id })
    end)
    if not ok then row = nil end
    TriggerClientEvent('wf_emote:loaded', src, {
        favorites = cleanList(row and decode(row.favorites), 200),
        recent    = cleanList(row and decode(row.recent), 12),
    })
end)

local lastSave = {}
local lastShared = {}
RegisterNetEvent('wf_emote:save', function(data)
    local src = source
    if type(data) ~= 'table' then return end

    local id = characterId(src)
    if not id then return end

    local now = GetGameTimer()
    if lastSave[src] and now - lastSave[src] < 500 then return end
    lastSave[src] = now

    MySQL.prepare([[
        INSERT INTO wf_emotes (identifier, favorites, recent) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE favorites = VALUES(favorites), recent = VALUES(recent)
    ]], {
        id,
        json.encode(cleanList(data.favorites, 200)),
        json.encode(cleanList(data.recent, 12)),
    })
end)

AddEventHandler('playerDropped', function()
    local src = source
    lastSave[src] = nil
    lastShared[src] = nil
end)

---------------------------------------------------------------------------
-- Shared emotes: validate and relay to both players
-- (reference: rpemotes shared emotes flow)
---------------------------------------------------------------------------
local SHARED_MAX_DISTANCE = 5.0
local SHARED_COOLDOWN_MS  = 1500

-- Positions come from the initiator, so only accept values close to where each
-- ped actually is; anything further looks like a teleport attempt.
local function sanitizePos(pos, ped)
    if type(pos) ~= 'table' then return nil end
    local x, y, z, h = tonumber(pos.x), tonumber(pos.y), tonumber(pos.z), tonumber(pos.h)
    if not x or not y or not z or not h then return nil end
    if math.abs(x) > 20000.0 or math.abs(y) > 20000.0 or z < -1000.0 or z > 5000.0 then return nil end
    local c = GetEntityCoords(ped)
    local dx, dy, dz = x - c.x, y - c.y, z - c.z
    if math.sqrt(dx * dx + dy * dy + dz * dz) > SHARED_MAX_DISTANCE then return nil end
    return { x = x, y = y, z = z, h = h }
end

RegisterNetEvent('wf_emote:sharedRequest', function(emoteId, targetSrc, pose)
    local src = source
    if type(emoteId) ~= 'string' or not validId[emoteId] then return end
    targetSrc = tonumber(targetSrc)
    if not targetSrc or targetSrc == src or not GetPlayerName(targetSrc) then return end

    local now = GetGameTimer()
    if lastShared[src] and now - lastShared[src] < SHARED_COOLDOWN_MS then return end

    local ped = GetPlayerPed(src)
    local targetPed = GetPlayerPed(targetSrc)
    if not ped or ped == 0 or not targetPed or targetPed == 0 then return end
    if #(GetEntityCoords(ped) - GetEntityCoords(targetPed)) > SHARED_MAX_DISTANCE then return end

    local mainPos, partnerPos
    if type(pose) == 'table' then
        mainPos = sanitizePos(pose.main, ped)
        partnerPos = sanitizePos(pose.partner, targetPed)
        if not mainPos or not partnerPos then mainPos, partnerPos = nil, nil end
    end

    lastShared[src] = now
    TriggerClientEvent('wf_emote:sharedPlay', targetSrc, emoteId, src, true, partnerPos)
    TriggerClientEvent('wf_emote:sharedPlay', src, emoteId, targetSrc, false, mainPos)
end)
