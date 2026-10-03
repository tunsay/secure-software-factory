"""Échoue si une dérogation de security/exceptions.yaml est expirée ou sans date d'expiration.

Une dérogation est une décision temporaire : passée sa date, elle doit être réexaminée, pas
oubliée. Bibliothèque standard uniquement (lancé par la CI avec le python3 du runner, et par
`make scan`). Le format du fichier est simple et maîtrisé : une entrée par « - id: ».
"""

import datetime
import re
import sys
from pathlib import Path

EXCEPTIONS = Path(__file__).resolve().parent.parent / "security" / "exceptions.yaml"


def entries(text: str) -> list[dict[str, str]]:
    """Découpe la liste `exceptions:` en entrées {clé: valeur}, commentaires ignorés."""
    found: list[dict[str, str]] = []
    for line in text.splitlines():
        if line.lstrip().startswith("#"):
            continue
        start = re.match(r"^\s*-\s+id:\s*(\S+)", line)
        if start:
            found.append({"id": start.group(1)})
            continue
        field = re.match(r"^\s+(expires|path|tool):\s*(\S+)", line)
        if field and found:
            found[-1][field.group(1)] = field.group(2)
    return found


def main() -> int:
    today = datetime.date.today()
    problems = []
    items = entries(EXCEPTIONS.read_text(encoding="utf-8"))
    for item in items:
        where = f"{item['id']} ({item.get('path', '?')})"
        if "expires" not in item:
            problems.append(f"sans date d'expiration : {where}")
            continue
        expires = datetime.date.fromisoformat(item["expires"])
        if expires < today:
            problems.append(f"expirée le {expires} : {where}")
    for problem in problems:
        print(f"DÉROGATION {problem}")
    if problems:
        print(f"{len(problems)} dérogation(s) à réexaminer sur {len(items)}")
        return 1
    print(f"{len(items)} dérogation(s), aucune expirée")
    return 0


if __name__ == "__main__":
    sys.exit(main())
