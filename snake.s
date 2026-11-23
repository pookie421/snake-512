# Bootable Snake for an x86 PC BIOS. Build the raw floppy image with make.
.intel_syntax noprefix
.code16
.text

.equ BOOT,       0x7c00
.equ TICKS,      0x046c           # BIOS timer, about 18.2 ticks per second
.equ QUEUE,      0x0600           # 1024 word offsets in conventional memory
.equ QUEUE_MASK, 0x07fe
.equ RNG,        QUEUE + 2048

.equ STRIDE,     160              # 80 VGA text cells, two bytes per cell
.equ LEFT,       8
.equ TOP,        4
.equ WIDTH,      64
.equ HEIGHT,     16
.equ CORNER,     TOP * STRIDE + LEFT * 2
.equ CELLS,      (WIDTH - 2) * (HEIGHT - 2)
.equ EMPTY,      0x0720
.equ WALL,       0x09b0
.equ BODY,       0x02db
.equ HEAD,       0x0adb
.equ FOOD,       0x0c04
.equ STATUS,     21 * STRIDE
.equ READY,      STATUS + 37 * 2

boot:
    cli
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, BOOT
    sti

restart:
    push ax                       # AL is zero on boot and Space on replay
    mov ax, 0x0003                # Set and clear 80x25 color text mode
    int 0x10
    mov ah, 1
    mov cx, 0x2000                # Hide the hardware text cursor
    int 0x10
    mov ax, 0xb800
    mov es, ax
    cld

    mov ax, WALL
    mov di, CORNER
    mov cx, WIDTH
    rep stosw
    mov di, CORNER + (HEIGHT - 1) * STRIDE
    mov cx, WIDTH
    rep stosw
    mov di, CORNER + STRIDE
    mov cx, HEIGHT - 2
walls:
    mov es:[di], ax
    mov es:[di + (WIDTH - 1) * 2], ax
    add di, STRIDE
    loop walls

    mov di, 2 * STRIDE + 35 * 2
    mov si, offset title_address
    mov ah, 0x0a
    call draw_text
    mov di, 23 * STRIDE + 25 * 2
    mov si, offset controls_address
    mov ah, 0x07
    call draw_text

    xor bp, bp                    # Tail and next insertion in the ring buffer
    xor bx, bx
    mov di, 12 * STRIDE + 28 * 2
    mov ax, BODY
    mov cx, 3
initial_snake:
    mov [QUEUE + bx], di
    add bx, 2
    stosw
    loop initial_snake
    sub di, 2
    mov word ptr es:[di], HEAD

    pop ax
    test al, al
    jnz play
    push di
    mov di, READY
    mov si, offset ready_address
    mov ah, 0x0e
    call draw_text
    call wait_space
    mov di, READY
    mov ax, EMPTY
    mov cx, 5
    rep stosw
    pop di

play:
    mov ax, [TICKS]
    mov [RNG], ax
    call spawn_food
    mov si, 2                    # Horizontal step in bytes, initially right

tick:
    mov dx, [TICKS]
frame_delay:
    hlt
    mov ax, [TICKS]
    sub ax, dx
    cmp ax, 2
    jb frame_delay

read_key:
    mov ah, 1
    int 0x16
    jz move
    xor ah, ah
    int 0x16
    mov cx, -STRIDE
    cmp ah, 0x48
    je turn
    mov cx, STRIDE
    cmp ah, 0x50
    je turn
    mov cx, -2
    cmp ah, 0x4b
    je turn
    mov cx, 2
    cmp ah, 0x4d
    jne read_key
turn:
    mov ax, cx
    neg ax
    cmp ax, si
    je read_key
    cmp cx, si
    je read_key
    mov si, cx                   # Apply at most one turn per frame

move:
    add di, si
    mov cl, es:[di]
    cmp cl, FOOD & 0xff
    je add_head
    mov dx, [QUEUE + bp]
    cmp cl, ' '
    je clear_tail
    cmp di, dx                   # The departing tail cell can be entered
    jne lost
clear_tail:
    push di
    mov di, dx
    mov word ptr es:[di], EMPTY
    pop di
    add bp, 2
    and bp, QUEUE_MASK
add_head:
    sub di, si
    mov word ptr es:[di], BODY
    add di, si
    mov word ptr es:[di], HEAD
    mov [QUEUE + bx], di
    add bx, 2
    and bx, QUEUE_MASK
    cmp cl, FOOD & 0xff
    jne tick
    mov ax, bx
    sub ax, bp
    and ax, QUEUE_MASK
    cmp ax, CELLS * 2
    je won
    call spawn_food
    jmp tick

lost:
    mov si, offset lost_address
    mov di, STATUS + 35 * 2
    jmp finish
won:
    mov si, offset won_address
    mov di, STATUS + 36 * 2
finish:
    mov ah, 0x0e
    call draw_text
    call wait_space
    jmp restart

spawn_food:
    push di
find_empty:
    # Full-period 16-bit LCG. Extreme coordinates hit the walls and retry.
    imul ax, [RNG], 25173
    add ax, 13849
    mov [RNG], ax
    mov di, ax
    and di, WIDTH - 1
    shl di, 1
    shr ax, 12
    imul ax, ax, STRIDE
    add di, ax
    add di, CORNER
    cmp byte ptr es:[di], ' '
    jne find_empty
    mov word ptr es:[di], FOOD
    pop di
    ret

wait_space:
    xor ah, ah
    int 0x16
    cmp al, ' '
    jne wait_space
    ret

draw_text:
    lodsb
    test al, al
    jz text_done
    stosw
    jmp draw_text
text_done:
    ret

title:    .asciz "S N A K E"
controls: .asciz "ARROWS TO MOVE   SPACE TO PLAY"
ready:    .asciz "READY"
lost_msg: .asciz "GAME OVER"
won_msg:  .asciz "YOU WIN"

.set title_address,    BOOT + title - boot
.set controls_address, BOOT + controls - boot
.set ready_address,    BOOT + ready - boot
.set lost_address,     BOOT + lost_msg - boot
.set won_address,      BOOT + won_msg - boot

.org 510, 0                       # Pad the sector, or fail if the game is too large
.word 0xaa55
