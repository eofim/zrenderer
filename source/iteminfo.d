module iteminfo;

import std.file : exists, read;
import std.string : split, strip;
import std.regex : regex, matchFirst, match;
import std.conv : to;
import std.typecons : Nullable;

/// Estrutura para armazenar informações de um item
struct ItemInfo
{
    uint id;
    string identifiedResourceName;
    string identifiedDisplayName;
    string unidentifiedResourceName;
    string unidentifiedDisplayName;
}

/// Parseia um arquivo Lua Iteminfo e retorna um array de ItemInfo
ItemInfo[] parseItemInfoFile(string filepath)
{
    if (!exists(filepath))
    {
        return [];
    }
    
    string content = read(filepath);
    ItemInfo[] items;
    
    // Regex para encontrar entradas de itens: [ID] = { ... }
    // Procura por padrões como [123] = { ... }
    auto itemIdPattern = regex(r"\[(\d+)\]\s*=\s*\{", "g");
    auto identifiedResourcePattern = regex(r"identifiedResourceName\s*=\s*\"([^\"]+)\"");
    auto identifiedDisplayPattern = regex(r"identifiedDisplayName\s*=\s*\"([^\"]+)\"");
    auto unidentifiedResourcePattern = regex(r"unidentifiedResourceName\s*=\s*\"([^\"]+)\"");
    auto unidentifiedDisplayPattern = regex(r"unidentifiedDisplayName\s*=\s*\"([^\"]+)\"");
    
    size_t lastPos = 0;
    
    // Encontra todos os IDs de itens
    foreach (m; match(content, itemIdPattern))
    {
        if (m.captures.length >= 2)
        {
            ItemInfo item;
            item.id = m.captures[1].to!uint;
            
            // Encontra o bloco do item (até o próximo [ ou fim do arquivo)
            size_t blockStart = m.pre.length + m.match.length;
            size_t blockEnd = content.length;
            
            // Procura pelo próximo [ID] = {
            auto nextMatch = matchFirst(content[blockStart .. $], itemIdPattern);
            if (!nextMatch.empty)
            {
                blockEnd = blockStart + nextMatch.pre.length;
            }
            
            string itemBlock = content[blockStart .. blockEnd];
            
            // Extrai identified resource name
            auto identifiedResourceMatch = matchFirst(itemBlock, identifiedResourcePattern);
            if (!identifiedResourceMatch.empty)
            {
                item.identifiedResourceName = identifiedResourceMatch.captures[1];
            }
            
            // Extrai identified display name
            auto identifiedDisplayMatch = matchFirst(itemBlock, identifiedDisplayPattern);
            if (!identifiedDisplayMatch.empty)
            {
                item.identifiedDisplayName = identifiedDisplayMatch.captures[1];
            }
            
            // Extrai unidentified resource name
            auto unidentifiedResourceMatch = matchFirst(itemBlock, unidentifiedResourcePattern);
            if (!unidentifiedResourceMatch.empty)
            {
                item.unidentifiedResourceName = unidentifiedResourceMatch.captures[1];
            }
            
            // Extrai unidentified display name
            auto unidentifiedDisplayMatch = matchFirst(itemBlock, unidentifiedDisplayPattern);
            if (!unidentifiedDisplayMatch.empty)
            {
                item.unidentifiedDisplayName = unidentifiedDisplayMatch.captures[1];
            }
            
            // Só adiciona se tiver pelo menos um resource name
            if (item.identifiedResourceName.length > 0 || item.unidentifiedResourceName.length > 0)
            {
                items ~= item;
            }
        }
    }
    
    return items;
}

/// Carrega todos os arquivos Iteminfo de um diretório
ItemInfo[] loadAllItemInfos(string systemPath)
{
    import std.path : buildPath;
    import std.file : dirEntries, DirEntry, SpanMode;
    import std.algorithm : filter, map;
    
    ItemInfo[] allItems;
    
    // Lista de arquivos Iteminfo conhecidos
    string[] itemInfoFiles = [
        "System/Iteminfo.lua",
        "System/Kafraverse/Geral.lua",
        "System/Kafraverse/Costumes.lua",
        "System/Kafraverse/Custom.lua",
        "System/Kafraverse/Rune-System.lua",
        "System/Kafraverse/Mascotes.lua",
        "System/Kafraverse/Chroma.lua",
        "System/Oficiais/bRO_Iteminfo.lua",
        "System/Oficiais/iRO_Iteminfo.lua",
        "System/Oficiais/twRO_Iteminfo.lua",
        "System/Oficiais/kRO_Iteminfo.lua"
    ];
    
    foreach (file; itemInfoFiles)
    {
        string fullPath = buildPath(systemPath, file);
        if (exists(fullPath))
        {
            auto items = parseItemInfoFile(fullPath);
            allItems ~= items;
        }
    }
    
    return allItems;
}

/// Encontra um item por ID
Nullable!ItemInfo findItemById(ItemInfo[] items, uint id)
{
    foreach (item; items)
    {
        if (item.id == id)
        {
            return Nullable!ItemInfo(item);
        }
    }
    return Nullable!ItemInfo.init;
}

/// Encontra um item por resource name
Nullable!ItemInfo findItemByResourceName(ItemInfo[] items, string resourceName)
{
    foreach (item; items)
    {
        if (item.identifiedResourceName == resourceName || item.unidentifiedResourceName == resourceName)
        {
            return Nullable!ItemInfo(item);
        }
    }
    return Nullable!ItemInfo.init;
}
