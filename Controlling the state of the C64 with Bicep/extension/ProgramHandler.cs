using Bicep.Local.Extension.Host.Handlers;

namespace C64Extension;

/// <summary>
/// Uploads and runs a local .prg program on the C64 via the C64 Ultimate's
/// run_prg runner (POST /v1/runners:run_prg).
/// Note: like Music, run state cannot be read back, so each deployment
/// (re)starts the declared program.
/// </summary>
public class ProgramHandler : TypedResourceHandler<Program64, Program64Identifiers>
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(30) };

    protected override Task<ResourceResponse> Preview(ResourceRequest request, CancellationToken cancellationToken)
    {
        Console.WriteLine($"[preview] program: would run {request.Properties.PrgFile}");
        return Task.FromResult(GetResponse(request));
    }

    protected override async Task<ResourceResponse> CreateOrUpdate(ResourceRequest request, CancellationToken cancellationToken)
    {
        var path = Path.GetFullPath(request.Properties.PrgFile);
        if (!File.Exists(path))
        {
            throw new FileNotFoundException($"PRG file not found: {path}", path);
        }

        var uri = $"http://{request.Properties.Host}/v1/runners:run_prg";

        Console.WriteLine($"[program] running {Path.GetFileName(path)}");

        // The API expects the raw .prg bytes as the request body.
        using var content = new ByteArrayContent(await File.ReadAllBytesAsync(path, cancellationToken));
        content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/octet-stream");

        using var response = await Http.PostAsync(uri, content, cancellationToken);
        response.EnsureSuccessStatusCode();

        return GetResponse(request);
    }

    protected override Program64Identifiers GetIdentifiers(Program64 properties) => new()
    {
        Host = properties.Host,
    };
}
