"""Automatically detect whether a user message needs Agent, Ask, or Plan mode."""

import re

# Turkish verb STEMS — trailing \b removed for agglutinative suffixes.
# "tasarla" alone matched "tasarla" but NOT "tasarlayabilir misin" (one word in Turkish).
# Removing the closing \b lets the stem match regardless of what follows.
_AGENT_PATTERNS = [
    # Türkçe eylem kökleri (sondaki \b kaldırıldı — aglutinatif ekleme)
    r"\byaz",           # yaz, yazabilir misin, yazıyor
    r"\boluştur",       # oluştur, oluşturabilir misin
    r"\byarat",         # yarat, yaratabilir
    r"\bkur\b",         # kur (kısa — 'kurulum' yakalanmasın diye \b korundu)
    r"\bekle\b",
    r"\bsil",           # sil, silerek
    r"\btemizle",       # temizle, temizleyelim
    r"\bdüzelt",        # düzelt, düzeltebilir misin
    r"\bgüncelle",      # güncelle, güncelleyelim
    r"\bdeğiştir",      # değiştir, değiştirebilir misin
    r"\bderle",         # derle, derleme
    r"\bsimüle",        # simüle, simüleyelim
    r"\bçalıştır",      # çalıştır, çalıştırabilir misin
    r"\btest\b",
    r"\bkodla",         # kodla, kodlayabilir misin
    r"\btasarla",       # tasarla, tasarlayabilir misin  ← düzeltildi
    r"\byükle",         # yükle, yükleyebilir misin
    r"\bprogramla",     # programla, programlayabilir misin
    r"\binşa",          # inşa et, inşa edelim  ← yeni
    r"\byeniden",       # yeniden yaz/kur/inşa  ← yeni
    r"\bgerçekleştir",  # gerçekleştir, gerçekleştirebilir  ← yeni
    r"\buygula",        # uygula, uygulayabilir  ← yeni
    r"\bgeliştir",      # geliştir, geliştirebilir  ← yeni
    r"\bentegre\s+et",  # entegre et  ← yeni
    r"\bsıfırdan",      # sıfırdan yaz/kur  ← yeni
    r"\büzer(in|ine)\s+(yaz|inşa|kur)", # üzerine yaz/inşa/kur  ← yeni

    # İngilizce eylemler
    r"\bwrite\b", r"\bcreate\b", r"\bgenerate\b", r"\bbuild\b",
    r"\bdelete\b", r"\bremove\b", r"\bcompile\b", r"\bsimulate\b",
    r"\brun\b", r"\bfix\b", r"\bimplement\b", r"\bcode\b",
    r"\bmodify\b", r"\bupdate\b", r"\bedit\b", r"\bdesign\b",
    r"\brebuild\b", r"\brefactor\b",

    # Nesne tetikleyiciler
    r"\bklas[öo]r\b", r"\bdosya\b",
]

_PLAN_PATTERNS = [
    r"\bplanla\b", r"\byol haritası\b", r"\bne yapmalı\b", r"\bnas[ıi]l yapmalı\b",
    r"\b[öo]neri\b", r"\bstrateji\b", r"\badımlar\b", r"\byaklaşım\b",
    r"\bplan\b", r"\broadmap\b", r"\bstrategy\b", r"\bsteps\b", r"\bapproach\b",
    r"\bnas[ıi]l başlamalı\b",
]

_ASK_PATTERNS = [
    r"\bnedir\b", r"\bnelerdir\b", r"\bnas[ıi]l çalışır\b", r"\bne demek\b",
    r"\baçıkla\b", r"\banlat\b", r"\btanımla\b", r"\bfark[ıi] nedir\b",
    r"\bwhat is\b", r"\bhow does\b", r"\bwhat are\b", r"\bexplain\b",
    r"\bdefine\b", r"\bdifference between\b", r"\bwhy is\b", r"\bwhat does\b",
    r"\bsoru\b",
]

_GREETING_PATTERNS = [
    r"^(merhaba|selam|hey|hi|hello|iyi günler|günaydın|iyi akşamlar|naber|nasılsın|ne haber)[!.,\s]*$",
    r"^(teşekkür|teşekkürler|sağ ol|tamam|tamam teşekkürler|eyvallah)[!.,\s]*$",
    r"^(ok|okay|sure|thanks|thank you|great|nice)[!.,\s]*$",
]


def detect_mode(message: str) -> str:
    """Returns 'agent', 'ask', or 'plan'."""
    msg = message.strip().lower()

    for pattern in _GREETING_PATTERNS:
        if re.match(pattern, msg, re.IGNORECASE):
            return "ask"

    for pattern in _AGENT_PATTERNS:
        if re.search(pattern, msg):
            return "agent"

    for pattern in _PLAN_PATTERNS:
        if re.search(pattern, msg):
            return "plan"

    for pattern in _ASK_PATTERNS:
        if re.search(pattern, msg):
            return "ask"

    if message.strip().endswith("?") or len(msg.split()) <= 6:
        return "ask"

    return "agent"
