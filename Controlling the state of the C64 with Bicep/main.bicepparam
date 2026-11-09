using 'main.bicep'

// Same C64 as used in test.ps1
param host = '192.168.68.61'

// Desired state of the physical C64 screen
param borderColor = 'red'
param backgroundColor = 'green'
// Note: text and the ascii art both manage the screen; use one at a time.
param text = 'Welcome to the C64 world!'

// Music: Lazy Jones (David Whittaker, 1984).
//param sidFile = 'music/Lazy_Jones.sid'
//param sidSong = 21

// 80's intro with animation and sound (built by build-intro.ps1)
//param prgFile = 'prg/intro.prg'
