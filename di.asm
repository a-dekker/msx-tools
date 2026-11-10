;*** DI DIR with LFN v0.22
;

;
; Compiled with SjASMPlus v1.22.0
;


; ASCII Code
LF  equ 0ah
CR  equ 0dh
ESC equ 1bh
; Standard BIOS and work area entries
CLS equ 000C3h
CHSNS equ 0009Ch
KILBUF  equ 00156h

; Variables
CALSLT  equ     0001Ch
BDOS  equ 00005h
WRSLT equ 00014h
ENASLT  equ 00024h
FCB equ 0005ch
DMA equ 00080h
RSLREG  equ 00138h
SNSMAT  equ 00141h
RAMAD1  equ 0f342h
RAMAD2  equ 0f343h
LOCATE  equ 0f3DCh
BUFTOP  equ 08000h
CHGET equ 0009fh
POSIT equ 000C6h
MNROM equ 0FCC1h    ; Main-ROM Slot number & Secondary slot flags table
DRVINV  equ 0FB22H  ; Installed Disk-ROM
WIDTH equ 0F3B0h    ; LINLEN: current screen width (was 0F3AEh = LINL40, wrong for 80 columns)
CRTCNT  equ 0F3B1h  ; number of text rows on screen
VDP_DATA  equ 098h  ; VDP data port (VRAM read/write)
VDP_CMD equ 099h    ; VDP command port (set VRAM address)

  org 0100h

START:
  jp  Main



NEXTOR_TXT: db  "Only for MSX Nextor!!",CR,LF,"$"
all_string: db  "*.*",0
HlpMes:
  db  "DI.COM v0.22 by Victor Martinez",CR,LF
  db  "DIR that shows Long File Name",CR,LF
  db  "Only for Nextor by Konamiman",CR,LF,CR,LF


  db  "Usage:",CR,LF
  db  "DI [Drive:][path][filename]   [/option]",CR,LF,CR,LF
  db  "Options:",CR,LF
  db  "  /?  Show this Help",CR,LF
  db  "  /H  Show Hidden files",CR,LF
  db  "  /S  Show System files",CR,LF
  db  "  /F  Don't show directories",CR,LF
  db  "  /P  Don't pause",CR,LF
  db  "  /W  Wide list: sorted, in columns",CR,LF
  db  "$"
DosErr:
  db  "Error reading file!",CR,LF,"$"
Directory_TXT:
  db  " Directory of ","$"
t_sistema_invalido
  db  CR,LF,"Only compatbile with FAT12 and FAT16!!",CR,LF,"$"

files_TXT:  db  " files,  ","$"
dirs_TXT: db  " dirs","$"
wait_files_TXT: db "Press any key to continue ","$"
end_RET_TXT:  db  CR,LF,CR,LF,"$"
end_1RET_TXT: db  CR,LF,"$"
;---------------------------------------------------

Main:


  call  CHKDOS2 ;DOS_VERSION  ->1=MSXDOS1,  2=MSXDOS2, 3=NEXTOR
  cp  3 ;Nextor??
  ld  de,NEXTOR_TXT
  jp  nz,Done

  call  Parameters;undad, path,etc... y parametros


  call  INIT_values



  ld  de,search_string
  ld  c,40h
  ld  ix,FIB
  ld  a,(atributos_a_mostrar)
  ld  b,a
  call  BDOS
  or  a ;error??
  jp  nz,error_exit

  call  write_directory_TEXT

  ld  a,(wide_mode)
  or  a
  jp  nz,wide_listing ;/W: sorted multi column list

  call  INI_LFN

  jp  print_JUMP



check_next_file:

  ld  c,41h;next entry
  ld  ix,FIB
  call  BDOS
print_JUMP:
  or  a
  ;TODO! JP end files
  jr  nz,no_more_files

  call  DEC_lines_printed


  call  print_file

  jp  check_next_file


;fin de listado
;ponemos numero de ficheros y directorios
no_more_files:

  ;We leave 2 spaces
  ld  e," "
  ld  c,2
  call  BDOS
  ld  e," "
  ld  c,2
  call  BDOS

  ;print the number of files
  ld  hl,(files_counter)
  call  put_decimal
  call  imprime_cantidad_en_pantalla

  ;We print the files
  ld  de,files_TXT
  ld  c,9
  call  BDOS



  ;We print a number of directories.
  ld  hl,(dirs_counter)
  call  put_decimal
  call  imprime_cantidad_en_pantalla

  ;imprimimos files
  ld  de,dirs_TXT
  ld  c,9
  call  BDOS
;fin OK
  rst 0 ;vuelve al DOS correctamente
  ;ret
;-----------------------------------------------------
put_decimal:
;Number in hl to decimal ASCII
;Thanks to z80 Bits
;inputs:  hl = number to ASCII
;example: hl=300 outputs '00300'
;destroys: af, bc, hl, de used

  ld  de,cantidad_valor_TXT

Num2Dec ld  bc,-10000
  call  Num1
  ld  bc,-1000
  call  Num1
  ld  bc,-100
  call  Num1
  ld  c,-10
  call  Num1
  ld  c,b

Num1  ld  a,'0'-1
Num2  inc a
  add hl,bc
  jr  c,Num2
  sbc hl,bc

  ld  (de),a
  inc de
  ret

imprime_cantidad_en_pantalla:

  ld  de,cantidad_valor_TXT-1
next_cantidad_to_print:
  inc de
  ld  a,(de)
  cp  "$"
  jr  z,cantidad_cero
  cp  030h
  jr  z,next_cantidad_to_print
imprime_cantidad_DOS:
  ld  c,9
  call  BDOS
  ret
cantidad_cero:
  dec de
  jr  imprime_cantidad_DOS




cantidad_valor_TXT: ds  7,"$"




;FIND FIRST ENTRY (40H)
;
;
;     Paramet:      C = 40H (_FFIRST)
;                   DE = Drive/path/file ASCIIZ string
;                                or fileinfo block pointer
;                        HL = filename ASCIIZ string (only if
;                                DE = fileinfo pointer)
;                         B = Search attributes
;                   IX = Pointer to new fileinfo block
;     Results:       A = Error
;                 (IX) = Filled in with matching entry



search_string:  ds  64
FIB:    ds  64


;     0 - Always 0FFh
; 1..13 - Filename as an ASCIIZ string
;    14 - File attributes byte
;15..16 - Time of last modification
;17..18 - Date of last modification
;19..20 - Start cluster
;21..24 - File size
;    25 - Logical drive
;26..63 - Internal information, must not be modified

line_file_2_PRINT:  ds  80,20h
    db  CR,LF,"$"

;--------------------------------------------------------------------------------------------
print_file:
;copy filename

  ld  hl,FIB+1
  ld  de,line_file_2_PRINT
  ld  b,13
next_character_name_FIB:
  ld  a,(hl)
  or  a
  jr  nz,ok_char_name
  ld  a," "
  dec  hl
ok_char_name:
  ld  (de),a
  inc hl
  inc de
  djnz  next_character_name_FIB

;verify attributes
  ld  a,(FIB+14)
  ld  c,a

  inc de
  bit 1,c
  ld  a," "
  jr  z,no_put_HIDDEN
  ld  a,"h"
no_put_HIDDEN:
  ld  (de),a

  inc de  ;leave a space
  bit 0,c
  ld  a," "
  jr  z,no_put_READONLY
  ld  a,"r"
no_put_READONLY:

  ld  (de),a
  ;inc  de
  bit 2,c
  ld  a," "
  jr  z,no_put_SYSTEMFILE
  ld  a,"s"

  ld  (de),a
no_put_SYSTEMFILE:
;it is a directory?
  bit 4,c
  jr  z,no_PUT_DIRECTORY


  ;increase the number of directories
  ld  hl,(dirs_counter)
  inc hl
  ld  (dirs_counter),hl

  ld  hl,dir_TXT
  ld  de,line_file_2_PRINT+16
  ld  bc,13
  ldir
  jp  check_LFN

no_PUT_DIRECTORY:
;write the size in bytes

  ;increase the number of files
  ld  hl,(files_counter)
  inc hl
  ld  (files_counter),hl


  ld  hl,FIB+21
  ld  bc,line_file_2_PRINT+16

  call  put_32bits
  ;IN:
  ;HL:pointer to 32 bits number
  ;BC:pointer to output buffer
  ld  hl,line_file_2_PRINT+27
  ld  (hl),0	;end of the line (a file name can contain "$")

check_LFN:
  ;check if screen width is greater than 35
  ld  a,(WIDTH)
  cp  35
  jr  c,end_print_line

  ld  a,(FIB+7)
  cp  "~"
  jr  nz,end_print_line
  call  Long_File_Name
  ld  hl,LFN
  ld  de,line_file_2_PRINT+27
long_LFN_to_write:  ld  bc,80-27
  ldir
  ex  de,hl
  ld  (hl),0	;end of the line (a file name can contain "$")



end_print_line:
  ld  a,(fast_screen_ok)
  or  a
  jp  nz,fast_print_line  ;40/80 column screen: write straight to VRAM
  jp  print_line_BDOS

;-----------------------------------------------------------------------------------
; Fast screen output
; Instead of BDOS function 9 (slow: the BIOS scrolls the screen char by char) the line
; is written straight into VRAM at the cursor row. When the bottom row is reached the
; screen (rows 2-24) is kept in a RAM mirror (screen_buffer); each new line scrolls the
; mirror one row up in RAM and the mirror is then copied to VRAM in one go.
; Only used in 40/80 column text screens with 24 rows and no redirected output.
; Assumes the text name table is at VRAM 0000h (default for SCREEN 0).
;-----------------------------------------------------------------------------------

;Called from INIT_values (output not redirected). Sets fast_screen_ok when possible
INIT_fast_screen:
  ld  a,(CRTCNT)
  cp  24
  ret nz      ;only 24 rows screens
  ld  a,(WIDTH)   ;LINLEN
  cp  33
  ret c     ;32 columns (SCREEN 1): use BDOS output
  ld  b,a     ;b=LINLEN
  cp  41
  ld  a,40
  ld  hl,40
  ld  de,23*40
  jr  c,screen_is_40
  ld  a,80
  ld  hl,80
  ld  de,23*80
screen_is_40:
  ld  (screen_row_len),hl ;characters per row in VRAM
  ld  (screen_rows23),de  ;bytes in 23 rows = VRAM offset of the last row
  sub b
  srl a
  ld  (screen_margin),a ;text is centered when LINLEN < 40/80
  ld  a,1
  ld  (fast_screen_ok),a
  ret

fast_print_line:
  ld  a,(screen_mirror_on)
  or  a
  jr  nz,fast_to_mirror

;screen not scrolled yet: write the line directly in VRAM at the cursor row
  ld  hl,0
  ld  a,(LOCATE)    ;cursor row (1=top)
  dec a
  jr  z,fast_row_top
  ld  de,(screen_row_len)
  ld  b,a
fast_row_loop:
  add hl,de
  djnz  fast_row_loop
fast_row_top:
  ld  a,(screen_margin)
  ld  c,a
  ld  b,0
  add hl,bc
  call  set_VDP_write_address
  ld  c,VDP_DATA
  ld  hl,line_file_2_PRINT
fast_vram_loop:
  ld  a,(hl)
  or  a		;end of the line (0, not "$": a file name can contain "$")
  jr  z,fast_vram_done
  outi
  jr  fast_vram_loop
fast_vram_done:
  ei
  jr  fast_next_row

;screen already scrolled: put the line in the last row of the RAM mirror
fast_to_mirror:
  ld  hl,(screen_rows23)
  ld  de,screen_buffer
  add hl,de
  ex  de,hl     ;de=last row of the mirror
  push  de
  ld  a,(screen_row_len)
  ld  b,a
  ld  a," "
fast_mirror_clear:
  ld  (de),a
  inc de
  djnz  fast_mirror_clear
  pop de
  ld  a,(screen_margin)
  add a,e
  ld  e,a
  jr  nc,fast_mirror_nc
  inc d
fast_mirror_nc:
  ld  hl,line_file_2_PRINT
fast_mirror_copy:
  ld  a,(hl)
  or  a		;end of the line (0, not "$": a file name can contain "$")
  jr  z,fast_next_row
  ld  (de),a
  inc hl
  inc de
  jr  fast_mirror_copy

;next row: increase cursor row, or scroll when on the last row
fast_next_row:
  ld  a,(LOCATE)
  cp  24
  jr  nz,fast_inc_row

  ld  a,(screen_mirror_on)
  or  a
  jr  nz,scroll_mirror
;first scroll: read rows 2-24 from VRAM into the mirror
  inc a
  ld  (screen_mirror_on),a
  ld  hl,(screen_row_len)
  call  set_VDP_read_address
  ld  hl,screen_buffer
  ld  bc,(screen_rows23)
  call  read_VDP_block
  jr  screen_redraw
;next scrolls: move the mirror one row up
scroll_mirror:
  ld  hl,(screen_row_len)
  ld  de,screen_buffer
  add hl,de
  ld  bc,(screen_rows23)
  ldir
screen_redraw:
;blank the last row
  ld  hl,(screen_rows23)
  call  set_VDP_write_address
  ld  a,(screen_row_len)
  ld  b,a
  ld  a," "
screen_blank_loop:
  out (VDP_DATA),a
  djnz  screen_blank_loop
;mirror -> rows 1-23
  ld  hl,0
  call  set_VDP_write_address
  ld  hl,screen_buffer
  ld  bc,(screen_rows23)
  call  write_VDP_block
  ei
  ret
fast_inc_row:
  inc a
  ld  (LOCATE),a
  ret

;IN: hl=VRAM address
set_VDP_write_address:
  di
  ld  a,l
  nop
  out (VDP_CMD),a
  ld  a,h
  or  040h
  out (VDP_CMD),a
  ret
set_VDP_read_address:
  di
  ld  a,l
  nop
  out (VDP_CMD),a
  ld  a,h
  out (VDP_CMD),a
  ret

;IN: hl=source, bc=number of bytes (>0)
write_VDP_block:
  ld  a,c
  or  a
  ld  a,b
  ld  b,c
  ld  c,VDP_DATA
  jr  z,write_VDP_block_loop
  inc a
write_VDP_block_loop:
  otir
  dec a
  jr  nz,write_VDP_block_loop
  ret

;IN: hl=destination, bc=number of bytes (>0)
read_VDP_block:
  ld  a,c
  or  a
  ld  a,b
  ld  b,c
  ld  c,VDP_DATA
  jr  z,read_VDP_block_loop
  inc a
read_VDP_block_loop:
  nop
  nop
  ini
  jr  nz,read_VDP_block_loop
  dec a
  jr  nz,read_VDP_block_loop
  ret

fast_screen_ok: db  0   ;1=use fast screen output
screen_mirror_on: db  0   ;1=RAM mirror of the screen is in use
screen_margin:  db  0   ;left margin (characters)
screen_row_len: dw  0   ;characters per VRAM row (40/80)
screen_rows23:  dw  0   ;23 * screen_row_len

;-----------------------------------------------------------------------------------
; /W : wide list. All entries are collected, sorted alphabetically and printed in
; columns of 16 characters (5 columns in 80 column mode). Directories first (in
; lowercase), then the files.
; No long file names.
; Records (14 bytes: name ASCIIZ 13 + directory flag) and a table of pointers to
; them (sorted instead of the records) are kept in free memory above the screen mirror.
;-----------------------------------------------------------------------------------
WIDE_MAX  equ 800   ;maximum number of entries
wide_area equ screen_buffer+2048
wide_sent equ wide_area   ;14 bytes: empty directory name, sorts before everything
wide_sentptr  equ wide_area+14  ;pointer to wide_sent (= entry -1 of the pointer table)
wide_ptrs equ wide_area+16  ;WIDE_MAX pointers
wide_records  equ wide_ptrs+2*WIDE_MAX

wide_listing:
  xor a
  ld  (wide_sent),a
  ld  a,010h
  ld  (wide_sent+13),a    ;directory flag
  ld  hl,wide_sent
  ld  (wide_sentptr),hl
  ld  hl,0
  ld  (wide_count),hl
  ld  hl,wide_records
  ld  (wide_rec_end),hl
  ld  hl,wide_ptrs
  ld  (wide_ptr_end),hl
;FIB contains the first entry (found by _FFIRST)
wide_collect:
  ld  hl,(wide_count)
  ld  de,WIDE_MAX
  or  a
  sbc hl,de
  jr  nc,wide_next_entry  ;table full: skip the rest
  ld  hl,(wide_ptr_end)
  ld  de,(wide_rec_end)
  ld  (hl),e
  inc hl
  ld  (hl),d
  inc hl
  ld  (wide_ptr_end),hl
  ld  hl,FIB+1
  ld  bc,13
  ldir
  ld  a,(FIB+14)
  and 010h
  ld  (de),a      ;directory flag
  inc de
  ld  (wide_rec_end),de
  ld  hl,(wide_count)
  inc hl
  ld  (wide_count),hl
  ld  a,(FIB+14)
  bit 4,a
  jr  z,wide_is_file
  ld  hl,(dirs_counter)
  inc hl
  ld  (dirs_counter),hl
  jr  wide_next_entry
wide_is_file:
  ld  hl,(files_counter)
  inc hl
  ld  (files_counter),hl
wide_next_entry:
  ld  c,41h     ;next entry
  ld  ix,FIB
  call  BDOS
  or  a
  jr  z,wide_collect

  call  wide_sort

;number of columns = screen width / 16 (at least 1)
  ld  a,(WIDTH)
  srl a
  srl a
  srl a
  srl a
  jr  nz,wide_cols_ok
  inc a
wide_cols_ok:
  ld  (wide_cols),a
  ld  hl,(wide_count)
  ld  (wide_left),hl
  ld  hl,wide_ptrs
  ld  (wide_pos),hl
wide_row:
  ld  hl,(wide_left)
  ld  a,h
  or  l
  jp  z,no_more_files
  call  DEC_lines_printed ;pause every screen
  ld  hl,line_file_2_PRINT
  ld  de,line_file_2_PRINT+1
  ld  bc,79
  ld  (hl)," "
  ldir
  ld  de,line_file_2_PRINT
  ld  a,(wide_cols)
  ld  b,a
wide_col:
  push  bc
  push  de      ;start of this column
  ld  hl,(wide_pos)
  ld  e,(hl)
  inc hl
  ld  d,(hl)
  inc hl
  ld  (wide_pos),hl
  ex  de,hl     ;hl=record
  ld  bc,13
  push  hl
  add hl,bc
  ld  a,(hl)      ;directory flag (0 or 10h)
  pop hl
  ld  c,a
  pop de
  push  de      ;de=output position
  ld  b,0     ;b=characters copied (stops counting at 8)
  ld  a,(hl)
  cp  "."
  jr  nz,wide_copy_name
  ld  b,255     ;"." and "..": no alignment
wide_copy_name:
  ld  a,(hl)
  or  a
  jr  z,wide_name_done
  cp  "."
  jr  nz,wide_not_dot
wide_pad:       ;align the extension: pad the name to 8 characters
  ld  a,b
  cp  8
  jr  nc,wide_dot
  ld  a," "
  ld  (de),a
  inc de
  inc b
  jr  wide_pad
wide_dot:
  ld  a,"."
  jr  wide_store
wide_not_dot:
  bit 4,c
  jr  z,wide_store
  cp  "A"
  jr  c,wide_store
  cp  "Z"+1
  jr  nc,wide_store
  add a,20h     ;directories in lowercase
wide_store:
  ld  (de),a
  inc hl
  inc de
  ld  a,b
  cp  8
  jr  nc,wide_copy_name
  inc b
  jr  wide_copy_name
wide_name_done:
  ld  (wide_row_end),de
  pop de
  ld  hl,16
  add hl,de
  ex  de,hl     ;de=start of next column
  ld  hl,(wide_left)
  dec hl
  ld  (wide_left),hl
  pop bc
  ld  a,h
  or  l
  jr  z,wide_row_full
  djnz  wide_col
wide_row_full:
  ld  hl,(wide_row_end)
  ld  (hl),0	;end of the line (a file name can contain "$")
  call  end_print_line
  jp  wide_row

;sort the pointer table alphabetically (insertion sort)
wide_sort:
  ld  hl,(wide_ptr_end)
  ld  (ws_limit),hl
  ld  hl,wide_ptrs+2
  ld  (ws_i),hl
ws_outer:
  ld  hl,(ws_i)
  ld  de,(ws_limit)
  or  a
  sbc hl,de
  ret nc      ;all entries done
  ld  hl,(ws_i)
  ld  e,(hl)
  inc hl
  ld  d,(hl)
  ld  (ws_key),de
  ld  hl,(ws_i)   ;hl=&ptr[j], j=i
ws_inner:
  push  hl
  dec hl
  ld  d,(hl)
  dec hl
  ld  e,(hl)      ;de=ptr[j-1]
  ld  hl,(ws_key)
  call  wide_compare
  pop hl
  jr  c,ws_place    ;ptr[j-1] < key
  jr  z,ws_place    ;equal
  dec hl      ;ptr[j]=ptr[j-1]
  ld  d,(hl)
  dec hl
  ld  e,(hl)
  inc hl
  inc hl
  ld  (hl),e
  inc hl
  ld  (hl),d
  dec hl
  dec hl
  dec hl      ;j=j-1
  jr  ws_inner
ws_place:
  ld  de,(ws_key)
  ld  (hl),e
  inc hl
  ld  (hl),d
  ld  hl,(ws_i)
  inc hl
  inc hl
  ld  (ws_i),hl
  jr  ws_outer

;compare entries (de) and (hl): directories first, then by name.
;Carry: (de) sorts before (hl)   Zero: equal
wide_compare:
  push  de
  push  hl
  ld  bc,13
  add hl,bc
  ld  a,(hl)      ;directory flag of (hl)
  ex  de,hl
  add hl,bc
  ld  c,(hl)      ;directory flag of (de)
  pop hl
  pop de
  cp  c
  ret nz      ;different: the directory goes first
  ld  b,13
wide_cmp_loop:
  ld  a,(de)
  cp  (hl)
  ret nz
  or  a
  ret z
  inc de
  inc hl
  djnz  wide_cmp_loop
  xor a
  ret

wide_mode:  db  0   ;1=/W
wide_cols:  db  0
wide_count: dw  0
wide_left:  dw  0
wide_pos: dw  0
wide_ptr_end: dw  0
wide_rec_end: dw  0
wide_row_end: dw  0
ws_i: dw  0
ws_limit: dw  0
ws_key: dw  0


;Prints line_file_2_PRINT (ended by 0) with BDOS, character by character, and a CR/LF.
;BDOS function 9 can't be used: it stops at the first "$" and a file name can contain one.
print_line_BDOS:
  ld  hl,line_file_2_PRINT
print_line_BDOS_loop:
  ld  a,(hl)
  or  a
  jr  z,print_line_BDOS_end
  ld  e,a
  ld  c,2
  push  hl
  call  BDOS
  pop hl
  inc hl
  jr  print_line_BDOS_loop
print_line_BDOS_end:
  ld  de,end_1RET_TXT
  ld  c,9
  jp  BDOS

dir_TXT:  db "  <dir>    ",0
;----------------------------------------------------------------------------------------

Parameters:
  ld  hl,DMA
  ld  b,(HL)
  inc b
  dec b
  jp  z,ver_todo    ; Jump if no parameter


  ld  hl,(DMA)  ; Esto pone un 255 al final de la entrada de parámetros. Necesario para los MSX1.
  ld  h,0
  ld  bc,DMA +1
  add hl,bc
  ld  (hl),255



;Mostrar solo ficheros (s)

  ld  hl,DMA
  ld  b,(HL)
  ld  c,"S"   ; Mostrar ficheros sistema
  call  SeekParameter
  cp  255
  jp  z,Done    ; Jump if syntax error
  or  a
  jr  z,no_S
  ld  a,(atributos_a_mostrar)
  set 2,a ; mostrar ficheros sistema
  ld  (atributos_a_mostrar),a
;------------------------------
;Mostrar solo lectura (h)
no_S:

  ld  hl,DMA
  ld  b,(HL)
  ld  c,"F"   ; Mostrar solo ficheros
  call  SeekParameter
  cp  255
  jp  z,Done    ; Jump if syntax error
  or  a
  jr  z,no_F
  ld  a,(atributos_a_mostrar)
  res 4,a ; quitamos que se vean subdirectorios
  ld  (atributos_a_mostrar),a
;------------------------------

no_F:
  ld  hl,DMA
  ld  b,(HL)
  ld  c,"P"   ; No pausar
  call  SeekParameter
  cp  255
  jp  z,Done    ; Jump if syntax error
  or  a
  jr  z,no_P

  ld  a,1
  ld  (no_wait_key),a

no_P:


;Mostrar solo lectura (h)
  ld  hl,DMA
  ld  b,(HL)
  ld  c,"H"   ; mostrar solo lectura
  call  SeekParameter
  cp  255
  jp  z,Done    ; Jump if syntax error
  or  a
  jr  z,no_H
  ld  a,(atributos_a_mostrar)
  set 1,a ; activamos que se vean ocultos
  ld  (atributos_a_mostrar),a
no_H:
  ld  hl,DMA
  ld  b,(HL)
  ld  c,"W"   ; wide list
  call  SeekParameter
  cp  255
  jp  z,Done    ; Jump if syntax error
  or  a
  jr  z,no_W
  ld  a,1
  ld  (wide_mode),a
no_W:

  ;jr ver_todo
  call clearDMA_parameters
  ld  (hl),20h
  inc hl
  ld  (hl),0FFh
  inc hl
  ld  (hl),0FFh

  ;set pointer to path or filename
  ld  hl,DMA
next_value_DMA_search_name:
  inc hl
  ld  a,(hl)
  cp  20h
  jr  z,next_value_DMA_search_name
  cp  0FFh
  jr  z,ver_todo

  ld  de,search_string
more_write_search_string:
  ldi
  ld  a,(hl)
  cp  20h
  jr  z,search_string_end
  cp  0FFh
  jr  z,search_string_end
  jr  more_write_search_string

search_string_end:
  ;In "search_string", we have the path in ASCIIZ format.
  ld  de,search_string
  ld  b,0 ;without volume
  ld  c,05Bh;parse pathname
  call  BDOS
;a la salida en B estos bits:
;b0 - set if any characters parsed other than drive name
;b1 - set if any directory path specified
;b2 - set if drive name specified
;b3 - set if main filename specified in last item
;b4 - set if filename extension specified in last item
;b5 - set if last item is ambiguous
;b6 - set if last item is "." or ".."
;b7 - set if last item is ".."
  ld  a,c
  ld  (DRIVE_to_DIR),a

  ;check . y ..
  bit 6,b ;ni "." ni ".."
  ret z

  bit 7,b
  jr  nz,put_previous_directory

  ;es un "."
  ld  (hl),0

  ;es un ".."
put_previous_directory:
  inc hl
  inc hl
  ld  (hl),5Ch;\
  inc hl
  ld  (hl),0
  ret




ver_todo:
fin_DMA:
  ld  c,019h  ;current drive
  call  BDOS
  inc a
  ld  (DRIVE_to_DIR),a

  ld  de,all_string
  ret
;----------------------------------------------------------
INI_LFN:




ok_path:

root_directory_to_check:  ld  a,00;self!!
  or  a
  jr  z,no_ROOT_directory

  ld  a,1
  ld  (root_directory_no_check_cluster+1),a

;ROOT directory
  ld  a,(DRIVE_to_DIR)
  ld  (path_FIB+25),a
  ld  de,(Drive_parameters+13);First root directory sector number
  xor a
  jp  ROOT_sector_OK


no_ROOT_directory:

posicion_ultima_path_TXT: ld  hl,0000 ;self!!

  ld  (hl),0
  ld  de,WHOLE_PATH_STRING
  ld  b,010000b ;bit 4   subdirectory
  ld  ix,path_FIB
  ld  c,040h  ;find first
  call  BDOS




;
;     Parameters:    C = 40H (_FFIRST)
;                   DE = Drive/path/file ASCIIZ string
;                                or fileinfo block pointer
;                        HL = filename ASCIIZ string (only if
;                                DE = fileinfo pointer)
;                         B = Search attributes
;                   IX = Pointer to new fileinfo block
;     Results:       A = Error
;                 (IX) = Filled in with matching entry

  ld  a,0
  ld  (root_directory_no_check_cluster+1),a

  ld  a,(sectors_per_cluster) ;inicializa contador sectores en cluster
  ld  (sectors_left_in_cluster),a


  ;ld c,01Ah ;set buffer disk transfer para sectores directorio
  ;ld de,buffer_disk
  ;call BDOS


  ld  hl,(path_FIB+19)  ;first cluster of directory
  ld  (cluster_p),hl  ;guardamos primer cluster del directorio
  ;hl=cluster number
  call  cluster2sector
  ;out hl,a


  ex  de,hl





ROOT_sector_OK:
  ld  (actual_sector_directory),de
  ld  (actual_sector_directory+2),a


  call  read_2_sectors_directory

  ret

;--------------------------------------------------------------
clearDMA_parameters:

  ld  hl,DMA

next_value_DMA:
  inc hl
  ld  a,(hl)
  cp  0FFh
  ret z ;fin DMA? entonces vuelve

  cp  20h
  jr  z,next_value_DMA

  cp  "/"
  jr  nz,next_value_DMA

clear_parameter:

  ld  (hl),20h
  inc hl
  ld  a,(hl)
  cp  0FFh
  ret z
  cp  20h
  jr  nz,clear_parameter
  jr  next_value_DMA+1
;----------------------------------------------------------------
error_TXT_INI:  db  CR,LF,"*** "
error_TXT:  ds  64


error_exit:
  ;coge numero de error en B
  ld  c,65h
  call  BDOS

  ;coge texto error
  ld  de,error_TXT
  ld  c,66h
  call  BDOS

  ld  de,error_TXT-1
next_error_TXT:
  inc de
  ld  a,(de)
  or  a
  jr  nz,next_error_TXT
  ld  a,"$"
  ld  (de),a


  ld  de,error_TXT_INI
  jp  Done
; Seek Parameter Routine
; In: B = Length of parameters zone, C = Character, HL = Pointer address
; Out: A = 0 if Parameter not found or 255 if syntax error, DE = HlpMes if syntax error
; Modify AF, BC, HL

SeekParameter:
  inc hl
  ld  a,(hl)
  cp  02Fh    ; Seek '/' character
  jr  nz,ParamBCL
  inc hl
  ld  a,(hl)
  and 0dfh
  cp  c   ; Compare found character with the input character
  ret z
  call  SyntaxCheck
  cp  255
  ret z
ParamBCL:
  djnz  SeekParameter
  xor a
  ret
SyntaxCheck:
  push  hl
  push  bc
  cp  "F"   ; 'F' character
  jr  z,SyntaxOK
  cp  "H"   ; 'H' character
  jr  z,SyntaxOK
  cp  "S"   ; 'S' character
  jr  z,SyntaxOK
  cp  "P"   ; 'P' character
  jr  z,SyntaxOK
  cp  "W"   ; 'W' character
  jr  z,SyntaxOK
  ld  de,HlpMes
  ld  a,255   ; Syntax error
SyntaxOK:
  pop bc
  pop hl
  ret
;-------------------------------

write_directory_TEXT:
  ld  de,WHOLE_PATH_STRING+3
  ld  c,05Eh;GET WHOLE PATH STRING
  call  BDOS

  ld  (posicion_ultima_path_TXT+1),hl

  ld  (hl),"$"

  ;comprueba root
  and a
  sbc hl,de ;iguales ->root directory
  ld  a,0
  jr  nz,no_in_ROOT_directory
  ld  a,1

no_in_ROOT_directory:

  ld  (root_directory_to_check+1),a;decimos que es ROOT o no

  ld  a,(DRIVE_to_DIR)
  add a,40h ;A, B,C...
  ld  (WHOLE_PATH_STRING),a
  ld  a,":"
  ld  (WHOLE_PATH_STRING+1),a
  ld  a,5Ch;\
  ld  (WHOLE_PATH_STRING+2),a


  ;conseguimos FIB del directorio




  ld  de,Directory_TXT
  ld  c,9
  call  BDOS

; ld  hl,WHOLE_PATH_STRING-1
;next_directory_character:
; inc hl
; ld  a,(hl)
; or  a
; jr  nz,next_directory_character


  ld  de,WHOLE_PATH_STRING
  ld  c,9
  call  BDOS

  ld  de,end_RET_TXT
  ld  c,9
  call  BDOS


  ret
;-------------------------------
Done:
;IN:  de,texto salida
  ei        ; Activa interrupciones. Por si acaso se han quedado desactivadas.

  ld  c,9
  call  BDOS      ; Imprime el mensaje de error.
  rst 0
;----------------------------------------------
DEC_lines_printed:

    ld  a,(no_wait_key)
    or  a
    ret nz



    ld  a,(lines_left)
    dec a
    ld  (lines_left),a
    or  a
    ret nz

    call  RESET_LINES


    ld  de,wait_files_TXT
    ld  c,9
    call  BDOS

    ld  hl,(LOCATE)
    push  hl

    ld  c,8;espera una tecla
    call  BDOS

    pop hl
    ;inc  hl
    ld  (LOCATE),hl

    ld  b,26

more_BS:  ld  e,07Fh  ;BS!! Delete backwards!!
    ld  c,2
    push  bc
    call  BDOS
    pop bc
    djnz  more_BS

    ;ld a, 13
    ;call CHPUT
    ;ld a, 10
    ;call CHPUT



    ret




lines_screen:   equ 0F3B1h
lines_left:   db  0 ;number of line printed... for WAIT

RESET_LINES:

    ld  a,(lines_screen)
    dec a

    ld  (lines_left),a
    ret
;---------------------------------------------------------------------------
;--- NOMBRE: CHKDOS2
;      Obtiene la version de MSX-DOS
;    ENTRADA:   -
;    SALIDA:    A=Version 1, 2
;    REGISTROS: F
;    LLAMADAS:  -
;    VARIABLES: -

CHKDOS2:


    ;Comprueba la version del DOS

  ;doscall  _DOSVER ;y establece DV.
  ld  c,06Fh;check DOS version
  call  BDOS
  or  a
  ld  a,1
  jr  nz,CD2END
  ld  a,b
  cp  2
  ld  a,1
  jp  c,CD2END

  ;DOS2 or NEXTOR
  ;comprueba si es Nextor!!
  ld  c,06Fh;DOS version
  ld  B,05Ah
  ld  HL,1234h
  ld  de,0ABCDh
  ld  IX,0
  call  BDOS

  push  IX
  POP HL
  ld  a,H;diferente de 0 ->Nextor
  or  a
  ld  a,2
  jp  z,CD2END


  ld  a,3;->Nextor

CD2END: ld  (DOS_VERSION),a



  ret
;------------------------------------------------------------------------------------------------

INIT_values:



  ;check conosoile output
  ld  c,070h; GET/SET REDIRECTION STATE (70H)
  ld  a,00; get redirection state
  call  BDOS
  ;check output
  bit 1,b
  jr  z,normal_output_set
  ld  a,1
  ld  (no_wait_key),a
  jr  output_set    ;redirected output: no direct VRAM output
normal_output_set:
  call  INIT_fast_screen
output_set:
  call  take_drive_INFO


  ;check driver version... Nextor???
  ld  a,(Drive_info+1);driver slot
  ld  d,a
  xor a
  ld  e,0FFh
  ld  c,078h;Get information about a device driver
  ld  hl,Device_drive_Info
  call  BDOS

  ;reset pointer search filename
  ld  hl,buffer_directory+512
  ld  (puntero_busqueda_HL),HL
  ld  a,16;entradas en 1 sector
  ld  (entradas_pendientes_busqueda),a


  call  RESET_LINES

  ld  a,(WIDTH)
  ld  l,a
  ld  h,0

  ld  de,27 ;nombre archivo+tamaño+...
  and a ;quitamos carry
  sbc hl,de

  ld  (long_LFN_to_write+1),hl


  ld  a,(lines_left);por el Directory of
  dec a
  dec a
  ld  (lines_left),a
  ret

;--------------------------------------------------------------------------------------------
Long_File_Name: ;solo en Nextor

  ld  de,FIB+1;nombre fichero ASCIIZ
  ld  hl,filename_to_check
  ld  c,5Ch;parse filename
  call  BDOS


;
;
;
;
;
;
;
;
;
;
;
;
;
;
; ;call take_File_Info_Block
;
;
;
; ld  c,5Bh
; ld  de,filename_to_check
; call  BDOS
;
;
; ld  (fn_termination),de
; ld  (fn_last_item),hl
;
;
; ; filename =   HL  ... DE
;
; push  hl
;
;
; ex  de,hl
;
; or  a
; sbc hl,de
; push  hl
; pop bc
; ld  de,filename
; pop hl
; push  hl
;
; ldir
; ex  de,hl
; ld  (hl),0  ;end of filename
;
;
; pop hl  ;principio filename
;
;
; ;push de
; ;push hl
;
; ld  de,(fn_termination)
; ld  hl,(fn_last_item)
; ld  de,filename_to_check
; and a
; sbc hl,de
;

; ;pop  hl
; ;pop  de
;
;
; jp  nz,read_path
;
;current_directory:
;;3.69 GET CURRENT DIRECTORY (59H)
;;
;;
;;     Parameters:    C = 59H (_GETCD)
;;                    B = Drive number (0=current, 1=A: etc)
;;                   DE = Pointer to 64 byte buffer
;;     Results:       A = Error
;;                   DE = Filled in with current path
;
;
;
; ld  a,(Drive_parameters)
; ld  b,a
;
; ld  de,path_file+1
; ld  c,59h
; call  BDOS
;
; jp  ok_path
;
;read_path:
; ;cogemos el path
;
; ld  hl,(fn_last_item)
;
; ld  de,filename_to_check
; and a
; sbc hl,de
; push  hl
; pop bc
;
; ld  hl,filename_to_check
; ld  de,path_file
;
; ldir
;
; ex  de,hl
; ld  (hl),0
;------------------------------------------------------------------------------------

  ;xor  a
  ;ld (fin_primera_busqueda),a
  ;call read_2_sectors_directory
search_filename_directory_loop:




  call  search_filename_in_directory
  or  a ;encontrado
  jp  z,file_found_in_directory

  cp  fin_trozo ;error
  jp  nz,RETURN_SET

  ;ld a,1
  ;ld (fin_primera_busqueda),a

  ;reset pointer search filename
  ld  hl,buffer_directory+512
  ld  (puntero_busqueda_HL),HL
  ld  a,16;entradas en 1 sector
  ld  (entradas_pendientes_busqueda),a

  call  INC_sectors_directory
  jp  c,RETURN_SET;fin directorio

  ;error vuelve con carry
  call  read_2_sectors_directory;lee otro sector
  jr  search_filename_directory_loop
file_found_in_directory:
  ld  a,1
  ld  (LFN_exists),a
  ret

fin_primera_busqueda: db  0
fin_trozo equ 1 ;termina busqueda en bloque leido
error_fin_directorio equ 2  ;no encontrado en todo el directorio
error_no_LFN_en_entrada equ 3
;-----------------------------------------------------------------------------------
read_2_sectors_directory:

  ;copiamos sector leido antes del otro
  ld  hl,buffer_directory+200h
  ld  de,buffer_directory
  ld  bc,0200h
  ldir

  ;Nextor Driver??
  ld  a,(Device_drive_Info+4)
  bit 7,a
  jr  read_sector_no_NEXTOR ;Nextor 3 fix: always use _RDDRV (73h), driver-direct DSKIO read broke in Nextor 3

  ld  hl,buffer_directory+200h
  ld  (dest_RAM),hl

  ld  de,(actual_sector_directory)
  ld  a,(actual_sector_directory+2)

read_PHY_sector_sub:

  ld  b,a


  and a;quitamos carry
  ld  hl,(first_sector_drive_PHY)
  add hl,de
  ld  a,(first_sector_drive_PHY+2)
  jr  nc,no_INC_3_byte_PHY
  inc a
no_INC_3_byte_PHY:
  add a,b

  ;ponemos sector fisico en tabla antes de llamar
  ld  (sector_to_read),hl
  ld  (sector_to_read+2),a





;  A  = Driver unit, starting at 0
;  Cy = 0 for reading sectors, 1 for writing sectors
;  B  = Number of sectors to read/write
;  C  = 1????
; DE = Adress with 4 byte sector number
; HL = source/destination address for the transfe



  ld  a,(Drive_info+1)
  ld  de,04160h; DRV_DSKIO
  ld  b,0FFh
  ld  c,07Bh;routine in device driver
  ld  hl,tabla_registros
  call  BDOS
  ret





read_sector_no_NEXTOR:


  ld  c,01Ah ;set buffer disk transfer
  ld  de,buffer_directory+200h
  call  BDOS

  ld  de,(actual_sector_directory)
  ld  a,(actual_sector_directory+2)

  ld  h,0
  ld  l,a

  ld  a,(DRIVE_to_DIR);unidad +1
  dec a

  ld  b,1 ;numero de sectores
  ld  c,073h
  call  BDOS  ;distinto sector?-> lee
  ret

tabla_registros:
    db  028h    ;F
Drive_unit: db  00;self!! ;A
    db  1h;self!! ;C
number_sectors: db  1   ;B
sector_number_ADRESS: dw  sector_to_read    ;DE

dest_RAM: dw  buffer_directory+200h;HL


sector_to_read: db  0,0,0,0 ;4 bytes!!


INC_sectors_directory:


root_directory_no_check_cluster:  ld  a,00  ;self!!
  or  a
  jr  nz,no_end_cluster ;root directory

  ld  a,(sectors_left_in_cluster)
  dec a
  ld  (sectors_left_in_cluster),a
  or  a ;fin cluster??
  jr  nz,no_end_cluster

  ld  hl,(cluster_p)
  call  read_FAT_cluster  ;hl:cluster number
  ld  (cluster_p),hl
  ret c;fin directorio!!

  ;hl=cluster number
  call  cluster2sector
  ;out hl,a
  ld  (actual_sector_directory),hl
  ld  (actual_sector_directory+2),a

  ld  a,(sectors_per_cluster) ;initialize sector counter within cluster

  ld  (sectors_left_in_cluster),a
  and a
  ret

no_end_cluster:
  ld  de,(actual_sector_directory)
  ld  a,(actual_sector_directory+2)
  ld  c,a

  inc de
  ld  a,d
  or  e
  jr  nz,no_INC_3byte_1
  inc c
no_INC_3byte_1:
  ld  a,c
  ld  (actual_sector_directory),de
  ld  (actual_sector_directory+2),a

  and a ;quita carry
  ret

entradas_pendientes_busqueda: db  0
puntero_busqueda_HL:    dw  0
sectors_left_in_cluster:  db  0
;-----------------------------------------------------------------------
search_filename_in_directory:
;IN:
; filename2PRINT  :nombre fichero CACAXX~1.ROM +0
;OUT: a=0 Encontrado
; a=fin_trozo no encontrado en bloque leido
; a>fin trozo -> no encontrado
;
; LFN : nombre largo del fichero, ASCIIZ


  ;ld a,(fin_primera_busqueda)
  ;or a
  ;ld hl,buffer_directory
  ;ld a,16*2;entradas en 2 sectores
  ;jr z,no_primera_busqueda
  ld  hl,(puntero_busqueda_HL)
  ld  a,(entradas_pendientes_busqueda)
;no_primera_busqueda:
  jr  first_check_filename
loop_busqueda_entrada_directorio:
  ld  (entradas_pendientes_busqueda),a
  ld  (puntero_busqueda_HL),HL

  ld  a,(hl)
  or  a
  jp  z,findirectorio
first_check_filename:
  ld  b,11;nombre
  ld  de,filename_to_check


check_name:
;IN:  HL directorio buffer
; DE filename
; B numero caracteres a comprobar
  ld  a,(de)
  cp  (hl)
  jp  nz,not_match_filename
  inc hl
  inc de
  djnz  check_name



  ;encontrado!!!


  ld  HL,(puntero_busqueda_HL)
  jp  read_LFN_backwards


not_match_filename:
  ld  HL,(puntero_busqueda_HL)
  ld  bc,20h
  add hl,bc






  ld  a,(entradas_pendientes_busqueda)
  dec a
  jp  nz,loop_busqueda_entrada_directorio


  ld  a,fin_trozo
  ret

findirectorio:
  ld  a,error_fin_directorio
  ret

;----------------------------------------------------
;-----------------
read_FAT_cluster:
;IN:
;ix,Drive_parameters  ;
;hl,cluster

;OUT:
;hl:next cluster
;carry set= end of file




  push  hl
  ld  c,1Ah
  ld  de,buffer_disk
  call  BDOS
  pop hl


  ld  ix,Drive_parameters  ;

;Also, position +28 of the returned parameter block contains the filesystem type:
;0: FAT12
;1: FAT16
;255: Other
  ld  a,(ix+28)
  or  a
  jp  z,read_FAT_cluster_F12

  cp  0FFh
  ld  de,t_sistema_invalido
  jp  z,Done

  ;FAT16

  push  hl;cluster number
  ld  l,h
  ld  h,0 ;sector amount

  ld  e,(ix+4)  ;first FAT sector
  ld  d,(ix+5)
  add hl,de


  ld  a,(ix+0) ;(a=1,B=2)
  dec a     ;a=0,B=1





  ex  de,hl ;parte baja de la unidad


  ;comprobar mismo sector
  ld  hl,(actual_sector_FAT)
  or  a ;quit carry
  sbc hl,de
  jp  z,readed_FAT_sector;same sector




  ;save current FAT sector
  ld  (actual_sector_FAT),de


  ld  a,(Device_drive_Info+4)
  bit 7,a
  jp  read_FAT_sector_no_NEXTOR ;Nextor 3 fix: always use _RDDRV (73h)

  ld  hl,buffer_disk
  ld  (dest_RAM),hl
  xor a;first sectors of partition

  call  read_PHY_sector_sub
  jp  readed_FAT_sector

read_FAT_sector_no_NEXTOR:
  ld  hl,0
  ld  a,(path_FIB+25)
  dec a
  ld  b,a
  ;ld a,1


  ld  a,b
  ld  b,1;cantidad de sectores
  ld  c,073h
  call  BDOS  ;distinto sector?-> lee


;Read absolute sectors from drive (_RDDRV, 73h)
;Parameters:   C = 73H (_RDDRV)
;A = Drive number (0=A: etc.)
;B = Number of sectors to read
;HL:DE = Sector number
;Results:          A = Error code (0=> no error)
readed_FAT_sector:
  pop hl;cluster number

  ld  h,0

  add hl,hl
  ld  bc,buffer_disk

  add hl,bc

  ld  e,(hl)
  inc hl
  ld  d,(hl)

  ex  de,hl

;0000h  Available Cluster
;0002h-FFEFh  Used, Next Cluster in File
;FFF0h-FFF6h  Reserved Cluster
;FFF7h  BAD Cluster
;FFF8h-FFFF   Used, Last Cluster in File
  ld  a,0F7h
  cp  l
  jp  nc,RETURN_UNSET
  ld  a,0FFh
  cp  h
  jp  z,RETURN_SET
  or  a ;quit carry
  ret
;-------------------------------------------------------------------
read_FAT_cluster_F12:

;IN:
;ix,Drive_parameters  ;
;hl,cluster

;OUT:
;hl:next cluster
;carry set= end of file


;   Subroutine get FAT entry content
;      Inputs  HL = clusternumber, IX = pointer to DPB
;      Outputs HL = clusterentry content, Zx set if entry is free, DE = pointer to FAT buffer

  push  hl  ;guarda numero de cluster

  ld  a,(FAT12_leida)
  or  a
  jp  nz,FAT_ya_leida

  ld  c,01Ah ;set buffer disk transfer
  ld  de,buffer_FAT12
  call  BDOS


  ld  e,(ix+4)  ;first FAT sector
  ld  d,(ix+5)
  ld  hl,0
  ld  a,(file_info_block+25)
  dec a
  ld  b,a
  ;ld a,1


  ld  a,b
  ld  b,24
  ld  c,073h
  call  BDOS  ;distinto sector?-> lee


  ld  a,1
  ld  (FAT12_leida),a

FAT_ya_leida:

  pop hl  ;recupera numero de cluster

  ld  de,buffer_FAT12; pointer to FAT buffer of drive

;A41F4:
; ld  e,(ix+013H)
;        ld d,(ix+014H)   ; pointer to FAT buffer of drive

        push  de
        ld  e,l
        ld  d,h
        srl h
        rr  l
        rra
        add hl,de
        pop de
        add hl,de
        rla
        ld  a,(hl)
        inc hl
        ld  h,(hl)
        jr  nc,A421A
        srl h
        rra
        srl h
        rra
        srl h
        rra
        srl h
        rra
A421A:  ld  l,a
        ld  a,h
        and 00FH
        ld  h,a
        or  l
;FAT12
;Meaning
;0x00  Unused
;0xFF0-0xFF6   Reserved cluster
;0xFF7 Bad cluster
;0xFF8-0xFFF   Last cluster in a file
;(anything else)  Number of the next cluster in the file

;FAT16
;0000h  Available Cluster
;0002h-FFEFh  Used, Next Cluster in File
;FFF0h-FFF6h  Reserved Cluster
;FFF7h  BAD Cluster
;FFF8h-FFFF   Used, Last Cluster in File

  ld  a,0F7h
  cp  l
  jp  nc,RETURN_UNSET
  ld  a,00Fh
  cp  h
  jp  z,RETURN_SET
  or  a ;quit carry
  ret


FAT12_leida:  db  0
;-------------------------------------------------------------
;buffer_directory (2 sectores)->1024 bytes
;filename nombre del fichero con .!!!
read_LFN_backwards:
;IN:  HL:puntero nombre fichero corto.
;OUT  A=0:encontrado
  ;LFN->nombre largo del fichero+$!!!

  ld  bc,-20h ;restamos 20
  add hl,bc


  push  hl
  pop ix


  ld  a,(ix+11)
  cp  0Fh
  ld  a,error_no_LFN_en_entrada;no tiene LFN
  jp  nz,RETURN_UNSET

  ld  de,LFN

loop_print_1_entry_LFN:

  push  hl

  inc hl
  ld  b,5
  call  copy_Unicode_String
  jr  c,end_unicode_part

  inc hl
  inc hl
  inc hl

  ld  b,6
  call  copy_Unicode_String
  jr  c,end_unicode_part

  inc hl
  inc hl

  ld  b,2
  call  copy_Unicode_String
  jr  c,end_unicode_part

end_unicode_part:
  pop hl



  ;
  bit 6,(hl)
  ld  bc,-20h ;restamos 20
  add hl,bc
  jr  z,loop_print_1_entry_LFN



  ex  de,hl
  ld  (hl),0	;end of the line (a file name can contain "$")

  xor a ;encontrado
  jp RETURN_UNSET


;---------------------
copy_Unicode_String:
  ld  a,(hl)
  or  a
  ld  (de),a

  jr  nz,no_end_unicode
  inc hl
  ld  a,(hl)
  dec hl
  or  a
  jp  z,RETURN_SET



no_end_unicode:
  inc hl
  inc hl
  inc de

  djnz  copy_Unicode_String
  jp  RETURN_UNSET
;-----------------------------------------------------------------------
RETURN_SET:
    scf
    ret
RETURN_UNSET:
    or a
    ret

;-------------------------------------
take_File_Info_Block:
  ld  de,0
  ld  (actual_sector_FAT),de

  ;crea File Info Block
  ld  de,filename_to_check
  ld  c,40h ;Find First Entry
  ld  ix,file_info_block
  ld  b,0 ;no special attributes
  ;call BDOS
  cp  0 ;error? a<>0
  ld  de,DosErr
  ;jp nz,Done


  ld  hl,file_info_block+1
  ld  de,filename2PRINT
  ld  bc,8
  ldir
  inc hl
  ;inc  de
  ld  bc,3;quitamos "."
  ldir
  ret
;-------------------------------------------
take_drive_INFO:

  ld  a,(DRIVE_to_DIR)
  ;ld a,(ix+25) ;drive (a=1,b=2...)
  dec a ;valor -1
  ld  hl,Drive_info
  ld  c,079h  ;drive info
  call  BDOS

  ld  a,(Drive_info+4);valores para leer sectores
  ld  (Drive_unit),a
  ;
  ;TODO Comprueba si es el slot Flashjack DISKROM!!
  ;
  ;ld hl,Drive_info+1
  ;ld a,(ERMSlt)
  ;cp (hl)
  ;jp nz,no_slot_FLASHJACKS

  ;guarda primer sector FISICO de la unidad
  ld  ix,Drive_info
  ld  a,(ix+6)
  ld  (first_sector_drive_PHY),a
  ld  a,(ix+7)
  ld  (first_sector_drive_PHY+1),a
  ld  a,(ix+8)
  ld  (first_sector_drive_PHY+2),a

;Take Disk Parameters

  ld  a,(DRIVE_to_DIR)
  ld  l,a
  ;ld l,(ix+25) ;drive in FIB (a=1,B=2,)

  ld  de,Drive_parameters
  ld  c,031h  ;Disk Parameters
  call  BDOS
;
;     Parameters:    C = 31H (_DPARM)
;                   DE = Pointer to 32 byte buffer
;                    L = Drive number (0=default, 1=A: etc.)
;     Results:       A = Error code
;                   DE = Preserved

  ld  ix,Drive_parameters
  ld  a,(ix+3)
  ld  (sectors_per_cluster),a


  ld  a,(ix+4)
  ld  (reserved_sectors),a
  ld  a,(ix+5)
  ld  (reserved_sectors+1),a

  ld  a,(ix+15)
  ld  (first_sector_DATA),a
  ld  a,(ix+16)
  ld  (first_sector_DATA+1),a

  ;calcula primer sector fisico de la FAT
  ld  hl,(first_sector_drive_PHY)
  ld  a,(first_sector_drive_PHY+2)
  ld  de,(first_sector_DATA)
  add hl,de
  jr  nc,save_first_sector_FAT_PHY
  inc a
save_first_sector_FAT_PHY:
  ld  (first_sector_DATA_PHY),hl
  ld  (first_sector_DATA_PHY+2),a
  ret



;-------------------------------------------------------------------
  ;IN: hl=cluster number
cluster2sector:

  and a; quitamos Carry
  ld  a,(Drive_parameters+3)  ;sectors per cluster
  ld  b,a
  rr  b

  ;ld e,a
  ;ld d,0


  dec hl  ;cluster number-2
  dec hl

  ;ld b,h
  ;ld c,l


  xor a
multiply_cluster:
  add hl,hl
  rla
  and a; quitamos Carry
  rr  b
  jr  nc,multiply_cluster

  ;añade el valor del primer sector de datos FISICO
  ld  de,(first_sector_DATA_PHY)
  add hl,de
  jr  nc,no_inc_5byte_sector
  inc a ;tercer byte
no_inc_5byte_sector:
  ld  b,a
  ld  a,(first_sector_DATA_PHY+2)
  ld  c,a
  ld  a,b
  add c




  ld  de,(first_sector_drive_PHY)

  and a
  sbc hl,de
  jr  nc,no_dec_PHY_sector_a
  dec a

no_dec_PHY_sector_a:

  ld  b,a


  ld  a,(first_sector_drive_PHY+2)
  ld  c,a
  ld  a,b
  sub c



  ret
;------------------------------------------------------------



put_32bits:
;IN:
;HL:pointer to 32 bits number
;BC:pointer to output buffer



    ld  e," ";space
    ld      a,e
    ld      (ZERO_CHAR),a           ;Store lead character

    push    bc
    ld      de,NUMBER
    ld      bc,4
    ldir

    ld      hl,POWER_TAB            ;HL -> power of 10 table
    ld      de,NUMBER               ;DE -> number to be printed

wr_32_loop:     ld      a,(hl)                  ;If we are at last entry in
    dec     a                       ; the table then force the
    jr      nz,not_last_char        ; lead character to be "0"
    ld      a,"0"                   ; to ensure that zero gets
    ld      (ZERO_CHAR),a           ; printed.
not_last_char:
    ld      c,0                     ;Divide by 32 bit subtraction
subtract_loop:  call    SUB_32                  ; and add last one back on to
    inc     c                       ; keep result +ve.
    jr      nc,subtract_loop
    call    ADD_32

    dec     c                       ;If the digit is zero then
    ld      a,(ZERO_CHAR)           ; use the lead character.
    jr      z,use_lead_char         ;If non-zero then set lead
    ld      a,"0"                   ; character to "0" for future
    ld      (ZERO_CHAR),a           ; zeroes and convert digit
    add     a,c                     ; to ASCII.
use_lead_char:  or      a                       ;Print the character unless
    jr      z,no_print              ; it is null.
    ex      (sp),hl
    ld      (hl),a
    inc     hl
    ex      (sp),hl

no_print:       ld      a,(hl)                  ;Test whether last entry in
    dec     a                       ; table yet.
    inc     hl
    inc     hl
    inc     hl                      ;Point HL at next entry
    inc     hl
    jr      nz,wr_32_loop           ;Loop 'til end of table

    pop     hl                      ;return new buffer ptr
    ld      (hl),0                  ;(terminate string with 0)
    ret

POWER_TAB:      dw       9680h,   98h           ;   10,000,000
    dw       4240h,   0Fh           ;    1,000,000
    dw       86A0h,    1h           ;      100,000
    dw       2710h,    0h           ;       10,000
    dw        3E8h,    0h           ;        1,000
    dw         64h,    0h           ;          100
    dw         0Ah,    0h           ;           10
    dw          1h,    0h           ;            1

NUMBER:         dw      0,0             ;Buffer for number calculation
ZERO_CHAR:      db      0               ;Character for leading zeroes


;
;    These two routines are almost identical.  They simply add or subtract the
; 32 bit number pointed to by HL to the 32 bit number pointed to by DE.  All
; registers are preserved except for AF, and the carry flag will be set
; correctly for the result.  The number at (HL) is not modified.
;
ADD_32:         push    hl
    push    de
    push    bc
    ld      b,4
    or      a
add_32_loop:    ld      a,(de)
    adc     a,(hl)
    ld      (de),a
    inc     hl
    inc     de
    djnz    add_32_loop
    pop     bc
    pop     de
    pop     hl
    ret

SUB_32:         push    hl
    push    de
    push    bc
    ld      b,4
    or      a
sub_32_loop:    ld      a,(de)
    sbc     a,(hl)
    ld      (de),a
    inc     hl
    inc     de
    djnz    sub_32_loop
    pop     bc
    pop     de
    pop     hl
    ret
;------------------------------------------------------------



DOS_VERSION:
  db  0
no_wait_key:  db  0
LFN_exists
  db  0
WHOLE_PATH_STRING:  ds  64
  ds  4
files_counter:  dw  0
dirs_counter: dw  0

DRIVE_to_DIR: db  0

Namefile:
  db  0,"           "

filename_to_check:  ds  13
    db  0
file_info_block:  ds  64

filename2PRINT: ds 13
    db  "$"

LFN:  ds  256
sectors_per_cluster:  db  0

atributos_a_mostrar:  db  010001b;por defecto con subdirectorios y read only

first_cluster_file: db  0,0
first_sector_file:  db  0,0,0


reserved_sectors: db  0,0
first_sector_FAT: db  0,0,0
first_sector_DATA:  db  0,0,0

first_sector_drive_PHY: db  0,0,0
first_sector_DATA_PHY:  db  0,0,0
actual_sector_FAT:  dw  0
cluster_p:  dw  0


actual_sector_directory:  db  0,0,0

fn_termination  dw  0
fn_last_item  dw  0

path_file db  92
    ds  256
filename: ds  12 ;ASCIIZ lleva .!!!
path_FIB: ds  64

Device_drive_Info:  ds  64
; 0: Driver slot number
; +1: Driver segment number, FFh if the driver is embedded within a Nextor or MSX-DOS kernel ROM(always FFh in current version)
; +2: Number of drive letters assigned to this driver at boot time
; +3: First drive letter assigned to this driver at boot time (A:=0, etc), unused if no drives are assigned at boot time
; +4: Driver flags:
;   bit 7: 1 => the driver is a Nextor driver0 => the driver is a MSX-DOS driver(embedded within a MSX-DOS kernel ROM)
;   bits 6-1: Unused, always zero
;   bit 0: 1 => the driver is a device-based driver0 => the driver is a drive-based driver


Drive_info:   ds  64
;+0: Drive status
; 0: Unassigned
; 1: Assigned to a storage device attached to a Nextor or MSX-DOS driver
; 2: Unused
; 3: Unused
; 4: Assigned to the RAM disk (all other fields will be zero)
;+1: Driver slot number
;+2: Driver segment number, FFh if the ;driver is embedded within a Nextor or MSXDOS kernel ROM(always FFh in current version)
;+3: Relative drive number within the driver (for drive based drivers only; FFh if device based driver)
;+4: Device index (for device based drivers only; 0 for drive based drivers and MSXDOS drivers)
;+5: Logical unit index (for device based drivers only; 0 for drive based drivers and MSXDOS drivers)
;+6..+8: First device sector number (for devices in device based drivers only always zero for drive based drivers and MSXDOS drivers)
;+9..+63: Reserved (currently always zero)


Drive_parameters: ds  32
;     DE+0      - Physical drive number (1=A: etc)
;     DE+1,2    - Sector size (always 512 currently)
;     DE+3      - Sectors per cluster (non-zero power of 2)
;     DE+4,5    - Number of reserved sectors (usually 1)
;     DE+6      - Number of copies of the FAT (usually 2)
;     DE+7,8    - Number of root directory entries
;     DE+9,10   - Total number of logical sectors
;     DE+11     - Media descriptor byte
;     DE+12     - Number of sectors per FAT
;     DE+13..14 - First root directory sector number
;     DE+15..16 - First data sector number
;     DE+17..18 - Maximum cluster number
;     DE+19     - Dirty disk flag
;     DE+20..23 - Volume id. (-1 => no volume id.)
;     DE+24..31 - Reserved (currently always zero)
;Also, position +28 of the returned parameter block contains the filesystem type:
;0: FAT12
;1: FAT16
;255: Other

buffer_directory: equ 08000h;ds 1024,020h ;2 sectores



buffer_disk:  equ buffer_directory+1024;ds  512

buffer_FAT12:
screen_buffer:  equ buffer_FAT12+24*512 ;RAM mirror of the screen (24 rows x 80)


; Fin del programa
end
