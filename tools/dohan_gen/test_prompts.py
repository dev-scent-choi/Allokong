import unittest

from prompts import CATEGORIES, SUBJECTS, build_prompt


class BuildPromptTest(unittest.TestCase):
    def test_네_카테고리가_정의되어_있다(self):
        self.assertEqual(
            set(CATEGORIES), {"animal", "car", "dinosaur", "character"}
        )

    def test_모든_카테고리에_소재가_있다(self):
        for category in CATEGORIES:
            self.assertTrue(SUBJECTS[category], f"{category}에 소재가 없다")

    def test_프롬프트에_소재와_필수_제약이_들어간다(self):
        prompt = build_prompt("dinosaur", "triceratops")

        self.assertIn("triceratops", prompt)
        self.assertIn("closed shapes", prompt)
        self.assertIn("no shading", prompt)
        self.assertIn("white background", prompt)

    def test_모르는_카테고리는_거부한다(self):
        with self.assertRaises(ValueError):
            build_prompt("spaceship", "rocket")

    def test_캐릭터는_기존_IP를_배제하는_문구를_포함한다(self):
        prompt = build_prompt("character", "friendly robot")

        self.assertIn("original", prompt.lower())


if __name__ == "__main__":
    unittest.main()
