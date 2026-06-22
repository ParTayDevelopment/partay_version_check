-- [[ ParTay Keys - Service Ped Defaults ]] --
-- Internal defaults for service peds. Live blackmarket settings are managed
-- from /locksmithadmin Universal settings.

Config.ServicePedDefaults = Config.ServicePedDefaults or {}

Config.ServicePedDefaults.Blackmarket = {
    Enabled = true,
    Model = 's_m_y_dealer_01',
    Coords = vector4(163.9359, -1675.2462, 29.7743, 140.6165),
    ShowOnMap = true,
    Blip = {
        Label = 'Blackmarket',
        Sprite = 378,
        Color = 1,
        Scale = 0.75
    },
    Currency = 'black_money',
    Items = {
        { item = Config.Items.Lockpick, label = 'Lockpick', price = 250 },
        { item = Config.Items.WiringKit, label = 'Wiring Kit', price = 750 },
        { item = Config.Items.ElectronicDecoder, label = 'Electronic Decoder', price = 2500 },
        { item = Config.Items.BlankKey, label = 'Blank Key Fob', price = 500 },
        { item = Config.Items.SaleContract, label = 'Vehicle Sale Contract', price = 100 }
    }
}
