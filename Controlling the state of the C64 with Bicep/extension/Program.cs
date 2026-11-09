using Bicep.Local.Extension.Host.Extensions;
using C64Extension;

var builder = WebApplication.CreateBuilder();

builder.AddBicepExtensionHost(args);
builder.Services
    .AddBicepExtension(
        name: "C64",
        version: "0.1.0",
        isSingleton: true,
        typeAssembly: typeof(Program).Assembly)
    .WithResourceHandler<ScreenHandler>()
    .WithResourceHandler<MusicHandler>()
    .WithResourceHandler<ProgramHandler>();

var app = builder.Build();

app.MapBicepExtension();

await app.RunAsync();
