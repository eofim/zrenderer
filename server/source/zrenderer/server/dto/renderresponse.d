module zrenderer.server.dto.renderresponse;

import vibe.data.serialization : optional;
import std.typecons : Nullable;

struct RenderResponseData
{
    /// Contains one or more paths to the rendered sprites.
    immutable(string)[] output;
    
    /// Temporary download link for zip file (if download was requested)
    @optional Nullable!string downloadLink;
}
