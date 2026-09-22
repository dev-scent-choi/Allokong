"""선화 원본을 모아 dohan_cli가 읽을 수 있는 폴더로 떨군다.

사용 예:
    python generate.py --category dinosaur --count 4 \
        --provider filesystem --source ./raw --out ./lineart
"""

import argparse
import json
from pathlib import Path

from prompts import CATEGORIES, SUBJECTS, build_prompt
from providers import FilesystemProvider


def main() -> int:
    parser = argparse.ArgumentParser(description="도안 선화 원본 생성")
    parser.add_argument("--category", required=True, choices=CATEGORIES)
    parser.add_argument("--count", type=int, default=4)
    parser.add_argument("--provider", default="filesystem",
                        choices=["filesystem"])
    parser.add_argument("--source", type=Path,
                        help="filesystem provider가 읽을 원본 디렉터리")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    if args.provider == "filesystem":
        if args.source is None:
            parser.error("--provider filesystem 에는 --source 가 필요합니다")
        provider = FilesystemProvider(args.source)

    args.out.mkdir(parents=True, exist_ok=True)
    subjects = SUBJECTS[args.category]
    manifest = []

    for i in range(args.count):
        subject = subjects[i % len(subjects)]
        prompt = build_prompt(args.category, subject)
        slug = subject.replace(" ", "-")
        name = f"{args.category}-{slug}-{i:02d}.png"
        (args.out / name).write_bytes(provider.fetch(prompt, i))
        manifest.append({
            "file": name,
            "category": args.category,
            "subject": subject,
            "prompt": prompt,
        })
        print(f"저장: {name}")

    (args.out / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"완료: {len(manifest)}장 → {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
