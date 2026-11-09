using Bicep.Local.Extension.Host.Handlers;

namespace C64Extension;

/// <summary>
/// Plays SID music on the C64 Ultimate's real SID chip via the built-in
/// SID player runner (POST /v1/runners:sidplay).
/// Note: playback state cannot be read back from the device, so each
/// deployment (re)starts the declared tune.
/// </summary>
public class MusicHandler : TypedResourceHandler<Music, MusicIdentifiers>
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(30) };

    protected override Task<ResourceResponse> Preview(ResourceRequest request, CancellationToken cancellationToken)
    {
        Console.WriteLine($"[preview] music: would play {request.Properties.SidFile}" +
                          (request.Properties.Song is null ? "" : $" (song {request.Properties.Song})"));
        return Task.FromResult(GetResponse(request));
    }

    protected override async Task<ResourceResponse> CreateOrUpdate(ResourceRequest request, CancellationToken cancellationToken)
    {
        var path = Path.GetFullPath(request.Properties.SidFile);
        if (!File.Exists(path))
        {
            throw new FileNotFoundException($"SID file not found: {path}", path);
        }

        var uri = $"http://{request.Properties.Host}/v1/runners:sidplay";
        if (request.Properties.Song is { } songNumber)
        {
            uri += $"?songnr={songNumber}";
        }

        Console.WriteLine($"[music] playing {Path.GetFileName(path)}" +
                          (request.Properties.Song is null ? "" : $" (song {request.Properties.Song})"));

        // The API expects the raw .sid bytes as the request body.
        using var content = new ByteArrayContent(await File.ReadAllBytesAsync(path, cancellationToken));
        content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/octet-stream");

        using var response = await Http.PostAsync(uri, content, cancellationToken);
        response.EnsureSuccessStatusCode();

        return GetResponse(request);
    }

    protected override MusicIdentifiers GetIdentifiers(Music properties) => new()
    {
        Host = properties.Host,
    };
}
