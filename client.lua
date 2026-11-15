--------------------------------------------------------------------------
-- WF-EMOTE (client)
-- Author: Hugo
-- Menu is drawn by this resource's own NUI page (ui/), with scrolling lists
-- and a 3D clone preview before selecting. No external menu resource needed.
--------------------------------------------------------------------------
local byId = {}
local byCategory = {}
for _, anim in ipairs(WF.Animations) do
    byId[anim.Command] = anim
    byCategory[anim.Category] = byCategory[anim.Category] or {}
    byCategory[anim.Category][#byCategory[anim.Category] + 1] = anim
end

local isOpen = false
local nearestPlayer  -- forward declaration
local data, pendingCb -- data = { favorites = {}, recent = {} }
local playing
local previewPed, previewCam

local function L(key, fallback)
    return fallback or key
end

local function rawNotify(n)
    if lib and lib.notify then return lib.notify(n) end
    TriggerEvent('chat:addMessage', { color = { 214, 156, 63 }, multiline = true, args = { n.title or 'WF Emote', n.description or '' } })
end

local function notify(text, kind)
    rawNotify({ title = 'WF Emote', description = text, type = kind or 'inform' })
end

---------------------------------------------------------------------------
-- Saving (debounced) + per character load
---------------------------------------------------------------------------
local saveQueued = false
local function queueSave()
    if saveQueued or not data then return end
    saveQueued = true
    SetTimeout(1500, function()
        saveQueued = false
        TriggerServerEvent('wf_emote:save', data)
    end)
end

local function loadData(cb)
    if data then return cb(true) end
    if not pendingCb then
        pendingCb = cb
        TriggerServerEvent('wf_emote:load')
        SetTimeout(5000, function()
            if pendingCb == cb then
                pendingCb = nil
                cb(false)
            end
        end)
    else
        local chained = cb
        SetTimeout(100, function()
            if data then return chained(true) end
            loadData(chained)
        end)
    end
end

RegisterNetEvent('wf_emote:loaded', function(payload)
    data = payload
    if pendingCb then
        local cb = pendingCb
        pendingCb = nil
        cb(true)
    end
end)

RegisterNetEvent('RSGCore:Client:OnPlayerLoaded', function() data = nil end)
RegisterNetEvent('RSGCore:Client:OnPlayerUnload', function() data = nil end)
RegisterNetEvent('vorp:SelectedCharacter', function() data = nil end)

local function pushRecent(id)
    if not data then return end
    local list = { id }
    for _, v in ipairs(data.recent) do
        if v ~= id and #list < 12 then list[#list + 1] = v end
    end
    data.recent = list
    queueSave()
end

---------------------------------------------------------------------------
-- Playback
---------------------------------------------------------------------------
local function loadDict(dict)
    if not DoesAnimDictExist(dict) then return false end
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > timeout then return false end
        Wait(10)
    end
    return true
end

local function deletePropHandles(handles)
    if not handles then return end
    for _, handle in ipairs(handles) do
        if handle and handle ~= 0 and DoesEntityExist(handle) then
            DetachEntity(handle, true, true)
            SetEntityAsMissionEntity(handle, true, true)
            DeleteObject(handle)
        end
    end
end

local function attachProps(ped, anim, alpha)
    if not anim.Props then return nil end
    local handles = {}
    local coords  = GetEntityCoords(ped)

    for _, prop in ipairs(anim.Props) do
        local hash = joaat(prop.model)
        RequestModel(hash)
        local deadline = GetGameTimer() + 3000
        while not HasModelLoaded(hash) and GetGameTimer() < deadline do
            Wait(10)
        end

        -- never attach a model that failed to stream; it would create an
        -- invisible placeholder object
        if HasModelLoaded(hash) then
            local handle = CreateObject(hash, coords.x, coords.y, coords.z, false, false, false)
            if handle and handle ~= 0 and DoesEntityExist(handle) then
                SetEntityAsMissionEntity(handle, true, true)

                local o = prop.offset or { 0.0, 0.0, 0.0 }
                local r = prop.rotation or { 0.0, 0.0, 0.0 }
                local bone = GetPedBoneIndex(ped, joaat(prop.bone))

                -- RedM attach: soft pinning on, world collision off (a colliding
                -- prop fights the ped and drifts), ped bone, fixed rotation.
                AttachEntityToEntity(handle, ped, bone, o[1], o[2], o[3], r[1], r[2], r[3], true, true, false, true, 2, true)
                SetEntityCollision(handle, false, false)
                if alpha then SetEntityAlpha(handle, alpha, false) end

                handles[#handles + 1] = handle
            end
            SetModelAsNoLongerNeeded(hash)
        end
    end
    return handles
end

local function stopAnimation(silent)
    local ped = PlayerPedId()
    local was = playing
    if was then deletePropHandles(was.props) end
    ClearPedTasks(ped)
    playing = nil
    if was and not silent then notify(L('stopped', 'Animation stopped.')) end
end

local function playAnimation(id, mode, role)
    local anim = byId[id]
    if not anim then return false, ('Animation "%s" not found.'):format(tostring(id)) end

    local ped = PlayerPedId()
    if IsEntityDead(ped) or IsPedRagdoll(ped) or IsPedSwimming(ped) or IsPedFalling(ped) then
        return false, L('cant_now', 'You cannot play animations right now.')
    end

    mode = mode == 'upper' and 'upper' or 'full'
    if IsPedOnMount(ped) or IsPedInAnyVehicle(ped, false) then
        if anim.Type == 'Scenario' then return false, L('not_on_horse', 'This animation cannot be played on horseback.') end
        mode = 'upper'
    end

    if playing then stopAnimation(true) end
    if mode == 'upper' then ClearPedSecondaryTask(ped) else ClearPedTasks(ped) end

    local dict, body, flag = anim.Dict, anim.Body, anim.Flag
    local partner = role == 'partner' and anim.Partner or nil
    if partner then
        dict = partner.Dict or dict
        body = partner.Body or body
        flag = partner.Flag or flag
    end

    local props
    if anim.Type == 'Anim' or anim.Type == 'Clip' or anim.Type == 'Prop' then
        if not loadDict(dict) then
            return false, L('load_failed', 'Could not load the animation.') .. ' (' .. dict .. ')'
        end
        if anim.Type == 'Clip' and WF.HolsterWeapon then
            SetCurrentPedWeapon(ped, joaat('WEAPON_UNARMED'), true)
        end
        local taskFlag = mode == 'upper' and (anim.UpperFlag or 31) or (flag or 0)
        local blendIn  = anim.BlendIn  or WF.ClipDefaults.BlendIn
        local blendOut = anim.BlendOut or WF.ClipDefaults.BlendOut
        TaskPlayAnim(ped, dict, body, blendIn, blendOut, -1, taskFlag, 1, false, false, false, 0, true)
        RemoveAnimDict(dict)
        if anim.Type == 'Prop' then
            props = attachProps(ped, anim)
        end
    elseif anim.Type == 'Emote' then
        local category = anim.EmoteCategory or 0
        if mode == 'upper' then
            Citizen.InvokeNative(0xB31A277C1AC7B7FF, ped, category, 0, joaat(anim.EmoteType), 1, 1, 0, 0, 0)
        else
            Citizen.InvokeNative(0xB31A277C1AC7B7FF, ped, category, 2, joaat(anim.EmoteType), 0, 0, 0, 0, 0)
        end
    elseif anim.Type == 'Scenario' then
        TaskStartScenarioInPlace(ped, joaat(anim.Scenario), -1, true)
    else
        return false, ('Animation "%s" not found.'):format(id)
    end

    playing = { id = id, anim = anim, mode = mode, since = GetGameTimer(), dict = dict, body = body, props = props }
    pushRecent(id)
    return true
end

local function stillPlaying()
    local ped = PlayerPedId()
    local anim = playing.anim
    if GetGameTimer() - playing.since < 1000 then return true end
    if anim.Type == 'Anim' or anim.Type == 'Clip' or anim.Type == 'Prop' then
        return IsEntityPlayingAnim(ped, playing.dict or anim.Dict, playing.body or anim.Body, 3)
    end
    if anim.Type == 'Scenario' then return IsPedUsingAnyScenario(ped) end
    return GetGameTimer() - playing.since < 6000 -- KIT emotes play once
end

CreateThread(function()
    while true do
        if playing then
            if not stillPlaying() then
                deletePropHandles(playing.props)
                playing = nil
            elseif not isOpen and WF.StopKey then
                for _ = 1, 25 do
                    Wait(0)
                    if not playing then break end
                    if IsControlJustReleased(0, WF.StopKey) then
                        stopAnimation(true)
                        break
                    end
                end
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

---------------------------------------------------------------------------
-- 3D clone preview (same technique as wf-interact): a local clone plays the
-- animation in front of the player while browsing the menu.
---------------------------------------------------------------------------
local previewToken = 0
local previewProps

local function deleteGhost(ghost)
    if ghost and ghost ~= 0 and DoesEntityExist(ghost) then
        ClearPedTasksImmediately(ghost)
        SetEntityAsMissionEntity(ghost, true, true)
        DeleteEntity(ghost)
    end
end

local function sampleGroundZ(x, y, z)
    if type(GetGroundZFor_3dCoord) == 'function' then
        -- probe slightly above the player's feet; ignore hits far below the
        -- player (bridges, wagons, interiors) so the clone never sinks
        local ok, gz = GetGroundZFor_3dCoord(x, y, z + 1.0, false)
        if ok and gz and gz > -100.0 and math.abs(gz - z) <= 0.75 then
            return gz + 0.03
        end
    end
    return z
end

local function previewPosition(ped)
    local dist = WF.Preview.distance or 2.4
    local coords = GetEntityCoords(ped)
    -- local +Y is forward, so this is independent of the heading convention
    local pos = GetOffsetFromEntityInWorldCoords(ped, 0.0, dist, 0.0)
    return pos.x, pos.y, sampleGroundZ(pos.x, pos.y, coords.z)
end

local function stopPreview()
    previewToken = previewToken + 1
    if previewCam then
        RenderScriptCams(false, true, 400, true, true, 0)
        SetCamActive(previewCam, false)
        DestroyCam(previewCam, false)
        previewCam = nil
    end
    deletePropHandles(previewProps)
    previewProps = nil
    deleteGhost(previewPed)
    previewPed = nil
end

local function playPreviewOnGhost(ghost, anim, x, y, z, heading)
    if not DoesEntityExist(ghost) then return end
    if anim.Type == 'Anim' or anim.Type == 'Clip' or anim.Type == 'Prop' then
        if not loadDict(anim.Dict) then return end
        -- loadDict yields: the ghost may have been replaced or deleted meanwhile
        if not DoesEntityExist(ghost) then return end
        TaskPlayAnim(ghost, anim.Dict, anim.Body, WF.ClipDefaults.BlendIn, WF.ClipDefaults.BlendOut, -1, anim.Flag or 1, 1, false, false, false, 0, true)
        RemoveAnimDict(anim.Dict)
        if anim.Type == 'Prop' then return attachProps(ghost, anim, WF.Preview.alpha or 105) end
    elseif anim.Type == 'Emote' then
        Citizen.InvokeNative(0xB31A277C1AC7B7FF, ghost, anim.EmoteCategory or 0, 2, joaat(anim.EmoteType), 0, 0, 0, 0, 0)
    elseif anim.Type == 'Scenario' then
        TaskStartScenarioAtPosition(ghost, joaat(anim.Scenario), x, y, z, heading, -1, false, true)
    end
end

local function startPreview(anim)
    if WF.Preview.enabled == false then return end

    local token = previewToken + 1
    previewToken = token

    CreateThread(function()
        local ped = PlayerPedId()
        if not DoesEntityExist(ped) or IsPedDeadOrDying(ped) then return end

        -- a fresh token invalidates older threads
        if previewToken ~= token then return end

        deleteGhost(previewPed)
        previewPed = nil
        deletePropHandles(previewProps)
        previewProps = nil
        if previewCam then
            SetCamActive(previewCam, false)
            DestroyCam(previewCam, false)
            previewCam = nil
        end

        local x, y, z = previewPosition(ped)
        local heading = GetEntityHeading(ped) + 180.0

        local ghost = ClonePed(ped, false, false, false)
        if not ghost or ghost == 0 or not DoesEntityExist(ghost) or ghost == ped then return end

        SetEntityAsMissionEntity(ghost, true, true)
        NetworkSetEntityInvisibleToNetwork(ghost, true)
        -- a clone can inherit a ragdoll or a half-finished task from the source
        -- ped; clear it before freezing or it collapses on spawn
        ClearPedTasksImmediately(ghost)
        SetEntityCollision(ghost, false, false)
        SetEntityInvincible(ghost, true)
        SetPedCanRagdoll(ghost, false)
        SetBlockingOfNonTemporaryEvents(ghost, true)
        RemoveAllPedWeapons(ghost, true, true)
        SetEntityAlpha(ghost, WF.Preview.alpha or 105, false)

        SetEntityCoordsNoOffset(ghost, x, y, z)
        SetEntityHeading(ghost, heading)
        -- collision is off so the player can walk through the clone; freeze it
        -- on the sampled ground or it drops through the terrain
        FreezeEntityPosition(ghost, true)

        -- let the clone settle before tasking, then pin it again: some frames
        -- still apply gravity while the clone streams in
        Wait(100)

        if not DoesEntityExist(ghost) or previewToken ~= token then
            deleteGhost(ghost)
            return
        end

        SetEntityCollision(ghost, false, false)
        SetPedCanRagdoll(ghost, false)
        SetEntityCoordsNoOffset(ghost, x, y, z)
        SetEntityHeading(ghost, heading)
        FreezeEntityPosition(ghost, true)

        previewPed = ghost
        local handles = playPreviewOnGhost(ghost, anim, x, y, z, heading)

        -- playPreviewOnGhost may yield inside loadDict; drop this ghost when a
        -- newer preview (or stopPreview) took over while waiting
        if previewToken ~= token then
            if previewPed == ghost then previewPed = nil end
            deletePropHandles(handles)
            deleteGhost(ghost)
            return
        end
        previewProps = handles

        if WF.Preview.camera and DoesEntityExist(ghost) then
            local off = WF.Preview.cameraOffset
            local camPos = GetOffsetFromEntityInWorldCoords(ped, off.x, off.y, off.z)
            local aim = GetOffsetFromEntityInWorldCoords(ghost, 0.0, 0.0, WF.Preview.aimHeight or 0.1)
            local tx, ty, tz = aim.x, aim.y, aim.z
            -- the book only covers the left side; aim to the side so the clone
            -- performs on the right, clear of the paper panel
            local shift = WF.Preview.sideShift or 0.0
            if shift ~= 0.0 then
                local dx, dy = tx - camPos.x, ty - camPos.y
                local len = math.sqrt(dx * dx + dy * dy)
                if len > 0.001 then
                    tx = tx - (dy / len) * shift
                    ty = ty + (dx / len) * shift
                end
            end
            if previewCam then
                DestroyCam(previewCam, false)
                previewCam = nil
            end
            previewCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', camPos.x, camPos.y, camPos.z, 0.0, 0.0, 0.0, WF.Preview.fov or 46.0, false, 0)
            PointCamAtCoord(previewCam, tx, ty, tz)
            SetCamActive(previewCam, true)
            RenderScriptCams(true, true, 400, true, true, 0)
        end
    end)
end

---------------------------------------------------------------------------
-- Menu (own NUI page in ui/)
--
-- The whole book is rendered by this resource's own ui_page, so no other
-- menu resource is needed. The game keeps keyboard focus off the player and
-- the page draws the list; callbacks come back through RegisterNUICallback.
---------------------------------------------------------------------------
local nuiHandlers
local currentRender
local toggleFavourite
local openRoot, openMenu, openMenuNode, openCategory, openTabValue

-- tab strip of the F7 book (icons are PNG masks in ui/assets/icons)
local MENU_TABS = {
    { key = 'all',     label = 'All',     icon = 'star',   value = 'root' },
    { key = 'general', label = 'General', icon = 'person', value = 'menu:Emotes' },
    { key = 'dance',   label = 'Dance',   icon = 'dancer', value = 'cat:dances' },
    { key = 'sit',     label = 'Sit',     icon = 'chair',  value = 'cat:sitting' },
    { key = 'social',  label = 'Social',  icon = 'heart',  value = 'cat:shared' },
    { key = 'dialog',  label = 'Dialog',  icon = 'dialog', value = 'cat:dialog' },
    { key = 'action',  label = 'Action',  icon = 'bolt',   value = 'menu:Standing / Roles' },
}

local ROOT_ICON = {
    Music = 'note', Sitting = 'chair', ['Standing / Roles'] = 'person', Emotes = 'cheer',
    Scenarios = 'gear', Props = 'hammer', Poses = 'sparkle',
}

local CAT_ICON = {
    __fav = 'star', music = 'note', sitting = 'chair', police = 'badge', trading = 'coin',
    smoking = 'smoke', washing = 'broom', posing = 'person', saloon = 'cup', injured = 'bandage',
    jobs = 'bag', reaction = 'laugh', action = 'cheer', taunts = 'laugh', greets = 'hat',
    shared = 'heart', dances = 'dancer', scenarios = 'gear', props = 'hammer',
    poses = 'sparkle', dialog = 'dialog',
}

local CAT_TAB = {
    dances = 'dance', sitting = 'sit', shared = 'social', dialog = 'dialog',
    police = 'action', trading = 'action', smoking = 'action', washing = 'action',
    posing = 'action', saloon = 'action', injured = 'action', jobs = 'action',
}

local NODE_TAB = { Emotes = 'general', ['Standing / Roles'] = 'action', Dialog = 'dialog' }

local TYPE_DESC = {
    Anim = 'Emote', Clip = 'Pose', Prop = 'Prop emote', Scenario = 'Scenario',
    Emote = 'Emote',
}

local function categoryIcon(catId)
    return CAT_ICON[catId] or 'person'
end

local function typeDesc(anim)
    return TYPE_DESC[anim.Type] or 'Emote'
end

local function countText(n)
    return n .. (n == 1 and ' emote' or ' emotes')
end

local function isFavourite(id)
    for _, v in ipairs((data and data.favorites) or {}) do
        if v == id then return true end
    end
    return false
end

local function nuiShow(payload, handlers)
    isOpen = true
    nuiHandlers = handlers
    SendNUIMessage({
        type      = 'wfEmoteShow',
        title     = payload.title,
        subtitle  = payload.subtext,
        index     = payload.index or 0,
        tabs      = MENU_TABS,
        activeTab = payload.tab or 'all',
        items     = payload.items or {},
    })
    -- mouse cursor is shown so tabs and rows can be clicked; the panel itself
    -- also handles wheel scrolling in ui/script.js
    SetNuiFocus(true, true)
end

local function nuiHide()
    nuiHandlers = nil
    currentRender = nil
    SendNUIMessage({ type = 'wfEmoteHide' })
    SetNuiFocus(false, false)
end

local function soundEffect(key)
    local cfg = WF.Sound
    if not cfg or cfg.enabled == false then return end
    local sound = cfg[key or 'open']
    if not sound or not sound.name then return end
    PlaySoundFrontend(sound.name, sound.set or '', true, 0)
end

RegisterNUICallback('wfEmoteHighlight', function(d, cb)
    cb('ok')
    local dir = tonumber(type(d) == 'table' and d.dir) or 0
    if dir ~= 0 then soundEffect(dir < 0 and 'navUp' or 'navDown') end
    local handlers = nuiHandlers
    if not handlers or not handlers.change then return end
    handlers.change(type(d) == 'table' and d.value or nil)
end)

RegisterNUICallback('wfEmotePick', function(d, cb)
    cb('ok')
    local handlers = nuiHandlers
    local value = type(d) == 'table' and d.value or nil
    if not handlers or not handlers.select or type(value) ~= 'string' then return end
    if value:sub(1, 5) ~= 'anim:' then soundEffect('accept') end
    handlers.select(value)
end)

RegisterNUICallback('wfEmoteBack', function(_, cb)
    cb('ok')
    local handlers = nuiHandlers
    if handlers and handlers.cancel then handlers.cancel() end
end)

RegisterNUICallback('wfEmoteTab', function(d, cb)
    cb('ok')
    local value = type(d) == 'table' and d.value or nil
    if type(value) == 'string' and openTabValue then
        local dir = tonumber(type(d) == 'table' and d.dir) or 0
        soundEffect(dir < 0 and 'navUp' or 'navDown')
        openTabValue(value)
    end
end)

RegisterNUICallback('wfEmoteFav', function(d, cb)
    cb('ok')
    local id = type(d) == 'table' and d.id or nil
    if type(id) ~= 'string' or not byId[id] then return end
    soundEffect('accept')
    local index = tonumber(type(d) == 'table' and d.index) or 0
    toggleFavourite(id, currentRender, index)
end)

local function catLabel(catId)
    if catId == '__fav' then return 'Favourites' end
    return WF.CategoryLabels[catId] or catId
end

local function previewValue(v)
    if type(v) == 'string' and v:sub(1, 5) == 'anim:' then
        local anim = byId[v:sub(6)]
        if anim then return startPreview(anim) end
    end
    stopPreview()
end

toggleFavourite = function(id, render, index)
    local anim = byId[id]
    if not anim then return end
    local list, had = {}, false
    for _, v in ipairs((data and data.favorites) or {}) do
        if v == id then had = true else list[#list + 1] = v end
    end
    if not had and #list < 200 then list[#list + 1] = id end
    data.favorites = list
    queueSave()
    rawNotify({ title = 'WF Emote', description = had and ('Favourite removed: ' .. id) or ('Favourite added: ' .. id) })
    if render then render(index or 0) end
end

local function buildRootElements()
    local els = {}
    els[#els + 1] = { label = 'Stop Current Animation', value = 'anim:__stop', desc = 'Stop the animation', icon = 'stop', kind = 'stop' }
    local fav = (data and data.favorites) or {}
    if #fav > 0 then
        els[#els + 1] = { label = 'Favourites (' .. #fav .. ')', value = 'cat:__fav', desc = #fav .. ' saved', icon = 'star' }
    end
    for _, m in ipairs(WF.Menu) do
        local count = 0
        if m.sub then
            for _, s in ipairs(m.sub) do
                for _, c in ipairs(s.cats) do
                    local list = byCategory[c]
                    if list then count = count + #list end
                end
            end
        else
            for _, c in ipairs(m.cats) do
                local list = byCategory[c]
                if list then count = count + #list end
            end
        end
        if count > 0 then
            els[#els + 1] = {
                label = m.label,
                value = 'menu:' .. m.label,
                desc = countText(count),
                icon = ROOT_ICON[m.label] or 'person',
            }
        end
    end
    return els
end

local function closeMenu(selected)
    if not selected then soundEffect('close') end
    isOpen = false
    nuiHide()
    stopPreview()
end

local function playPicked(id)
    local anim = byId[id]
    if anim and anim.Shared then
        local target = nearestPlayer(3.2)
        if not target then
            soundEffect('deny')
            rawNotify({ title = 'WF Emote', description = 'No player nearby to share this emote.', type = 'error' })
            return
        end
        soundEffect('accept')
        closeMenu(true)
        local pose = buildSharedPose(anim, PlayerPedId(), GetPlayerPed(target))
        TriggerServerEvent('wf_emote:sharedRequest', id, GetPlayerServerId(target), pose)
        return
    end
    soundEffect('accept')
    closeMenu(true)
    local ok, err = playAnimation(id, 'full')
    if not ok then rawNotify({ title = 'WF Emote', description = err, type = 'error' }) end
end

local function handlePick(v)
    if v == 'anim:__stop' then
        soundEffect('accept')
        closeMenu(true)
        stopAnimation()
        return true
    end
    return false
end

-- opens the node of a WF.Menu entry (a flat category list or sub menu)
openMenuNode = function(node, index)
    local els = {}
    els[#els + 1] = { label = 'Back', value = 'back', desc = 'Back to all emotes', icon = 'back' }
    local total = 0

    if node.sub then
        for _, s in ipairs(node.sub) do
            local count = 0
            for _, c in ipairs(s.cats) do
                local list = byCategory[c]
                if list then count = count + #list end
            end
            if count > 0 then
                els[#els + 1] = {
                    label = s.label,
                    value = 'node:' .. s.label,
                    desc = countText(count),
                    icon = categoryIcon(s.cats[1]),
                }
                total = total + count
            end
        end
    else
        -- flatten every category of this node into one list
        local entries = {}
        for _, c in ipairs(node.cats) do
            local list = byCategory[c]
            if list then
                for _, a in ipairs(list) do entries[#entries + 1] = { anim = a, cat = c } end
            end
        end
        for _, e in ipairs(entries) do
            els[#els + 1] = {
                label = e.anim.Label,
                value = 'anim:' .. e.anim.Command,
                desc = typeDesc(e.anim),
                icon = categoryIcon(e.cat),
                kind = 'anim',
                fav = isFavourite(e.anim.Command),
            }
        end
        total = #entries
    end

    local rerender = function(i) openMenuNode(node, i) end
    currentRender = rerender
    nuiShow({
        title   = node.label,
        subtext = countText(total),
        tab     = NODE_TAB[node.label] or 'all',
        index   = index,
        items   = els,
    }, {
        select = function(v)
            if v == 'back' then
                openRoot()
            elseif handlePick(v) then
                -- handled
            elseif v:sub(1, 5) == 'anim:' then
                playPicked(v:sub(6))
            elseif v:sub(1, 5) == 'node:' then
                local label = v:sub(6)
                for _, s in ipairs(node.sub) do
                    if s.label == label then return openMenuNode(s) end
                end
            end
        end,
        cancel = function() soundEffect('close'); openRoot() end,
        change = previewValue,
    })
end

-- favourites category
openCategory = function(catId, index)
    local items
    if catId == '__fav' then
        items = {}
        for _, id in ipairs((data and data.favorites) or {}) do
            if byId[id] then items[#items + 1] = byId[id] end
        end
    else
        items = byCategory[catId] or {}
    end

    local els = {}
    els[#els + 1] = { label = 'Back', value = 'back', desc = 'Back to all emotes', icon = 'back' }
    if #items == 0 then
        els[#els + 1] = { label = 'Nothing here yet', value = 'noop', desc = 'Use /' .. WF.Commands.fav .. ' <command>', icon = 'star' }
    end
    local icon = categoryIcon(catId)
    for _, a in ipairs(items) do
        els[#els + 1] = {
            label = a.Label,
            value = 'anim:' .. a.Command,
            desc = typeDesc(a),
            icon = icon,
            kind = 'anim',
            fav = isFavourite(a.Command),
        }
    end

    local subtext
    if catId == '__fav' then
        subtext = #items .. ' saved'
    else
        subtext = countText(#items)
    end

    currentRender = function(i) openCategory(catId, i) end
    nuiShow({
        title   = catLabel(catId),
        subtext = subtext,
        tab     = CAT_TAB[catId] or 'all',
        index   = index,
        items   = els,
    }, {
        select = function(v)
            if v == 'back' then return openRoot() end
            if handlePick(v) then return end
            if v:sub(1, 5) == 'anim:' then
                playPicked(v:sub(6))
            end
        end,
        cancel = function() soundEffect('close'); openRoot() end,
        change = previewValue,
    })
end

openRoot = function(index)
    currentRender = function(i) openRoot(i) end
    nuiShow({
        title   = 'All Emotes',
        subtext = #WF.Menu .. ' sections',
        tab     = 'all',
        index   = index,
        items   = buildRootElements(),
    }, {
        select = function(v)
            if handlePick(v) then return end
            if v:sub(1, 5) == 'menu:' then
                local label = v:sub(6)
                for _, m in ipairs(WF.Menu) do
                    if m.label == label then return openMenuNode(m) end
                end
            elseif v:sub(1, 4) == 'cat:' then
                return openCategory(v:sub(5))
            end
        end,
        cancel = function() closeMenu() end,
        change = previewValue,
    })
end

openTabValue = function(value)
    if value == 'root' then return openRoot(0) end
    if value:sub(1, 5) == 'menu:' then
        local label = value:sub(6)
        for _, m in ipairs(WF.Menu) do
            if m.label == label then return openMenuNode(m, 0) end
        end
    elseif value:sub(1, 4) == 'cat:' then
        return openCategory(value:sub(5), 0)
    end
end

openMenu = function()
    if isOpen then return end
    if WFInteract_IsPickerOpen and WFInteract_IsPickerOpen() then
        soundEffect('deny')
        return notify('Close the world interaction menu first.', 'error')
    end
    loadData(function(ok)
        if not ok then
            soundEffect('deny')
            return notify('Character not loaded yet.', 'error')
        end
        if isOpen then return end
        -- leave any world interaction (chair/bed/...) before previewing emotes
        if WFInteract_StopCurrentInteraction then WFInteract_StopCurrentInteraction() end
        soundEffect('open')
        openRoot()
    end)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if isOpen then closeMenu(true) end
    nuiHide()
    stopPreview()
    if playing then
        deletePropHandles(playing.props)
        playing = nil
    end
end)

---------------------------------------------------------------------------
-- Shared emotes (played together with the nearest player)
-- Reference mechanism: rpemotes shared emotes (initiator -> nearest player
-- -> server relay -> both face each other and play their animation).
---------------------------------------------------------------------------
nearestPlayer = function(maxDist)
    local players = (GetActivePlayers and GetActivePlayers()) or {}
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local best, bestDist
    for _, p in ipairs(players) do
        local other = GetPlayerPed(p)
        if other and other ~= ped and other ~= 0 then
            local d = #(coords - GetEntityCoords(other))
            if d <= (maxDist or 3.0) and (not best or d < bestDist) then
                best = p
                bestDist = d
            end
        end
    end
    return best, bestDist
end

-- Works out where each ped has to stand for a pair animation. Normal emotes
-- split the move between both players (midpoint); poses that need the
-- initiator to stay put (e.g. sitting) set Anchor = 'initiator'.
buildSharedPose = function(anim, ped, otherPed)
    if not ped or not otherPed or otherPed == 0 or otherPed == ped then return nil end
    if IsPedOnMount(ped) or IsPedInAnyVehicle(ped, false) then return nil end
    if IsPedOnMount(otherPed) or IsPedInAnyVehicle(otherPed, false) then return nil end

    local c1, c2 = GetEntityCoords(ped), GetEntityCoords(otherPed)
    local front = math.max(tonumber(anim.OffsetFront) or 0.9, 0.05)
    local side = tonumber(anim.OffsetSide) or 0.0
    local dz = tonumber(anim.OffsetZ) or 0.0

    local dx, dy = c2.x - c1.x, c2.y - c1.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local dirx, diry
    if dist > 0.01 then
        dirx, diry = dx / dist, dy / dist
    else
        local h = math.rad(GetEntityHeading(ped))
        dirx, diry = math.sin(h), math.cos(h)
    end

    local mainPos, partnerPos
    if anim.Anchor == 'initiator' then
        mainPos = { x = c1.x, y = c1.y, z = c1.z }
        partnerPos = { x = c1.x + dirx * front, y = c1.y + diry * front, z = c2.z + dz }
    else
        local midx, midy = (c1.x + c2.x) * 0.5, (c1.y + c2.y) * 0.5
        local half = front * 0.5
        mainPos = { x = midx - dirx * half, y = midy - diry * half, z = c1.z }
        partnerPos = { x = midx + dirx * half, y = midy + diry * half, z = c2.z + dz }
    end

    if side ~= 0.0 then
        local rx, ry = diry, -dirx
        partnerPos.x = partnerPos.x + rx * side
        partnerPos.y = partnerPos.y + ry * side
    end

    local mainH
    if anim.MainHeading == 'keep' then
        mainH = GetEntityHeading(ped)
    else
        mainH = GetHeadingFromVector_2d(partnerPos.x - mainPos.x, partnerPos.y - mainPos.y)
    end
    local partnerH
    if anim.PartnerHeading == 'same' then
        partnerH = mainH
    elseif type(anim.PartnerHeading) == 'number' then
        partnerH = mainH + anim.PartnerHeading
    else
        partnerH = GetHeadingFromVector_2d(mainPos.x - partnerPos.x, mainPos.y - partnerPos.y)
    end

    return {
        main = { x = mainPos.x, y = mainPos.y, z = mainPos.z, h = mainH },
        partner = { x = partnerPos.x, y = partnerPos.y, z = partnerPos.z, h = partnerH },
    }
end

local function playShared(id, otherSrc, isPartner, myPos)
    local anim = byId[id]
    if not anim then return end
    local ped = PlayerPedId()
    local otherPed = GetPlayerPed(GetPlayerFromServerId(otherSrc))
    if type(myPos) == 'table' and tonumber(myPos.x) and tonumber(myPos.y) and tonumber(myPos.z) and tonumber(myPos.h) then
        SetEntityCoordsNoOffset(ped, myPos.x + 0.0, myPos.y + 0.0, myPos.z + 0.0, false, false, false)
        SetEntityHeading(ped, myPos.h + 0.0)
    elseif otherPed and otherPed ~= 0 and otherPed ~= ped then
        local c1, c2 = GetEntityCoords(ped), GetEntityCoords(otherPed)
        SetEntityHeading(ped, GetHeadingFromVector_2d(c2.x - c1.x, c2.y - c1.y))
    end
    local ok, err = playAnimation(id, 'full', isPartner and 'partner' or 'main')
    if not ok then rawNotify({ title = 'WF Emote', description = err, type = 'error' }) end
end

RegisterNetEvent('wf_emote:sharedPlay', function(id, otherSrc, isPartner, myPos)
    if type(id) ~= 'string' then return end
    otherSrc = tonumber(otherSrc)
    if not otherSrc then return end
    playShared(id, otherSrc, isPartner == true, myPos)
end)

---------------------------------------------------------------------------
-- Keys & commands
---------------------------------------------------------------------------
CreateThread(function()
    local raw = IsRawKeyReleased ~= nil
    while true do
        Wait(0)
        if not isOpen and not IsPauseMenuActive() and not IsNuiFocused() then
            if raw and IsRawKeyReleased(WF.OpenKey) then
                openMenu()
            elseif not playing and not WFInteractActive and WF.StopKey and IsControlJustReleased(0, WF.StopKey) then
                -- X stops animations, but never kills a live world interaction
                stopAnimation(true)
            end
        end
    end
end)

RegisterCommand(WF.Commands.menu, openMenu, false)
RegisterCommand('poses', openMenu, false)

RegisterCommand(WF.Commands.play, function(_, args)
    local name = args[1] and args[1]:lower()
    if not name then return openMenu() end
    if name == 'c' or name == 'stop' then return stopAnimation() end
    local ok, err = playAnimation(name, args[2] == 'upper' and 'upper' or 'full')
    if not ok then rawNotify({ title = 'WF Emote', description = err, type = 'error' }) end
end, false)

RegisterCommand(WF.Commands.fav, function(_, args)
    local id = args[1] and args[1]:lower()
    if not id then return end
    loadData(function(ok)
        if not ok then return notify('Character not loaded yet.', 'error') end
        if not byId[id] then
            return rawNotify({ title = 'WF Emote', description = ('Animation "%s" not found.'):format(id), type = 'error' })
        end
        toggleFavourite(id)
    end)
end, false)

TriggerEvent('chat:addSuggestion', '/' .. WF.Commands.menu, 'Open the WF emote menu')
TriggerEvent('chat:addSuggestion', '/poses', 'Open the WF emote menu')
TriggerEvent('chat:addSuggestion', '/' .. WF.Commands.play, 'Play an animation (/e c to stop)', {
    { name = 'command', help = 'Animation name (ex: sit)' },
})
TriggerEvent('chat:addSuggestion', '/' .. WF.Commands.fav, 'Toggle a favourite', {
    { name = 'command', help = 'Animation command (ex: sit)' },
})

---------------------------------------------------------------------------
-- Exports
---------------------------------------------------------------------------
exports('PlayAnimation', playAnimation)
exports('StopAnimation', function() stopAnimation(true) end)
exports('OpenMenu', openMenu)
exports('CloseMenu', closeMenu)
exports('IsPlaying', function() return playing ~= nil, playing and playing.id end)

-- used by wf_interact_client.lua to avoid opening the world picker over this menu
function WF_IsMenuOpen()
    return isOpen
end
