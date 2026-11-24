from argparse import ArgumentParser
from pathlib import Path
from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'app/assets/fonts/survey/NotoSansSC.ttf'

def ui_characters():
    # Keep common Mandarin characters for names, plus every character used by
    # the app and computation package. Platform fonts cover other user input.
    chars = set()
    for lead in range(0xB0, 0xD8):
        for trail in range(0xA1, 0xFF):
            chars.update(bytes([lead, trail]).decode('gb2312', errors='ignore'))
    for bounds in ((0x20, 0x250), (0x370, 0x400), (0x2000, 0x2070),
                   (0x2070, 0x21FF), (0x2200, 0x2300),
                   (0x3000, 0x3040), (0xFF00, 0xFFF0)):
        chars.update(chr(cp) for cp in range(*bounds))
    for source in (ROOT / 'app/lib', ROOT / 'packages/survey_core/lib'):
        for file in source.rglob('*.dart'):
            chars.update(file.read_text(encoding='utf-8'))
    return chars

def main():
    parser = ArgumentParser()
    parser.add_argument('original', type=Path, help='Original full static Noto Sans SC font')
    args = parser.parse_args()
    if args.original.resolve() == OUTPUT:
        parser.error('provide a full font outside the destination path')
    font = TTFont(args.original, recalcTimestamp=False)
    if 'fvar' in font:
        parser.error('provide the full static Regular (400) font')
    chars = ui_characters()
    expected = set(map(ord, chars)) & font.getBestCmap().keys()
    if len(font.getBestCmap()) < 10000:
        parser.error('the input appears to have already been subset')
    options = subset.Options()
    options.name_IDs = ['*']
    options.name_languages = ['*']
    cutter = subset.Subsetter(options=options)
    cutter.populate(text=''.join(sorted(chars)))
    cutter.subset(font)
    if not expected <= font.getBestCmap().keys():
        raise RuntimeError('font subset lost required characters')
    font.save(OUTPUT)
    print(f'{len(expected):,} glyph mappings, {args.original.stat().st_size:,} -> {OUTPUT.stat().st_size:,} bytes')

if __name__ == '__main__':
    main()
