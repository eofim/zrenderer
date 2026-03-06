module zrenderer.server.routes.download;

import std.file : read, FileException;
import std.typecons : Nullable;
import vibe.core.log : logError, logWarn;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.http.status;
import zrenderer.server.downloads : downloadManager;
import zrenderer.server.routes : setErrorResponse;

void handleDownloadRequest(HTTPServerRequest req, HTTPServerResponse res) @trusted
{
    import std.exception : ifThrown;
    import std.conv : to;
    
    // Obtém o ID do download dos parâmetros da rota
    string downloadId;
    try
    {
        downloadId = req.params.get("id", string.init);
        if (downloadId.length == 0)
        {
            setErrorResponse(res, HTTPStatus.badRequest, "Download ID is required");
            return;
        }
    }
    catch (Exception err)
    {
        setErrorResponse(res, HTTPStatus.badRequest, "Invalid download ID");
        return;
    }
    
    // Obtém o caminho do arquivo
    auto filepath = downloadManager.getDownload(downloadId);
    
    if (filepath.isNull)
    {
        setErrorResponse(res, HTTPStatus.notFound, "Download not found or expired");
        return;
    }
    
    // Serve o arquivo
    res.contentType("application/zip");
    res.headers["Content-Disposition"] = "attachment; filename=\"sprites.zip\"";
    
    try
    {
        res.writeBody(cast(ubyte[]) read(filepath.get));
    }
    catch (FileException err)
    {
        logError("Error reading download file %s: %s", filepath.get, err.msg);
        setErrorResponse(res, HTTPStatus.internalServerError, "Error reading download file");
        return;
    }
}
