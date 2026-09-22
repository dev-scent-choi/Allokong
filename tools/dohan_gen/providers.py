"""이미지 수급 provider.

이미지 생성 서비스를 아직 고르지 않았으므로, 지금은 수동으로 내려받은
파일을 읽어 쓰는 FilesystemProvider만 제공한다. 서비스를 정하면 Provider를
상속한 클래스를 하나 추가하면 된다 — generate.py는 바뀌지 않는다.
"""

from abc import ABC, abstractmethod
from pathlib import Path


class Provider(ABC):
    """프롬프트 하나에 대해 선화 이미지 바이트를 돌려준다."""

    @abstractmethod
    def fetch(self, prompt: str, index: int) -> bytes:
        ...


class FilesystemProvider(Provider):
    """미리 준비한 이미지를 순서대로 읽는다.

    API 키 없이 파이프라인 전체를 돌려볼 수 있게 하는 구현이다.
    `source_dir` 안의 png/jpg 파일을 이름순으로 하나씩 내준다.
    """

    def __init__(self, source_dir: Path):
        self.files = sorted(
            p for p in source_dir.iterdir()
            if p.suffix.lower() in (".png", ".jpg", ".jpeg")
        )
        if not self.files:
            raise FileNotFoundError(f"이미지가 없습니다: {source_dir}")

    def fetch(self, prompt: str, index: int) -> bytes:
        return self.files[index % len(self.files)].read_bytes()
