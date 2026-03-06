module zrenderer.server.routes.render;

import config;
import std.datetime : seconds;
import std.typecons : Nullable;
import std.zip : ArchiveMember, ZipArchive;
import validation : isJobArgValid, isCanvasArgValid;
import vibe.core.concurrency : send, receiveTimeout, OwnerTerminated;
import vibe.core.core : runWorkerTaskH;
import vibe.core.log : logInfo, logError;
import vibe.core.task : Task;
import vibe.data.json;
import vibe.data.serialization;
import vibe.http.common : HTTPStatusException;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.http.status;
import zrenderer.server.auth : AccessToken, checkAuth;
import zrenderer.server.dto : RenderRequestData, RenderResponseData, toString;
import zrenderer.server.globals : defaultConfig, accessTokens;
import zrenderer.server.routes : setErrorResponse, mergeStruct, unauthorized, logCustomRequest;
import zrenderer.server.worker : renderWorker;
import zrenderer.server.downloads : downloadManager;

void handleRenderRequest(HTTPServerRequest req, HTTPServerResponse res) @trusted
{
    immutable accessToken = checkAuth(req, accessTokens);

    if (accessToken.isNull() || !accessToken.get.isValid)
    {
        unauthorized(res);
        return;
    }

    if (req.json == Json.undefined)
    {
        setErrorResponse(res, HTTPStatus.badRequest, "Expected json input");
        return;
    }

    RenderRequestData requestData;

    try
    {
        requestData = deserializeJson!RenderRequestData(req.json);
    }
    catch (Exception err)
    {
        setErrorResponse(res, HTTPStatus.badRequest, err.msg);
        return;
    }

    logCustomRequest(req, requestData.toString, accessToken);

    const(Config) mergedConfig = mergeStruct(defaultConfig, requestData);

    if (!isJobArgValid(mergedConfig.job, accessToken.get.properties.maxJobIdsPerRequest))
    {
        setErrorResponse(res, HTTPStatus.badRequest, "Invalid job element");
        return;
    }

    if (!isCanvasArgValid(mergedConfig.canvas))
    {
        setErrorResponse(res, HTTPStatus.badRequest, "Invalid canvas element");
        return;
    }

    auto worker = runWorkerTaskH(&renderWorker, Task.getThis);
    send(worker, cast(immutable Config) mergedConfig);

    RenderResponseData response;
    bool renderingSucceeded = false;

    try
    {
        receiveTimeout(5.seconds,
                (immutable(string)[] filenames) {
                    response.output = filenames;
                    renderingSucceeded = true;
                },
                (bool failed) {
                    renderingSucceeded = !failed;
                }
        );
    }
    catch (OwnerTerminated e)
    {
        setErrorResponse(res, HTTPStatus.internalServerError, "Rendering timed out / was aborted");
        return;
    }

    if (!renderingSucceeded)
    {
        setErrorResponse(res, HTTPStatus.internalServerError, "Error during rendering process");
        return;
    }

    import std.file : read, FileException, write, exists;
    import std.path : buildPath, baseName;
    import std.exception : ifThrown;
    import std.format : format;
    import std.datetime.systime : Clock;
    import std.conv : to;

    // Verifica se foi solicitado download (zip dos arquivos)
    bool downloadRequested = false;
    try
    {
        downloadRequested = req.query.get("download", string.init).length > 0;
    }
    catch (Exception) {}

    if (mergedConfig.outputFormat == OutputFormat.zip)
    {
        if (response.output.length == 0)
        {
            setErrorResponse(res, HTTPStatus.noContent, "Nothing rendered");
            return;
        }

        // Se download foi solicitado, cria link temporário
        if (downloadRequested)
        {
            string zipFilepath = response.output[$-1];
            
            // Registra o arquivo zip no gerenciador de downloads
            string downloadId = downloadManager.addDownload(zipFilepath);
            
            // Constrói o link de download
            string host = req.headers.get("Host", "localhost");
            string protocol = defaultConfig.enableSSL ? "https" : "http";
            string downloadLink = format("%s://%s/download/%s", protocol, host, downloadId);
            
            response.downloadLink = downloadLink;
            res.writeJsonBody(serializeToJson(response));
        }
        else
        {
            // Comportamento original: retorna o zip diretamente
            res.contentType("application/zip");
            try
            {
                res.writeBody(cast(ubyte[]) read(response.output[$-1]));
            }
            catch (FileException err)
            {
                logError(err.message);
                setErrorResponse(res, HTTPStatus.internalServerError, "Error when writing response");
                return;
            }
        }
    }
    else
    {
        // Para formato PNG, verifica se foi solicitado download (zip dos arquivos PNG)
        if (downloadRequested)
        {
            if (response.output.length == 0)
            {
                setErrorResponse(res, HTTPStatus.noContent, "Nothing rendered");
                return;
            }

            // Cria um zip com todos os arquivos PNG gerados
            try
            {
                import std.zip : ArchiveMember, CompressionMethod;
                
                auto archive = new ZipArchive();
                
                foreach (filename; response.output)
                {
                    if (exists(filename))
                    {
                        auto member = new ArchiveMember();
                        member.compressionMethod = CompressionMethod.none;
                        member.name = baseName(filename);
                        member.expandedData(cast(ubyte[]) read(filename));
                        archive.addMember(member);
                    }
                }
                
                // Salva o zip temporário
                import std.file : mkdirRecurse;
                mkdirRecurse(mergedConfig.outdir);
                
                auto now = Clock.currTime();
                string zipFilename = format("%s/download_%s.zip", 
                    mergedConfig.outdir, 
                    now.toUnixTime.to!string);
                
                write(zipFilename, archive.build());
                
                // Registra no gerenciador de downloads
                string downloadId = downloadManager.addDownload(zipFilename);
                
                // Constrói o link de download
                string host = req.headers.get("Host", "localhost");
                string protocol = defaultConfig.enableSSL ? "https" : "http";
                string downloadLink = format("%s://%s/download/%s", protocol, host, downloadId);
                
                response.downloadLink = downloadLink;
                res.writeJsonBody(serializeToJson(response));
            }
            catch (Exception err)
            {
                logError("Error creating zip for download: %s", err.msg);
                setErrorResponse(res, HTTPStatus.internalServerError, "Error creating download zip");
                return;
            }
        }
        else
        {
            // Comportamento original
            bool downloadImage = (req.query["downloadimage"].length >= 0).ifThrown(false);

            if (downloadImage)
            {
                if (response.output.length == 0)
                {
                    setErrorResponse(res, HTTPStatus.noContent, "Nothing rendered");
                    return;
                }

                res.contentType("image/png");
                try
                {
                    res.writeBody(cast(ubyte[]) read(response.output[0]));
                }
                catch (FileException err)
                {
                    logError(err.message);
                    setErrorResponse(res, HTTPStatus.internalServerError, "Error when writing response");
                    return;
                }
            }
            else
            {
                res.writeJsonBody(serializeToJson(response));
            }
        }
    }
}

