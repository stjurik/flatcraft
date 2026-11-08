"""Тести Python enclosed_shelf-гейта (issue #283): ребро жорсткості і
перфорація боковин. Паритет із TS
`packages/cad-engine/src/validators/enclosed-shelf.test.ts`.

Юніт-рівень (`validate_enclosed_shelf`) + інтеграційний (`POST /export`, щоб
довести, що `server.py` реально викликає `validate_export_enclosed_shelf`
у списку гейтів, а не лише те, що функція сама по собі правильна).
"""

from __future__ import annotations

from collections.abc import Iterator

import boto3
import pytest
from fastapi.testclient import TestClient
from moto import mock_aws

from flatcraft_cad.server import app
from flatcraft_cad.validate.enclosed_shelf import validate_enclosed_shelf

from .test_server import ENCLOSED_SHELF_VALID_PARAMS

SIDE = {"hole_size_mm": 10, "pitch_x_mm": 20, "pitch_y_mm": 20, "margin_mm": 20}


def _codes(params: dict[str, object], t: float) -> list[str]:
    return [e.code for e in validate_enclosed_shelf("enclosed_shelf", params, t)]


class TestEnclosedShelfGateUnit:
    def test_невідомий_slug_повертає_порожнє(self) -> None:
        assert validate_enclosed_shelf("l_bracket", {"stiffening_rib": {"height_mm": 1}}, 2) == []

    def test_без_ребра_і_перфорації_порожнє(self) -> None:
        assert validate_enclosed_shelf("enclosed_shelf", {"depth_mm": 200}, 2) == []

    def test_ребро_на_межі_t_r_невалідне(self) -> None:
        # height_mm == t+r (5 == 2.5+2.5) → невалідно (строго >).
        errs = validate_enclosed_shelf(
            "enclosed_shelf",
            {"stiffening_rib": {"height_mm": 5}, "bend_radius_mm": 2.5},
            2.5,
        )
        assert len(errs) == 1
        assert errs[0].code == "FLANGE_TOO_SHORT"
        assert errs[0].field == "stiffening_rib.height_mm"
        assert "5" in errs[0].detail

    def test_ребро_трохи_більше_валідне(self) -> None:
        assert (
            validate_enclosed_shelf(
                "enclosed_shelf",
                {"stiffening_rib": {"height_mm": 5.5}, "bend_radius_mm": 2.5},
                2.5,
            )
            == []
        )

    def test_ребро_без_bend_radius_пропускається(self) -> None:
        # bend_radius_mm відсутній (None після sanitize_for_gates) — правило
        # залежить від r, тож пропускається, а не падає.
        assert (
            validate_enclosed_shelf(
                "enclosed_shelf", {"stiffening_rib": {"height_mm": 1}, "bend_radius_mm": None}, 2.5
            )
            == []
        )

    @pytest.mark.parametrize("pitch_field", ["pitch_x_mm", "pitch_y_mm"])
    def test_крок_рівний_отвору_holes_overlap(self, pitch_field: str) -> None:
        errs = validate_enclosed_shelf(
            "enclosed_shelf", {"side_perforation": {**SIDE, pitch_field: 10}}, 2
        )
        codes_fields = [(e.code, e.field) for e in errs]
        assert ("HOLES_OVERLAP", f"side_perforation.{pitch_field}") in codes_fields

    def test_margin_рівний_половині_отвору_margin_too_small(self) -> None:
        errs = validate_enclosed_shelf(
            "enclosed_shelf", {"side_perforation": {**SIDE, "margin_mm": 5}}, 2
        )
        assert any(
            e.code == "MARGIN_TOO_SMALL" and e.field == "side_perforation.margin_mm" for e in errs
        )

    def test_margin_не_залежить_від_радіуса(self) -> None:
        # 2a/2b не залежать від bend_radius_mm/товщини (issue #283 п.2).
        errs = validate_enclosed_shelf(
            "enclosed_shelf",
            {"side_perforation": {**SIDE, "margin_mm": 3}, "bend_radius_mm": None},
            2,
        )
        assert any(e.code == "MARGIN_TOO_SMALL" for e in errs)

    def test_перфорація_не_вміщається_margin(self) -> None:
        # d=100, t=2, r=2.5 → w=95.5; margin=48 → 2*48=96 > 95.5.
        errs = validate_enclosed_shelf(
            "enclosed_shelf",
            {
                "depth_mm": 100,
                "bend_radius_mm": 2.5,
                "side_perforation": {**SIDE, "margin_mm": 48},
            },
            2,
        )
        hit = [
            e
            for e in errs
            if e.code == "PERFORATION_DOES_NOT_FIT" and e.field == "side_perforation.margin_mm"
        ]
        assert hit
        assert "48" in hit[0].detail

    def test_перфорація_на_межі_вміщається(self) -> None:
        # margin=47.5 → 2*47.5=95 ≤ 95.5 — валідно (межа inclusive).
        errs = validate_enclosed_shelf(
            "enclosed_shelf",
            {
                "depth_mm": 100,
                "bend_radius_mm": 2.5,
                "side_perforation": {**SIDE, "margin_mm": 47.5},
            },
            2,
        )
        assert errs == []

    def test_отвір_не_менший_за_боковину(self) -> None:
        side = {"hole_size_mm": 96, "pitch_x_mm": 100, "pitch_y_mm": 100, "margin_mm": 45}
        errs = validate_enclosed_shelf(
            "enclosed_shelf", {"depth_mm": 100, "bend_radius_mm": 2.5, "side_perforation": side}, 2
        )
        codes_fields = {(e.code, e.field) for e in errs}
        assert ("PERFORATION_DOES_NOT_FIT", "side_perforation.hole_size_mm") in codes_fields
        assert ("MARGIN_TOO_SMALL", "side_perforation.margin_mm") in codes_fields

    def test_усі_порушення_разом(self) -> None:
        side = {"hole_size_mm": 10, "pitch_x_mm": 8, "pitch_y_mm": 8, "margin_mm": 3}
        codes = _codes({"side_perforation": side}, 2)
        assert codes.count("HOLES_OVERLAP") == 2
        assert "MARGIN_TOO_SMALL" in codes


@pytest.fixture(autouse=True)
def _s3(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    monkeypatch.delenv("S3_ENDPOINT", raising=False)
    monkeypatch.setenv("S3_ACCESS_KEY_ID", "test")
    monkeypatch.setenv("S3_SECRET_ACCESS_KEY", "test")
    monkeypatch.setenv("S3_BUCKET", "flatcraft-test")
    monkeypatch.setenv("S3_REGION", "us-east-1")
    with mock_aws():
        boto3.client("s3", region_name="us-east-1").create_bucket(Bucket="flatcraft-test")
        yield


class TestEnclosedShelfGateServer:
    """Інтеграція: доводить, що `/export` реально викликає гейт (не лише
    юніт-функцію саму по собі)."""

    def test_замале_ребро_через_export_422(self) -> None:
        res = TestClient(app).post(
            "/export",
            json={
                "template_slug": "enclosed_shelf",
                "parameters": {
                    **ENCLOSED_SHELF_VALID_PARAMS,
                    "bend_radius_mm": 2.5,
                    "stiffening_rib": {"height_mm": 5},
                },
                "thickness_mm": 2.5,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 422, res.text
        detail = res.json()["detail"]
        assert any(e.get("code") == "FLANGE_TOO_SHORT" for e in detail), detail

    def test_перфорація_не_вміщається_через_export_422(self) -> None:
        res = TestClient(app).post(
            "/export",
            json={
                "template_slug": "enclosed_shelf",
                "parameters": {
                    **ENCLOSED_SHELF_VALID_PARAMS,
                    "depth_mm": 100,
                    "bend_radius_mm": 2.5,
                    "side_perforation": {**SIDE, "margin_mm": 48},
                },
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 422, res.text
        detail = res.json()["detail"]
        assert any(e.get("code") == "PERFORATION_DOES_NOT_FIT" for e in detail), detail

    def test_валідна_перфорація_через_export_200(self) -> None:
        res = TestClient(app).post(
            "/export",
            json={
                "template_slug": "enclosed_shelf",
                "parameters": {**ENCLOSED_SHELF_VALID_PARAMS, "side_perforation": SIDE},
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 200, res.text
