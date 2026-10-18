# Retro Gateway (RGP) -- Parallels RAS C64 Console

## Overview

Retro Gateway is a proof-of-concept project that allows a Commodore 64
(Ultimate 64 with networking) to monitor a live Parallels RAS
environment over TCP/IP.

The project consists of three major components:

1.  Commodore 64 client (BASIC)
2.  Retro Gateway (PowerShell)
3.  Parallels RAS

Communication uses **RGP (Retro Gateway Protocol)** over a raw TCP
socket.

## Architecture

``` text
+-------------------+
| Commodore 64      |
| RAS64TCP.BAS/PRG  |
+---------+---------+
          |
          | RGP over TCP (port 6464)
          |
+---------v---------+
| Retro Gateway     |
| PowerShell (.ps1) |
+---------+---------+
          |
          | Parallels RAS PowerShell Cmdlets
          |
+---------v---------+
| Parallels RAS     |
| Publishing Agent  |
| Secure Gateway    |
+-------------------+
```

## Components

### Commodore 64 Client

Responsibilities:

-   Connects to the Retro Gateway.
-   Sends an RGP command.
-   Receives a 40×25 screen.
-   Renders the screen.
-   Waits for user input.
-   Supports Q (Quit). Other menu items are placeholders.

Current menu:

``` text
MENU

 F FARM   S SITES   H HOSTS   U USERS
 Q QUIT
```

### Retro Gateway (PowerShell)

Responsibilities:

-   Listens on TCP port 6464.
-   Accepts Commodore 64 connections.
-   Validates incoming RGP commands.
-   Queries Parallels RAS.
-   Generates a complete 40×25 screen.
-   Sends the rendered screen back.

### Parallels RAS

Current live information includes:

-   Farm name
-   RDSH Host Pool count
-   VDI Host Pool count
-   AVD Host Pool count
-   Host count
-   Gateway information

Data is retrieved dynamically using RAS PowerShell cmdlets each time a
screen is requested.

## RGP (Retro Gateway Protocol)

Current protocol is intentionally simple.

Client:

    S

Server:

-   Returns one complete screen image.

Future protocol ideas:

-   F (Farm)
-   H (Hosts)
-   U (Users)
-   S (Sites)
-   L (Live Dashboard)
-   HELP
-   VERSION

## Security

Current protection:

-   Azure NSG restricted to trusted public IP(s)
-   Windows Firewall restriction
-   Raw TCP listener
-   Matching demo pre-shared key in the BASIC client and PowerShell gateway

Planned:

-   Shared secret between client and gateway
-   Challenge/response authentication
-   Optional TLS reverse proxy

For the published demo set, the key value is sanitized and must match in [RAS64TCP129.BAS](RAS64TCP129.BAS) and [RetroGateway-RawTcp-v129.ps1](RetroGateway-RawTcp-v129.ps1).

## Current UI

Displays:

-   Farm
-   Gateway
-   Status
-   Protocol version
-   Time
-   RDSH Pools
-   VDI Pools
-   AVD Pools
-   Hosts
-   Menu

## Current Status

Working:

-   Stable TCP communication
-   Stable screen rendering
-   Dynamic RAS queries
-   Fast rendering
-   Menu display
-   Quit command

Planned:

-   Farm page
-   Sites page
-   Hosts page
-   Users page
-   Live dashboard
-   Administrative actions (drain, enable, reboot)
-   Incremental screen updates
-   Full RGP specification

## Versioning

Current development follows incremental releases (v1.xx), with each
version introducing a single functional change to simplify testing and
troubleshooting.

## Vision

The long-term vision is to build a fully functional retro administration
console for Parallels RAS running on a Commodore 64, while keeping the
architecture clean:

-   C64 = presentation + keyboard
-   RGP = transport protocol
-   PowerShell = business logic
-   Parallels RAS = authoritative data source

This creates a unique demonstration of modern infrastructure management
using classic computing hardware.
