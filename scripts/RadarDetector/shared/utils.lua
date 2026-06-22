RadarDetector = RadarDetector or {}

function RadarDetector.Locale(key, ...)
    local lang = Config.Locale or 'en'
    local phrase = Locales[lang] and Locales[lang][key] or key

    if select('#', ...) > 0 then
        return phrase:format(...)
    end

    return phrase
end

function RadarDetector.TrimPlate(plate)
    if not plate then return nil end
    plate = tostring(plate):gsub('^%s+', ''):gsub('%s+$', '')
    if plate == '' then return nil end
    return plate:upper()
end

function RadarDetector.Clamp(value, min, max)
    value = tonumber(value) or min
    if value < min then return min end
    if value > max then return max end
    return value
end

function RadarDetector.TableContains(tbl, value)
    for _, entry in pairs(tbl or {}) do
        if entry == value then return true end
    end

    return false
end
