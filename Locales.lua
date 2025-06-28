local addonName, addonTable = ...
local Locales = {
    enUS = {},
    enGB = {},
    deDE = {},
    esES = {},
    esMX = {},
    frFR = {},
    itIT = {},
    koKR = {},
    ptBR = {},
    ruRU = {},
    zhCN = {},
    zhTW = {}
}

EVENTQ_LOCALES = Locales

local L = Locales.enUS

L["EVENTQ"]         = "eventq"

L["ENABLED"]        = "Enabled"
L["ENABLED_DESC"]   = "Toggle to show or hide the queue button."

L["AUTO_ENROLLMENT"]        = "Auto Enrollment"
L["AUTO_ENROLLMENT_DESC"]   = "Toggle to automatically enroll in events based on whether or not they're active or not."

L["BREWFEST"]               = "Brewfest"
L["LOVE_IS_IN_THE_AIR"]     = "Love is in the Air"
L["HALLOWS_END"]            = "Hallow's End"
L["MIDSUMMER"]              = "Midsummer Fire Festival"
L["TIMEWALKING_CLASSIC"]    = "Timewalking: " .. EXPANSION_NAME0
L["TIMEWALKING_TBC"]        = "Timewalking: " .. EXPANSION_NAME1
L["TIMEWALKING_WOTLK"]      = "Timewalking: " .. EXPANSION_NAME2
L["TIMEWALKING_CATA"]       = "Timewalking: " .. EXPANSION_NAME3
L["TIMEWALKING_MOP"]        = "Timewalking: " .. EXPANSION_NAME4
L["TIMEWALKING_WOD"]        = "Timewalking: " .. EXPANSION_NAME5
L["TIMEWALKING_LEGION"]     = "Timewalking: " .. EXPANSION_NAME6
L["TIMEWALKING_BFA"]        = "Timewalking: " .. EXPANSION_NAME7

local L = Locales.enGB

L["EVENTQ"]         = "eventq"

L["ENABLED"]        = "Enabled"
L["ENABLED_DESC"]   = "Toggle to show or hide the queue button."

L["AUTO_ENROLLMENT"]        = "Auto Enrollment"
L["AUTO_ENROLLMENT_DESC"]   = "Toggle to automatically enroll in events based on whether or not they're active or not."

L["BREWFEST"]               = "Brewfest"
L["LOVE_IS_IN_THE_AIR"]     = "Love is in the Air"
L["HALLOWS_END"]            = "Hallow's End"
L["MIDSUMMER"]              = "Midsummer Fire Festival"
L["TIMEWALKING_CLASSIC"]    = "Timewalking: " .. EXPANSION_NAME0
L["TIMEWALKING_TBC"]        = "Timewalking: " .. EXPANSION_NAME1
L["TIMEWALKING_WOTLK"]      = "Timewalking: " .. EXPANSION_NAME2
L["TIMEWALKING_CATA"]       = "Timewalking: " .. EXPANSION_NAME3
L["TIMEWALKING_MOP"]        = "Timewalking: " .. EXPANSION_NAME4
L["TIMEWALKING_WOD"]        = "Timewalking: " .. EXPANSION_NAME5
L["TIMEWALKING_LEGION"]     = "Timewalking: " .. EXPANSION_NAME6
L["TIMEWALKING_BFA"]        = "Timewalking: " .. EXPANSION_NAME7

local L = Locales.deDE

L["EVENTQ"]         = "eventq"

L["ENABLED"]        = "Aktiviert"
L["ENABLED_DESC"]   = "Umschalten, um die Warteschlangen-Schaltfläche anzuzeigen oder zu verbergen."

L["AUTO_ENROLLMENT"]        = "Automatische Registrierung"
L["AUTO_ENROLLMENT_DESC"]   = "Umschalten, um sich automatisch für Ereignisse zu registrieren, je nachdem, ob sie aktiv sind oder nicht."

L["BREWFEST"]               = "Braufest"
L["LOVE_IS_IN_THE_AIR"]     = "Liebe liegt in der Luft"
L["HALLOWS_END"]            = "Schlotternächte"
L["MIDSUMMER"]              = "Sonnenwendfest"
L["TIMEWALKING_CLASSIC"]    = "Timewalking: " .. EXPANSION_NAME0
L["TIMEWALKING_TBC"]        = "Timewalking: " .. EXPANSION_NAME1
L["TIMEWALKING_WOTLK"]      = "Timewalking: " .. EXPANSION_NAME2
L["TIMEWALKING_CATA"]       = "Timewalking: " .. EXPANSION_NAME3
L["TIMEWALKING_MOP"]        = "Timewalking: " .. EXPANSION_NAME4
L["TIMEWALKING_WOD"]        = "Timewalking: " .. EXPANSION_NAME5
L["TIMEWALKING_LEGION"]     = "Timewalking: " .. EXPANSION_NAME6
L["TIMEWALKING_BFA"]        = "Timewalking: " .. EXPANSION_NAME7

local L = Locales.esES

L["EVENTQ"]         = "eventq"

L["ENABLED"]        = "Activado"
L["ENABLED_DESC"]   = "Alternar para mostrar u ocultar el botón de cola."

L["AUTO_ENROLLMENT"]        = "Inscripción automática"
L["AUTO_ENROLLMENT_DESC"]   = "Alternar para inscribirse automáticamente en eventos en función de si están activos o no."

L["BREWFEST"]               = "Fiesta de la Cerveza"
L["LOVE_IS_IN_THE_AIR"]     = "Amor en el aire"
L["HALLOWS_END"]            = "Halloween"
L["MIDSUMMER"]              = "Festival del Fuego del Solsticio de Verano"
L["TIMEWALKING_CLASSIC"]    = "Timewalking: " .. EXPANSION_NAME0
L["TIMEWALKING_TBC"]        = "Timewalking: " .. EXPANSION_NAME1
L["TIMEWALKING_WOTLK"]      = "Timewalking: " .. EXPANSION_NAME2
L["TIMEWALKING_CATA"]       = "Timewalking: " .. EXPANSION_NAME3
L["TIMEWALKING_MOP"]        = "Timewalking: " .. EXPANSION_NAME4
L["TIMEWALKING_WOD"]        = "Timewalking: " .. EXPANSION_NAME5
L["TIMEWALKING_LEGION"]     = "Timewalking: " .. EXPANSION_NAME6
L["TIMEWALKING_BFA"]        = "Timewalking: " .. EXPANSION_NAME7

local L = Locales.esMX

L["EVENTQ"]         = "eventq"

L["ENABLED"]        = "Activado"
L["ENABLED_DESC"]   = "Alternar para mostrar u ocultar el botón de cola."

L["AUTO_ENROLLMENT"]        = "Inscripción automática"
L["AUTO_ENROLLMENT_DESC"]   = "Alternar para inscribirse automáticamente en eventos dependiendo de si están activos o no."

L["BREWFEST"]               = "Fiesta de la Cerveza"
L["LOVE_IS_IN_THE_AIR"]     = "Amor en el aire"
L["HALLOWS_END"]            = "Halloween"
L["MIDSUMMER"]              = "Festival de Fuego del Solsticio de Verano"
L["TIMEWALKING_CLASSIC"]    = "Timewalking: " .. EXPANSION_NAME0
L["TIMEWALKING_TBC"]        = "Timewalking: " .. EXPANSION_NAME1
L["TIMEWALKING_WOTLK"]      = "Timewalking: " .. EXPANSION_NAME2
L["TIMEWALKING_CATA"]       = "Timewalking: " .. EXPANSION_NAME3
L["TIMEWALKING_MOP"]        = "Timewalking: " .. EXPANSION_NAME4
L["TIMEWALKING_WOD"]        = "Timewalking: " .. EXPANSION_NAME5
L["TIMEWALKING_LEGION"]     = "Timewalking: " .. EXPANSION_NAME6
L["TIMEWALKING_BFA"]        = "Timewalking: " .. EXPANSION_NAME7

local L = Locales.frFR

L["EVENTQ"]         = "eventq"

L["ENABLED"]        = "Activé"
L["ENABLED_DESC"]   = "Basculer pour afficher ou masquer le bouton de file d'attente."

L["AUTO_ENROLLMENT"]        = "Inscription automatique"
L["AUTO_ENROLLMENT_DESC"]   = "Toggle to automatically enroll in events based on whether or not they're active or not."

L["BREWFEST"]               = "Fête des Brasseurs"
L["LOVE_IS_IN_THE_AIR"]     = "De l'amour dans l'air"
L["HALLOWS_END"]            = "Sanssaint"
L["MIDSUMMER"]              = "Fête du Feu du solstice d'été"
L["TIMEWALKING_CLASSIC"]    = "Timewalking: " .. EXPANSION_NAME0
L["TIMEWALKING_TBC"]        = "Timewalking: " .. EXPANSION_NAME1
L["TIMEWALKING_WOTLK"]      = "Timewalking: " .. EXPANSION_NAME2
L["TIMEWALKING_CATA"]       = "Timewalking: " .. EXPANSION_NAME3
L["TIMEWALKING_MOP"]        = "Timewalking: " .. EXPANSION_NAME4
L["TIMEWALKING_WOD"]        = "Timewalking: " .. EXPANSION_NAME5
L["TIMEWALKING_LEGION"]     = "Timewalking: " .. EXPANSION_NAME6
L["TIMEWALKING_BFA"]        = "Timewalking: " .. EXPANSION_NAME7

local L = Locales.itIT

L["EVENTQ"]         = "eventq"

L["ENABLED"]        = "Abilitato"
L["ENABLED_DESC"]   = "Attiva per mostrare o nascondere il pulsante della coda."

L["AUTO_ENROLLMENT"]        = "Iscrizione Automatica"
L["AUTO_ENROLLMENT_DESC"]   = "Attiva per iscriversi automaticamente agli eventi in base al fatto che siano attivi o meno."

L["BREWFEST"]               = "Festa della Birra"
L["LOVE_IS_IN_THE_AIR"]     = "Amore nell'Aria"
L["HALLOWS_END"]            = "Veglia delle Ombre"
L["MIDSUMMER"]              = "Fuochi di Mezza Estate"
L["TIMEWALKING_CLASSIC"]    = "Timewalking: " .. EXPANSION_NAME0
L["TIMEWALKING_TBC"]        = "Timewalking: " .. EXPANSION_NAME1
L["TIMEWALKING_WOTLK"]      = "Timewalking: " .. EXPANSION_NAME2
L["TIMEWALKING_CATA"]       = "Timewalking: " .. EXPANSION_NAME3
L["TIMEWALKING_MOP"]        = "Timewalking: " .. EXPANSION_NAME4
L["TIMEWALKING_WOD"]        = "Timewalking: " .. EXPANSION_NAME5
L["TIMEWALKING_LEGION"]     = "Timewalking: " .. EXPANSION_NAME6
L["TIMEWALKING_BFA"]        = "Timewalking: " .. EXPANSION_NAME7

local L = Locales.koKR

L["EVENTQ"]         = "eventq"

L["ENABLED"]        = "Enabled"
L["ENABLED_DESC"]   = "Toggle to show or hide the queue button."

L["AUTO_ENROLLMENT"]        = "Auto Enrollment"
L["AUTO_ENROLLMENT_DESC"]   = "Toggle to automatically enroll in events based on whether or not they're active or not."

L["BREWFEST"]               = "Brewfest"
L["LOVE_IS_IN_THE_AIR"]     = "Love is in the Air"
L["HALLOWS_END"]            = "Hallow's End"
L["MIDSUMMER"]              = "Midsummer Fire Festival"
L["TIMEWALKING_CLASSIC"]    = "Timewalking: " .. EXPANSION_NAME0
L["TIMEWALKING_TBC"]        = "Timewalking: " .. EXPANSION_NAME1
L["TIMEWALKING_WOTLK"]      = "Timewalking: " .. EXPANSION_NAME2
L["TIMEWALKING_CATA"]       = "Timewalking: " .. EXPANSION_NAME3
L["TIMEWALKING_MOP"]        = "Timewalking: " .. EXPANSION_NAME4
L["TIMEWALKING_WOD"]        = "Timewalking: " .. EXPANSION_NAME5
L["TIMEWALKING_LEGION"]     = "Timewalking: " .. EXPANSION_NAME6
L["TIMEWALKING_BFA"]        = "Timewalking: " .. EXPANSION_NAME7

local L = Locales.ptBR

L["EVENTQ"]         = "eventq"

L["ENABLED"]        = "Enabled"
L["ENABLED_DESC"]   = "Toggle to show or hide the queue button."

L["AUTO_ENROLLMENT"]        = "Auto Enrollment"
L["AUTO_ENROLLMENT_DESC"]   = "Toggle to automatically enroll in events based on whether or not they're active or not."

L["BREWFEST"]               = "Brewfest"
L["LOVE_IS_IN_THE_AIR"]     = "Love is in the Air"
L["HALLOWS_END"]            = "Hallow's End"
L["MIDSUMMER"]              = "Midsummer Fire Festival"
L["TIMEWALKING_CLASSIC"]    = "Timewalking: " .. EXPANSION_NAME0
L["TIMEWALKING_TBC"]        = "Timewalking: " .. EXPANSION_NAME1
L["TIMEWALKING_WOTLK"]      = "Timewalking: " .. EXPANSION_NAME2
L["TIMEWALKING_CATA"]       = "Timewalking: " .. EXPANSION_NAME3
L["TIMEWALKING_MOP"]        = "Timewalking: " .. EXPANSION_NAME4
L["TIMEWALKING_WOD"]        = "Timewalking: " .. EXPANSION_NAME5
L["TIMEWALKING_LEGION"]     = "Timewalking: " .. EXPANSION_NAME6
L["TIMEWALKING_BFA"]        = "Timewalking: " .. EXPANSION_NAME7

local L = Locales.ruRU

L["EVENTQ"]         = "eventq"

L["ENABLED"]        = "Enabled"
L["ENABLED_DESC"]   = "Toggle to show or hide the queue button."

L["AUTO_ENROLLMENT"]        = "Auto Enrollment"
L["AUTO_ENROLLMENT_DESC"]   = "Toggle to automatically enroll in events based on whether or not they're active or not."

L["BREWFEST"]               = "Brewfest"
L["LOVE_IS_IN_THE_AIR"]     = "Love is in the Air"
L["HALLOWS_END"]            = "Hallow's End"
L["MIDSUMMER"]              = "Midsummer Fire Festival"
L["TIMEWALKING_CLASSIC"]    = "Timewalking: " .. EXPANSION_NAME0
L["TIMEWALKING_TBC"]        = "Timewalking: " .. EXPANSION_NAME1
L["TIMEWALKING_WOTLK"]      = "Timewalking: " .. EXPANSION_NAME2
L["TIMEWALKING_CATA"]       = "Timewalking: " .. EXPANSION_NAME3
L["TIMEWALKING_MOP"]        = "Timewalking: " .. EXPANSION_NAME4
L["TIMEWALKING_WOD"]        = "Timewalking: " .. EXPANSION_NAME5
L["TIMEWALKING_LEGION"]     = "Timewalking: " .. EXPANSION_NAME6
L["TIMEWALKING_BFA"]        = "Timewalking: " .. EXPANSION_NAME7

local L = Locales.zhCN

L["EVENTQ"]         = "eventq"

L["ENABLED"]        = "Enabled"
L["ENABLED_DESC"]   = "Toggle to show or hide the queue button."

L["AUTO_ENROLLMENT"]        = "Auto Enrollment"
L["AUTO_ENROLLMENT_DESC"]   = "Toggle to automatically enroll in events based on whether or not they're active or not."

L["BREWFEST"]               = "Brewfest"
L["LOVE_IS_IN_THE_AIR"]     = "Love is in the Air"
L["HALLOWS_END"]            = "Hallow's End"
L["MIDSUMMER"]              = "Midsummer Fire Festival"
L["TIMEWALKING_CLASSIC"]    = "Timewalking: " .. EXPANSION_NAME0
L["TIMEWALKING_TBC"]        = "Timewalking: " .. EXPANSION_NAME1
L["TIMEWALKING_WOTLK"]      = "Timewalking: " .. EXPANSION_NAME2
L["TIMEWALKING_CATA"]       = "Timewalking: " .. EXPANSION_NAME3
L["TIMEWALKING_MOP"]        = "Timewalking: " .. EXPANSION_NAME4
L["TIMEWALKING_WOD"]        = "Timewalking: " .. EXPANSION_NAME5
L["TIMEWALKING_LEGION"]     = "Timewalking: " .. EXPANSION_NAME6
L["TIMEWALKING_BFA"]        = "Timewalking: " .. EXPANSION_NAME7

local L = Locales.zhTW

L["EVENTQ"]         = "eventq"

L["ENABLED"]        = "Enabled"
L["ENABLED_DESC"]   = "Toggle to show or hide the queue button."

L["AUTO_ENROLLMENT"]        = "Auto Enrollment"
L["AUTO_ENROLLMENT_DESC"]   = "Toggle to automatically enroll in events based on whether or not they're active or not."

L["BREWFEST"]               = "Brewfest"
L["LOVE_IS_IN_THE_AIR"]     = "Love is in the Air"
L["HALLOWS_END"]            = "Hallow's End"
L["MIDSUMMER"]              = "Midsummer Fire Festival"
L["TIMEWALKING_CLASSIC"]    = "Timewalking: " .. EXPANSION_NAME0
L["TIMEWALKING_TBC"]        = "Timewalking: " .. EXPANSION_NAME1
L["TIMEWALKING_WOTLK"]      = "Timewalking: " .. EXPANSION_NAME2
L["TIMEWALKING_CATA"]       = "Timewalking: " .. EXPANSION_NAME3
L["TIMEWALKING_MOP"]        = "Timewalking: " .. EXPANSION_NAME4
L["TIMEWALKING_WOD"]        = "Timewalking: " .. EXPANSION_NAME5
L["TIMEWALKING_LEGION"]     = "Timewalking: " .. EXPANSION_NAME6
L["TIMEWALKING_BFA"]        = "Timewalking: " .. EXPANSION_NAME7