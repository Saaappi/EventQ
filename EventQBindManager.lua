local addonName, addonTable = ...

BINDING_HEADER_EVENTQ = "EventQ"
BINDING_NAME_EVENTQ_CLICKBUTTON = "Click Button"

function EventQBindManager(key)
    if key == GetBindingKey("EVENTQ_CLICKBUTTON") then
        addonTable.ClickEventQButton()
    end
end