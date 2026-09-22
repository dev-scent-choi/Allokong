# dohan_gen

도안 선화 원본을 모아 `dohan_cli`에 넘길 폴더를 만든다.

## 흐름

```
generate.py → lineart/*.png → dohan build → 도안 패키지
```

## 지금 할 수 있는 것

이미지 생성 서비스를 아직 고르지 않았으므로, 직접 준비한 선화 이미지를
`FilesystemProvider`로 읽어 쓴다.

```bash
python generate.py --category dinosaur --count 4 \
    --provider filesystem --source ./raw --out ./lineart
```

`manifest.json`에 각 파일의 프롬프트가 기록되므로, 나중에 같은 프롬프트로
재생성할 수 있다.

## 서비스를 고른 뒤

`providers.py`에 `Provider`를 상속한 클래스를 하나 추가하고 `generate.py`의
`--provider` 선택지에 넣는다. 그 밖의 코드는 바뀌지 않는다.

**반드시 먼저 확인할 것:** 생성물의 상업적 이용 조건. 내장 도안이 앱의
판매 가능성에 직접 걸린다.

## 프롬프트 규칙

`prompts.py`의 기본 템플릿은 다음을 강제한다.

- 굵고 균일한 검정 외곽선
- 모든 외곽선이 닫혀 있을 것 (끊긴 선은 색이 새는 원인)
- 명암·그라데이션·텍스처·해칭 없음
- 순백 배경
- 크고 단순한 칠할 영역

`character` 카테고리에는 기존 IP를 배제하는 문구가 자동으로 붙는다.
