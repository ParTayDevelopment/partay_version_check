-- Simple localization support for Partay_hustle
-- Configure language via Config.Locale = 'en' | 'es'

Locales = Locales or {}

Locales.en = {
    claimed_rewards = 'Claimed {count} reward(s)',
    no_rewards = 'No rewards to claim',
    claim_button = 'Claim Level Rewards',
    claim_button_none = 'Level Rewards',
    claim_you_have = 'You have {count} unclaimed reward(s)',

    item_received = 'Nice work, you received {text}',
    vehicle_stored = 'Nice work, your reward has been stored in the garage for your safety.',

    progress_title = 'Your Progress — {name}',
    progress_ready = 'Reached next level threshold. Click to claim reward(s).',
    progress_line = 'Rank: {rank} (Lvl {level})',

    need_item = 'You need a {item}',
    cannot_sell_here = 'You cannot sell here.',
    selling_already = 'You are already selling. Relax!',

    -- UI/menu titles
    leaderboard_title = 'Top Trap Stars',

    -- Confirm sale prompt (reserved for future use)
    confirm_sale_title = 'Confirm Sale',
    confirm_sale_desc = 'Proceed with the street sale?',
    confirm_yes = 'Yes',
    confirm_no = 'No',

    -- Hotspots
    hotspots_on = 'Hotspots: ON',
    hotspots_off = 'Hotspots: OFF',

    -- The Hustle Menu
    academy_menu_title = 'The Hustle',
    academy_menu_desc = 'Learn the ropes and start hustling.',
    academy_start = 'Start Hustle',
    academy_cancel = 'Cancel',
    academy_requirements = 'Requirements',
}

Locales.es = {
    claimed_rewards = 'Reclamaste {count} recompensa(s)',
    no_rewards = 'No hay recompensas para reclamar',
    claim_button = 'Reclamar Recompensas de Nivel',
    claim_button_none = 'Recompensas de Nivel',
    claim_you_have = 'Tienes {count} recompensa(s) sin reclamar',

    item_received = 'Buen trabajo, recibiste {text}',
    vehicle_stored = 'Buen trabajo, tu recompensa ha sido guardada en el garaje por tu seguridad.',

    progress_title = 'Tu Progreso — {name}',
    progress_ready = 'Alcanzaste el siguiente nivel. Haz clic para reclamar.',
    progress_line = 'Rango: {rank} (Nivel {level})',

    need_item = 'Necesitas un(a) {item}',
    cannot_sell_here = 'No puedes vender aquí.',
    selling_already = 'Ya estás vendiendo. ¡Tranquilo!'
    ,
    -- UI/menu titles
    leaderboard_title = 'Estrellas del Tráfico',

    -- Confirm sale prompt (reservado para uso futuro)
    confirm_sale_title = 'Confirmar Venta',
    confirm_sale_desc = '¿Deseas continuar con la venta?',
    confirm_yes = 'Sí',
    confirm_no = 'No',

    -- Hotspots
    hotspots_on = 'Zonas activas: ON',
    hotspots_off = 'Zonas activas: OFF',

    -- Menú Academia Hustle
    academy_menu_title = 'Academia de Hustle',
    academy_menu_desc = 'Aprende lo básico y empieza a hustlear.',
    academy_start = 'Comenzar',
    academy_cancel = 'Cancelar',
    academy_requirements = 'Requisitos',
}

-- Locale helper
function _L(key, data)
    local lang = (Config and Config.Locale) or 'en'
    local pack = Locales[lang] or Locales.en
    local str = (pack and pack[key]) or (Locales.en and Locales.en[key]) or key
    if data and type(data) == 'table' then
        for k, v in pairs(data) do
            str = tostring(str):gsub('{'..k..'}', tostring(v))
        end
    end
    return str
end

