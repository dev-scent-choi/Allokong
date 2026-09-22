"""카테고리별 선화 생성 프롬프트."""

CATEGORIES = ("animal", "car", "dinosaur", "character")

SUBJECTS = {
    "animal": [
        "sitting cat", "puppy with floppy ears", "elephant with raised trunk",
        "rabbit eating a carrot", "penguin standing", "lion with a mane",
        "giraffe reaching for leaves", "turtle with a patterned shell",
    ],
    "car": [
        "fire truck", "school bus", "excavator", "police car",
        "race car", "garbage truck", "tractor", "ambulance",
    ],
    "dinosaur": [
        "triceratops", "stegosaurus", "tyrannosaurus rex", "brachiosaurus",
        "pterodactyl in flight", "ankylosaurus", "baby dinosaur hatching",
    ],
    "character": [
        "friendly robot", "smiling cloud with a face", "star wearing a hat",
        "little astronaut", "cheerful sun", "sleepy moon",
    ],
}

_BASE = (
    "thick black outline coloring book page for toddlers, {subject}, "
    "closed shapes with every outline fully connected, no shading, "
    "no gradients, no texture, no hatching, pure white background, "
    "bold uniform line weight, centered composition, "
    "large simple fillable areas"
)

# 캐릭터는 기존 IP를 쓰지 않는다. 생성 단계에서 못을 박아 둔다.
_CHARACTER_SUFFIX = (
    ", completely original character design, "
    "not resembling any existing franchise or branded character"
)


def build_prompt(category: str, subject: str) -> str:
    """도안 한 장을 만들 프롬프트를 조립한다."""
    if category not in CATEGORIES:
        raise ValueError(
            f"알 수 없는 카테고리: {category!r}. "
            f"가능한 값: {', '.join(CATEGORIES)}"
        )
    prompt = _BASE.format(subject=subject)
    if category == "character":
        prompt += _CHARACTER_SUFFIX
    return prompt
