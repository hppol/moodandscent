# ==========================================
# 브랜드 등급 분류표 (luxury: 니치/하이엔드, affordable: 가성비 대안)
# - 데이터셋의 Brand 값과 비교할 때는 normalize_brand()로 정규화한 키를 사용합니다.
# - 여기에 없는 브랜드의 향수는 DB에 들어가지 않습니다.
# ==========================================

LUXURY_BRANDS = [
    "Diptyque", "Le Labo", "Byredo", "Frederic Malle", "Maison Francis Kurkdjian",
    "Creed", "Tom Ford", "Kilian", "By Kilian", "Aesop", "Maison Martin Margiela",
    "Maison Margiela", "Santa Maria Novella", "Penhaligon's", "Jo Malone London",
    "Acqua di Parma", "Serge Lutens", "L'Artisan Parfumeur", "Atelier Cologne",
    "Xerjoff", "Parfums de Marly", "Amouage", "Initio Parfums Prives", "Nishane",
    "Memo Paris", "Ormonde Jayne", "Juliette Has A Gun", "D.S. & Durga",
    "Maison Crivelli", "Goldfield & Banks Australia", "Escentric Molecules",
    "Hermes", "Chanel", "Guerlain", "Louis Vuitton", "Dior", "Annick Goutal",
    "Goutal", "Etat Libre d'Orange", "Comme des Garcons", "Mancera", "Montale",
    "Histoires de Parfums", "Floraiku", "Ex Nihilo", "BDK Parfums", "Vilhelm Parfumerie",
    "Lancome", "Bvlgari", "Narciso Rodriguez", "Roja Dove", "Clive Christian",
]

AFFORDABLE_BRANDS = [
    "Zara", "Tamburins", "Nonfiction", "Granhand", "Clean", "Clean Reserve",
    "Innisfree", "The Body Shop", "Dossier", "Lattafa Perfumes", "Armaf",
    "Afnan", "Maison Alhambra", "Al Haramain Perfumes", "Rasasi", "Ajmal",
    "Mango", "Bath & Body Works", "Victoria's Secret", "Jo Loves",
    "Demeter Fragrance", "Kayali Fragrances", "Ariana Grande", "Phlur",
    "Commodity", "Sol de Janeiro", "Forment", "W.Dressroom", "Kenzo",
    "Davidoff", "Calvin Klein", "Elizabeth Arden", "Nautica", "Adidas",
]


def normalize_brand(name: str) -> str:
    """대소문자, 하이픈, 악센트, 기호 차이를 무시하고 비교하기 위한 키"""
    import unicodedata

    s = unicodedata.normalize("NFKD", str(name)).encode("ascii", "ignore").decode()
    return "".join(ch for ch in s.lower() if ch.isalnum())


BRAND_TIERS = {normalize_brand(b): "luxury" for b in LUXURY_BRANDS}
BRAND_TIERS.update({normalize_brand(b): "affordable" for b in AFFORDABLE_BRANDS})
DISPLAY_NAMES = {normalize_brand(b): b for b in LUXURY_BRANDS + AFFORDABLE_BRANDS}
