"""Issue #289 (A8 057): отвір l_bracket/z_bracket без обов'язкових ключів чи
поза межами — 422 зі списком помилок на пре-гейті воркера, не 200.

ADR-019 — воркер остання лінія оборони: прямий `POST /export` обходить
Zod-гейт API (`packages/types/src/templates/l-bracket.ts`/`z-bracket.ts`,
`HoleSchema`). До доробки 057 `holes: [{}]` і отвір з `diameter_mm: -10`
проходили як 200 — `LBracketBuildParameters`/`ZBracketBuildParameters` поля
`holes` не мають (зайве ігнорується), а `validate/holes.py` на відсутньому
ключі робить `continue`.
"""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

import boto3
import pytest
from fastapi.testclient import TestClient
from moto import mock_aws

from flatcraft_cad.server import app

from .test_server import VALID_PARAMS, Z_VALID_PARAMS

# Безпечний базовий отвір — достатньо далеко від лінії гиба (min_edge_mm для
# cold_rolled_steel при t=2, r=2.5 — 6.5 мм), щоб не зачепити
# HOLE_TOO_CLOSE_TO_BEND (`validate/holes.py`) і не плутатися з гейтом цієї
# задачі.
L_HOLE: dict[str, object] = {
    "leg": "A",
    "distance_from_edge_mm": 20,
    "distance_from_bend_mm": 20,
    "diameter_mm": 8,
}
Z_HOLE: dict[str, object] = {
    "segment": "T",
    "distance_from_edge_mm": 20,
    "distance_from_bend_mm": 20,
    "diameter_mm": 8,
}
BASE: dict[str, tuple[dict[str, object], dict[str, object], str]] = {
    "l_bracket": (VALID_PARAMS, L_HOLE, "leg"),
    "z_bracket": (Z_VALID_PARAMS, Z_HOLE, "segment"),
}
NUMERIC_KEYS = ("distance_from_edge_mm", "distance_from_bend_mm", "diameter_mm")
SLUGS = ("l_bracket", "z_bracket")


@pytest.fixture(autouse=True)
def _s3_env(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    monkeypatch.delenv("S3_ENDPOINT", raising=False)
    monkeypatch.setenv("S3_ACCESS_KEY_ID", "test")
    monkeypatch.setenv("S3_SECRET_ACCESS_KEY", "test")
    monkeypatch.setenv("S3_BUCKET", "flatcraft-test")
    monkeypatch.setenv("S3_REGION", "us-east-1")
    with mock_aws():
        boto3.client("s3", region_name="us-east-1").create_bucket(Bucket="flatcraft-test")
        yield


@pytest.fixture
def client() -> TestClient:
    return TestClient(app, raise_server_exceptions=False)


def _export(client: TestClient, slug: str, holes: object) -> Any:
    params = {**BASE[slug][0], "holes": holes}
    return client.post(
        "/export",
        json={
            "template_slug": slug,
            "parameters": params,
            "thickness_mm": 2,
            "material_code": "cold_rolled_steel",
        },
    )


def _codes_by_field(detail: list[dict[str, str]]) -> dict[str, set[str]]:
    out: dict[str, set[str]] = {}
    for e in detail:
        out.setdefault(e["field"], set()).add(e["code"])
    return out


class TestОбовязковіКлючі:
    """Правило 1 — HOLE_FIELD_MISSING, окремо на кожен відсутній ключ."""

    @pytest.mark.parametrize("slug", SLUGS)
    def test_порожній_отвір_усі_чотири(self, client: TestClient, slug: str) -> None:
        res = _export(client, slug, [{}])
        assert res.status_code == 422, res.text
        by_field = _codes_by_field(res.json()["detail"])
        key = BASE[slug][2]
        for k in (key, *NUMERIC_KEYS):
            assert "HOLE_FIELD_MISSING" in by_field.get(f"holes.0.{k}", set()), (k, by_field)

    @pytest.mark.parametrize("slug", SLUGS)
    @pytest.mark.parametrize("missing", ["leg_or_segment", *NUMERIC_KEYS])
    def test_бракує_одного_ключа(self, client: TestClient, slug: str, missing: str) -> None:
        key = BASE[slug][2] if missing == "leg_or_segment" else missing
        hole = {k: v for k, v in BASE[slug][1].items() if k != key}
        res = _export(client, slug, [hole])
        assert res.status_code == 422, res.text
        by_field = _codes_by_field(res.json()["detail"])
        assert "HOLE_FIELD_MISSING" in by_field.get(f"holes.0.{key}", set()), by_field


class TestМежі:
    """Правило 2 — HOLE_VALUE_OUT_OF_RANGE, межі включно."""

    @pytest.mark.parametrize("slug", SLUGS)
    @pytest.mark.parametrize(
        ("field", "bad"),
        [
            ("diameter_mm", -10),
            ("diameter_mm", 0),
            ("diameter_mm", 1.99),
            ("diameter_mm", 50.01),
            ("distance_from_edge_mm", 4.99),
            ("distance_from_edge_mm", -1),
            ("distance_from_bend_mm", 4.99),
            ("distance_from_bend_mm", 0),
        ],
    )
    def test_поза_межами(self, client: TestClient, slug: str, field: str, bad: float) -> None:
        res = _export(client, slug, [{**BASE[slug][1], field: bad}])
        assert res.status_code == 422, res.text
        by_field = _codes_by_field(res.json()["detail"])
        assert "HOLE_VALUE_OUT_OF_RANGE" in by_field.get(f"holes.0.{field}", set()), by_field

    @pytest.mark.parametrize("slug", SLUGS)
    def test_межі_включно_без_помилки_діапазону(self, client: TestClient, slug: str) -> None:
        # distance_from_bend_mm=5 зачепить HOLE_TOO_CLOSE_TO_BEND (окрема
        # перевірка `validate/holes.py`) — тут важливо лише, що НАШ гейт не
        # додає HOLE_VALUE_OUT_OF_RANGE на межі.
        hole = {**BASE[slug][1], "diameter_mm": 2, "distance_from_edge_mm": 5}
        res = _export(client, slug, [hole])
        if res.status_code == 422:
            by_field = _codes_by_field(res.json()["detail"])
            assert "HOLE_VALUE_OUT_OF_RANGE" not in by_field.get("holes.0.diameter_mm", set())
            assert "HOLE_VALUE_OUT_OF_RANGE" not in by_field.get(
                "holes.0.distance_from_edge_mm", set()
            )

        big = {
            **BASE[slug][1],
            "diameter_mm": 50,
            "distance_from_bend_mm": 60,
            "distance_from_edge_mm": 30,
        }
        res = _export(client, slug, [big])
        assert res.status_code == 200, res.text


class TestНедозволенийВибір:
    """Правило 3 — HOLE_INVALID_CHOICE, без 500 на нехешованому значенні."""

    @pytest.mark.parametrize(
        ("slug", "bad"),
        [
            ("l_bracket", "C"),
            ("l_bracket", "a"),
            ("z_bracket", "A"),
            ("z_bracket", 1),
        ],
    )
    def test_недозволене_значення(self, client: TestClient, slug: str, bad: object) -> None:
        key = BASE[slug][2]
        res = _export(client, slug, [{**BASE[slug][1], key: bad}])
        assert res.status_code == 422, res.text
        by_field = _codes_by_field(res.json()["detail"])
        assert "HOLE_INVALID_CHOICE" in by_field.get(f"holes.0.{key}", set()), by_field

    @pytest.mark.parametrize("slug", SLUGS)
    @pytest.mark.parametrize("bad", [None, True, False, ["A"], {"a": 1}, 0])
    def test_будь_який_тип_не_падає_і_не_бракує(
        self, client: TestClient, slug: str, bad: object
    ) -> None:
        key = BASE[slug][2]
        res = _export(client, slug, [{**BASE[slug][1], key: bad}])
        assert res.status_code == 422, res.text
        by_field = _codes_by_field(res.json()["detail"])
        assert "HOLE_INVALID_CHOICE" in by_field.get(f"holes.0.{key}", set()), by_field
        assert "HOLE_FIELD_MISSING" not in by_field.get(f"holes.0.{key}", set()), by_field


class TestЗабагатоОтворів:
    """Правило 4 — HOLE_TOO_MANY, поле `holes` (не конкретний отвір)."""

    @pytest.mark.parametrize("slug", SLUGS)
    def test_понад_20(self, client: TestClient, slug: str) -> None:
        res = _export(client, slug, [BASE[slug][1]] * 21)
        assert res.status_code == 422, res.text
        by_field = _codes_by_field(res.json()["detail"])
        assert "HOLE_TOO_MANY" in by_field.get("holes", set()), by_field


class TestБезДублюванняЗТипГейтом:
    """Правило 5 — поле з INVALID_PARAMETER_TYPE не отримує ще й 1–2."""

    @pytest.mark.parametrize("slug", SLUGS)
    def test_nan_лише_тип_помилка(self, client: TestClient, slug: str) -> None:
        res = _export(client, slug, [{**BASE[slug][1], "diameter_mm": "nan"}])
        assert res.status_code == 422, res.text
        by_field = _codes_by_field(res.json()["detail"])
        assert by_field.get("holes.0.diameter_mm") == {"INVALID_PARAMETER_TYPE"}, by_field

    @pytest.mark.parametrize("slug", SLUGS)
    def test_рядок_число_приймається_межі_після_float(self, client: TestClient, slug: str) -> None:
        res = _export(client, slug, [{**BASE[slug][1], "diameter_mm": "8"}])
        assert res.status_code == 200, res.text

        res = _export(client, slug, [{**BASE[slug][1], "diameter_mm": "-10"}])
        assert res.status_code == 422, res.text
        by_field = _codes_by_field(res.json()["detail"])
        assert "HOLE_VALUE_OUT_OF_RANGE" in by_field.get("holes.0.diameter_mm", set()), by_field

    @pytest.mark.parametrize("slug", SLUGS)
    def test_holes_не_список_без_нових_помилок(self, client: TestClient, slug: str) -> None:
        res = _export(client, slug, "x" * 25)
        assert res.status_code != 500, res.text
        if res.status_code == 422:
            codes = {e["code"] for e in res.json()["detail"]}
            assert not any(c.startswith("HOLE_") for c in codes), codes


class TestНезалежність:
    """Правило 6 — усі отвори й усі ключі перевіряються незалежно, без
    раннього виходу."""

    @pytest.mark.parametrize("slug", SLUGS)
    def test_кілька_помилок_разом(self, client: TestClient, slug: str) -> None:
        key = BASE[slug][2]
        bad0 = {**BASE[slug][1], key: "Q", "diameter_mm": -1}
        bad1 = {k: v for k, v in BASE[slug][1].items() if k != "distance_from_edge_mm"}
        res = _export(client, slug, [bad0, bad1])
        assert res.status_code == 422, res.text
        by_field = _codes_by_field(res.json()["detail"])
        assert "HOLE_INVALID_CHOICE" in by_field.get(f"holes.0.{key}", set()), by_field
        assert "HOLE_VALUE_OUT_OF_RANGE" in by_field.get("holes.0.diameter_mm", set()), by_field
        assert "HOLE_FIELD_MISSING" in by_field.get("holes.1.distance_from_edge_mm", set()), (
            by_field
        )

    @pytest.mark.parametrize("slug", SLUGS)
    def test_too_many_разом_з_поганим_отвором(self, client: TestClient, slug: str) -> None:
        key = BASE[slug][2]
        bad = {**BASE[slug][1], key: "Q"}
        res = _export(client, slug, [BASE[slug][1]] * 20 + [bad])
        assert res.status_code == 422, res.text
        by_field = _codes_by_field(res.json()["detail"])
        assert "HOLE_TOO_MANY" in by_field.get("holes", set()), by_field
        assert "HOLE_INVALID_CHOICE" in by_field.get(f"holes.20.{key}", set()), by_field


class TestВалідно:
    @pytest.mark.parametrize("slug", SLUGS)
    @pytest.mark.parametrize("holes", [[], "one_valid"])
    def test_200(self, client: TestClient, slug: str, holes: object) -> None:
        payload = [BASE[slug][1]] if holes == "one_valid" else holes
        res = _export(client, slug, payload)
        assert res.status_code == 200, res.text
