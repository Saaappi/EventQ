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
L["AUTO_ENROLLMENT_DESC"]   = "Toggle to automatically enroll in events based on whether they're active or not."

L["QUEUE_REPORT_OUT"]       = "Queue Report Out"
L["QUEUE_REPORT_OUT_DESC"]  = "Report the stats of the queue to the chat frame every 60 seconds."

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
L["AUTO_ENROLLMENT_DESC"]   = "Toggle to automatically enroll in events based on whether they're active or not."

L["QUEUE_REPORT_OUT"]       = "Queue Report Out"
L["QUEUE_REPORT_OUT_DESC"]  = "Report the stats of the queue to the chat frame every 60 seconds."

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

L["QUEUE_REPORT_OUT"]       = "Warteschlangenbericht"
L["QUEUE_REPORT_OUT_DESC"]  = "Gibt die Warteschlangenstatistiken alle 60 Sekunden im Chatfenster aus."

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

L["QUEUE_REPORT_OUT"]       = "Informe de cola"
L["QUEUE_REPORT_OUT_DESC"]  = "Informa las estadísticas de la cola en el chat cada 60 segundos"

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

L["QUEUE_REPORT_OUT"]       = "Reporte de Cola"
L["QUEUE_REPORT_OUT_DESC"]  = "Reporta las estadísticas de la cola en el chat cada 60 segundos."

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

L["QUEUE_REPORT_OUT"]       = "Rapport de File d'Attente"
L["QUEUE_REPORT_OUT_DESC"]  = "Signale les statistiques de la file d'attente dans la fenêtre de chat toutes les 60 secondes."

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

L["QUEUE_REPORT_OUT"]       = "Coda Statistiche Rapporto"
L["QUEUE_REPORT_OUT_DESC"]  = "Riporta le statistiche della coda nella chat ogni 60 secondi."

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

L["ENABLED"]        = "활성화됨"
L["ENABLED_DESC"]   = "대기열 버튼을 표시하거나 숨기려면 전환하세요."

L["AUTO_ENROLLMENT"]        = "자동 등록"
L["AUTO_ENROLLMENT_DESC"]   = "이벤트가 활성 상태인지 여부에 따라 자동으로 등록하도록 전환합니다."

L["QUEUE_REPORT_OUT"]       = "대기열 보고"
L["QUEUE_REPORT_OUT_DESC"]  = "60초마다 대기열 통계를 채팅창에 보고합니다."

L["BREWFEST"]               = "가을 축제"
L["LOVE_IS_IN_THE_AIR"]     = "온누리에 사랑을"
L["HALLOWS_END"]            = "할로윈 축제"
L["MIDSUMMER"]              = "한여름 불꽃축제"
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

L["ENABLED"]        = "Ativado"
L["ENABLED_DESC"]   = "Alternar para mostrar ou ocultar o botão da fila."

L["AUTO_ENROLLMENT"]        = "Inscrição Automática"
L["AUTO_ENROLLMENT_DESC"]   = "Alternar para se inscrever automaticamente em eventos com base em estarem ativos ou não."

L["QUEUE_REPORT_OUT"]       = "Relatório da Fila"
L["QUEUE_REPORT_OUT_DESC"]  = "Relata as estatísticas da fila no chat a cada 60 segundos."

L["BREWFEST"]               = "CervaFest"
L["LOVE_IS_IN_THE_AIR"]     = "O Amor Está No Ar"
L["HALLOWS_END"]            = "Noturnália"
L["MIDSUMMER"]              = "Festival do Fogo do Solstício"
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

L["ENABLED"]        = "Активировать"
L["ENABLED_DESC"]   = "Переключить, чтобы показать или скрыть кнопку очереди."

L["AUTO_ENROLLMENT"]        = "Автоматическая регистрация"
L["AUTO_ENROLLMENT_DESC"]   = "Переключить для автоматической регистрации на события в зависимости от их активности."

L["QUEUE_REPORT_OUT"]       = "Отчет о очереди"
L["QUEUE_REPORT_OUT_DESC"]  = "Отправлять статистику очереди в чат каждые 60 секунд."

L["BREWFEST"]               = "Хмельной фестиваль"
L["LOVE_IS_IN_THE_AIR"]     = "Любовная лихорадка"
L["HALLOWS_END"]            = "Тыквовин"
L["MIDSUMMER"]              = "Огненный солнцеворот"
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

L["ENABLED"]        = "啟用"
L["ENABLED_DESC"]   = "切換以顯示或隱藏隊列按鈕。"

L["AUTO_ENROLLMENT"]        = "自動報名"
L["AUTO_ENROLLMENT_DESC"]   = "切換以根據活動是否啟動自動報名參加活動。"

L["QUEUE_REPORT_OUT"]       = "佇列報告輸出"
L["QUEUE_REPORT_OUT_DESC"]  = "每60秒將隊列狀態報告到聊天視窗。"

L["BREWFEST"]               = "美酒节"
L["LOVE_IS_IN_THE_AIR"]     = "情人节"
L["HALLOWS_END"]            = "万圣节"
L["MIDSUMMER"]              = "仲夏火焰节"
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

L["ENABLED"]        = "啟用"
L["ENABLED_DESC"]   = "切換以顯示或隱藏佇列按鈕。"

L["AUTO_ENROLLMENT"]        = "自動報名"
L["AUTO_ENROLLMENT_DESC"]   = "切換此選項，系統會根據活動是否正在進行，自動報名參加。"

L["QUEUE_REPORT_OUT"]       = "隊列報告輸出"
L["QUEUE_REPORT_OUT_DESC"]  = "每60秒將隊列統計資料報告到聊天視窗。"

L["BREWFEST"]               = "啤酒節"
L["LOVE_IS_IN_THE_AIR"]     = "愛就在身邊"
L["HALLOWS_END"]            = "萬鬼節"
L["MIDSUMMER"]              = "仲夏火焰節慶"
L["TIMEWALKING_CLASSIC"]    = "Timewalking: " .. EXPANSION_NAME0
L["TIMEWALKING_TBC"]        = "Timewalking: " .. EXPANSION_NAME1
L["TIMEWALKING_WOTLK"]      = "Timewalking: " .. EXPANSION_NAME2
L["TIMEWALKING_CATA"]       = "Timewalking: " .. EXPANSION_NAME3
L["TIMEWALKING_MOP"]        = "Timewalking: " .. EXPANSION_NAME4
L["TIMEWALKING_WOD"]        = "Timewalking: " .. EXPANSION_NAME5
L["TIMEWALKING_LEGION"]     = "Timewalking: " .. EXPANSION_NAME6
L["TIMEWALKING_BFA"]        = "Timewalking: " .. EXPANSION_NAME7