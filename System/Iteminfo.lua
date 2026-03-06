function add_url()
    local M = ""
    return M
end
function add_item_link(v)
    if v <= 1 then
        return ""
    end
    local M =
        "^FF0000[ID:" ..
        tostring(v) ..
        "]^000000 <URL>[DATABASE]<INFO>https://kafraverse.com/database/item/info?search=" ..
        tostring(v) .. "&tab=monstros</INFO></URL>"
    return M
end

function main()
    IInfo = {
        "System.Kafraverse.Geral",
        -- "System.Kafraverse.!Geral-PK",
        "System.Kafraverse.Costumes",
        "System.Kafraverse.Custom",
        "System.Kafraverse.Rune-System",
        "System.Kafraverse.Mascotes",
        "System.Kafraverse.Chroma",
        "System.Oficiais.bRO_Iteminfo",
        "System.Oficiais.iRO_Iteminfo",
        "System.Oficiais.twRO_Iteminfo",
        "System.Oficiais.kRO_Iteminfo"
    }
    ItemList = {}
    for key, ItemInfo in pairs(IInfo) do
        require(ItemInfo)
        for ItemID, DESCS in pairs(tbl) do
            if not ItemList[ItemID] then
                ItemList[ItemID] = true
                result, msg =
                    AddItem(
                    ItemID,
                    DESCS.unidentifiedDisplayName,
                    DESCS.unidentifiedResourceName,
                    DESCS.identifiedDisplayName,
                    DESCS.identifiedResourceName,
                    DESCS.slotCount,
                    DESCS.ClassNum
                )
                if not result == true then
                    return false, msg
                end
                AddItemUnidentifiedDesc(ItemID, add_url())
                for k, v in pairs(DESCS.unidentifiedDescriptionName) do
                    result, msg = AddItemUnidentifiedDesc(ItemID, v)
                    if not result == true then
                        return false, msg
                    end
                end
                AddItemUnidentifiedDesc(ItemID, add_item_link(ItemID))
                AddItemIdentifiedDesc(ItemID, add_url())
                for k, v in pairs(DESCS.identifiedDescriptionName) do
                    result, msg = AddItemIdentifiedDesc(ItemID, v)
                    if not result == true then
                        return false, msg
                    end
                end
                AddItemIdentifiedDesc(ItemID, add_item_link(ItemID))
                if nil ~= DESCS.EffectID then
                    result, msg = AddItemEffectInfo(ItemID, DESCS.EffectID)
                end
                if not result == true then
                    return false, msg
                end
                if nil ~= DESCS.costume then
                    result, msg = AddItemIsCostume(ItemID, DESCS.costume)
                end
                if not result == true then
                    return false, msg
                end
            end
        end
    end
    return true, "good"
end