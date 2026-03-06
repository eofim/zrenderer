module zrenderer.server.downloads;

import std.conv : to;
import std.file : read, remove, FileException;
import std.path : buildPath;
import std.string : format;
import std.datetime.systime : Clock, SysTime;
import std.typecons : Nullable;
import core.sync.mutex : Mutex;
import vibe.core.log : logInfo, logWarn;
import vibe.core.core : runTask;

/// Estrutura para armazenar informações de download temporário
struct DownloadInfo
{
    string filepath;      // Caminho do arquivo zip
    SysTime createdAt;    // Quando foi criado
    uint accessCount;     // Quantas vezes foi acessado
}

/// Gerenciador de downloads temporários
class DownloadManager
{
private:
    string[string] downloads;  // ID -> filepath
    SysTime[string] createdTimes;  // ID -> quando foi criado
    uint[string] accessCounts;  // ID -> contador de acessos
    shared bool _running = false;
    Mutex _mutex;
    
    /// Tempo de expiração em horas (padrão: 24 horas)
    const int expirationHours = 24;
    
    /// Limpa downloads expirados periodicamente
    void cleanupExpired()
    {
        import vibe.core.task : sleep;
        import std.datetime : hours;
        
        while (_running)
        {
            sleep(1.hours);
            
            auto now = Clock.currTime();
            string[] toRemove;
            
            synchronized (_mutex)
            {
                foreach (id, createdAt; createdTimes)
                {
                    auto age = now - createdAt;
                    if (age.total!"hours" > expirationHours)
                    {
                        toRemove ~= id;
                    }
                }
            }
            
            foreach (id; toRemove)
            {
                removeDownload(id);
            }
            
            if (toRemove.length > 0)
            {
                logInfo("Removed %d expired downloads", toRemove.length);
            }
        }
    }
    
public:
    this()
    {
        _mutex = new Mutex();
        _running = true;
        runTask(&cleanupExpired);
    }
    
    /// Adiciona um arquivo para download temporário e retorna um ID único
    string addDownload(string filepath)
    {
        import std.random : uniform;
        import std.digest.md : MD5;
        import std.digest : toHexString;
        
        // Gera um ID único baseado em timestamp + random
        auto now = Clock.currTime();
        auto timestamp = now.toUnixTime.to!string;
        auto random = uniform(0, 1000000).to!string;
        auto input = timestamp ~ random ~ filepath;
        
        MD5 hash;
        hash.put(input);
        string id = hash.finish().toHexString();
        
        synchronized (_mutex)
        {
            downloads[id] = filepath;
            createdTimes[id] = now;
            accessCounts[id] = 0;
        }
        
        logInfo("Created temporary download: %s -> %s", id, filepath);
        return id;
    }
    
    /// Obtém o caminho do arquivo para um ID de download
    Nullable!string getDownload(string id)
    {
        synchronized (_mutex)
        {
            if (id in downloads)
            {
                accessCounts[id]++;
                return Nullable!string(downloads[id]);
            }
        }
        return Nullable!string.init;
    }
    
    /// Remove um download
    void removeDownload(string id)
    {
        string filepath;
        
        synchronized (_mutex)
        {
            if (id in downloads)
            {
                filepath = downloads[id];
                downloads.remove(id);
                createdTimes.remove(id);
                accessCounts.remove(id);
            }
            else
            {
                return;
            }
        }
        
        // Tenta remover o arquivo físico
        try
        {
            remove(filepath);
            logInfo("Removed download file: %s", filepath);
        }
        catch (FileException err)
        {
            logWarn("Could not remove download file %s: %s", filepath, err.msg);
        }
    }
    
    /// Limpa todos os downloads (útil para shutdown)
    void cleanup()
    {
        _running = false;
        string[] ids;
        
        synchronized (_mutex)
        {
            ids = downloads.keys.array;
        }
        
        foreach (id; ids)
        {
            removeDownload(id);
        }
    }
}

/// Instância global do gerenciador de downloads
__gshared DownloadManager downloadManager = new DownloadManager();
