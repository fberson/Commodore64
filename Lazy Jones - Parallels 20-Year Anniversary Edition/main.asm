; =====================================================================
;  LAZY JONES  -  Parallels 20th Anniversary Edition
;  Clean-room C64 recreation (6502 assembly, ACME syntax)
;
;  This version uses a CUSTOM CHARACTER SET (detailed doors, ferns,
;  filmstrip rails, lift windows) plus HARDWARE SPRITES for Lazy Jones
;  and the three enemies - for proper C64-quality graphics.
;
;  Original concept: David Whittaker / Terminal Software (1984).
;  Independent re-implementation - no original code/assets are used.
;
;  Controls:  A/D move, W = up (enter door / lift up), S = lift down,
;             SPACE = start / leave a room.
;
;  Build:  acme -f cbm -o lazyjones.prg main.asm   (see build.ps1)
; =====================================================================

* = $0801
        !word +, 10
        !byte $9e
        !text "2064"
        !byte 0
+       !word 0

; =====================================================================
;  Constants
; =====================================================================
SCREEN   = $0400
COLRAM   = $d800
BORDER   = $d020
BGCOL    = $d021
D018     = $d018
CHARSET  = $3000            ; custom charset lives here (VIC bank 0)

; colours
BLACK=0 : WHITE=1 : RED=2 : CYAN=3 : PURPLE=4 : GREEN=5 : BLUE=6
YELLOW=7 : ORANGE=8 : BROWN=9 : LRED=10 : GREY1=11 : GREY2=12
LGREEN=13 : LBLUE=14 : GREY3=15

; custom tile char codes (contiguous 96..108 -> charset+96*8 = $3300)
TILE_RAIL  = 96
TILE_SHAFT = 97
TILE_WIN   = 98
DOOR_TL    = 99
DOOR_TR    = 100
DOOR_ML    = 101
DOOR_MR    = 102
DOOR_BL    = 103
DOOR_BR    = 104
PLANT_TL   = 105
PLANT_TR   = 106
PLANT_BL   = 107
PLANT_BR   = 108
CAR_TOP    = 109
CAR_MID    = 110
CAR_GRL    = 111
CAR_BOT    = 112
DOOR_OTL   = 113
DOOR_OTR   = 114
DOOR_OL    = 115
DOOR_OR    = 116
DESK_TOP   = 117
CHAIR      = 118
MON_TL     = 119
MON_H      = 120
MON_TR     = 121
MON_VL     = 122
MON_VR     = 123
MON_BL     = 124
MON_BR     = 125
CH_SPACE   = 32

; shaft columns
SHAFT_L = 17
SHAFT_R = 22

; zero page
ZP_PTR  = $fb
ZP_PTR2 = $fd
plrX     = $02
plrFloor = $03
plrFace  = $04
liftFloor= $05
delay    = $06
tmp      = $07
tmp2     = $08
roomsLo  = $09
hi       = $0b
mask     = $0c
e_col0   = $0d
e_col1   = $0e
e_col2   = $0f
e_dir0   = $10
e_dir1   = $11
e_dir2   = $12
fidx     = $13
doorcol  = $15
doorrow  = $16
doorc    = $17
dci      = $18
hitflash = $19
animf    = $1a
ride_from= $1b
ride_to  = $1c
ride_step= $1d
ride_cr  = $1e
jumpz    = $1f
lives    = $20
deathz   = $21
invuln   = $22
m_li     = $23      ; music: lead melody index
m_ld     = $24      ; music: lead note duration remaining
m_bi     = $25      ; music: bass melody index
m_bd     = $26      ; music: bass note duration remaining
factptr  = $27      ; fun-fact source pointer (2 bytes: $27/$28)

; =====================================================================
;  Entry
; =====================================================================
* = $0810
start:
        sei
        lda #BLACK
        sta BORDER
        sta BGCOL
        jsr setup_charset          ; build custom charset + switch VIC to it
        jsr music_init             ; start the SID chiptune

        jsr title_screen
        jsr wait_fire

        jsr init_sprites

init_game:
        lda #0
        sta roomsLo
        sta delay
        lda #4
        sta plrX
        lda #2
        sta plrFloor
        lda #1
        sta plrFace
        lda #2
        sta liftFloor
        lda #0
        sta hitflash
        sta jumpz
        sta invuln
        lda #5
        sta lives

        jsr reset_score

        ; enemies
        lda #30 : sta e_col0
        lda #4  : sta e_col1
        lda #30 : sta e_col2
        lda #1  : sta e_dir0
        lda #1  : sta e_dir1
        lda #$ff: sta e_dir2

        jsr draw_hotel

main_loop:
        jsr wait_frame
        jsr read_keys
        jsr move_enemies
        jsr check_collision
        jsr update_sprites
        jsr update_border
        jmp main_loop

; =====================================================================
;  Custom charset: copy ROM charset to $3000, then stamp our tiles,
;  then point VIC at it.
; =====================================================================
setup_charset:
        sei
        lda $01
        and #%11111011             ; char ROM visible at $d000
        sta $01
        lda #$d0 : sta ZP_PTR+1
        lda #$30 : sta ZP_PTR2+1
        lda #0   : sta ZP_PTR : sta ZP_PTR2
        ldx #8                     ; 8 pages = 2KB (uppercase set)
cs_page:
        ldy #0
cs_byte:
        lda (ZP_PTR),y
        sta (ZP_PTR2),y
        iny
        bne cs_byte
        inc ZP_PTR+1
        inc ZP_PTR2+1
        dex
        bne cs_page
        lda $01
        ora #%00000100             ; char ROM back out (IO in)
        sta $01
        cli

        ; stamp custom tiles: 30 tiles * 8 = 240 bytes -> $3300
        ldx #0
cs_tiles:
        lda tile_src,x
        sta CHARSET+96*8,x
        inx
        cpx #240
        bne cs_tiles

        ; VIC: screen $0400, charset $3000 -> $d018 = $1C
        lda #$1c
        sta D018
        rts

; =====================================================================
;  Sprites
; =====================================================================
init_sprites:
        lda #%00001111 : sta $d015     ; enable sprites 0-3
        lda #%00001111 : sta $d01c     ; multicolour 0-3
        lda #%00000000 : sta $d017     ; no Y expand
        sta $d01d                      ; no X expand
        lda #BROWN : sta $d025         ; shared mc0
        lda #LRED  : sta $d026         ; shared mc1 (pink)
        lda #ORANGE : sta $d027        ; player (orange cap/body)
        lda #LBLUE : sta $d028         ; top-floor guard (blue)
        lda #LGREEN : sta $d029        ; middle-floor machine (green)
        lda #BLACK : sta $d02a         ; bottom-floor man (black silhouette)
        jsr set_sprite_ptrs
        rts

; sprite pointers live in the last 8 bytes of screen RAM ($07F8-$07FF);
; clear_screen wipes them, so we restore them every frame.
set_sprite_ptrs:
        lda #160 : sta $07f8           ; player frame (animated) -> $2000/$2040
        lda #164 : sta $07f9           ; manager -> $2100
        lda #162 : sta $07fa           ; cart -> $2080
        lda #163 : sta $07fb           ; ghost -> $20C0
        rts

; A = floor -> A = walk row
floor_to_walkrow:
        tax
        lda walkrow,x
        rts

; A = row -> A = sprite Y pixel (row*8 + 34)
rowY:
        asl
        asl
        asl
        clc
        adc #34
        rts

; A = col, X = sprite*2 -> set sprite X low + $d010 MSB
set_sx:
        sta tmp2
        lda #0 : sta hi
        lda tmp2
        asl : rol hi
        asl : rol hi
        asl : rol hi
        clc : adc #24
        sta $d000,x
        bcc +
        inc hi
+       txa : lsr : tay
        lda sprmask,y : sta mask
        lda hi : beq sx_clr
        lda $d010 : ora mask : sta $d010 : rts
sx_clr:
        lda mask : eor #$ff : and $d010 : sta $d010 : rts

update_sprites:
        jsr set_sprite_ptrs            ; guard against clear_screen wiping them
        ; animate player: alternate frame 128/129 every 8 frames while moving
        jsr scan_left  : bcs us_moving
        jsr scan_right : bcs us_moving
        ; standing -> frame 0 (facing left or right)
        lda plrFace : bne +
        lda #169 : sta $07f8 : jmp us_pos      ; standing, facing left
+       lda #160 : sta $07f8 : jmp us_pos      ; standing, facing right
us_moving:
        lda delay : and #%00001000 : beq us_mv0
        ; frame 1
        lda plrFace : bne +
        lda #170 : sta $07f8 : jmp us_pos      ; stride, facing left
+       lda #161 : sta $07f8 : jmp us_pos      ; stride, facing right
us_mv0: ; frame 0
        lda plrFace : bne +
        lda #169 : sta $07f8 : jmp us_pos      ; frame0, facing left
+       lda #160 : sta $07f8
us_pos:
        ; enemies: alternate frames every 8 frames (always moving)
        lda delay : and #%00001000 : bne us_e1
        ; blue guard frame 0 - mirror to left frame when walking left
        lda e_dir0 : bmi ue0l
        lda #164 : sta $07f9 : jmp ue0d
ue0l:   lda #171 : sta $07f9
ue0d:
        lda #162 : sta $07fa           ; cart frame 0
        lda #163 : sta $07fb           ; ghost frame 0
        jmp us_pl
us_e1:
        lda e_dir0 : bmi ue1l
        lda #165 : sta $07f9 : jmp ue1d
ue1l:   lda #172 : sta $07f9
ue1d:
        lda #166 : sta $07fa           ; cart frame 1
        lda #167 : sta $07fb           ; ghost frame 1
us_pl:
        ; player (sprite 0) - +6 so his (higher) feet reach the floor
        lda plrFloor : jsr floor_to_walkrow : jsr rowY
        clc : adc #6
        ldx jumpz : sec : sbc jheight,x    ; lift by jump arc
        sta $d001
        ldx #0 : lda plrX : jsr set_sx
        ; manager floor 0 (sprite 1)
        lda #0 : jsr floor_to_walkrow : jsr rowY
        clc : adc #6 : sta $d003
        ldx #2 : lda e_col0 : jsr set_sx
        ; cart floor 1 (sprite 2)
        lda #1 : jsr floor_to_walkrow : jsr rowY
        clc : adc #6 : sta $d005
        ldx #4 : lda e_col1 : jsr set_sx
        ; ghost floor 2 (sprite 3)
        lda #2 : jsr floor_to_walkrow : jsr rowY
        clc : adc #6 : sta $d007
        ldx #6 : lda e_col2 : jsr set_sx
        rts

; =====================================================================
;  Enemy movement
; =====================================================================
move_enemies:
        lda delay
        and #$07
        bne me_done
        ; manager 2..37 (full floor)
        lda e_dir0 : bmi mm0d
        inc e_col0 : lda e_col0 : cmp #37 : bne mm1 : lda #$ff : sta e_dir0 : jmp mm1
mm0d:   dec e_col0 : lda e_col0 : cmp #2 : bne mm1 : lda #1 : sta e_dir0
mm1:    ; cart 2..37 (full floor)
        lda e_dir1 : bmi mm1d
        inc e_col1 : lda e_col1 : cmp #37 : bne mm2 : lda #$ff : sta e_dir1 : jmp mm2
mm1d:   dec e_col1 : lda e_col1 : cmp #2 : bne mm2 : lda #1 : sta e_dir1
mm2:    ; ghost 2..37 (full floor)
        lda e_dir2 : bmi mm2d
        inc e_col2 : lda e_col2 : cmp #37 : bne me_done : lda #$ff : sta e_dir2 : jmp me_done
mm2d:   dec e_col2 : lda e_col2 : cmp #2 : bne me_done : lda #1 : sta e_dir2
me_done:
        rts

; =====================================================================
;  Collision: same floor & within 1 column -> flash + reposition
; =====================================================================
check_collision:
        ; grace period after respawn -> no collision
        lda invuln
        beq cc_go
        dec invuln
        rts
cc_go:
        ; airborne? if jump height clears the enemy, no collision
        ldx jumpz
        lda jheight,x
        cmp #7
        bcs cc_none          ; >= 7px off the floor -> safe
        lda plrFloor
        cmp #0 : beq cc_m
        cmp #1 : beq cc_c
        ; floor 2 -> ghost
        lda e_col2 : jmp cc_test
cc_m:   lda e_col0 : jmp cc_test
cc_c:   lda e_col1
cc_test:
        sec
        sbc plrX
        ; A = e_col - plrX ; take abs and compare < 2
        bpl +
        eor #$ff
        clc
        adc #1
+       cmp #2
        bcs cc_none
        ; hit!
        jsr player_die
cc_none:
        rts

; =====================================================================
;  Player death: float up off screen, lose a life, restart (or game over)
; =====================================================================
player_die:
        lda #20 : sta hitflash          ; flash border red
        ; base pixel Y at player's floor
        lda plrFloor : jsr floor_to_walkrow : jsr rowY : clc : adc #6
        sta deathz
        ; only show the player sprite during the death float
        lda #%00000001 : sta $d015
        jsr set_sprite_ptrs
        lda #160 : sta $07f8
        ldx #0 : lda plrX : jsr set_sx
        ldx #24                         ; number of up-steps
pd_up:
        lda deathz : sec : sbc #4 : sta deathz
        sta $d001
        txa : pha
        jsr wait_frame
        jsr wait_frame
        lda hitflash : beq +
        dec hitflash
        lda #RED : sta BORDER : jmp pd_bc
+       lda #BLACK : sta BORDER
pd_bc:  pla : tax
        dex : bne pd_up
        lda #BLACK : sta BORDER
        ; lose a life
        dec lives
        lda lives : beq pd_gameover
        ; restart at start position
        lda #24 : sta plrX
        lda #2  : sta plrFloor
        lda #2  : sta liftFloor
        lda #0  : sta jumpz
        ; reset enemies to their start positions/directions
        lda #30 : sta e_col0
        lda #4  : sta e_col1
        lda #30 : sta e_col2
        lda #1  : sta e_dir0
        lda #1  : sta e_dir1
        lda #$ff: sta e_dir2
        ; grace period so we don't instantly die again
        lda #120 : sta invuln
        lda #%00001111 : sta $d015
        jsr draw_hotel
        rts
pd_gameover:
        jmp game_over

; =====================================================================
;  Game over: show GAME OVER, then auto-return to title after ~3 sec.
;  SPACE can still skip immediately.
; =====================================================================
game_over:
        lda #0 : sta $d015              ; hide all sprites
        jsr clear_screen
        lda #BLACK : sta BORDER
        ; draw GAME OVER
        lda #12 : jsr row_to_ptr
        lda #0 : sta tmp
go_on:  ldx tmp : lda gameover_txt,x : beq go_ondone
        txa : clc : adc #15 : tay
        lda gameover_txt,x : sta (ZP_PTR),y
        lda #WHITE : sta (ZP_PTR2),y
        inc tmp : jmp go_on
go_ondone:
        ldx #6                           ; ~6 seconds at 50Hz
go_sec:
        ldy #50
go_fr:  jsr scan_space : bcs go_restart
        jsr wait_frame
        dey : bne go_fr
        dex : bne go_sec
go_restart:
        jmp start

update_border:
        lda hitflash
        beq +
        dec hitflash
        lda #RED : sta BORDER : rts
+       lda #BLACK : sta BORDER : rts

; =====================================================================
;  Frame sync
; =====================================================================
wait_frame:
        lda #$ff
-       cmp $d012
        bne -
        inc delay
        jsr music_play
        rts

; =====================================================================
;  Title screen
; =====================================================================
title_screen:
        jsr clear_screen
        ; "welcome to the world of" (row 3, col 8)
        ldx #0
tw1:    lda welcome_txt,x : beq tw2
        sta SCREEN+40*3+8,x
        lda #LBLUE : sta COLRAM+40*3+8,x
        inx : bne tw1
tw2:    ; "lazy jones" (row 6, col 15)
        ldx #0
tl1:    lda title_txt,x : beq tl2
        sta SCREEN+40*6+15,x
        lda #WHITE : sta COLRAM+40*6+15,x
        inx : bne tl1
tl2:    ; subtitle (row 9, col 1)
        ldx #0
tl3:    lda sub_txt,x : beq tl4
        sta SCREEN+40*9+1,x
        lda #YELLOW : sta COLRAM+40*9+1,x
        inx : bne tl3
tl4:    ; "by freek berson" (row 12, col 12)
        ldx #0
tb1:    lda author_txt,x : beq tb2
        sta SCREEN+40*12+12,x
        lda #LRED : sta COLRAM+40*12+12,x
        inx : bne tb1
tb2:    ; "inspired by david whittaker" (row 15, col 6)
        ldx #0
ti1:    lda inspired_txt,x : beq ti2
        sta SCREEN+40*15+3,x
        lda #GREY2 : sta COLRAM+40*15+3,x
        inx : bne ti1
ti2:    ; "by david whittaker" (row 16, col 11)
        ldx #0
tj1:    lda inspired2_txt,x : beq tj2
        sta SCREEN+40*16+11,x
        lda #GREY2 : sta COLRAM+40*16+11,x
        inx : bne tj1
tj2:    ; "press space to start" (row 20, col 10)
        ldx #0
tl5:    lda start_txt,x : beq tl6
        sta SCREEN+40*20+10,x
        lda #ORANGE : sta COLRAM+40*20+10,x
        inx : bne tl5
tl6:    rts

wait_fire:
-       jsr wait_frame
        jsr scan_space
        bcc -
-       jsr wait_frame
        jsr scan_space
        bcs -
        rts

; =====================================================================
;  Clear screen
; =====================================================================
clear_screen:
        ldx #0
        lda #CH_SPACE
-       sta SCREEN,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+$300,x
        inx
        bne -
        ldx #0
        lda #BLACK
-       sta COLRAM,x
        sta COLRAM+$100,x
        sta COLRAM+$200,x
        sta COLRAM+$300,x
        inx
        bne -
        rts

; =====================================================================
;  Draw the hotel
; =====================================================================
draw_hotel:
        jsr clear_screen
        ; title along top
        ldx #0
dh1:    lda title_txt,x : beq dh2
        sta SCREEN+40*0+15,x
        lda #LBLUE : sta COLRAM+40*0+15,x
        inx : bne dh1
dh2:    ; subtitle on the second row
        ldx #0
dh1b:   lda sub_txt,x : beq dh2b
        sta SCREEN+40*1+1,x
        lda #GREY2 : sta COLRAM+40*1+1,x
        inx : bne dh1b
dh2b:
        jsr draw_shaft
        jsr draw_rails
        jsr draw_doors
        jsr draw_plants
        jsr draw_status
        rts

; ---- rails (ceiling = railtop, floor = railtop+4) ----
draw_rails:
        lda #0 : sta fidx
dr_f:   ldx fidx
        lda railtop,x
        jsr fill_rail_row
        ldx fidx
        lda railtop,x
        clc : adc #4
        jsr fill_rail_row
        inc fidx
        lda fidx : cmp #3 : bne dr_f
        rts

fill_rail_row:                       ; A = row (full width, runs over the shaft)
        jsr row_to_ptr
        ldy #0
frl:    lda #TILE_RAIL : sta (ZP_PTR),y
        lda #WHITE     : sta (ZP_PTR2),y
        iny : cpy #40 : bne frl
        rts

; ---- lift shaft + windows ----
draw_shaft:
        ; blue shaft box only at each floor (door-height rows), not in the
        ; gaps between floors. Elevator car appears there only while moving.
        lda #0 : sta fidx
ds_f:   ldx fidx : lda railtop,x : clc : adc #1 : sta tmp   ; first door row
        lda #0 : sta tmp2                                    ; row within floor
ds_row: lda tmp : jsr row_to_ptr
        ldy #SHAFT_L
ds_col: lda #TILE_SHAFT : sta (ZP_PTR),y
        lda #BLUE       : sta (ZP_PTR2),y
        iny : cpy #SHAFT_R+1 : bne ds_col
        inc tmp : inc tmp2 : lda tmp2 : cmp #3 : bne ds_row
        inc fidx : lda fidx : cmp #3 : bne ds_f
        ; windows
        ldx #0
dw_f:   txa : pha
        lda railtop,x : clc : adc #2 : jsr row_to_ptr
        pla : tax
        txa : cmp liftFloor : beq dw_lit
        lda #BLACK : jmp dw_set
dw_lit: lda #WHITE
dw_set: sta tmp2
        ldy #SHAFT_L+1 : lda #TILE_WIN : sta (ZP_PTR),y : lda tmp2 : sta (ZP_PTR2),y
        ldy #SHAFT_R-1 : lda #TILE_WIN : sta (ZP_PTR),y : lda tmp2 : sta (ZP_PTR2),y
        inx : cpx #3 : bne dw_f
        rts

; ---- doors ----
draw_doors:
        lda #0 : sta fidx
dd_f:   ldx fidx : lda doorcoltab,x : sta doorcol
        ldx fidx : lda railtop,x : sta doorrow
        lda #0 : sta dci
dd_c:   ldx dci : lda door_cols,x : cmp #$ff : beq dd_next : sta doorc
        ; top
        lda doorrow : clc : adc #1 : jsr row_to_ptr
        ldy doorc : lda #DOOR_TL : sta (ZP_PTR),y : lda doorcol : sta (ZP_PTR2),y
        iny       : lda #DOOR_TR : sta (ZP_PTR),y : lda doorcol : sta (ZP_PTR2),y
        ; mid
        lda doorrow : clc : adc #2 : jsr row_to_ptr
        ldy doorc : lda #DOOR_ML : sta (ZP_PTR),y : lda doorcol : sta (ZP_PTR2),y
        iny       : lda #DOOR_MR : sta (ZP_PTR),y : lda doorcol : sta (ZP_PTR2),y
        ; bottom
        lda doorrow : clc : adc #3 : jsr row_to_ptr
        ldy doorc : lda #DOOR_BL : sta (ZP_PTR),y : lda doorcol : sta (ZP_PTR2),y
        iny       : lda #DOOR_BR : sta (ZP_PTR),y : lda doorcol : sta (ZP_PTR2),y
        inc dci : jmp dd_c
dd_next:
        inc fidx : lda fidx : cmp #3 : bne dd_f
        rts

; ---- plants (foliage at railtop+2, pot at railtop+3) ----
draw_plants:
        lda #0 : sta fidx
dp_f:   ldx fidx : lda railtop,x : sta doorrow
        lda doorrow : clc : adc #2 : jsr row_to_ptr
        ldy #15 : lda #PLANT_TL : sta (ZP_PTR),y : lda #GREEN : sta (ZP_PTR2),y
        iny     : lda #PLANT_TR : sta (ZP_PTR),y : lda #GREEN : sta (ZP_PTR2),y
        ldy #23 : lda #PLANT_TL : sta (ZP_PTR),y : lda #GREEN : sta (ZP_PTR2),y
        iny     : lda #PLANT_TR : sta (ZP_PTR),y : lda #GREEN : sta (ZP_PTR2),y
        lda doorrow : clc : adc #3 : jsr row_to_ptr
        ldy #15 : lda #PLANT_BL : sta (ZP_PTR),y : lda #BROWN : sta (ZP_PTR2),y
        iny     : lda #PLANT_BR : sta (ZP_PTR),y : lda #BROWN : sta (ZP_PTR2),y
        ldy #23 : lda #PLANT_BL : sta (ZP_PTR),y : lda #BROWN : sta (ZP_PTR2),y
        iny     : lda #PLANT_BR : sta (ZP_PTR),y : lda #BROWN : sta (ZP_PTR2),y
        inc fidx : lda fidx : cmp #3 : bne dp_f
        rts

; =====================================================================
;  Keyboard + player logic
; =====================================================================
read_keys:
        ; jump handling (runs every frame)
        lda jumpz : bne rk_jump_adv
        jsr scan_space : bcc rk_move
        lda #24 : sta jumpz              ; start a jump
        jmp rk_move
rk_jump_adv:
        lda delay : and #1 : bne rk_move ; advance arc every other frame
        dec jumpz
rk_move:
        lda delay : and #$03 : bne rk_act
        jsr scan_left  : bcc rk_r
        lda plrX : cmp #1 : bcc rk_act : dec plrX : lda #0 : sta plrFace
        jmp rk_act
rk_r:   jsr scan_right : bcc rk_act
        lda plrX : cmp #38 : bcs rk_act : inc plrX : lda #1 : sta plrFace
rk_act:
        lda delay : and #$07 : bne rk_done
        jsr scan_down : bcc rk_up
        jsr lift_down
        jmp rk_done
rk_up:  jsr scan_up   : bcc rk_done
        jsr try_enter_or_lift
rk_done:
        rts

try_enter_or_lift:
        lda plrX : cmp #SHAFT_L : bcc teol_room
        cmp #SHAFT_R+1 : bcs teol_room
        ; at shaft -> ride up one floor
        lda plrFloor : beq teol_ret
        jsr ride_up
teol_ret:
        rts
teol_room:
        lda #0 : sta dci
        lda plrX : sta tmp2
        lda plrFace : bne ter_l
        inc tmp2                        ; facing left: visual center is +1 col
ter_l:  ldx dci : lda door_cols,x : cmp #$ff : beq teol_ret
        cmp tmp2 : beq ter_hit
        clc : adc #1
        cmp tmp2 : beq ter_hit
        inc dci : bne ter_l
ter_hit:
        ldx dci : lda door_cols,x : sta doorc   ; matched door left column
        jsr open_door_anim
        jsr scroll_out_left
        inc roomsLo
        jsr show_room
        jsr add_score
        jsr draw_hotel
        rts

; =====================================================================
;  Door-opening animation: door swings open, Jones stands in the lit
;  doorway for a moment, then the room screen appears.
; =====================================================================
open_door_anim:
        ldx plrFloor : lda doorcoltab,x : sta doorcol
        ldx plrFloor : lda railtop,x : sta doorrow
        ; top row (lintel)
        lda doorrow : clc : adc #1 : jsr row_to_ptr
        ldy doorc : lda #DOOR_OTL : sta (ZP_PTR),y : lda doorcol : sta (ZP_PTR2),y
        iny       : lda #DOOR_OTR : sta (ZP_PTR),y : lda doorcol : sta (ZP_PTR2),y
        ; mid row (jambs)
        lda doorrow : clc : adc #2 : jsr row_to_ptr
        ldy doorc : lda #DOOR_OL : sta (ZP_PTR),y : lda doorcol : sta (ZP_PTR2),y
        iny       : lda #DOOR_OR : sta (ZP_PTR),y : lda doorcol : sta (ZP_PTR2),y
        ; bottom row (jambs)
        lda doorrow : clc : adc #3 : jsr row_to_ptr
        ldy doorc : lda #DOOR_OL : sta (ZP_PTR),y : lda doorcol : sta (ZP_PTR2),y
        iny       : lda #DOOR_OR : sta (ZP_PTR),y : lda doorcol : sta (ZP_PTR2),y
        ; place Jones (sprite 0) standing in the doorway
        jsr set_sprite_ptrs
        lda #160 : sta $07f8
        lda plrFloor : jsr floor_to_walkrow : jsr rowY : clc : adc #6 : sta $d001
        ldx #0 : lda doorc : jsr set_sx
        ; hold the open doorway for ~40 frames
        ldy #40
oda_wait:
        jsr wait_frame
        dey : bne oda_wait
        rts

; =====================================================================
;  Scroll the whole play area off to the left until the screen is black,
;  then it's ready for the room screen.
; =====================================================================
scroll_out_left:
        lda #0 : sta $d015              ; hide sprites during scroll
        lda #40 : sta tmp2             ; number of columns to push out
sol_step:
        ; shift every row left by one column (screen + colour RAM)
        lda #0 : sta tmp              ; row counter
sol_row:
        lda tmp : jsr row_to_ptr
        ldy #0
sol_col:
        iny
        lda (ZP_PTR),y : dey : sta (ZP_PTR),y : iny
        lda (ZP_PTR2),y : dey : sta (ZP_PTR2),y : iny
        cpy #39 : bne sol_col
        ; blank the last column
        ldy #39
        lda #CH_SPACE : sta (ZP_PTR),y
        lda #BLACK    : sta (ZP_PTR2),y
        inc tmp : lda tmp : cmp #25 : bne sol_row
        ; pace the scroll
        jsr wait_frame
        jsr wait_frame
        dec tmp2 : lda tmp2 : bne sol_step
        rts


lift_down:
        lda plrX : cmp #SHAFT_L : bcc ld_ret
        cmp #SHAFT_R+1 : bcs ld_ret
        lda plrFloor : cmp #2 : beq ld_ret
        jsr ride_down
ld_ret: rts

; =====================================================================
;  Animated elevator ride (cage car slides through the shaft)
; =====================================================================
ride_up:
        lda plrFloor : jsr floor_to_walkrow : sta ride_from
        dec plrFloor
        lda plrFloor : jsr floor_to_walkrow : sta ride_to
        lda #$ff : sta ride_step         ; move up = decreasing row
        jmp ride_run
ride_down:
        lda plrFloor : jsr floor_to_walkrow : sta ride_from
        inc plrFloor
        lda plrFloor : jsr floor_to_walkrow : sta ride_to
        lda #1 : sta ride_step           ; move down = increasing row
ride_run:
        lda #$ff : sta liftFloor          ; no floor window lit while travelling
        jsr draw_shaft                    ; static background, drawn once
        lda ride_from : sta ride_cr
rr_loop:
        jsr draw_car
        jsr place_rider
        ldy #3
rr_wait:
        jsr wait_frame
        dey : bne rr_wait
        lda ride_cr : cmp ride_to : beq rr_done
        jsr erase_car                     ; leave a black gap behind the car
        lda ride_cr : clc : adc ride_step : sta ride_cr
        jmp rr_loop
rr_done:
        lda plrFloor : sta liftFloor
        jsr draw_hotel
        rts

; erase the 3 car rows (restore rail bars on rail rows, else black)
erase_car:
        lda ride_cr : sec : sbc #1 : sta tmp
        lda #0 : sta tmp2
ec_row: lda tmp : jsr row_to_ptr
        ; is this a rail row?  (2,6, 9,13, 16,20)
        ldx #0
ec_israil:
        lda railrows,x : cmp #$ff : beq ec_black
        cmp tmp : beq ec_rail
        inx : jmp ec_israil
ec_rail:
        ldy #SHAFT_L
ec_rc:  lda #TILE_RAIL : sta (ZP_PTR),y
        lda #WHITE     : sta (ZP_PTR2),y
        iny : cpy #SHAFT_R+1 : bne ec_rc
        jmp ec_next
ec_black:
        ldy #SHAFT_L
ec_bc:  lda #CH_SPACE : sta (ZP_PTR),y
        lda #BLACK    : sta (ZP_PTR2),y
        iny : cpy #SHAFT_R+1 : bne ec_bc
ec_next:
        inc tmp : inc tmp2 : lda tmp2 : cmp #3 : bne ec_row
        rts

railrows: !byte 2,6,9,13,16,20,$ff

; draw the cage car centred on row ride_cr, shaft cols 18..21
draw_car:
        lda ride_cr : sec : sbc #1 : jsr row_to_ptr
        ldy #SHAFT_L
dc_top: lda #CAR_TOP : sta (ZP_PTR),y : lda #WHITE : sta (ZP_PTR2),y
        iny : cpy #SHAFT_R+1 : bne dc_top
        lda ride_cr : jsr row_to_ptr
        ldy #SHAFT_L
        lda #CAR_GRL : sta (ZP_PTR),y : lda #WHITE : sta (ZP_PTR2),y
dc_grl: iny : cpy #SHAFT_R : beq dc_grr
        lda #CAR_MID : sta (ZP_PTR),y : lda #WHITE : sta (ZP_PTR2),y
        jmp dc_grl
dc_grr: lda #CAR_GRL : sta (ZP_PTR),y : lda #WHITE : sta (ZP_PTR2),y
        lda ride_cr : clc : adc #1 : jsr row_to_ptr
        ldy #SHAFT_L
dc_bot: lda #CAR_BOT : sta (ZP_PTR),y : lda #WHITE : sta (ZP_PTR2),y
        iny : cpy #SHAFT_R+1 : bne dc_bot
        rts

; place Lazy Jones (sprite 0) inside the car at row ride_cr
place_rider:
        jsr set_sprite_ptrs
        lda #160 : sta $07f8
        lda ride_cr : jsr rowY : clc : adc #6 : sta $d001
        ldx #0 : lda #19 : jsr set_sx
        rts

; =====================================================================
;  Room screen (arcade cabinet): monitor, score/time bar, logo, EXIT,
;  Jones walks to the chair, sits, then GET READY flashes on the screen.
;  REVSP (160) = reversed space = solid colour block.
; =====================================================================
REVSP = 160

show_room:
        lda #0 : sta $d015          ; hide sprites during build
        jsr clear_screen
        jsr music_room              ; start Star Dust tune when room appears

        ; ---- monitor/cabinet: thin-line 3D look ----
        ; monitor thin bezel border (rows 2..14, cols 2..38)
        lda #2 : jsr row_to_ptr
        ldy #2 : lda #MON_TL : sta (ZP_PTR),y : lda #LBLUE : sta (ZP_PTR2),y
        ldy #38 : lda #MON_TR : sta (ZP_PTR),y : lda #LBLUE : sta (ZP_PTR2),y
        ldy #3
mon_toph:
        lda #MON_H : sta (ZP_PTR),y : lda #LBLUE : sta (ZP_PTR2),y
        iny : cpy #38 : bne mon_toph

        lda #14 : jsr row_to_ptr
        ldy #2 : lda #MON_BL : sta (ZP_PTR),y : lda #LBLUE : sta (ZP_PTR2),y
        ldy #38 : lda #MON_BR : sta (ZP_PTR),y : lda #LBLUE : sta (ZP_PTR2),y
        ldy #3
mon_btmh:
        lda #MON_H : sta (ZP_PTR),y : lda #LBLUE : sta (ZP_PTR2),y
        iny : cpy #38 : bne mon_btmh

        lda #3 : sta tmp
mon_side:
        lda tmp : jsr row_to_ptr
        ldy #2  : lda #MON_VL : sta (ZP_PTR),y : lda #LBLUE : sta (ZP_PTR2),y
        ldy #38 : lda #MON_VR : sta (ZP_PTR),y : lda #LBLUE : sta (ZP_PTR2),y
        inc tmp : lda tmp : cmp #14 : bne mon_side

        ; no in-monitor score/time strip; keep monitor interior clean black
        ; no right/bottom thick grey cabinet shadow

        ; ---- EXIT sign + door (right side, lower) ----
        lda #16 : jsr row_to_ptr
        ldx #0
ex1:    lda exit_txt,x : beq ex1d
        txa : clc : adc #31 : tay
        lda exit_txt,x : sta (ZP_PTR),y : lda #GREEN : sta (ZP_PTR2),y
        inx : jmp ex1
ex1d:
        jsr draw_room_door

        ; ---- thin solid grey desk: cols 8..23, rows 17..18, chair notch in middle ----
        lda #17 : sta tmp               ; top row
tdk_row:
        lda tmp : jsr row_to_ptr
        ldy #8
tdk_col:
        lda #REVSP : sta (ZP_PTR),y
        lda #GREY2 : sta (ZP_PTR2),y
        iny : cpy #24 : bne tdk_col
        inc tmp : lda tmp : cmp #19 : bne tdk_row

        ; ---- maroon chair sitting in a notch in the middle (col 15) ----
        lda #17 : jsr row_to_ptr
        ldy #15 : lda #CH_SPACE : sta (ZP_PTR),y     ; carve notch in desk top
        lda #18 : jsr row_to_ptr
        ldy #15 : lda #CHAIR : sta (ZP_PTR),y : lda #RED : sta (ZP_PTR2),y

        jsr draw_status

        ; ---- Jones walks in from the EXIT door (right) to the chair ----
        lda #%00000001 : sta $d015      ; only player sprite
        lda #14 : sta ride_to           ; target column (centered on the chair)
        lda #31 : sta ride_cr           ; start column (exit door)
walk_in:
        ; animate frame by delay (facing left, moving left)
        jsr set_sprite_ptrs
        lda delay : and #%00000100 : beq +
        lda #170 : sta $07f8 : jmp wi_pos
+       lda #169 : sta $07f8
wi_pos:
        lda #18 : jsr rowY : clc : adc #6 : sta $d001
        ldx #0 : lda ride_cr : jsr set_sx
        jsr wait_frame
        jsr wait_frame
        jsr wait_frame
        dec ride_cr : lda ride_cr : cmp ride_to : bne walk_in

        ; ---- sit (standing frame at chair) ----
        jsr set_sprite_ptrs
        lda #160 : sta $07f8
        ldy #30
sit_w:  jsr wait_frame : dey : bne sit_w

        ; ---- flash GET READY on the monitor ----
        ldx #6                          ; number of flashes
gr_flash:
        txa : pha
        ; draw
        lda #7 : jsr row_to_ptr
        lda #0 : sta tmp
gr_on:  ldx tmp : lda getready_txt,x : beq gr_ondone
        txa : clc : adc #16 : tay
        lda getready_txt,x : sta (ZP_PTR),y
        lda #WHITE : sta (ZP_PTR2),y
        inc tmp : jmp gr_on
gr_ondone:
        ldy #25
grw1:   jsr wait_frame : dey : bne grw1
        ; erase
        lda #7 : jsr row_to_ptr
        lda #0 : sta tmp
gr_off: ldx tmp : lda getready_txt,x : beq gr_offdone
        txa : clc : adc #16 : tay
        lda #CH_SPACE : sta (ZP_PTR),y
        inc tmp : jmp gr_off
gr_offdone:
        ldy #15
grw2:   jsr wait_frame : dey : bne grw2
        pla : tax
        dex : bne gr_flash

        jsr draw_fun_fact
        jsr wait_fire

        ; ---- Jones walks back to the EXIT door ----
        lda #14 : sta ride_cr           ; start at chair
        lda #31 : sta ride_to           ; exit door column
walk_out:
        jsr set_sprite_ptrs
        lda delay : and #%00000100 : beq +
        lda #161 : sta $07f8 : jmp wo_pos
+       lda #160 : sta $07f8
wo_pos:
        lda #18 : jsr rowY : clc : adc #6 : sta $d001
        ldx #0 : lda ride_cr : jsr set_sx
        jsr wait_frame
        jsr wait_frame
        jsr wait_frame
        jsr wait_frame
        inc ride_cr : lda ride_cr : cmp ride_to : bne walk_out

        lda #BLACK : sta BORDER
        jsr music_main                  ; back to hotel theme
        lda #%00001111 : sta $d015 ; show all sprites again
        rts

; =====================================================================
;  Status bar
; =====================================================================
draw_status:
        ldx #0
st1:    lda status_txt,x : beq st2
        sta SCREEN+40*24+2,x
        lda #CYAN : sta COLRAM+40*24+2,x
        inx : bne st1
st2:    ; overwrite the lives digit with the real count
        lda lives : clc : adc #$30      ; PETSCII/screen code for digit 0..9
        sta SCREEN+40*24+2+21
        ; score digits (offset 6..11)
        ldx #0
sts_l:  lda score,x : clc : adc #$30 : sta SCREEN+40*24+2+6,x
        inx : cpx #6 : bne sts_l
        ; hi-score digits (offset 28..33)
        ldx #0
sth_l:  lda hi_sc,x : clc : adc #$30 : sta SCREEN+40*24+2+28,x
        inx : cpx #6 : bne sth_l
        rts

; =====================================================================
;  Score handling  (6 decimal digits, index 0 = most significant)
; =====================================================================
reset_score:
        lda #0
        ldx #5
rs_l:   sta score,x : dex : bpl rs_l
        rts

add_score:                              ; add 2500 to the score
        lda score+3 : clc : adc #5 : sta score+3
        lda score+2 : clc : adc #2 : sta score+2
        ldx #5
as_norm:
        lda score,x
        cmp #10 : bcc as_next
        sec : sbc #10 : sta score,x
        cpx #0 : beq as_next            ; ignore overflow past 6 digits
        dex : inc score,x : inx
        jmp as_norm
as_next:
        dex : bpl as_norm
        ; fall through to update hi-score
check_hi:
        ldx #0
ch_l:   lda score,x : cmp hi_sc,x
        bcc ch_done                     ; score digit lower -> not a record
        bne ch_copy                     ; score digit higher -> new record
        inx : cpx #6 : bne ch_l
        rts                             ; equal
ch_copy:
        ldx #0
ch_cl:  lda score,x : sta hi_sc,x
        inx : cpx #6 : bne ch_cl
ch_done:
        rts

; =====================================================================
;  row_to_ptr:  A = row -> ZP_PTR = SCREEN row, ZP_PTR2 = COLRAM row
; =====================================================================
row_to_ptr:
        tax
        lda row_lo,x : sta ZP_PTR
        lda row_hi,x : sta ZP_PTR+1
        lda row_lo,x : sta ZP_PTR2
        lda row_hi,x : clc : adc #$d4 : sta ZP_PTR2+1
        rts

; =====================================================================
;  SID music  (David Whittaker - "Lazy Jones", original tune from HVSC)
;  Binary is loaded at $1480; init=$1500, play=$1630, 21 subtunes.
; =====================================================================
SID_INIT   = $1500
SID_PLAY   = $1630
MUSIC_SONG = 0                  ; subtune 0 = main title/hotel theme
ROOM_SONG  = 20                 ; subtune 21 (0-based) inside a room (Star Dust)

music_init:
        lda #MUSIC_SONG
        jsr SID_INIT
        rts

music_play:
        jsr SID_PLAY
        rts

; switch to the in-room (Star Dust) tune
music_room:
        lda #ROOM_SONG
        jsr SID_INIT
        rts

; back to the main hotel theme
music_main:
        lda #MUSIC_SONG
        jsr SID_INIT
        rts

; =====================================================================
;  Keyboard matrix
; =====================================================================
CIA1_PRA = $dc00
CIA1_PRB = $dc01

scan_left:
        lda #$ff : sta CIA1_PRA
        lda CIA1_PRB : and #%00000100 : beq sl_hit   ; joystick port 1 left
        lda CIA1_PRA : and #%00000100 : beq sl_hit   ; joystick port 2 left
        lda #%11111101 : sta CIA1_PRA
        lda CIA1_PRB : and #%00000100 : beq sl_hit   ; keyboard A
        clc : rts
sl_hit: sec : rts
scan_right:
        lda #%11111011 : sta CIA1_PRA
        lda CIA1_PRB : and #%00000100 : beq sr_hit
        lda #$ff : sta CIA1_PRA
        lda CIA1_PRB : and #%00001000 : beq sr_hit   ; joystick port 1 right
        lda CIA1_PRA : and #%00001000 : beq sr_hit   ; joystick port 2 right
        clc : rts
sr_hit: sec : rts
scan_up:
        lda #%11111101 : sta CIA1_PRA
        lda CIA1_PRB : and #%00000010 : beq su_hit
        lda #$ff : sta CIA1_PRA
        lda CIA1_PRB : and #%00000001 : beq su_hit   ; joystick port 1 up
        lda CIA1_PRA : and #%00000001 : beq su_hit   ; joystick port 2 up
        clc : rts
su_hit: sec : rts
scan_down:
        lda #%11111101 : sta CIA1_PRA
        lda CIA1_PRB : and #%00100000 : beq sd_hit
        lda #$ff : sta CIA1_PRA
        lda CIA1_PRB : and #%00000010 : beq sd_hit   ; joystick port 1 down
        lda CIA1_PRA : and #%00000010 : beq sd_hit   ; joystick port 2 down
        clc : rts
sd_hit: sec : rts
scan_space:
        lda #%01111111 : sta CIA1_PRA
        lda CIA1_PRB : and #%00010000 : beq ss_hit
        lda #$ff : sta CIA1_PRA
        lda CIA1_PRB : and #%00010000 : beq ss_hit   ; joystick port 1 fire
        lda CIA1_PRA : and #%00010000 : beq ss_hit   ; joystick port 2 fire
        clc : rts
ss_hit: sec : rts

; =====================================================================
;  Data tables
;  Relocated above the embedded SID ($1480-$217F) so the tune fits in
;  low memory. This free region ($2180-$27FF) sits below the sprites.
; =====================================================================
* = $2180
walkrow:    !byte 5, 12, 19
railtop:    !byte 2, 9, 16
jheight:    !byte 0,3,6,9,11,13,15,16,17,18,19,20,20,20,19,18,17,16,15,13,11,9,6,3,0
doorcoltab: !byte YELLOW, RED, GREY3
door_cols:  !byte 2, 7, 12, 26, 31, 36, $ff
sprmask:    !byte 1, 2, 4, 8, 16, 32, 64, 128

title_txt:  !scr "lazy jones", 0
sub_txt:    !scr "parallels 20 year anniversary edition", 0
start_txt:  !scr "press space to start", 0
welcome_txt: !scr "welcome to the world of", 0
author_txt: !scr "by freek berson", 0
inspired_txt: !scr "inspired by the original lazy jones", 0
inspired2_txt: !scr "by david whittaker", 0
room_hdr:   !scr "parallels room", 0
room_l1:    !scr "celebrating 20 years of", 0
room_l2:    !scr "running worlds side by side.", 0
room_l3:    !scr "* happy 20th anniversary! *", 0
room_leave: !scr "press space to leave the room", 0
status_txt: !scr "score 000000   lives 5   hi 000000", 0
gameover_txt: !scr "game over", 0
scoretime_txt: !scr "score 000    time 9999", 0
getready_txt:  !scr "get ready", 0

; ---- detailed red EXIT door with grey shadow (placed here to keep the
;      main code block below the SID at $1480) ----
draw_room_door:
        ; detailed red panel door (2x3 tiles) at cols 32..33, rows 17..19
        lda #0 : sta dci
drd_row:
        ldx dci : lda drd_rowtab,x : jsr row_to_ptr
        ldx dci : txa : asl : tax        ; x = dci*2 into tile table
        ldy #32
        lda drd_tiles,x   : sta (ZP_PTR),y : lda #RED : sta (ZP_PTR2),y
        iny
        lda drd_tiles+1,x : sta (ZP_PTR),y : lda #RED : sta (ZP_PTR2),y
        inc dci : lda dci : cmp #3 : bne drd_row
        rts
drd_rowtab: !byte 17, 18, 19
drd_tiles:  !byte DOOR_TL, DOOR_TR, DOOR_ML, DOOR_MR, DOOR_BL, DOOR_BR


; facts moved to a dedicated segment at $3800 to avoid low-memory overlap

; score digits, most-significant first (persist in RAM across restarts)
score:  !byte 0,0,0,0,0,0
hi_sc:  !byte 0,0,0,0,0,0
logo_l1:    !scr "lazy", 0
logo_l2:    !scr "jones", 0
exit_txt:   !scr "exit", 0

; ---- custom tile bitmaps (13 tiles, 8 bytes each) ----
tile_src:
; TILE_RAIL - filmstrip
        !byte %11111111,%10001000,%10001000,%10001000,%11111111,%00000000,%00000000,%00000000
; TILE_SHAFT - solid
        !byte %11111111,%11111111,%11111111,%11111111,%11111111,%11111111,%11111111,%11111111
; TILE_WIN - solid window rectangle
        !byte %00000000,%11111111,%11111111,%11111111,%11111111,%11111111,%11111111,%00000000
; DOOR_TL
        !byte %11111111,%11000000,%11011111,%11011111,%11011111,%11011111,%11011111,%11011111
; DOOR_TR
        !byte %11111111,%00000011,%11111011,%11111011,%11111011,%11111011,%11111011,%11111011
; DOOR_ML (knob)
        !byte %11011111,%11011111,%11011111,%11010011,%11010011,%11011111,%11011111,%11011111
; DOOR_MR
        !byte %11111011,%11111011,%11111011,%11111011,%11111011,%11111011,%11111011,%11111011
; DOOR_BL
        !byte %11011111,%11011111,%11011111,%11011111,%11011111,%11011111,%11000000,%11111111
; DOOR_BR
        !byte %11111011,%11111011,%11111011,%11111011,%11111011,%11111011,%00000011,%11111111
; PLANT_TL (leafy fern, thin green lines, left half)
        !byte %01001001,%00100101,%00010011,%00001001,%00100101,%00010011,%00001001,%00000001
; PLANT_TR (leafy fern, thin green lines, right half)
        !byte %10010010,%10100100,%11001000,%10010000,%10100100,%11001000,%10010000,%10000000
; PLANT_BL (tapered pot, left half)
        !byte %00111111,%00011011,%00011111,%00001111,%00001101,%00000111,%00000111,%00001111
; PLANT_BR (tapered pot, right half)
        !byte %11111100,%01101000,%11111000,%11110000,%10110000,%11100000,%11100000,%11110000
; CAR_TOP (cage roof)
        !byte %00000000,%11111111,%11111111,%11111111,%11111111,%11111111,%11111111,%11111111
; CAR_MID (cage interior, solid)
        !byte %11111111,%11111111,%11111111,%11111111,%11111111,%11111111,%11111111,%11111111
; CAR_GRL (cage grille bars)
        !byte %11011011,%11011011,%11011011,%11011011,%11011011,%11011011,%11011011,%11011011
; CAR_BOT (cage floor)
        !byte %11111111,%11111111,%11111111,%11111111,%11111111,%11111111,%11111111,%00000000
; DOOR_OTL (open door top-left: lintel + left jamb)
        !byte %11111111,%11000000,%11000000,%11000000,%11000000,%11000000,%11000000,%11000000
; DOOR_OTR (open door top-right: lintel + right jamb)
        !byte %11111111,%00000011,%00000011,%00000011,%00000011,%00000011,%00000011,%00000011
; DOOR_OL (open door left jamb)
        !byte %11000000,%11000000,%11000000,%11000000,%11000000,%11000000,%11000000,%11000000
; DOOR_OR (open door right jamb)
        !byte %00000011,%00000011,%00000011,%00000011,%00000011,%00000011,%00000011,%00000011
; DESK_TOP (grey console top with dark control detail)
        !byte %11111111,%11111111,%10110110,%11111111,%10011001,%11111111,%11111111,%11111111
; CHAIR (maroon seat + backrest)
        !byte %00000000,%00111100,%00111100,%01111110,%01111110,%00011000,%00011000,%00111100
; MON_TL (thin monitor corner top-left)
        !byte %00000000,%01111111,%01000000,%01000000,%01000000,%01000000,%01000000,%01000000
; MON_H (thin monitor top line)
        !byte %00000000,%11111111,%00000000,%00000000,%00000000,%00000000,%00000000,%00000000
; MON_TR (thin monitor corner top-right)
        !byte %00000000,%11111110,%00000010,%00000010,%00000010,%00000010,%00000010,%00000010
; MON_VL (thin monitor side left)
        !byte %01000000,%01000000,%01000000,%01000000,%01000000,%01000000,%01000000,%01000000
; MON_VR (thin monitor side right)
        !byte %00000010,%00000010,%00000010,%00000010,%00000010,%00000010,%00000010,%00000010
; MON_BL (thin monitor corner bottom-left)
        !byte %01000000,%01000000,%01000000,%01000000,%01000000,%01000000,%01111111,%00000000
; MON_BR (thin monitor corner bottom-right)
        !byte %00000010,%00000010,%00000010,%00000010,%00000010,%00000010,%11111110,%00000000

; =====================================================================
;  Fun fact display inside the monitor (placed here, in the data region
;  below the sprites, so the main code stays clear of the SID at $1480).
;  Fact chosen by (roomsLo-1) mod 6.  Lines are null-terminated; the
;  whole fact ends with an $ff byte.
; =====================================================================
draw_fun_fact:
        lda roomsLo
        sec : sbc #1
ff_mod: cmp #6 : bcc ff_have
        sec : sbc #6 : jmp ff_mod
ff_have:
        asl
        tax
        lda fact_table,x   : sta factptr
        lda fact_table+1,x : sta factptr+1
        lda #4 : sta tmp                ; starting row
ff_line:
        ldy #0
        lda (factptr),y
        cmp #$ff : beq ff_done
        lda tmp : jsr row_to_ptr
        lda #3 : sta tmp2               ; starting column
ff_char:
        ldy #0
        lda (factptr),y
        beq ff_eol
        ldy tmp2
        sta (ZP_PTR),y
        lda #WHITE : sta (ZP_PTR2),y
        inc tmp2
        inc factptr : bne ff_c2 : inc factptr+1
ff_c2:  jmp ff_char
ff_eol:
        inc factptr : bne ff_e2 : inc factptr+1
ff_e2:  inc tmp
        jmp ff_line
ff_done:
        jmp color_parallels

; recolour every "parallels" occurrence in the monitor interior to red
color_parallels:
        lda #4 : sta tmp
cp_row: lda tmp : jsr row_to_ptr
        lda #3 : sta tmp2
cp_col: ldx #0
cp_cmp: txa : clc : adc tmp2 : tay
        lda (ZP_PTR),y
        cmp par_pat,x
        bne cp_no
        inx : cpx #9 : bne cp_cmp
        ldx #0
cp_set: txa : clc : adc tmp2 : tay
        lda #RED : sta (ZP_PTR2),y
        inx : cpx #9 : bne cp_set
cp_no:  inc tmp2 : lda tmp2 : cmp #30 : bne cp_col
        inc tmp : lda tmp : cmp #13 : bne cp_row
        rts
par_pat: !scr "parallels"

; =====================================================================
;  Room facts/timeline text in high RAM to protect main game data.
; =====================================================================
* = $3800
fact_table: !word fact0, fact1, fact2, fact3, fact4, fact5
fact0:
        !scr "before parallels ras, there was 2x.", 0
        !scr "and if you look closely, you can", 0
        !scr "still spot references to 2x in", 0
        !scr "parallels ras today.", 0
        !byte $ff
fact1:
        !scr "at wwdc 2007, steve jobs talked", 0
        !scr "about running windows on a mac.", 0
        !scr "and guess what appeared on screen?", 0
        !scr "parallels desktop!", 0
        !byte $ff
fact2:
        !scr "in 2011, parallels desktop was", 0
        !scr "spotted on nasa macbook pros", 0
        !scr "used during the curiosity rover", 0
        !scr "mission.", 0
        !byte $ff
fact3:
        !scr "in 2023, microsoft authorized", 0
        !scr "parallels desktop as a solution", 0
        !scr "for running windows 11 on apple", 0
        !scr "silicon macs. an official", 0
        !scr "microsoft thumbs-up!", 0
        !byte $ff
fact4:
        !scr "parallels has always been a very", 0
        !scr "international company, with teams", 0
        !scr "and talent spread across the globe.", 0
        !byte $ff
fact5:
        !scr "the parallels vipp program brings", 0
        !scr "together experts from across the", 0
        !scr "globe. they share their experience", 0
        !scr "and feedback with parallels.", 0
        !scr "euc nerds? definitely. and proud!", 0
        !byte $ff

; =====================================================================
;  Hardware sprite data (must be in VIC bank 0)
;  ptr 128 = $2000 (Lazy Jones), 130 = $2080 (cart), 131 = $20C0 (ghost)
; =====================================================================
code_end:
* = $2800
; --- Lazy Jones frame 0 (side profile, facing right, standing) ---
; multicolour: 01=brown 11=pink(face/shirt/feet) 10=orange(hat/body)
        !byte $02,$80,$00      ; hat crown
        !byte $0a,$a0,$00      ; hat top
        !byte $0a,$aa,$00      ; hat + brim to the right
        !byte $03,$f0,$00      ; face (pink)
        !byte $03,$d0,$00      ; face + eye
        !byte $02,$80,$00      ; neck
        !byte $0a,$a0,$00      ; shoulders
        !byte $0b,$e0,$00      ; body + pink shirt
        !byte $0b,$e0,$00      ; body + pink shirt
        !byte $0a,$a0,$00      ; body
        !byte $02,$80,$00      ; waist
        !byte $02,$80,$00      ; legs
        !byte $02,$80,$00      ; legs
        !byte $0a,$28,$00      ; legs split
        !byte $08,$08,$00      ; ankles
        !byte $3c,$3c,$00      ; pink feet
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00

* = $2840
; --- Lazy Jones frame 1 (side profile, facing right, stride) ---
        !byte $02,$80,$00      ; hat crown
        !byte $0a,$a0,$00      ; hat top
        !byte $0a,$aa,$00      ; hat + brim to the right
        !byte $03,$f0,$00      ; face (pink)
        !byte $03,$d0,$00      ; face + eye
        !byte $02,$80,$00      ; neck
        !byte $0a,$a0,$00      ; shoulders
        !byte $0b,$e0,$00      ; body + pink shirt
        !byte $0b,$e0,$00      ; body + pink shirt
        !byte $0a,$a0,$00      ; body
        !byte $02,$80,$00      ; waist
        !byte $02,$80,$00      ; legs
        !byte $02,$80,$00      ; legs
        !byte $28,$0a,$00      ; legs spread stride
        !byte $20,$02,$00      ; ankles apart
        !byte $f0,$03,$00      ; pink feet spread
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00

* = $2880
; --- middle-floor cleaning cart frame 0 ---
; multicolour: 00=black 01=brown($d025) 10=green($d029) 11=pink($d026)
        !byte $00,$00,$10      ; broom handle tip (brown)
        !byte $00,$00,$40      ; broom handle
        !byte $00,$01,$00      ; broom handle
        !byte $00,$04,$00      ; broom handle
        !byte $00,$10,$00      ; broom handle
        !byte $00,$40,$00      ; broom handle base
        !byte $2a,$aa,$a8      ; cart top rim (green)
        !byte $25,$55,$58      ; body top, brown interior
        !byte $24,$51,$48      ; body w/ thin black detail
        !byte $25,$55,$58      ; body
        !byte $2a,$aa,$a8      ; green band
        !byte $25,$55,$58      ; body
        !byte $25,$55,$58      ; body
        !byte $2a,$aa,$a8      ; bottom rim (green)
        !byte $08,$00,$20      ; wheel struts
        !byte $2a,$00,$a8      ; wheel tyres (green)
        !byte $22,$00,$88      ; wheel hubs (black)
        !byte $2a,$00,$a8      ; wheel tyres (green)
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00

* = $28C0
; --- bottom-floor man frame 0 (black silhouette, brimmed hat, stride) ---
; colour via $d02a = BLACK; solid body uses colour bits (10)
        !byte $00,$28,$00      ; hat top
        !byte $0f,$fc,$00      ; hat brim (wide)
        !byte $02,$a0,$00      ; head
        !byte $02,$a8,$00      ; head + snout/eye nub
        !byte $02,$a0,$00      ; neck
        !byte $0a,$a0,$00      ; shoulders
        !byte $2a,$a0,$00      ; body
        !byte $2a,$a0,$00      ; body
        !byte $0a,$a0,$00      ; body
        !byte $0a,$a0,$00      ; waist
        !byte $02,$a0,$00      ; hips
        !byte $02,$a0,$00      ; legs
        !byte $0a,$20,$00      ; legs split (back/front)
        !byte $08,$08,$00      ; legs stride
        !byte $28,$0a,$00      ; feet spread
        !byte $20,$02,$00      ; feet tips
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00

* = $2900
; --- top-floor guard frame 0 (blue man w/ cap, side profile, standing) ---
; colour via $d028 = LBLUE; mc0=brown mc1=pink(face)
        !byte $02,$80,$00      ; cap crown (blue)
        !byte $0a,$a0,$00      ; cap top
        !byte $0a,$aa,$00      ; cap + peak to the right
        !byte $03,$f0,$00      ; face (pink)
        !byte $03,$d0,$00      ; face + eye
        !byte $02,$80,$00      ; neck
        !byte $0a,$a0,$00      ; shoulders (blue)
        !byte $2a,$a0,$00      ; arm + body
        !byte $2a,$a0,$00      ; arm + body
        !byte $0a,$a0,$00      ; body
        !byte $02,$80,$00      ; waist
        !byte $02,$80,$00      ; legs
        !byte $02,$80,$00      ; legs
        !byte $0a,$28,$00      ; legs split
        !byte $08,$08,$00      ; ankles
        !byte $14,$14,$00      ; brown shoes
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00

* = $2940
; --- top-floor guard frame 1 (blue man w/ cap, side profile, stride) ---
        !byte $02,$80,$00      ; cap crown (blue)
        !byte $0a,$a0,$00      ; cap top
        !byte $0a,$aa,$00      ; cap + peak to the right
        !byte $03,$f0,$00      ; face (pink)
        !byte $03,$d0,$00      ; face + eye
        !byte $02,$80,$00      ; neck
        !byte $0a,$a0,$00      ; shoulders (blue)
        !byte $2a,$a0,$00      ; arm + body
        !byte $2a,$a0,$00      ; arm + body
        !byte $0a,$a0,$00      ; body
        !byte $02,$80,$00      ; waist
        !byte $02,$80,$00      ; legs
        !byte $02,$80,$00      ; legs
        !byte $28,$0a,$00      ; legs spread stride
        !byte $20,$02,$00      ; ankles apart
        !byte $50,$05,$00      ; brown shoes spread
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00

* = $2980
; --- middle-floor cleaning cart frame 1 (wheels rolled) ---
        !byte $00,$00,$10      ; broom handle tip (brown)
        !byte $00,$00,$40      ; broom handle
        !byte $00,$01,$00      ; broom handle
        !byte $00,$04,$00      ; broom handle
        !byte $00,$10,$00      ; broom handle
        !byte $00,$40,$00      ; broom handle base
        !byte $2a,$aa,$a8      ; cart top rim (green)
        !byte $25,$55,$58      ; body top, brown interior
        !byte $25,$45,$18      ; body w/ thin black detail (shifted)
        !byte $25,$55,$58      ; body
        !byte $2a,$aa,$a8      ; green band
        !byte $25,$55,$58      ; body
        !byte $25,$55,$58      ; body
        !byte $2a,$aa,$a8      ; bottom rim (green)
        !byte $08,$00,$20      ; wheel struts
        !byte $22,$00,$88      ; wheel hubs (black, rolled)
        !byte $2a,$00,$a8      ; wheel tyres (green)
        !byte $22,$00,$88      ; wheel hubs (black)
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00

* = $29C0
; --- bottom-floor man frame 1 (black silhouette, legs together) ---
        !byte $00,$28,$00      ; hat top
        !byte $0f,$fc,$00      ; hat brim (wide)
        !byte $02,$a0,$00      ; head
        !byte $02,$a8,$00      ; head + eye nub
        !byte $02,$a0,$00      ; neck
        !byte $0a,$a0,$00      ; shoulders
        !byte $2a,$a0,$00      ; body
        !byte $2a,$a0,$00      ; body
        !byte $0a,$a0,$00      ; body
        !byte $0a,$a0,$00      ; waist
        !byte $02,$a0,$00      ; hips
        !byte $02,$a0,$00      ; legs
        !byte $02,$a0,$00      ; legs together
        !byte $02,$a0,$00      ; legs together
        !byte $02,$a0,$00      ; legs
        !byte $02,$80,$00      ; feet
        !byte $0a,$00,$00      ; feet base
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00

* = $2A00
; --- Lazy Jones JUMP pose (pointer 136): arms up, legs tucked ---
; multicolour: 01=brown(shoes) 11=pink(face/legs) 10=orange(cap/body)
        !byte $28,$0a,$00      ; arms raised (orange)
        !byte $08,$28,$00      ; arms up
        !byte $00,$a0,$00      ; cap top
        !byte $02,$a8,$00      ; cap
        !byte $03,$f0,$00      ; face (pink)
        !byte $03,$f0,$00      ; face
        !byte $02,$a0,$00      ; shoulders (orange)
        !byte $0a,$a8,$00      ; body
        !byte $0a,$a8,$00      ; body
        !byte $02,$a0,$00      ; body
        !byte $03,$f0,$00      ; hips (pink)
        !byte $03,$fc,$00      ; legs tucked out
        !byte $0f,$3c,$00      ; knees bent/tucked
        !byte $0c,$0c,$00      ; feet tucked up
        !byte $14,$14,$00      ; brown shoes tucked
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00

* = $2A40
; --- Lazy Jones frame 0 LEFT (mirror of $2800, facing left) ---
        !byte $00,$02,$80      ; hat crown
        !byte $00,$0a,$a0      ; hat top
        !byte $00,$aa,$a0      ; hat + brim to the left
        !byte $00,$0f,$c0      ; face (pink)
        !byte $00,$1f,$c0      ; face + eye
        !byte $00,$02,$80      ; neck
        !byte $00,$0a,$a0      ; shoulders
        !byte $00,$0b,$e0      ; body + pink shirt
        !byte $00,$0b,$e0      ; body + pink shirt
        !byte $00,$0a,$a0      ; body
        !byte $00,$02,$80      ; waist
        !byte $00,$02,$80      ; legs
        !byte $00,$02,$80      ; legs
        !byte $00,$28,$a0      ; legs split
        !byte $00,$20,$20      ; ankles
        !byte $00,$3c,$3c      ; pink feet
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00

* = $2A80
; --- Lazy Jones frame 1 LEFT (mirror of $2840, facing left, stride) ---
        !byte $00,$02,$80      ; hat crown
        !byte $00,$0a,$a0      ; hat top
        !byte $00,$aa,$a0      ; hat + brim to the left
        !byte $00,$0f,$c0      ; face (pink)
        !byte $00,$1f,$c0      ; face + eye
        !byte $00,$02,$80      ; neck
        !byte $00,$0a,$a0      ; shoulders
        !byte $00,$0b,$e0      ; body + pink shirt
        !byte $00,$0b,$e0      ; body + pink shirt
        !byte $00,$0a,$a0      ; body
        !byte $00,$02,$80      ; waist
        !byte $00,$02,$80      ; legs
        !byte $00,$02,$80      ; legs
        !byte $00,$a0,$28      ; legs spread stride
        !byte $00,$80,$08      ; ankles apart
        !byte $00,$c0,$0f      ; pink feet spread
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00

* = $2AC0
; --- top-floor guard frame 0 LEFT (mirror of $2900, facing left) ---
        !byte $00,$02,$80      ; cap crown (blue)
        !byte $00,$0a,$a0      ; cap top
        !byte $00,$aa,$a0      ; cap + peak to the left
        !byte $00,$0f,$c0      ; face (pink)
        !byte $00,$07,$c0      ; face + eye
        !byte $00,$02,$80      ; neck
        !byte $00,$0a,$a0      ; shoulders (blue)
        !byte $00,$0a,$a8      ; arm + body
        !byte $00,$0a,$a8      ; arm + body
        !byte $00,$0a,$a0      ; body
        !byte $00,$02,$80      ; waist
        !byte $00,$02,$80      ; legs
        !byte $00,$02,$80      ; legs
        !byte $00,$28,$a0      ; legs split
        !byte $00,$20,$20      ; ankles
        !byte $00,$14,$14      ; brown shoes
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00

* = $2B00
; --- top-floor guard frame 1 LEFT (mirror of $2940, facing left, stride) ---
        !byte $00,$02,$80      ; cap crown (blue)
        !byte $00,$0a,$a0      ; cap top
        !byte $00,$aa,$a0      ; cap + peak to the left
        !byte $00,$0f,$c0      ; face (pink)
        !byte $00,$07,$c0      ; face + eye
        !byte $00,$02,$80      ; neck
        !byte $00,$0a,$a0      ; shoulders (blue)
        !byte $00,$0a,$a8      ; arm + body
        !byte $00,$0a,$a8      ; arm + body
        !byte $00,$0a,$a0      ; body
        !byte $00,$02,$80      ; waist
        !byte $00,$02,$80      ; legs
        !byte $00,$02,$80      ; legs
        !byte $00,$a0,$28      ; legs spread stride
        !byte $00,$80,$08      ; ankles apart
        !byte $00,$50,$05      ; brown shoes spread
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00

; ---- screen row address tables ----
row_lo:
        !for i, 0, 24 { !byte <(SCREEN + i*40) }
row_hi:
        !for i, 0, 24 { !byte >(SCREEN + i*40) }

; =====================================================================
;  Embedded SID tune - David Whittaker "Lazy Jones" (HVSC).
;  The .sid file is PSID: 124-byte header + 2-byte embedded load addr
;  = 126 bytes skipped, leaving the raw C64 image that lives at $1480.
;  init = $1500, play = $1630.
; =====================================================================
* = $1480
!binary "music/Lazy_Jones.sid", , 126
