module zrenderer.server.routes.itemicon;

import std.file : exists, read;
import std.path : buildPath;
import std.conv : to;
import std.exception : ifThrown;
import std.typecons : Nullable;
import vibe.core.log : logError, logInfo;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.http.status;
import zrenderer.server.globals : defaultConfig;
import zrenderer.server.routes : setErrorResponse;
import iteminfo : ItemInfo, loadAllItemInfos, findItemById;
import imageformats.bmp : loadBmpFile, removeMagentaBackground, rawImageToPngBytes;
import draw : RawImage;

/// Cache de ItemInfos carregados
__gshared ItemInfo[] cachedItemInfos;
__gshared bool itemInfosLoaded = false;

/// Carrega os ItemInfos se ainda não foram carregados
void ensureItemInfosLoaded()
{
    if (!itemInfosLoaded)
    {
        import std.path : dirName, absolutePath;
        
        // Tenta encontrar o diretório System
        string[] possiblePaths = [
            "System",
            buildPath("..", "System"),
            buildPath("..", "..", "System"),
            buildPath(dirName(dirName(dirName(__FILE__))), "..", "System"),
        ];
        
        string systemPath;
        bool found = false;
        
        foreach (path; possiblePaths)
        {
            if (exists(path))
            {
                systemPath = absolutePath(path);
                found = true;
                break;
            }
        }
        
        if (found)
        {
            cachedItemInfos = loadAllItemInfos(systemPath);
            itemInfosLoaded = true;
            logInfo("Loaded %d items from Iteminfo files in %s", cachedItemInfos.length, systemPath);
        }
        else
        {
            import std.array : join;
            logError("Could not find System directory for Iteminfo files. Tried: %s", possiblePaths.join(", "));
        }
    }
}

/// Encontra o caminho do arquivo de textura de item
Nullable!string findItemTexturePath(string resourceName, string textureType = "item")
{
    import std.algorithm : canFind;
    
    // Lista de possíveis caminhos
    string[] possiblePaths = [
        buildPath("resources", "data", "texture", "유저인터페이스", textureType, resourceName ~ ".bmp"),
        buildPath("data", "texture", "유저인터페이스", textureType, resourceName ~ ".bmp"),
        buildPath(defaultConfig.resourcepath, "data", "texture", "유저인터페이스", textureType, resourceName ~ ".bmp"),
    ];
    
    foreach (path; possiblePaths)
    {
        if (exists(path))
        {
            return Nullable!string(path);
        }
    }
    
    return Nullable!string.init;
}

/// Serve o ícone de um item por ID
void handleItemIcon(HTTPServerRequest req, HTTPServerResponse res) @trusted
{
    ensureItemInfosLoaded();
    
    // Obtém o ID do item
    string itemIdStr;
    try
    {
        itemIdStr = req.params.get("id", string.init);
        if (itemIdStr.length == 0)
        {
            setErrorResponse(res, HTTPStatus.badRequest, "Item ID is required");
            return;
        }
    }
    catch (Exception err)
    {
        setErrorResponse(res, HTTPStatus.badRequest, "Invalid item ID");
        return;
    }
    
    uint itemId = itemIdStr.to!uint.ifThrown(0);
    if (itemId == 0)
    {
        setErrorResponse(res, HTTPStatus.badRequest, "Invalid item ID");
        return;
    }
    
    // Encontra o item
    auto item = findItemById(cachedItemInfos, itemId);
    if (item.isNull)
    {
        setErrorResponse(res, HTTPStatus.notFound, "Item not found");
        return;
    }
    
    // Tenta encontrar o arquivo de textura
    string resourceName = item.get.identifiedResourceName.length > 0 
        ? item.get.identifiedResourceName 
        : item.get.unidentifiedResourceName;
    
    if (resourceName.length == 0)
    {
        setErrorResponse(res, HTTPStatus.notFound, "Item resource name not found");
        return;
    }
    
    auto texturePath = findItemTexturePath(resourceName, "item");
    if (texturePath.isNull)
    {
        setErrorResponse(res, HTTPStatus.notFound, "Item texture file not found");
        return;
    }
    
    // Carrega e processa a imagem
    try
    {
        RawImage image = loadBmpFile(texturePath.get);
        removeMagentaBackground(image);
        
        // Converte para PNG e serve
        ubyte[] pngData = rawImageToPngBytes(image);
        
        res.contentType("image/png");
        res.writeBody(pngData);
    }
    catch (Exception err)
    {
        logError("Error loading item icon: %s", err.msg);
        setErrorResponse(res, HTTPStatus.internalServerError, "Error loading item icon");
        return;
    }
}

/// Serve uma imagem de coleção por nome
void handleCollectionIcon(HTTPServerRequest req, HTTPServerResponse res) @trusted
{
    // Obtém o nome da coleção
    string collectionName;
    try
    {
        collectionName = req.params.get("name", string.init);
        if (collectionName.length == 0)
        {
            setErrorResponse(res, HTTPStatus.badRequest, "Collection name is required");
            return;
        }
    }
    catch (Exception err)
    {
        setErrorResponse(res, HTTPStatus.badRequest, "Invalid collection name");
        return;
    }
    
    // Encontra o arquivo de textura da coleção
    auto texturePath = findItemTexturePath(collectionName, "collection");
    if (texturePath.isNull)
    {
        setErrorResponse(res, HTTPStatus.notFound, "Collection texture file not found");
        return;
    }
    
    // Carrega e processa a imagem
    try
    {
        RawImage image = loadBmpFile(texturePath.get);
        // Coleções podem não precisar remover fundo magenta, mas vamos fazer mesmo assim
        removeMagentaBackground(image);
        
        // Converte para PNG e serve
        ubyte[] pngData = rawImageToPngBytes(image);
        
        res.contentType("image/png");
        res.writeBody(pngData);
    }
    catch (Exception err)
    {
        logError("Error loading collection icon: %s", err.msg);
        setErrorResponse(res, HTTPStatus.internalServerError, "Error loading collection icon");
        return;
    }
}
