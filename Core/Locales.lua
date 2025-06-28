local addonName, addonTable = ...
addonTable.Locales = CopyTable(EVENTQ_LOCALES.enUS)

for key, translation in pairs(EVENTQ_LOCALES[GetLocale()]) do
    addonTable.Locales[key] = translation
end

for key, translation in pairs(addonTable.Locales) do
    _G["EVENTQ_L_" .. key] = translation
end
