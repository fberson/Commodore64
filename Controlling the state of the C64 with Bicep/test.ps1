$C64 = "192.168.68.73"

Invoke-RestMethod -Uri "http://$C64/v1/info"

# Change the border to red
Invoke-RestMethod `
    -Method Put `
    -Uri "http://$C64/v1/machine:writemem?address=D020&data=02"

# Change the background to black
Invoke-RestMethod `
    -Method Put `
    -Uri "http://$C64/v1/machine:writemem?address=D021&data=00"

$uri = "http://$C64/v1/machine:readmem?address=D020&length=2"

$response = Invoke-WebRequest -Uri $uri

# Display response metadata
$response.Headers

# Display raw bytes as hexadecimal
[Convert]::ToHexString($response.RawContentStream.ToArray())


##

$colors = @(
    "Black", "White", "Red", "Cyan",
    "Purple", "Green", "Blue", "Yellow",
    "Orange", "Brown", "Light Red", "Dark Gray",
    "Gray", "Light Green", "Light Blue", "Light Gray"
)

$uri = "http://$C64/v1/machine:readmem?address=D020&length=2"
$response = Invoke-WebRequest -Uri $uri

$bytes = $response.RawContentStream.ToArray()

$border = $bytes[0] -band 0x0F
$background = $bytes[1] -band 0x0F

[PSCustomObject]@{
    BorderColor     = $colors[$border]
    BackgroundColor = $colors[$background]
}