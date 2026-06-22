-- Add this to ox_inventory/data/items.lua

['radar_detector'] = {
    label = 'Radar Detector',
    weight = 850,
    stack = true,
    close = true,
    description = 'A vehicle-mounted radar detector tuned to police radar activity.',
    consume = 1,
    client = {
        usetime = 8000,
        cancel = true,
        disable = {
            car = true,
            move = true,
            combat = true
        }
    },
    server = {
        export = 'RadarDetector.radar_detector'
    }
},
