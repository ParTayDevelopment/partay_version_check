-- [[ ParTay Animations Dictionary ]] --
-- Safely edit dictionaries, names, and flags here without breaking core logic.

Animations = {}

-- Used when installing GPS trackers at a tire well.
Animations.TrackerInstall = {
    dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@',
    name = 'machinic_loop_mechandplayer',
    flags = 1, -- 1: Full body loop, 49: Upper body only.
    duration = 5000
}

-- Used when installing an alarm in the engine bay.
Animations.AlarmInstall = {
    dict = 'amb@prop_human_bum_bin@base',
    name = 'base',
    flags = 1,
    duration = 5000
}

Animations.RemoveTracker = {
    dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@',
    name = 'machinic_loop_mechandplayer',
    flags = 1,
    duration = 3500
}

Animations.Lockpick = {
    dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@',
    name = 'machinic_loop_mechandplayer',
    flags = 49,
    duration = -1
}

Animations.Hotwire = {
    dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@',
    name = 'machinic_loop_mechandplayer',
    flags = 49,
    duration = -1
}

Animations.Decoder = {
    dict = 'amb@code_human_in_bus_passenger_idles@female@tablet@base',
    name = 'base',
    flags = 49,
    duration = -1
}

Animations.ContractHandoff = {
    dict = 'mp_common',
    name = 'givetake2_a',
    flags = 48,
    duration = 2000
}

Animations.NpcKeyGive = {
    dict = 'mp_common',
    name = 'givetake1_a',
    flags = 48,
    duration = 1400
}

Animations.NpcKeyReceive = {
    dict = 'mp_common',
    name = 'givetake1_b',
    flags = 48,
    duration = 1400
}

Animations.FobPress = {
    dict = 'anim@mp_player_intmenu@key_fob@',
    name = 'fob_click',
    flags = 48,
    duration = 800
}

-- Used by basic physical keys before sending the lock toggle.
Animations.BasicKeyTurn = {
    dict = 'mp_common',
    name = 'givetake1_a',
    flags = 48,
    duration = 900
}

-- Optional future custom animations for staged pocket in/out key handling.
-- Leave disabled until a clean custom animation is available.
Animations.BasicKeyPocketOut = nil
Animations.BasicKeyPocketIn = nil

-- Used while tablet-style NUI is open, including GPS, signal finder, key menu, and service ped menus.
Animations.TabletHold = {
    dict = 'amb@code_human_in_bus_passenger_idles@female@tablet@base',
    name = 'base',
    flags = 49
}

-- Used while a sale contract clipboard NUI is open.
Animations.ClipboardHold = {
    dict = 'missfam4',
    name = 'base',
    flags = 49
}

Animations.TerminalHold = {
    dict = 'cellphone@',
    name = 'cellphone_text_read_base',
    flags = 49
}

Animations.LocksmithInvoice = {
    dict = 'missfam4',
    name = 'base',
    flags = 49,
    duration = 3500
}

Animations.LocksmithPayment = {
    dict = 'cellphone@',
    name = 'cellphone_text_read_base',
    flags = 49,
    duration = 3500
}

Animations.LocksmithDoorWork = {
    dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@',
    name = 'machinic_loop_mechandplayer',
    flags = 1,
    duration = 3500
}

Animations.LocksmithWorkbench = {
    dict = 'amb@prop_human_bum_bin@base',
    name = 'base',
    flags = 1,
    duration = 5000
}

Animations.LocksmithStockBox = {
    dict = 'anim@heists@box_carry@',
    name = 'idle',
    flags = 49,
    duration = 3000
}
