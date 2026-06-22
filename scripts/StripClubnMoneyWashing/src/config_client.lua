Config.Notify = function(message, type)
    TriggerEvent('ox_lib:notify', {
        title = 'Club Management',
        description = message,
        type = type or 'inform',
        position = 'top-center'
    })
end

Config.PlayAnimation = function(animName, targetCoords)
    if not animName then return end

    local ped = type(PlayerPedId) == 'function' and PlayerPedId() or nil
    local menus = Config.EmoteMenus or {}
    local order = menus.priority or {}
    local handlers = menus.handlers or {}
    local tipConfig = Config.Tip or {}

    local function resolveTipAnimationConfig()
        local animation = tipConfig.anim
        if type(animation) == 'table' then
            return animation.dict, animation.clip or animation.anim
        end

        return tipConfig.dict, animation
    end

    local function resolveTipPropConfig()
        local prop = tipConfig.prop
        if type(prop) == 'table' then
            local pos = prop.pos or vec3(0.12, 0.028, 0.001)
            local rot = prop.rot or vec3(300.0, 180.0, 20.0)
            return prop.model, prop.bone or 18905, {
                x = pos.x or 0.12,
                y = pos.y or 0.028,
                z = pos.z or 0.001,
                rx = rot.x or 300.0,
                ry = rot.y or 180.0,
                rz = rot.z or 20.0
            }
        end

        return prop, tipConfig.bone or 18905, tipConfig.attach or {}
    end

    local function resolveTipParticleConfig()
        if type(tipConfig.ptfx) == 'table' then
            local placement = tipConfig.ptfx.placement or {}
            local offset = placement[1] or vec3(0.0, 0.0, 0.0)
            local rotation = placement[2] or vec3(0.0, 0.0, 0.0)
            local releaseDelay = math.max(0, tonumber(tipConfig.releaseDelay) or 0)
            local sequenceEndDelay = math.max(releaseDelay, tonumber(tipConfig.sequenceEndDelay) or releaseDelay)
            local particleDelay = 150

            return {
                hand = {
                    asset = tipConfig.ptfx.asset or 'core',
                    effect = tipConfig.ptfx.name or 'ent_brk_banknotes',
                    bone = tipConfig.ptfx.bone,
                    delay = particleDelay,
                    duration = math.max(900, sequenceEndDelay - particleDelay),
                    looped = true,
                    offset = { x = offset.x or 0.0, y = offset.y or 0.0, z = offset.z or 0.0 },
                    rotation = { x = rotation.x or 0.0, y = rotation.y or 180.0, z = rotation.z or 0.0 },
                    scale = tipConfig.ptfx.scale or 1.0,
                    attachToProp = true
                }
            }
        end

        return tipConfig.particle or {}
    end

    local function resolveGroundZ(x, y, z)
        local found, groundZ = GetGroundZFor_3dCoord(x, y, z + 3.0, false)
        if found then
            return groundZ
        end

        return z
    end

    local function playTipSequence(pedEntity, skipAnim, desiredTargetCoords)
        if not pedEntity or not DoesEntityExist(pedEntity) then return end

        local dict, anim = resolveTipAnimationConfig()

        if skipAnim and dict and anim and not IsEntityPlayingAnim(pedEntity, dict, anim, 3) then
            skipAnim = false
        end

        if not skipAnim and dict and anim then
            if lib and lib.requestAnimDict then
                lib.requestAnimDict(dict)
            else
                RequestAnimDict(dict)
                while not HasAnimDictLoaded(dict) do
                    Wait(10)
                end
            end
            TaskPlayAnim(pedEntity, dict, anim, 8.0, -8.0, -1, 1, 0.0, false, false, false)
        end

        local cashProp
        local propName, propBone, attach = resolveTipPropConfig()
        if propName then
            local model = GetHashKey(propName)
            if model and model ~= 0 then
                if not HasModelLoaded(model) then
                    RequestModel(model)
                    local timeout = GetGameTimer() + 2000
                    while not HasModelLoaded(model) and GetGameTimer() < timeout do
                        Wait(10)
                    end
                end
                if HasModelLoaded(model) then
                    cashProp = CreateObject(model, 0.0, 0.0, 0.0, true, true, false)
                    if DoesEntityExist(cashProp) then
                        AttachEntityToEntity(
                            cashProp,
                            pedEntity,
                            GetPedBoneIndex(pedEntity, propBone or 18905),
                            attach.x or 0.12,
                            attach.y or 0.028,
                            attach.z or 0.001,
                            attach.rx or 300.0,
                            attach.ry or 180.0,
                            attach.rz or 20.0,
                            true,
                            true,
                            false,
                            true,
                            1,
                            true
                        )
                    end
                    SetModelAsNoLongerNeeded(model)
                end
            end
        end

        CreateThread(function()
            local particles = resolveTipParticleConfig()

            local function playParticle(particleCfg, useTargetCoords)
                if type(particleCfg) ~= 'table' then return end

                local delay = math.max(0, particleCfg.delay or 0)
                if delay > 0 then
                    Wait(delay)
                end

                local asset = particleCfg.asset or 'core'
                local effect = particleCfg.effect or 'ent_brk_banknotes'
                local handle

                if DoesEntityExist(pedEntity) and effect then
                    RequestNamedPtfxAsset(asset)
                    while not HasNamedPtfxAssetLoaded(asset) do
                        Wait(10)
                    end
                    UseParticleFxAssetNextCall(asset)
                    local ox = (particleCfg.offset and particleCfg.offset.x) or 0.0
                    local oy = (particleCfg.offset and particleCfg.offset.y) or 0.0
                    local oz = (particleCfg.offset and particleCfg.offset.z) or 0.0
                    local rx = (particleCfg.rotation and particleCfg.rotation.x) or 0.0
                    local ry = (particleCfg.rotation and particleCfg.rotation.y) or 0.0
                    local rz = (particleCfg.rotation and particleCfg.rotation.z) or 0.0
                    local scale = particleCfg.scale or 1.0
                    local bone = tonumber(particleCfg.bone)
                    local attachToProp = particleCfg.attachToProp and cashProp and DoesEntityExist(cashProp)

                    if useTargetCoords and desiredTargetCoords then
                        if particleCfg.looped then
                            handle = StartParticleFxLoopedAtCoord(effect, desiredTargetCoords.x + ox, desiredTargetCoords.y + oy, desiredTargetCoords.z + oz, rx, ry, rz, scale, false, false, false, false)
                        else
                            StartParticleFxNonLoopedAtCoord(effect, desiredTargetCoords.x + ox, desiredTargetCoords.y + oy, desiredTargetCoords.z + oz, rx, ry, rz, scale, false, false, false)
                        end
                    elseif attachToProp then
                        if particleCfg.looped then
                            handle = StartParticleFxLoopedOnEntity(effect, cashProp, ox, oy, oz, rx, ry, rz, scale, false, false, false)
                        else
                            StartParticleFxNonLoopedOnEntity(effect, cashProp, ox, oy, oz, rx, ry, rz, scale, false, false, false)
                        end
                    elseif bone then
                        if particleCfg.looped then
                            handle = StartParticleFxLoopedOnPedBone(effect, pedEntity, ox, oy, oz, rx, ry, rz, bone, scale, false, false, false)
                        else
                            StartParticleFxNonLoopedOnPedBone(effect, pedEntity, ox, oy, oz, rx, ry, rz, bone, scale, false, false, false)
                        end
                    elseif particleCfg.looped then
                        handle = StartParticleFxLoopedOnEntity(effect, pedEntity, ox, oy, oz, rx, ry, rz, scale, false, false, false)
                    else
                        StartParticleFxNonLoopedOnEntity(effect, pedEntity, ox, oy, oz, rx, ry, rz, scale, false, false, false)
                    end
                end

                local duration = math.max(0, particleCfg.duration or particleCfg.cleanup or 3000)
                if duration > 0 then
                    Wait(duration)
                end

                if handle then
                    StopParticleFxLooped(handle, false)
                    RemoveParticleFx(handle, false)
                end

                if asset then
                    RemoveNamedPtfxAsset(asset)
                end
            end

            CreateThread(function()
                playParticle(particles.hand, false)
            end)

            CreateThread(function()
                playParticle(particles.target, true)
            end)

            local sequenceEndDelay = math.max(
                math.max(0, tonumber(tipConfig.releaseDelay) or 0),
                tonumber(tipConfig.sequenceEndDelay) or 0
            )
            if sequenceEndDelay > 0 then
                Wait(sequenceEndDelay)
            end

            if cashProp and DoesEntityExist(cashProp) then
                DetachEntity(cashProp, true, true)
                SetEntityCollision(cashProp, true, true)
                SetEntityDynamic(cashProp, true)
                ActivatePhysics(cashProp)
                FreezeEntityPosition(cashProp, false)

                local pedCoords = GetEntityCoords(pedEntity)
                local forward = GetEntityForwardVector(pedEntity)
                local dropCfg = tipConfig.drop or {}
                local forwardDistance = tonumber(dropCfg.forward) or 0.75
                local startHeight = tonumber(dropCfg.height) or 0.85
                local speed = tonumber(dropCfg.speed) or 3.0
                local upward = tonumber(dropCfg.upward) or 0.55
                local velocity = dropCfg.velocity or {}
                local landingX = desiredTargetCoords and desiredTargetCoords.x or (pedCoords.x + (forward.x * forwardDistance))
                local landingY = desiredTargetCoords and desiredTargetCoords.y or (pedCoords.y + (forward.y * forwardDistance))
                local landingZ = resolveGroundZ(landingX, landingY, pedCoords.z)
                local startCoords = GetEntityCoords(cashProp)
                local dx = landingX - startCoords.x
                local dy = landingY - startCoords.y
                local distance = math.sqrt((dx * dx) + (dy * dy))
                if distance < 0.001 then distance = 1.0 end

                SetEntityCoords(cashProp, startCoords.x, startCoords.y, math.max(startCoords.z, landingZ + startHeight), false, false, false, false)
                SetEntityVelocity(
                    cashProp,
                    (dx / distance) * speed + (tonumber(velocity.x) or 0.0),
                    (dy / distance) * speed + (tonumber(velocity.y) or 0.0),
                    upward + (tonumber(velocity.z) or -0.15)
                )

                SetTimeout(math.max(1000, tonumber(tipConfig.floorLifetime) or 12000), function()
                    if DoesEntityExist(cashProp) then
                        DeleteObject(cashProp)
                    end
                end)
            end
        end)
    end

    local handled = false

    for _, key in ipairs(order) do
        local handler = handlers[key]
        if handler and handler.call and handler.enabled ~= false then
            local ok, result = pcall(handler.call, animName)
            if ok and result ~= false then
                handled = true
                break
            end
        end
    end

    if handled then
        if ped and DoesEntityExist(ped) and animName == Config.Tip.name then
            CreateThread(function()
                Wait(200)
                if not ped or not DoesEntityExist(ped) then return end
                playTipSequence(ped, true, targetCoords)
            end)
        end
        return
    end

    if not ped or not DoesEntityExist(ped) then return end

    if animName == Config.Tip.name then
        playTipSequence(ped, false, targetCoords)
    end
end
