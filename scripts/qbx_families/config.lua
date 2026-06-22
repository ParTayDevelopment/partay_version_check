Config = {}

Config.Command = 'family'
Config.AdminPermission = 'group.admin'

Config.Debug = {
    enabled = true,
    eventZonePlacement = true,
}

Config.Allowance = {
    moneyType = 'cash',
    maxAmount = 5000,
}

Config.Funds = {
    donationAccounts = {
        { value = 'cash', label = 'Cash' },
        { value = 'bank', label = 'Bank' },
    },
    minDonation = 1,
    maxDonation = 100000,
}

Config.Progression = {
    defaultGarage = 'Legion Square',
    levels = {
        [1] = 0,
        [2] = 500,
        [3] = 1500,
        [4] = 3000,
        [5] = 5000,
    },
    rewards = {
        {
            id = 'starter_cash',
            label = '$10,000 Family Bonus',
            description = 'Money paid to the Head of House who redeems it.',
            type = 'money',
            requiredLevel = 1,
            cost = 250,
            fundCost = 0,
            account = 'bank',
            amount = 10000,
            repeatable = true,
        },
        {
            id = 'radio_pack',
            label = 'Family Radio Pack',
            description = 'Gives radios to the Head of House.',
            type = 'item',
            requiredLevel = 1,
            cost = 150,
            fundCost = 0,
            item = 'radio',
            count = 5,
            repeatable = true,
        },
        {
            id = 'family_suv',
            label = 'Family SUV',
            description = 'Owned vehicle given to the Head of House garage.',
            type = 'vehicle',
            requiredLevel = 2,
            cost = 750,
            fundCost = 25000,
            vehicle = 'baller',
            garage = 'Legion Square',
            repeatable = false,
        },
        {
            id = 'street_event_props',
            label = 'Street Event Props',
            description = 'Unlocks coolers, cones, and street scene props for family event creation.',
            type = 'prop_unlock',
            requiredLevel = 1,
            cost = 200,
            fundCost = 5000,
            repeatable = false,
        },
        {
            id = 'party_event_props',
            label = 'Party Event Props',
            description = 'Unlocks speakers and party scene props for family event creation.',
            type = 'prop_unlock',
            requiredLevel = 2,
            cost = 450,
            fundCost = 12000,
            repeatable = false,
        },
    },
}

Config.Events = {
    defaultPreset = 'small',
    startCountdownMinutes = 10,
    defaultRadius = 35.0,
    minRadius = 10.0,
    maxRadius = 120.0,
    defaultPointsPerTick = 10,
    minPointsPerTick = 1,
    maxPointsPerTick = 100,
    tickMinutes = 5,
    minimumMembersInZone = 1,
    minZonePoints = 4,
    debugZone = false,
    debugPlacement = false,
    screenshotEncoding = 'jpg',
    screenshotQuality = 0.68,
    maxBannerBytes = 900000,
    maxPropsPerEvent = 10,
    propStreamDistance = 140.0,
    allowedProps = {
        {
            id = 'folding_chair',
            label = 'Folding Chair',
            model = 'prop_table_03_chr',
        },
        {
            id = 'cooler',
            label = 'Cooler',
            model = 'prop_coolbox_01',
            unlock = 'street_event_props',
        },
        {
            id = 'speaker',
            label = 'Speaker',
            model = 'prop_speaker_06',
            unlock = 'party_event_props',
        },
        {
            id = 'traffic_cone',
            label = 'Traffic Cone',
            model = 'prop_roadcone02a',
            unlock = 'street_event_props',
        },
        {
            id = 'barrier',
            label = 'Barrier',
            model = 'prop_barrier_work05',
            unlock = 'street_event_props',
        },
    },
    presets = {
        small = {
            label = 'Small Event',
            description = 'Neighborhood-sized scene.',
            maxArea = 2500.0,
            radius = 35.0,
            pointsPerTick = 10,
        },
        medium = {
            label = 'Medium Event',
            description = 'Bigger block or business scene.',
            maxArea = 7500.0,
            radius = 55.0,
            pointsPerTick = 20,
        },
        large = {
            label = 'Large Event',
            description = 'Large family-hosted scene.',
            radius = 80.0,
            pointsPerTick = 35,
        },
    },
}

Config.Management = {
    maxHeadsPerFamily = 2,
    headPermissions = {
        canInvite = true,
        canKick = true,
        canSetRole = true,
        canGiveAllowance = true,
    },
}

Config.Families = {
    none = {
        label = 'No Family',
        roles = {
            none = {
                label = 'Unaffiliated',
            },
        },
    },

    carter = {
        label = 'Carter Family',
        roles = {
            member = {
                label = 'Member',
            },
            brother = {
                label = 'Brother',
            },
            stepbrother = {
                label = 'Step Brother',
            },
            sister = {
                label = 'Sister',
            },
            stepsister = {
                label = 'Step Sister',
            },
            cousin = {
                label = 'Cousin',
            },
            uncle = {
                label = 'Uncle',
            },
            aunt = {
                label = 'Aunt',
            },
        },
    },
    nolove = {
        label = 'No Love Lost Family',
        roles = {
            member = {
                label = 'Member',
            },
            brother = {
                label = 'Brother',
            },
            stepbrother = {
                label = 'Step Brother',
            },
            sister = {
                label = 'Sister',
            },
            stepsister = {
                label = 'Step Sister',
            },
            cousin = {
                label = 'Cousin',
            },
            uncle = {
                label = 'Uncle',
            },
            aunt = {
                label = 'Aunt',
            },
        },
    },
}
