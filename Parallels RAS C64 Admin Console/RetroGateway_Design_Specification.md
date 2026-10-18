# Retro Gateway (RGP) Design Specification

**Project:** Parallels RAS C64 Console\
**Protocol:** Retro Gateway Protocol (RGP)\
**Status:** Living Design Document

------------------------------------------------------------------------

# 1. Purpose

Retro Gateway demonstrates that a modern Parallels RAS environment can
be monitored and (eventually) administered from a Commodore 64 over
TCP/IP.

The project intentionally separates presentation, protocol and business
logic.

    Commodore 64
         │
         │  RGP (TCP)
         ▼
    Retro Gateway (PowerShell)
         │
         │  RAS PowerShell Cmdlets
         ▼
    Parallels RAS

------------------------------------------------------------------------

# 2. Goals

## Goals

-   Native C64 experience
-   Live Parallels RAS data
-   Simple protocol
-   No third-party database
-   Stateless server
-   One request = one rendered screen

## Non-goals

-   Replace the RAS Console
-   Remote desktop over RGP
-   High-performance graphics
-   General-purpose terminal

------------------------------------------------------------------------

# 3. High-Level Architecture

    +------------------------------+
    | Commodore 64                 |
    | BASIC + ML renderer          |
    +--------------+---------------+
                   |
                   | TCP 6464
                   |
    +--------------v---------------+
    | Retro Gateway                |
    | PowerShell                   |
    | Screen Renderer              |
    | RGP Parser                   |
    +--------------+---------------+
                   |
                   | RAS Cmdlets
                   |
    +--------------v---------------+
    | Publishing Agent / CB        |
    | Secure Gateway               |
    | Host Pools                   |
    +------------------------------+

------------------------------------------------------------------------

# 4. Components

## Commodore 64 Client

Responsibilities:

-   Open TCP connection
-   Send RGP command
-   Receive full screen payload
-   Render to screen RAM
-   Capture keyboard
-   Send next command

The client intentionally contains almost no business logic.

------------------------------------------------------------------------

## Retro Gateway

Responsibilities:

-   Listen on TCP/6464
-   Authenticate requests (future shared secret)
-   Execute RAS cmdlets
-   Render a complete 40×25 screen
-   Return payload
-   Close connection

------------------------------------------------------------------------

## Parallels RAS

Acts as the authoritative data source.

Current cmdlets:

-   Get-RASFarmSettings
-   Get-RASRDSHostPool
-   Get-RASVDIHostPool
-   Get-RASAVDHostPool

Future:

-   Hosts
-   Users
-   Sessions
-   Sites
-   Drain mode
-   Enable/Disable host

------------------------------------------------------------------------

# 5. RGP Protocol

Current request:

    S

Current response:

    1000-byte screen

Future commands:

  Command   Description
  --------- --------------------
  M         Main Menu
  F         Farm
  S         Sites
  H         Hosts
  U         Users
  L         Live Dashboard
  P         Ping
  V         Version
  Q         Quit (client-side)

Future authentication:

    S SHAREDSECRET

------------------------------------------------------------------------

# 6. Screen Layout

40 × 25 characters.

Current main screen:

    ****************************************
    * PARALLELS RAS C64 CONSOLE           *
    ****************************************

    FARM           :
    GATEWAY        :
    STATUS         :
    PROTOCOL       :
    TIME           :

    RDSH POOLS     :
    VDI POOLS      :
    AVD POOLS      :
    HOSTS          :

    MENU

     F FARM  S SITES  H HOSTS  U USERS
     Q QUIT

------------------------------------------------------------------------

# 7. Rendering Model

The PowerShell gateway renders the entire screen.

The C64:

1.  receives payload
2.  copies to screen RAM
3.  waits for keyboard

No formatting decisions are made on the C64.

------------------------------------------------------------------------

# 8. Data Flow

    Key Press
        │
        ▼
    RGP Command
        │
        ▼
    PowerShell
        │
        ▼
    RAS Cmdlets
        │
        ▼
    Screen Renderer
        │
        ▼
    1000-byte payload
        │
        ▼
    C64

------------------------------------------------------------------------

# 9. Security

Current:

-   Azure NSG
-   Windows Firewall
-   Dedicated TCP port
-   Current demo release uses a matching pre-shared key in the BASIC client and PowerShell gateway

Planned:

-   Stronger shared secret handling
-   Challenge/response
-   Optional TLS proxy

For the published demo files, the key value is sanitized and must be kept identical in both [RAS64TCP129.BAS](RAS64TCP129.BAS) and [RetroGateway-RawTcp-v129.ps1](RetroGateway-RawTcp-v129.ps1).

------------------------------------------------------------------------

# 10. Coding Guidelines

PowerShell

-   One function per screen
-   One function per RAS query
-   One renderer

BASIC

-   Communication
-   Rendering
-   Keyboard
-   Utilities

Machine language reserved for rendering speed.

------------------------------------------------------------------------

# 11. Versioning

Each release introduces exactly one functional change.

Examples:

-   v1.05 AVD pools
-   v1.06 VDI pools
-   v1.07 Shared secret
-   v1.08 Farm screen

------------------------------------------------------------------------

# 12. Roadmap

Phase 1

-   Main screen ✔
-   Quit ✔
-   Live RAS data ✔

Phase 2

-   Farm page
-   Sites page
-   Hosts page
-   Users page

Phase 3

-   Live dashboard
-   Incremental updates

Phase 4

-   Administrative actions
-   Drain host
-   Enable host
-   Logoff session

------------------------------------------------------------------------

# 13. Future Enhancements

-   Color support
-   PETSCII boxes
-   Progress indicators
-   Status line
-   Challenge/response authentication
-   Differential screen updates
-   Multiple client implementations

------------------------------------------------------------------------

# 14. Design Principles

-   Simplicity over cleverness
-   Server owns presentation
-   Client remains lightweight
-   Real RAS data only
-   Incremental, testable changes
-   Preserve compatibility where possible

------------------------------------------------------------------------

# Appendix A - Naming

**RGP** -- Retro Gateway Protocol

**Retro Gateway** -- PowerShell service

**Parallels RAS C64 Console** -- Commodore application
