targetScope = 'local'

extension c64

@description('IP address or hostname of the C64 Ultimate.')
param host string

@description('Desired border color ($D020).')
@allowed([
  'black', 'white', 'red', 'cyan'
  'purple', 'green', 'blue', 'yellow'
  'orange', 'brown', 'lightRed', 'darkGray'
  'gray', 'lightGreen', 'lightBlue', 'lightGray'
])
param borderColor string

@description('Desired background color ($D021).')
@allowed([
  'black', 'white', 'red', 'cyan'
  'purple', 'green', 'blue', 'yellow'
  'orange', 'brown', 'lightRed', 'darkGray'
  'gray', 'lightGreen', 'lightBlue', 'lightGray'
])
param backgroundColor string

@description('Text to display on the top row of the screen (max 40 characters).')
@maxLength(40)
param text string = ''

@description('Path to a .sid music file to play on the real SID chip. Empty = no music.')
param sidFile string = ''

@description('Subtune number to play (1-based).')
param sidSong int = 1

@description('Path to a .prg program to upload and run. Empty = no program.')
param prgFile string = ''

resource screen 'Screen' = {
  host: host
  borderColor: borderColor
  backgroundColor: backgroundColor
  text: text
}

resource music 'Music' = if (sidFile != '') {
  host: host
  sidFile: sidFile
  song: sidSong
  dependsOn: [screen]
}

resource program 'Program' = if (prgFile != '') {
  host: host
  prgFile: prgFile
}

output actualBorderColor string = screen.borderColor
output actualBackgroundColor string = screen.backgroundColor
output actualText string = screen.text
