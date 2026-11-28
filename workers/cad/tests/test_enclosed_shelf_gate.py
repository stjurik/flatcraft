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

    def test_ребро_трохи_більше_t_r_але_менше_m_невалідне(self) -> None:
        # Доробка #304 (issue #304, рішення yurii 06.11): ребро — це полиця,
        # тож h > t+r=5 само по собі більше не достатньо — потрібно ще й
        # h >= M (global.min_flange_mm = 7.5).
        errs = validate_enclosed_shelf(
            "enclosed_shelf",
            {"stiffening_rib": {"height_mm": 5.5}, "bend_radius_mm": 2.5},
            2.5,
        )
        assert len(errs) == 1
        assert errs[0].code == "FLANGE_TOO_SHORT"
        assert "полиц" in errs[0].detail.lower()

    def test_ребро_на_межі_m_валідне(self) -> None:
        assert (
            validate_enclosed_shelf(
                "enclosed_shelf",
                {"stiffening_rib": {"height_mm": 7.5}, "bend_radius_mm": 2.5},
                2.5,
            )
            == []
        )

    def test_ребро_більше_m_але_на_межі_t_r_невалідне(self) -> None:
        # M=7.5 < t+r=13 — тут діє геометрія (товщина+радіус), не мінімальна полиця.
        errs = validate_enclosed_shelf(
            "enclosed_shelf",
            {"stiffening_rib": {"height_mm": 13}, "bend_radius_mm": 5},
            8,
        )
        assert len(errs) == 1
        assert errs[0].code == "FLANGE_TOO_SHORT"
        detail_lower = errs[0].detail.lower()
        assert "товщин" in detail_lower
        assert "радіус" in detail_lower

    def test_ребро_трохи_більше_t_r_і_більше_m_валідне(self) -> None:
        assert (
            validate_enclosed_shelf(
                "enclosed_shelf",
                {"stiffening_rib": {"height_mm": 13.5}, "bend_radius_mm": 5},
                8,
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

    @pytest.mark.parametrize("hole", [None, "x", True])
    def test_вміщення_не_залежить_від_отвору(self, hole: object) -> None:
        # 2c (2·margin ≤ d − (t+r)) від hole_size_mm не залежить: зіпсований отвір
        # не ховає PERFORATION_DOES_NOT_FIT (рецензія #314, паритет із TS).
        side = {**SIDE, "hole_size_mm": hole, "margin_mm": 48}
        errs = validate_enclosed_shelf(
            "enclosed_shelf", {"depth_mm": 100, "bend_radius_mm": 2.5, "side_perforation": side}, 2
        )
        assert ("PERFORATION_DOES_NOT_FIT", "side_perforation.margin_mm") in {
            (e.code, e.field) for e in errs
        }

    def test_рядки_числа_не_сліплять_гейт(self) -> None:
        # Pydantic у _params_with_defaults впала з іншої причини → рядки-числа
        # лишаються рядками; гейт усе одно бачить усі правила (контрприклад
        # Argon, PR #314; паритет із perforation.py, #274).
        side = {"hole_size_mm": "10", "pitch_x_mm": "10", "pitch_y_mm": "10", "margin_mm": "48"}
        params = {
            "depth_mm": 100,
            "bend_radius_mm": "2.5",
            "side_perforation": side,
            "stiffening_rib": {"height_mm": "5"},
        }
        codes = {(e.code, e.field) for e in validate_enclosed_shelf("enclosed_shelf", params, 2.5)}
        assert {
            ("FLANGE_TOO_SHORT", "stiffening_rib.height_mm"),
            ("HOLES_OVERLAP", "side_perforation.pitch_x_mm"),
            ("HOLES_OVERLAP", "side_perforation.pitch_y_mm"),
            ("PERFORATION_DOES_NOT_FIT", "side_perforation.margin_mm"),
        } <= codes, codes

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

    def test_issue_303_занадто_близько_до_гиба_і_в_кутовому_виступі(self) -> None:
        # depth=100, t=r=2.5, rib=15, h=20, px=37, py=39.5, m=10.5:
        # e_x-h/2=0.5 < a·t+r=7.5; e_y-h/2=0.5 < q=tr=5.
        side = {"hole_size_mm": 20, "pitch_x_mm": 37, "pitch_y_mm": 39.5, "margin_mm": 10.5}
        errs = validate_enclosed_shelf(
            "enclosed_shelf",
            {
                "depth_mm": 100,
                "bend_radius_mm": 2.5,
                "side_perforation": side,
                "stiffening_rib": {"height_mm": 15},
            },
            2.5,
            "cold_rolled_steel",
        )
        codes_fields = {(e.code, e.field) for e in errs}
        assert ("HOLE_TOO_CLOSE_TO_BEND", "side_perforation.margin_mm") in codes_fields
        assert ("HOLE_IN_CORNER_TAB", "side_perforation.margin_mm") in codes_fields

    def test_межа_гиба_валідна(self) -> None:
        # e_x-h/2 = 12.5-5 = 7.5 = a·t+r — межа включна.
        side = {"hole_size_mm": 10, "pitch_x_mm": 35, "pitch_y_mm": 35, "margin_mm": 12.5}
        errs = validate_enclosed_shelf(
            "enclosed_shelf",
            {
                "depth_mm": 100,
                "bend_radius_mm": 2.5,
                "side_perforation": side,
                "stiffening_rib": {"height_mm": 15},
            },
            2.5,
            "cold_rolled_steel",
        )
        assert not any(e.code == "HOLE_TOO_CLOSE_TO_BEND" for e in errs)

    def test_невідомий_материал_пропускає_лише_too_close_to_bend(self) -> None:
        side = {"hole_size_mm": 20, "pitch_x_mm": 37, "pitch_y_mm": 39.5, "margin_mm": 10.5}
        errs = validate_enclosed_shelf(
            "enclosed_shelf",
            {
                "depth_mm": 100,
                "bend_radius_mm": 2.5,
                "side_perforation": side,
                "stiffening_rib": {"height_mm": 15},
            },
            2.5,
            "unobtanium",
        )
        codes = [e.code for e in errs]
        assert "HOLE_TOO_CLOSE_TO_BEND" not in codes
        assert "HOLE_IN_CORNER_TAB" in codes


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
                "density_kg_m3": 7850,
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
                "density_kg_m3": 7850,
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
                "density_kg_m3": 7850,
            },
        )
        assert res.status_code == 200, res.text

    @staticmethod
    def _export(params: dict[str, object], t: float) -> tuple[int, set[tuple[str, str]]]:
        res = TestClient(app).post(
            "/export",
            json={
                "template_slug": "enclosed_shelf",
                "parameters": {**ENCLOSED_SHELF_VALID_PARAMS, **params},
                "thickness_mm": t,
                "material_code": "cold_rolled_steel",
                "density_kg_m3": 7850,
            },
        )
        if res.status_code != 422:
            return res.status_code, set()
        return 422, {(str(e.get("code")), str(e.get("field"))) for e in res.json()["detail"]}

    @pytest.mark.parametrize("axis", ["pitch_x_mm", "pitch_y_mm"])
    def test_крок_рівний_отвору_через_export_422(self, axis: str) -> None:
        # 2a через POST /export (постановка 056: кожне правило 1, 2a–2d).
        status, codes = self._export({"side_perforation": {**SIDE, axis: 10}}, 2)
        assert status == 422
        assert ("HOLES_OVERLAP", f"side_perforation.{axis}") in codes, codes

    def test_відступ_половина_отвору_через_export_422(self) -> None:
        # 2b через POST /export.
        status, codes = self._export({"side_perforation": {**SIDE, "margin_mm": 5}}, 2)
        assert status == 422
        assert ("MARGIN_TOO_SMALL", "side_perforation.margin_mm") in codes, codes

    def test_отвір_не_менший_за_боковину_через_export_422(self) -> None:
        # 2d через POST /export: отвір 96 ≥ боковини 100 − (2 + 2.5) = 95.5.
        side = {"hole_size_mm": 96, "pitch_x_mm": 100, "pitch_y_mm": 100, "margin_mm": 45}
        status, codes = self._export(
            {"depth_mm": 100, "bend_radius_mm": 2.5, "side_perforation": side}, 2
        )
        assert status == 422
        assert ("PERFORATION_DOES_NOT_FIT", "side_perforation.hole_size_mm") in codes, codes

    def test_ребро_на_межі_t_r_але_менше_m_через_export_422(self) -> None:
        # Доробка #304: 5.5 > t+r=5, але < M=7.5 — ребро — це полиця.
        status, codes = self._export(
            {"bend_radius_mm": 2.5, "stiffening_rib": {"height_mm": 5.5}}, 2.5
        )
        assert status == 422
        assert ("FLANGE_TOO_SHORT", "stiffening_rib.height_mm") in codes, codes

    def test_ребро_на_межі_m_через_export_200(self) -> None:
        # Межа правила 1 (M=7.5): 7.5 >= M і 7.5 > t+r=5 → експорт проходить.
        status, codes = self._export(
            {"bend_radius_mm": 2.5, "stiffening_rib": {"height_mm": 7.5}}, 2.5
        )
        assert status == 200, codes

    def test_зіпсований_отвір_не_ховає_вміщення_через_export(self) -> None:
        # Регресія рецензії #314: hole_size_mm не число → обидві помилки, а не одна.
        side = {**SIDE, "hole_size_mm": None, "margin_mm": 48}
        status, codes = self._export(
            {"depth_mm": 100, "bend_radius_mm": 2.5, "side_perforation": side}, 2
        )
        assert status == 422
        assert ("INVALID_PARAMETER_TYPE", "side_perforation.hole_size_mm") in codes, codes
        assert ("PERFORATION_DOES_NOT_FIT", "side_perforation.margin_mm") in codes, codes

    def test_рядки_числа_і_інше_зіпсоване_поле_через_export(self) -> None:
        # width_mm 200 < 300 валить Pydantic → сирі parameters з рядками; гейт
        # усе одно дає структуровані помилки, а не лише текст invalid_parameters.
        side = {"hole_size_mm": "10", "pitch_x_mm": "10", "pitch_y_mm": "10", "margin_mm": "48"}
        status, codes = self._export(
            {"width_mm": 200, "depth_mm": 100, "side_perforation": side}, 2.5
        )
        assert status == 422
        assert ("HOLES_OVERLAP", "side_perforation.pitch_x_mm") in codes, codes
        assert ("PERFORATION_DOES_NOT_FIT", "side_perforation.margin_mm") in codes, codes


class TestSideHolesNearBendExport:
    """#303 через POST /export — сценарії постановки 060, яких бракувало (рецензія #321)."""

    BEND = ("HOLE_TOO_CLOSE_TO_BEND", "side_perforation.margin_mm")
    TAB = ("HOLE_IN_CORNER_TAB", "side_perforation.margin_mm")

    @staticmethod
    def _post(
        side: dict[str, float], rib: float | None = 15, material: str = "cold_rolled_steel"
    ) -> tuple[int, set[tuple[str, str]]]:
        params: dict[str, object] = {
            **ENCLOSED_SHELF_VALID_PARAMS,
            "depth_mm": 100,
            "bend_radius_mm": 2.5,
            "side_perforation": side,
            "stiffening_rib": None if rib is None else {"height_mm": rib},
        }
        res = TestClient(app).post(
            "/export",
            json={
                "template_slug": "enclosed_shelf",
                "parameters": params,
                "thickness_mm": 2.5,
                "material_code": material,
                "density_kg_m3": 7850,
            },
        )
        if res.status_code != 422:
            return res.status_code, set()
        return 422, {(str(e.get("code")), str(e.get("field"))) for e in res.json()["detail"]}

    @staticmethod
    def _side(h: float, px: float, py: float, m: float) -> dict[str, float]:
        return {"hole_size_mm": h, "pitch_x_mm": px, "pitch_y_mm": py, "margin_mm": m}

    def test_випадок_303_обидві_помилки(self) -> None:
        status, codes = self._post(self._side(20, 37, 39.5, 10.5))
        assert status == 422, codes
        assert {self.BEND, self.TAB} <= codes, codes

    def test_межа_гиба_200(self) -> None:
        # e_x − h/2 = 12.5 − 5 = 7.5 = a·t + r — межа включна.
        status, codes = self._post(self._side(10, 35, 35, 12.5))
        assert status == 200, codes

    def test_ближче_до_гиба_без_виступу(self) -> None:
        # n_x = 3, e_x = 11.5 → 6.5 < 7.5.
        status, codes = self._post(self._side(10, 36, 35, 11.5))
        assert status == 422, codes
        assert self.BEND in codes, codes
        assert self.TAB not in codes, codes

    def test_виступ_лише_з_ребром(self) -> None:
        status, codes = self._post(self._side(10, 35, 42, 8), rib=15)
        assert status == 422, codes
        assert self.TAB in codes, codes
        assert self.BEND not in codes, codes
        status, codes = self._post(self._side(10, 35, 42, 8), rib=None)
        assert status == 200, codes

    def test_від_ефективного_відступу_y(self) -> None:
        # n_y = 2, e_y = 27.5 (а не margin 8) → без виступу.
        status, codes = self._post(self._side(10, 35, 45, 8))
        assert status == 200, codes

    def test_коефіцієнт_матеріалу_з_таблиці(self) -> None:
        status, codes = self._post(self._side(10, 36, 35, 11.5), material="aluminum_5754")
        assert self.BEND not in codes, codes
        status, codes = self._post(self._side(10, 35, 35, 12.5), material="stainless_304")
        assert status == 422, codes
        assert self.BEND in codes, codes

    def test_крок_нуль_повз_pydantic_422_а_не_500(self) -> None:
        # width_mm 200 < 300 валить Pydantic → гейт бачить сирі параметри з кроком 0.
        res = TestClient(app, raise_server_exceptions=False).post(
            "/export",
            json={
                "template_slug": "enclosed_shelf",
                "parameters": {
                    **ENCLOSED_SHELF_VALID_PARAMS,
                    "width_mm": 200,
                    "depth_mm": 100,
                    "bend_radius_mm": 2.5,
                    "side_perforation": self._side(20, 0, 39.5, 10.5),
                    "stiffening_rib": {"height_mm": 15},
                },
                "thickness_mm": 2.5,
                "material_code": "cold_rolled_steel",
                "density_kg_m3": 7850,
            },
        )
        assert res.status_code == 422, res.text
