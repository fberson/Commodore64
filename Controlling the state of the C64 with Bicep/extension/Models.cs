using Azure.Bicep.Types.Concrete;
using Bicep.Local.Extension.Types.Attributes;

namespace C64Extension;

/// <summary>
/// Identifiers uniquely locate the resource instance (the C64 on the network).
/// </summary>
public class ScreenIdentifiers
{
    [TypeProperty("IP address or hostname of the C64 Ultimate.", ObjectTypePropertyFlags.Required | ObjectTypePropertyFlags.Identifier)]
    public required string Host { get; set; }
}

/// <summary>
/// Desired state of the C64 screen (VIC-II color registers $D020 / $D021).
/// </summary>
[ResourceType("Screen")]
public class Screen : ScreenIdentifiers
{
    [TypeProperty("Border color name, e.g. 'red', 'blue', 'lightGreen'.")]
    public string? BorderColor { get; set; }

    [TypeProperty("Background color name, e.g. 'black', 'blue'.")]
    public string? BackgroundColor { get; set; }

    [TypeProperty("Text to display on the top row of the screen (max 40 characters).")]
    public string? Text { get; set; }
}

/// <summary>
/// Identifiers for the Music resource (the C64 on the network).
/// </summary>
public class MusicIdentifiers
{
    [TypeProperty("IP address or hostname of the C64 Ultimate.", ObjectTypePropertyFlags.Required | ObjectTypePropertyFlags.Identifier)]
    public required string Host { get; set; }
}

/// <summary>
/// Desired state of the SID music player.
/// </summary>
[ResourceType("Music")]
public class Music : MusicIdentifiers
{
    [TypeProperty("Path to a .sid music file (relative to the deployment working directory) to play on the real SID chip.", ObjectTypePropertyFlags.Required)]
    public required string SidFile { get; set; }

    [TypeProperty("Subtune number to play (1-based). Defaults to the SID file's default song.")]
    public int? Song { get; set; }
}

/// <summary>
/// Identifiers for the Program resource (the C64 on the network).
/// </summary>
public class Program64Identifiers
{
    [TypeProperty("IP address or hostname of the C64 Ultimate.", ObjectTypePropertyFlags.Required | ObjectTypePropertyFlags.Identifier)]
    public required string Host { get; set; }
}

/// <summary>
/// Runs a local .prg program on the C64.
/// </summary>
[ResourceType("Program")]
public class Program64 : Program64Identifiers
{
    [TypeProperty("Path to a .prg file (relative to the deployment working directory) to upload and run.", ObjectTypePropertyFlags.Required)]
    public required string PrgFile { get; set; }
}

/// <summary>
/// The 16 VIC-II colors. Index == register value.
/// </summary>
public static class C64Colors
{
    private static readonly string[] Names =
    [
        "black", "white", "red", "cyan",
        "purple", "green", "blue", "yellow",
        "orange", "brown", "lightRed", "darkGray",
        "gray", "lightGreen", "lightBlue", "lightGray",
    ];

    public static byte ToValue(string name)
    {
        var index = Array.FindIndex(Names, n => string.Equals(n, name, StringComparison.OrdinalIgnoreCase));
        return index >= 0
            ? (byte)index
            : throw new ArgumentException($"Unknown C64 color '{name}'. Valid colors: {string.Join(", ", Names)}");
    }

    public static string ToName(byte value) => Names[value & 0x0F];
}

/// <summary>
/// Converts text to/from C64 screen codes (as stored in screen RAM at $0400).
/// </summary>
public static class ScreenCodes
{
    public static byte ToScreenCode(char c)
    {
        // PETSCII block graphics for ASCII-art use.
        switch (c)
        {
            case '█': return 160; // solid block (reverse space)
            case '▌': return 97;  // left half block
            case '▐': return 225; // right half block (reverse of left half)
            case '▄': return 98;  // lower half block
            case '▀': return 226; // upper half block (reverse of lower half)
            case '▒': return 102; // medium shade (checkerboard)
        }

        c = char.ToUpperInvariant(c);
        return c switch
        {
            '@' => 0,
            >= 'A' and <= 'Z' => (byte)(c - 'A' + 1),
            >= ' ' and <= '?' => (byte)c, // space, punctuation, digits: screen code == ASCII
            _ => 32, // unsupported characters become spaces
        };
    }

    public static char ToChar(byte code) => (code & 0x7F) switch
    {
        0 => '@',
        >= 1 and <= 26 => (char)('A' + code - 1),
        >= 32 and <= 63 => (char)code,
        _ => ' ',
    };
}
