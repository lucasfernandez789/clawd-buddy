# Pixel frames (16x11). Keep this file ASCII-only.
# . empty  O body  D feet  E eyes  K blush  B book  P pages  L laptop  S laptop logo  G keyboard  Z sparkle

$script:Palette = @{
    O = '#D97757'; D = '#A8553A'; E = '#2B1D16'; K = '#F2A08A'
    B = '#5B7FA6'; P = '#F3E9DC'; L = '#4A4A55'; S = '#F4B08F'; G = '#8A8A96'; Z = '#F6D365'
}

$script:Frames = @{
    # Idle: sitting still, reading a book.
    idle = @(
        '................',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '...OOEEOOEEOO...',
        '...OOOOOOOOOO...',
        '..OBBBBBBBBBBO..',
        '...BBBBBBBBBB...',
        '...PPPPPPPPPP...',
        '....DD....DD....',
        '................'
    )
    # Working: typing on a laptop (two frames, hands alternate).
    work1 = @(
        '..............Z.',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '...OOEEOOEEOO...',
        '...OOEEOOEEOO...',
        '...OOOOOOOOOO...',
        '...LLLLLLLLLL...',
        '..OLLLLSSLLLLO..',
        '...LLLLLLLLLL...',
        '..GGGGGGGGGGGG..',
        '....DD....DD....'
    )
    work2 = @(
        '.............Z..',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '...OOEEOOEEOO...',
        '...OOEEOOEEOO...',
        '...OOOOOOOOOO...',
        '...LLLLLLLLLL...',
        '...LLLLSSLLLL...',
        '..OLLLLLLLLLLO..',
        '..GGGGGGGGGGGG..',
        '....DD....DD....'
    )
    # Done: arms up, content closed eyes.
    done = @(
        '.O............O.',
        '.O.OOOOOOOOOO.O.',
        '..OOOOOOOOOOOO..',
        '...OOOOOOOOOO...',
        '...OEEOOOOEEO...',
        '...OKOOOOOOKO...',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '....DD....DD....',
        '................'
    )
    # Attention: wide eyes, waving (two frames).
    attn1 = @(
        '..............O.',
        '...OOOOOOOOOO.O.',
        '...OOOOOOOOOOOO.',
        '...OOEEOOEEOO...',
        '...OOEEOOEEOO...',
        '...OOOOOOOOOO...',
        '..OOOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '....DD....DD....',
        '................'
    )
    attn2 = @(
        '................',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO.OO',
        '...OOEEOOEEOOOO.',
        '...OOEEOOEEOO...',
        '...OOOOOOOOOO...',
        '..OOOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '....DD....DD....',
        '................'
    )
    # Error: X eyes, arms down.
    error = @(
        '................',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '...OEOEOOEOEO...',
        '...OOEOOOOEOO...',
        '...OEOEOOEOEO...',
        '...OOOOOOOOOO...',
        '..OOOOOOOOOOOO..',
        '...OOOOOOOOOO...',
        '....DD....DD....',
        '................'
    )
}
