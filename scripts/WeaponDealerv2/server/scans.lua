Server = Server or {}
Server.Scans = Server.Scans or {}

local recentScans = {}

local function validateSession(scan)
    if not scan then return nil end

    if os.time() - scan.time > Config.Documents.VerificationSession.DurationSeconds then
        return nil
    end

    local store = Server.GetStore(scan.store)
    if not store then return nil end

    if Config.Documents.VerificationSession.RequireEmployeeInStore and not Server.IsInStoreZone(scan.employee, store) then
        return nil
    end

    if Config.Documents.VerificationSession.RequireBuyerInStore and not Server.IsInStoreZone(scan.buyer, store) then
        return nil
    end

    return scan
end

local function scanProgress(source, rows, buyer)
    TriggerClientEvent('qbx_weapondealer:client:scanProgress', source, rows)

    if buyer then
        TriggerClientEvent('qbx_weapondealer:client:buyerScanProgress', buyer, rows)
    end
end

local function progressRows(states)
    return {
        { label = 'Authenticating employee credentials', status = states.employee or 'pending' },
        { label = 'Requesting customer consent', status = states.consent or 'pending' },
        { label = 'Reading government ID metadata', status = states.idRead or 'pending' },
        { label = 'Matching ID holder to selected customer', status = states.identity or 'pending' },
        { label = 'Reading weapon license certificate', status = states.licenseRead or 'pending' },
        { label = 'Verifying ID and license citizen match', status = states.match or 'pending' },
        { label = 'Checking license status flags', status = states.licenseState or 'pending' },
        { label = 'Checking license expiration window', status = states.expiry or 'pending' },
        { label = 'Querying cs_license registry record', status = states.csRecord or 'pending' },
        { label = 'Saving customer registry profile', status = states.profile or 'pending' }
    }
end

local function delayScanStep()
    local cfg = Config.Documents.ScanStepDelay or {}
    local min = cfg.Min or 250
    local max = cfg.Max or min
    if max < min then max = min end
    Wait(math.random(min, max))
end

local function delayLicenseCheck()
    local min = Config.Documents.LicenseCheckDelay.Min or 3
    local max = Config.Documents.LicenseCheckDelay.Max or min
    if max < min then max = min end
    Wait(math.random(min, max) * 1000)
end

local function normalizeMetadata(metadata)
    metadata = metadata or {}

    return {
        citizenid = metadata.citizenid or metadata.citizenId or metadata.citizen_id,
        firstname = metadata.firstname or metadata.firstName or metadata.first_name,
        lastname = metadata.lastname or metadata.lastName or metadata.last_name,
        dob = metadata.dob or metadata.birthdate or metadata.dateofbirth,
        license_id = metadata.license_id or metadata.licenseId or metadata.public_id or metadata.cardId,
        status = metadata.status,
        expiry = metadata.expiry or metadata.expire or metadata.expires
    }
end

local function isExpired(expiry)
    if not expiry or expiry == '' then return false end

    local numeric = tonumber(expiry)
    if numeric then return numeric < os.time() end

    local year, month, day = tostring(expiry):match('^(%d%d%d%d)%-(%d%d)%-(%d%d)')
    if not year then return false end

    return os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 23, min = 59, sec = 59 }) < os.time()
end

function Server.Scans.GetRecent(buyer)
    local scan = recentScans[buyer]
    if not validateSession(scan) then
        recentScans[buyer] = nil
        return nil
    end

    return scan
end

function Server.Scans.GetForEmployee(employee, storeId)
    for buyer, scan in pairs(recentScans) do
        if scan.employee == employee and scan.store == storeId and validateSession(scan) then
            return scan
        elseif scan.employee == employee and scan.store == storeId then
            recentScans[buyer] = nil
        end
    end
end

function Server.Scans.GetForBuyer(buyer, storeId)
    local scan = recentScans[buyer]
    if scan and scan.store == storeId and validateSession(scan) then
        return scan
    end

    recentScans[buyer] = nil
end

function Server.Scans.GetVerifiedForEmployee(employee, storeId)
    local verified = {}

    for buyer, scan in pairs(recentScans) do
        if scan.employee == employee and scan.store == storeId and validateSession(scan) then
            verified[#verified + 1] = {
                label = ('%s (%s)'):format(scan.buyerName, scan.citizenid),
                value = buyer,
                verified = true,
                citizenid = scan.citizenid,
                buyerName = scan.buyerName,
                licenseId = scan.licenseId,
                verifiedAt = scan.time
            }
        elseif scan.employee == employee and scan.store == storeId then
            recentScans[buyer] = nil
        end
    end

    table.sort(verified, function(a, b)
        return (a.verifiedAt or 0) > (b.verifiedAt or 0)
    end)

    return verified
end

function Server.Scans.ClearForEmployee(employee)
    for buyer, scan in pairs(recentScans) do
        if scan.employee == employee then
            recentScans[buyer] = nil
        end
    end
end

function Server.Scans.ClearBuyer(buyer)
    recentScans[buyer] = nil
end

RegisterNetEvent('qbx_weapondealer:server:clearVerification', function()
    Server.Scans.ClearForEmployee(source)
end)

RegisterNetEvent('qbx_weapondealer:server:clearStoreVerification', function(storeId)
    local source = source
    for buyer, scan in pairs(recentScans) do
        if scan.employee == source and (not storeId or scan.store == storeId) then
            recentScans[buyer] = nil
        end
    end
end)

lib.callback.register('qbx_weapondealer:server:getVerifiedCustomers', function(source, storeId)
    local allowed, reason = Bridge.Framework.IsAuthorized(source, 'Scan')
    if not allowed then
        Server.Notify(source, reason, 'error')
        return {}
    end

    local store = Server.GetStore(storeId)
    if not store or not Server.IsNear(source, store.salesDesk.coords) then
        Server.Notify(source, 'not_at_sales_desk', 'error')
        return {}
    end

    return Server.Scans.GetVerifiedForEmployee(source, storeId)
end)

lib.callback.register('qbx_weapondealer:server:scanDocuments', function(source, storeId, buyer)
    if not Server.CheckCooldown(source, 'scan') then return false end

    local progress = {
        employee = 'processing'
    }
    scanProgress(source, progressRows(progress))

    local allowed, reason = Bridge.Framework.IsAuthorized(source, 'Scan')
    if not allowed then
        progress.employee = 'error'
        scanProgress(source, progressRows(progress))
        Server.Notify(source, reason, 'error')
        Server.Logs.Blocked(source, 'scan', reason)
        return false
    end
    delayScanStep()
    progress.employee = 'success'
    scanProgress(source, progressRows(progress))

    local store = Server.GetStore(storeId)
    if not store or not Server.IsNear(source, store.salesDesk.coords) then
        Server.Notify(source, 'not_at_sales_desk', 'error')
        Server.Logs.Blocked(source, 'scan', 'not_at_sales_desk', { store = storeId })
        return false
    end

    buyer = tonumber(buyer)
    local buyerPed = buyer and GetPlayerPed(buyer)
    if not buyerPed or buyerPed == 0 or not Server.IsNear(source, GetEntityCoords(buyerPed), Config.Security.NearbyBuyerDistance) then
        Server.Notify(source, 'no_nearby_buyer', 'error')
        return false
    end

    progress.consent = 'processing'
    scanProgress(source, progressRows(progress), buyer)

    local consent = lib.callback.await('qbx_weapondealer:client:confirmDocumentScan', buyer, Bridge.Framework.GetName(source), store.label)
    if not consent then
        progress.consent = 'error'
        scanProgress(source, progressRows(progress), buyer)
        Server.Logs.Blocked(source, 'scan', 'buyer_declined_scan', { buyer = buyer })
        return false
    end
    delayScanStep()
    progress.consent = 'success'
    scanProgress(source, progressRows(progress), buyer)

    local buyerIdentifier = Bridge.Framework.GetIdentifier(buyer)

    progress.idRead = 'processing'
    scanProgress(source, progressRows(progress), buyer)
    delayScanStep()
    local idRawMeta, idItem = Bridge.Inventory.GetItemMetadata(buyer, Config.Documents.IdCardItem)
    local idMeta = normalizeMetadata(idRawMeta)

    if not idItem or not idMeta.citizenid then
        progress.idRead = 'error'
        scanProgress(source, progressRows(progress), buyer)

        progress.licenseRead = 'processing'
        scanProgress(source, progressRows(progress), buyer)
        delayScanStep()
        local licenseRawMeta, licenseItem = Bridge.Inventory.GetItemMetadata(buyer, Config.Documents.WeaponLicenseItem)
        local licenseMeta = normalizeMetadata(licenseRawMeta)
        if licenseItem and licenseMeta.citizenid then
            progress.licenseRead = 'success'
            progress.licenseState = (licenseMeta.status and licenseMeta.status ~= 'valid') and 'error' or 'success'
            progress.expiry = isExpired(licenseMeta.expiry) and 'error' or 'success'
            if progress.licenseState == 'success' and progress.expiry == 'success' then
                progress.csRecord = 'processing'
                scanProgress(source, progressRows(progress), buyer)
                delayLicenseCheck()
                local licenseOk = Bridge.License.HasWeaponLicense(buyer, buyerIdentifier, Config.Documents.WeaponLicenseItem)
                progress.csRecord = licenseOk and 'success' or 'error'
            end
        else
            progress.licenseRead = 'error'
        end
        scanProgress(source, progressRows(progress), buyer)

        Server.Notify(source, 'missing_id', 'error')
        Server.Logs.Blocked(source, 'scan', 'missing_id', { buyer = buyerIdentifier })
        return false
    end
    progress.idRead = 'success'
    scanProgress(source, progressRows(progress), buyer)

    progress.identity = 'processing'
    scanProgress(source, progressRows(progress), buyer)
    delayScanStep()
    if idMeta.citizenid ~= buyerIdentifier then
        progress.identity = 'error'
        scanProgress(source, progressRows(progress), buyer)
        Server.Notify(source, 'buyer_mismatch', 'error')
        Server.Logs.Blocked(source, 'scan', 'buyer_mismatch', { buyer = buyerIdentifier })
        return false
    end
    progress.identity = 'success'
    scanProgress(source, progressRows(progress), buyer)

    progress.licenseRead = 'processing'
    scanProgress(source, progressRows(progress), buyer)
    delayScanStep()
    local licenseRawMeta, licenseItem = Bridge.Inventory.GetItemMetadata(buyer, Config.Documents.WeaponLicenseItem)
    local licenseMeta = normalizeMetadata(licenseRawMeta)

    WD.Debug('scan metadata parsed', { id = idMeta, license = licenseMeta, buyer = buyerIdentifier })

    if not licenseItem or not licenseMeta.citizenid then
        progress.licenseRead = 'error'
        scanProgress(source, progressRows(progress), buyer)
        Server.Notify(source, 'missing_license', 'error')
        Server.Logs.Blocked(source, 'scan', 'missing_license', { buyer = buyerIdentifier })
        return false
    end
    progress.licenseRead = 'success'
    scanProgress(source, progressRows(progress), buyer)

    progress.match = 'processing'
    scanProgress(source, progressRows(progress), buyer)
    delayScanStep()
    if idMeta.citizenid ~= licenseMeta.citizenid then
        progress.match = 'error'
        scanProgress(source, progressRows(progress), buyer)
        Server.Notify(source, 'doc_mismatch', 'error')
        Server.Logs.Blocked(source, 'scan', 'doc_mismatch', { buyer = buyerIdentifier })
        return false
    end
    progress.match = 'success'
    scanProgress(source, progressRows(progress), buyer)

    progress.licenseState = 'processing'
    scanProgress(source, progressRows(progress), buyer)
    delayScanStep()
    if licenseMeta.status and licenseMeta.status ~= 'valid' then
        progress.licenseState = 'error'
        scanProgress(source, progressRows(progress), buyer)
        Server.Notify(source, 'license_invalid', 'error')
        Server.Logs.Blocked(source, 'scan', 'license_invalid_status', { buyer = buyerIdentifier, status = licenseMeta.status })
        return false
    end
    progress.licenseState = 'success'
    scanProgress(source, progressRows(progress), buyer)

    progress.expiry = 'processing'
    scanProgress(source, progressRows(progress), buyer)
    delayScanStep()
    if isExpired(licenseMeta.expiry) then
        progress.expiry = 'error'
        scanProgress(source, progressRows(progress), buyer)
        Server.Notify(source, 'license_expired', 'error')
        Server.Logs.Blocked(source, 'scan', 'license_expired', { buyer = buyerIdentifier })
        return false
    end
    progress.expiry = 'success'
    scanProgress(source, progressRows(progress), buyer)

    progress.csRecord = 'processing'
    scanProgress(source, progressRows(progress), buyer)
    delayLicenseCheck()

    local licenseOk, licenseReason = Bridge.License.HasWeaponLicense(buyer, buyerIdentifier, Config.Documents.WeaponLicenseItem)
    if not licenseOk then
        progress.csRecord = 'error'
        scanProgress(source, progressRows(progress), buyer)
        Server.Notify(source, licenseReason or 'license_invalid', 'error')
        Server.Logs.Blocked(source, 'scan', licenseReason or 'license_invalid', { buyer = buyerIdentifier })
        return false
    end
    progress.csRecord = 'success'
    scanProgress(source, progressRows(progress), buyer)

    local buyerName = Bridge.Framework.GetName(buyer)
    recentScans[buyer] = {
        time = os.time(),
        employee = source,
        store = storeId,
        buyer = buyer,
        citizenid = buyerIdentifier,
        buyerName = buyerName,
        licenseId = licenseMeta.license_id or Config.Documents.WeaponLicenseItem
    }

    progress.profile = 'processing'
    scanProgress(source, progressRows(progress), buyer)
    delayScanStep()
    Server.Profiles.SaveFromScan(recentScans[buyer], idMeta, licenseMeta)
    progress.profile = 'success'
    scanProgress(source, progressRows(progress), buyer)

    MySQL.insert('INSERT INTO license_scan_logs (employee_identifier, buyer_identifier, store_id, result, reason, metadata) VALUES (?, ?, ?, ?, ?, ?)', {
        Bridge.Framework.GetIdentifier(source),
        buyerIdentifier,
        storeId,
        'approved',
        nil,
        json.encode({ id = idMeta, license = licenseMeta })
    })

    Server.Notify(source, 'scan_approved', 'success', { name = buyerName })
    Server.Notify(buyer, 'scan_approved', 'success', { name = buyerName })
    Server.Logs.Write('document_scan', 'Weapon license documents approved.', {
        employee = Bridge.Framework.GetIdentifier(source),
        buyer = buyerIdentifier,
        store = storeId
    })

    return {
        buyer = buyer,
        buyerName = buyerName,
        citizenid = buyerIdentifier,
        licenseId = recentScans[buyer].licenseId
    }
end)
