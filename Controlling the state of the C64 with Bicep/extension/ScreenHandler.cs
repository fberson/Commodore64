using Bicep.Local.Extension.Host.Handlers;

namespace C64Extension;

/// <summary>
/// Ensures the desired state of the C64 screen colors via the
/// C64 Ultimate REST API. Idempotent: reads the actual state of
/// $D020/$D021 first and only writes registers that differ.
/// </summary>
public class ScreenHandler : TypedResourceHandler<Screen, ScreenIdentifiers>
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(10) };

    private const int BorderRegister = 0xD020;     // $D020
    private const int BackgroundRegister = 0xD021; // $D021
    private const int ScreenRam = 0x0400;          // $0400 (top-left of screen)
    private const int ColorRam = 0xD800;           // $D800 (per-character color)
    private const int ScreenWidth = 40;
    private const int ScreenSize = 1000;           // 40 x 25 characters

    protected override async Task<ResourceResponse> Preview(ResourceRequest request, CancellationToken cancellationToken)
    {
        // What-if: report the actual state without changing anything.
        var (border, background) = await ReadActualStateAsync(request.Properties.Host, cancellationToken);

        Console.WriteLine($"[preview] actual: border={C64Colors.ToName(border)}, background={C64Colors.ToName(background)} | " +
                          $"desired: border={request.Properties.BorderColor}, background={request.Properties.BackgroundColor}");

        return GetResponse(request);
    }

    protected override async Task<ResourceResponse> CreateOrUpdate(ResourceRequest request, CancellationToken cancellationToken)
    {
        var host = request.Properties.Host;

        // Ensure the screen content first, then the colors.
        // An empty/omitted text means: leave the screen contents alone.
        if (request.Properties.Text is { Length: > 0 } text)
        {
            await EnsureTextAsync(host, text, cancellationToken);
        }

        var (actualBorder, actualBackground) = await ReadActualStateAsync(host, cancellationToken);

        if (request.Properties.BorderColor is { } borderName)
        {
            var desired = C64Colors.ToValue(borderName);
            if ((actualBorder & 0x0F) != desired)
            {
                Console.WriteLine($"[drift] border: {C64Colors.ToName(actualBorder)} -> {borderName}. Writing ${BorderRegister:X4}={desired:X2}");
                await WriteMemoryAsync(host, BorderRegister, desired, cancellationToken);
            }
            else
            {
                Console.WriteLine($"[ok] border already {borderName}, no write needed.");
            }
        }

        if (request.Properties.BackgroundColor is { } backgroundName)
        {
            var desired = C64Colors.ToValue(backgroundName);
            if ((actualBackground & 0x0F) != desired)
            {
                Console.WriteLine($"[drift] background: {C64Colors.ToName(actualBackground)} -> {backgroundName}. Writing ${BackgroundRegister:X4}={desired:X2}");
                await WriteMemoryAsync(host, BackgroundRegister, desired, cancellationToken);
            }
            else
            {
                Console.WriteLine($"[ok] background already {backgroundName}, no write needed.");
            }
        }

        // Reflect the (new) actual state back into the resource body.
        var (border, background) = await ReadActualStateAsync(host, cancellationToken);
        request.Properties.BorderColor = C64Colors.ToName(border);
        request.Properties.BackgroundColor = C64Colors.ToName(background);

        if (request.Properties.Text is { Length: > 0 })
        {
            request.Properties.Text = await ReadTextAsync(host, cancellationToken);
        }

        return GetResponse(request);
    }

    /// <summary>
    /// Ensures the screen shows a mimicked C64 boot screen with the desired
    /// text shown as the output of a typed PRINT"<text>" command.
    /// No reset is performed: the full screen RAM is written directly.
    /// Idempotent: compares the complete desired screen with the actual one.
    /// </summary>
    private static async Task EnsureTextAsync(string host, string text, CancellationToken cancellationToken)
    {
        if (text.Length > ScreenWidth)
        {
            text = text[..ScreenWidth];
        }

        var desired = BuildBootScreen(text);
        var actual = await ReadMemoryAsync(host, ScreenRam, ScreenSize, cancellationToken);

        // Compare ignoring bit 7: the blinking cursor inverts the character
        // underneath it in screen RAM.
        var matches = true;
        for (var i = 0; i < ScreenSize; i++)
        {
            if ((desired[i] & 0x7F) != (actual[i] & 0x7F))
            {
                matches = false;
                break;
            }
        }

        if (matches)
        {
            Console.WriteLine("[ok] screen already matches, no write needed.");
            return;
        }

        Console.WriteLine($"[drift] rewriting the boot screen with text: {text}");
        await WriteMemoryAsync(host, ScreenRam, desired, cancellationToken);

        // Color RAM: light blue (0E), the authentic C64 text color.
        var colors = new byte[ScreenSize];
        Array.Fill(colors, (byte)0x0E);
        await WriteMemoryAsync(host, ColorRam, colors, cancellationToken);

        // Move the real cursor to row 9 (just below the final READY.):
        // inject HOME ($13) + 9x cursor-down ($11) into the keyboard buffer.
        await MoveCursorAsync(host, row: 9, cancellationToken);
    }

    /// <summary>
    /// Moves the hardware cursor to the given row (column 0) by injecting
    /// HOME + cursor-down keys into the KERNAL keyboard buffer
    /// ($0277, count at $00C6, max 10 keys per batch).
    /// </summary>
    private static async Task MoveCursorAsync(string host, int row, CancellationToken cancellationToken)
    {
        const int keyboardBuffer = 0x0277;
        const int bufferCount = 0x00C6;
        const int maxKeys = 10;

        var keys = new List<byte> { 0x13 }; // HOME
        keys.AddRange(Enumerable.Repeat((byte)0x11, row)); // cursor down

        foreach (var chunk in keys.Chunk(maxKeys))
        {
            await WriteMemoryAsync(host, keyboardBuffer, chunk, cancellationToken);
            await WriteMemoryAsync(host, bufferCount, (byte)chunk.Length, cancellationToken);

            // Wait until the KERNAL has consumed the keystrokes.
            for (var i = 0; i < 20; i++)
            {
                var count = await ReadMemoryAsync(host, bufferCount, 1, cancellationToken);
                if (count[0] == 0)
                {
                    break;
                }

                await Task.Delay(50, cancellationToken);
            }
        }
    }

    /// <summary>
    /// Builds the full 40x25 screen RAM content mimicking the C64 boot
    /// screen, followed by the typed PRINT command and its output.
    /// </summary>
    private static byte[] BuildBootScreen(string text)
    {
        var screen = new byte[ScreenSize];
        Array.Fill(screen, (byte)32); // spaces

        void WriteRow(int row, string content)
        {
            for (var i = 0; i < content.Length && i < ScreenWidth; i++)
            {
                screen[row * ScreenWidth + i] = ScreenCodes.ToScreenCode(content[i]);
            }
        }

        WriteRow(1, "    **** COMMODORE 64 BASIC V2 ****");
        WriteRow(3, " 64K RAM SYSTEM  38911 BASIC BYTES FREE");
        WriteRow(5, "READY.");
        WriteRow(6, text);
        WriteRow(8, "READY.");

        return screen;
    }

    /// <summary>Reads back the text as shown on the screen (row 6).</summary>
    private static async Task<string> ReadTextAsync(string host, CancellationToken cancellationToken)
    {
        var bytes = await ReadMemoryAsync(host, ScreenRam + 6 * ScreenWidth, ScreenWidth, cancellationToken);
        return new string(bytes.Select(ScreenCodes.ToChar).ToArray()).TrimEnd();
    }

    protected override ScreenIdentifiers GetIdentifiers(Screen properties) => new()
    {
        Host = properties.Host,
    };

    /// <summary>Reads $D020 and $D021 in one call (2 raw bytes).</summary>
    private static async Task<(byte Border, byte Background)> ReadActualStateAsync(string host, CancellationToken cancellationToken)
    {
        var uri = $"http://{host}/v1/machine:readmem?address={BorderRegister:X4}&length=2";
        var bytes = await Http.GetByteArrayAsync(uri, cancellationToken);

        if (bytes.Length < 2)
        {
            throw new InvalidOperationException($"Expected 2 bytes from {uri}, got {bytes.Length}.");
        }

        return (bytes[0], bytes[1]);
    }

    private static async Task<byte[]> ReadMemoryAsync(string host, int address, int length, CancellationToken cancellationToken)
    {
        var uri = $"http://{host}/v1/machine:readmem?address={address:X4}&length={length}";
        var bytes = await Http.GetByteArrayAsync(uri, cancellationToken);

        if (bytes.Length < length)
        {
            throw new InvalidOperationException($"Expected {length} bytes from {uri}, got {bytes.Length}.");
        }

        return bytes;
    }

    private static Task WriteMemoryAsync(string host, int address, byte value, CancellationToken cancellationToken)
        => WriteMemoryAsync(host, address, [value], cancellationToken);

    private static async Task WriteMemoryAsync(string host, int address, byte[] data, CancellationToken cancellationToken)
    {
        // Chunk writes to keep the URL length within safe limits.
        const int chunkSize = 128;
        for (var offset = 0; offset < data.Length; offset += chunkSize)
        {
            var chunk = data[offset..Math.Min(offset + chunkSize, data.Length)];
            var hex = Convert.ToHexString(chunk);
            var uri = $"http://{host}/v1/machine:writemem?address={address + offset:X4}&data={hex}";
            using var response = await Http.PutAsync(uri, content: null, cancellationToken);
            response.EnsureSuccessStatusCode();
        }
    }
}
