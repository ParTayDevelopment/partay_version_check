Bridge = Bridge or {}
Bridge.License = {}

local function parseDate(value)
    if not value or value == '' then return nil end
    if type(value) == 'number' then return value end

    local year, month, day = tostring(value):match('^(%d%d%d%d)%-(%d%d)%-(%d%d)')
    if year then
        return os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 23, min = 59, sec = 59 })
    end

    return nil
end

function Bridge.License.HasWeaponLicense(source, identifier, licenseItem)
    if not Config.License.Enabled or GetResourceState(Config.License.Resource) ~= 'started' then
        return true
    end

    local ok, result = pcall(function()
        return exports[Config.License.Resource]:CheckID(source, licenseItem or Config.License.WeaponLicenseItem)
    end)

    if not ok or not result then
        return false, 'license_invalid'
    end

    local listOk, licenses = pcall(function()
        return exports[Config.License.Resource]:GetPlayerLicenses(identifier)
    end)

    if listOk and type(licenses) == 'table' then
        for _, license in pairs(licenses) do
            if license.license == (licenseItem or Config.License.WeaponLicenseItem) then
                local expires = parseDate(license.expireDate)
                if expires and expires < os.time() then
                    return false, 'license_expired'
                end
                return true
            end
        end
    end

    return true
end
