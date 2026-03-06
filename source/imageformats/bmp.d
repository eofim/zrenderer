module imageformats.bmp;

import std.stdio : File;
import std.exception : enforce, ErrnoException;
import draw : RawImage, Color;

/// Carrega um arquivo BMP e retorna uma RawImage
RawImage loadBmpFile(string filename)
{
    auto file = File(filename, "rb");
    scope (exit) file.close();
    
    // Lê o cabeçalho do BMP
    ubyte[14] fileHeader;
    file.rawRead(fileHeader);
    
    // Verifica assinatura BMP (BM)
    enforce(fileHeader[0] == 'B' && fileHeader[1] == 'M', "Invalid BMP file signature");
    
    // Lê o cabeçalho de informações
    ubyte[40] infoHeader;
    file.rawRead(infoHeader);
    
    // Extrai largura e altura (little-endian)
    int width = cast(int)(infoHeader[4] | (infoHeader[5] << 8) | (infoHeader[6] << 16) | (infoHeader[7] << 24));
    int height = cast(int)(infoHeader[8] | (infoHeader[9] << 8) | (infoHeader[10] << 16) | (infoHeader[11] << 24));
    
    // Bits por pixel
    ushort bitsPerPixel = cast(ushort)(infoHeader[14] | (infoHeader[15] << 8));
    
    enforce(bitsPerPixel == 24 || bitsPerPixel == 32, "Unsupported BMP format: only 24-bit and 32-bit BMPs are supported");
    
    // Offset dos dados de pixel
    uint dataOffset = cast(uint)(fileHeader[10] | (fileHeader[11] << 8) | (fileHeader[12] << 16) | (fileHeader[13] << 24));
    
    // Move para o início dos dados de pixel
    file.seek(dataOffset);
    
    RawImage image;
    image.width = cast(uint)width;
    image.height = cast(uint)height.abs; // altura pode ser negativa (top-down)
    bool topDown = height < 0;
    image.pixels = new Color[image.width * image.height];
    
    // Calcula o tamanho da linha (alinhado para múltiplo de 4 bytes)
    uint rowSize = ((image.width * bitsPerPixel + 31) / 32) * 4;
    uint pixelDataSize = rowSize * image.height;
    
    ubyte[] pixelData = new ubyte[pixelDataSize];
    file.rawRead(pixelData);
    
    // Converte os dados do BMP para RawImage
    for (uint y = 0; y < image.height; ++y)
    {
        uint srcY = topDown ? y : (image.height - 1 - y);
        uint rowOffset = srcY * rowSize;
        
        for (uint x = 0; x < image.width; ++x)
        {
            uint pixelOffset = rowOffset + x * (bitsPerPixel / 8);
            
            Color pixel;
            if (bitsPerPixel == 24)
            {
                // BMP 24-bit: BGR (sem alpha)
                pixel.b() = pixelData[pixelOffset];
                pixel.g() = pixelData[pixelOffset + 1];
                pixel.r() = pixelData[pixelOffset + 2];
                pixel.a() = 255;
            }
            else // 32-bit
            {
                // BMP 32-bit: BGRA
                pixel.b() = pixelData[pixelOffset];
                pixel.g() = pixelData[pixelOffset + 1];
                pixel.r() = pixelData[pixelOffset + 2];
                pixel.a() = pixelData[pixelOffset + 3];
            }
            
            image.pixels[y * image.width + x] = pixel;
        }
    }
    
    return image;
}

/// Remove o fundo magenta (transparência) de uma imagem
/// O fundo magenta é definido como RGB(255, 0, 255) ou próximo disso
void removeMagentaBackground(ref RawImage image, uint threshold = 10)
{
    foreach (ref pixel; image.pixels)
    {
        // Verifica se o pixel é magenta ou próximo de magenta
        // Magenta é RGB(255, 0, 255) ou RGB(255, 0, 255) com variação
        ubyte r = pixel.r();
        ubyte g = pixel.g();
        ubyte b = pixel.b();
        
        // Verifica se é magenta (R alto, G baixo, B alto)
        if (r > (255 - threshold) && g < threshold && b > (255 - threshold))
        {
            // Torna transparente
            pixel.a() = 0;
        }
    }
}

/// Converte RawImage para PNG em memória (retorna bytes)
ubyte[] rawImageToPngBytes(const scope RawImage image)
{
    import imageformats.png : saveToPngFile;
    import std.file : write, remove, FileException, mkdirRecurse;
    import std.path : buildPath, tempDir;
    import std.datetime.systime : Clock;
    import std.format : format;
    import std.conv : to;
    
    // Cria um arquivo temporário
    string tempDirPath = tempDir();
    mkdirRecurse(tempDirPath);
    auto now = Clock.currTime();
    string tempFile = buildPath(tempDirPath, format("zrenderer_%s_%d.png", 
        now.toUnixTime.to!string, 
        cast(int)(now.usecs % 1000000)));
    
    try
    {
        saveToPngFile(image, tempFile);
        import std.file : read;
        auto data = cast(ubyte[]) read(tempFile);
        remove(tempFile);
        return data;
    }
    catch (Exception err)
    {
        // Tenta limpar o arquivo temporário mesmo em caso de erro
        try { remove(tempFile); } catch {}
        throw err;
    }
}
