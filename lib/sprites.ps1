# Pixel frames (16x11). Keep this file ASCII-only.
# . empty  O body  D feet/lids  E eyes  K blush  B book  P pages  L laptop  S laptop logo  G keyboard
# Z sparkle  A alert  M smoke/string  Q sleep  N music note  T mate gourd  Y yerba  W bombilla

$script:Palette = @{
    O = '#D97757'; D = '#A8553A'; E = '#2B1D16'; K = '#F2A08A'
    B = '#5B7FA6'; P = '#F3E9DC'; L = '#4A4A55'; S = '#F4B08F'; G = '#8A8A96'; Z = '#F6D365'
    A = '#E8A33D'; M = '#B9B4AE'; Q = '#CFE3F5'; N = '#9FD3C7'; T = '#8B5A2B'; Y = '#7FA03A'; W = '#D7D7DF'
}

# Small effects drawn over the sprite, in grid cells relative to its top-left corner.
$script:Overlays = @{
    zzz     = @('QQQ', '..Q', '.Q.', 'Q..', 'QQQ')
    bang    = @('A', 'A', 'A', '.', 'A')
    smoke   = @('.MM..', 'MMMM.', 'MMMMM', '.MMM.')
    sparkle = @('.Z.', 'ZZZ', '.Z.')
    dot     = @('Z')
    note    = @('.N', '.N', 'NN')
    yoyo1   = @('M.', 'BB', 'BB')
    yoyo2   = @('M.', 'M.', 'M.', 'BB', 'BB')
    bulb    = @('.ZZ.', 'ZZZZ', 'ZZZZ', '.ZZ.', '.GG.')
    grr     = @('A.A.', '.AA.', 'A..A')
    grr2    = @('.A.A', 'AA..', '.A.A')
    what    = @('AA.', '..A', '.A.', '...', '.A.')
    sweat   = @('Q', 'Q')
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
    # Idle variants: a blink (also used to sleep) and a page turn.
    idleBlink = @(
        '................',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '...OODDOODDOO...',
        '...OOOOOOOOOO...',
        '..OBBBBBBBBBBO..',
        '...BBBBBBBBBB...',
        '...PPPPPPPPPP...',
        '....DD....DD....',
        '................'
    )
    idlePage = @(
        '................',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '...OOEEOOEEOO...',
        '...OOOOOPPOOO...',
        '..OBBBBBPBBBBO..',
        '...BBBBBBBBBB...',
        '...PPPPPPPPPP...',
        '....DD....DD....',
        '................'
    )
    # Random idle activities. Mate: holding the gourd, then sipping.
    mate1 = @(
        '................',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '...OOEEOOEEOO.W.',
        '...OOOOOOOOOO.W.',
        '..OOOOOOOOOOOYY.',
        '...OOOOOOOOOOTT.',
        '...OOOOOOOOOOTT.',
        '....DD....DD....',
        '................'
    )
    mate2 = @(
        '................',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '...OODDOODDOOW..',
        '...OOOOOOOOOO.YY',
        '..OOOOOOOOOOOOTT',
        '...OOOOOOOOOO.TT',
        '...OOOOOOOOOO...',
        '....DD....DD....',
        '................'
    )
    # Headphones on, eyes closed, enjoying the music.
    music = @(
        '...LLLLLLLLLL...',
        '..LOOOOOOOOOOL..',
        '..LOOOOOOOOOOL..',
        '.LLOOOOOOOOOOLL.',
        '.LLOODDOODDOOLL.',
        '...OOOOOOOOOO...',
        '..OOOOOOOOOOOO..',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '....DD....DD....',
        '................'
    )
    # Stretching with a yawn.
    stretch = @(
        '.O............O.',
        '.O.OOOOOOOOOO.O.',
        '..OOOOOOOOOOOO..',
        '...OOOOOOOOOO...',
        '...OODDOODDOO...',
        '...OOOOEEOOOO...',
        '...OOOOEEOOOO...',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '....DD....DD....',
        '................'
    )
    # Looking around.
    lookL = @(
        '................',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '...OEEOOEEOOO...',
        '...OEEOOEEOOO...',
        '...OOOOOOOOOO...',
        '..OOOOOOOOOOOO..',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '....DD....DD....',
        '................'
    )
    lookR = @(
        '................',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '...OOOEEOOEEO...',
        '...OOOEEOOEEO...',
        '...OOOOOOOOOO...',
        '..OOOOOOOOOOOO..',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '....DD....DD....',
        '................'
    )
    # Playing with a yo-yo (the string and yo-yo are an overlay under the hand).
    yoyo = @(
        '................',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '...OOOEEOOEEO...',
        '...OOOEEOOEEO...',
        '...OOOOOOOOOOOO.',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '....DD....DD....',
        '................'
    )
    # Working, frustrated: frowning brows.
    workAngry = @(
        '................',
        '...OOOOOOOOOO...',
        '...OEOOOOOOEO...',
        '...OOEOOOOEOO...',
        '...OOEEOOEEOO...',
        '...OOOOOOOOOO...',
        '...LLLLLLLLLL...',
        '..OLLLLSSLLLLO..',
        '...LLLLLLLLLL...',
        '..GGGGGGGGGGGG..',
        '....DD....DD....'
    )
    # Working, puzzled: scratching the head with one hand.
    workScratch = @(
        '................',
        '...OOOOOOOOOOO..',
        '...OOOOOOOOOOO..',
        '...OOEEOOEEOOO..',
        '...OOEEOOEEOOO..',
        '...OOOOOOOOOOO..',
        '...LLLLLLLLLL...',
        '..OLLLLSSLLLL...',
        '...LLLLLLLLLL...',
        '..GGGGGGGGGGGG..',
        '....DD....DD....'
    )
    # Working: thinking, eyes up at the ceiling.
    work3 = @(
        '................',
        '...OOOOOOOOOO...',
        '...OOEEOOEEOO...',
        '...OOEEOOEEOO...',
        '...OOOOOOOOOO...',
        '...OOOOOOOOOO...',
        '...LLLLLLLLLL...',
        '..OLLLLSSLLLLO..',
        '...LLLLLLLLLL...',
        '..GGGGGGGGGGGG..',
        '....DD....DD....'
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
