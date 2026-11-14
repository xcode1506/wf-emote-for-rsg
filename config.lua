--------------------------------------------------------------------------
-- WF-EMOTE configuration
-- Author: Hugo
--------------------------------------------------------------------------
WF = WF or {}

-- Opens / closes the menu (Windows virtual key, read with IsRawKeyReleased).
-- 0x76 = F7
WF.OpenKey = 0x76

-- Stops the current animation (RedM control hash). 0x8CC9CD42 = X.
WF.StopKey = 0x8CC9CD42

WF.Commands = {
    menu = 'wfemotes',  -- /wfemotes opens the menu
    play = 'e',         -- /e sit plays an animation, /e c stops it
    fav  = 'wfefav',    -- /wfefav <command> toggles a favourite
}

-- Framework used to save favourites per character: 'auto' | 'rsg' | 'vorp'
WF.Framework = 'auto'

-- Preview: a local clone of your character plays the animation while you
-- browse the menu, so you can see it before selecting (same technique as wf-interact).
WF.Preview = {
    enabled      = true,
    distance     = 2.4,    -- how far in front of the player the clone stands
    alpha        = 105,    -- clone transparency (0-255)
    camera       = true,   -- aim a camera at the clone while the menu is open
    cameraOffset = { x = 1.4, y = -2.6, z = 0.4 }, -- relative to the player (negative Y = behind)
    aimHeight    = 0.85,   -- camera look-at height above the clone's feet
    sideShift    = 1.45,   -- slides the clone to the right side of the screen
    fov          = 46.0,
}

-- Native RDR2 frontend sounds for the emote book (same layout as WFInteract.Sound).
-- Set enabled = false to mute the book.
WF.Sound = {
    enabled = true,
    open    = { name = 'INFO_SHOW',   set = 'Ledger_Sounds' },
    close   = { name = 'BACK',        set = 'HUD_SHOP_SOUNDSET' },
    navUp   = { name = 'NAV_UP',      set = 'Ledger_Sounds' },
    navDown = { name = 'NAV_DOWN',    set = 'Ledger_Sounds' },
    accept  = { name = 'SELECT',      set = 'HUD_SHOP_SOUNDSET' },
    deny    = { name = 'UNAFFORDABLE', set = 'Ledger_Sounds' },
}

-- Streamed clip defaults (rm_30 female pose pack)
WF.ClipDefaults = {
    BlendIn  = 4.0,
    BlendOut = -4.0,
}

-- Holster the weapon before playing a streamed pose clip
WF.HolsterWeapon = true

-- Language (reserved for future use)
WF.Locale = 'en'
