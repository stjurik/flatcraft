"""DXF-експорт: structural-snapshot + byte-у-байт регресія (in-process)."""

import json
from pathlib import Path
from typing import Any

import pytest
from ezdxf import readfile  # type: ignore[attr-defined]

from flatcraft_cad.export.dxf import (
    DXF_LAYERS,
    export_corner_angle_dxf,
    export_l_bracket_dxf,
    export_perforated_panel_dxf,
    export_wall_shelf_dxf,
    export_z_bracket_dxf,
)
from flatcraft_cad.templates.corner_angle import CornerAngleBuildParameters
from flatcraft_cad.templates.l_bracket import LBracketBuildParameters
from flatcraft_cad.templates.perforated_panel import PerforatedPanelBuildParameters
from flatcraft_cad.templates.wall_shelf import WallShelfBuildParameters
from flatcraft_cad.templates.z_bracket import ZBracketBuildParameters
from flatcraft_cad.unfold import (
    unfold_corner_angle,
    unfold_l_bracket,
    unfold_perforated_panel,
    unfold_wall_shelf,
    unfold_z_bracket,
)

SNAPSHOTS_DIR = Path(__file__).parent / "snapshots" / "dxf"

# Шари, які DXF-стандарт/ezdxf створює автоматично і які ми НЕ контролюємо
# (їх не можна видалити). Production-перевірки рахують лише наші custom-шари.
_MANDATORY_LAYERS = frozenset({"0", "Defpoints"})
# ADR-024: рівно 2 виробничі шари.
_EXPECTED_CUSTOM_LAYERS = frozenset({"LASER_CUT", "BEND_LINES"})


def _custom_layer_names(doc: Any) -> set[str]:
    """Імена шарів без обов'язкових авто-генерованих (0, Defpoints)."""
    return {layer.dxf.name for layer in doc.layers} - _MANDATORY_LAYERS


def _params(**overrides: Any) -> LBracketBuildParameters:
    defaults: dict[str, Any] = {
        "leg_a_mm": 60.0,
        "leg_b_mm": 60.0,
        "bend_radius_mm": 2.5,
        "bend_angle_deg": 90,
        "width_mm": 100.0,
        "thickness_mm": 2.0,
    }
    defaults.update(overrides)
    return LBracketBuildParameters(**defaults)


def _dxf_structure(dxf_path: Path) -> dict[str, Any]:
    """Витягує стабільний знімок DXF: layers + entities (без handles, без
    timestamp-ів, без $HANDSEED, без CLASS section). Структурний snapshot
    стабільний між середовищами (ezdxf-handles різняться по runtime,
    байтовий snapshot — ні)."""
    doc = readfile(dxf_path)

    layers = sorted(
        (
            {"name": layer.dxf.name, "color": int(layer.dxf.color)}
            for layer in doc.layers
            if layer.dxf.name in {name for name, _ in DXF_LAYERS}
        ),
        key=lambda r: r["name"],
    )

    entities: list[dict[str, Any]] = []
    for e in doc.modelspace():
        dxftype = e.dxftype()
        layer = e.dxf.layer
        # color 256 = BYLAYER (entity успадковує колір шару).
        color = int(e.dxf.color)
        if dxftype == "LWPOLYLINE":
            entities.append(
                {
                    "type": dxftype,
                    "layer": layer,
                    "color": color,
                    "closed": bool(e.closed),  # type: ignore[attr-defined]
                    "points": [
                        [round(x, 6), round(y, 6)]
                        for x, y in e.get_points("xy")  # type: ignore[attr-defined]
                    ],
                }
            )
        elif dxftype == "LINE":
            entities.append(
                {
                    "type": dxftype,
                    "layer": layer,
                    "color": color,
                    "start": [round(e.dxf.start.x, 6), round(e.dxf.start.y, 6)],
                    "end": [round(e.dxf.end.x, 6), round(e.dxf.end.y, 6)],
                }
            )
        elif dxftype == "CIRCLE":
            entities.append(
                {
                    "type": dxftype,
                    "layer": layer,
                    "color": color,
                    "center": [round(e.dxf.center.x, 6), round(e.dxf.center.y, 6)],
                    "radius": round(e.dxf.radius, 6),
                }
            )
        else:
            # ADR-024: TEXT/DIMENSION тощо у DXF заборонені (CAM-noise) —
            # фіксуємо лише тип, щоб snapshot впав, якщо щось просочиться.
            entities.append({"type": dxftype, "layer": layer})

    return {"layers": layers, "entities": entities}


class TestStructural:
    """Перевіряємо, що saved DXF дійсно містить очікувані entities на
    очікуваних шарах — не залежить від байтового layout."""

    def test_має_всі_очікувані_шари(self, tmp_path: Path) -> None:
        params = _params()
        unf = unfold_l_bracket(params, k_factor=0.4)
        out = export_l_bracket_dxf(unf, tmp_path / "l.dxf", bend_radius_mm=params.bend_radius_mm)
        doc = readfile(out)
        layer_names = {layer.dxf.name for layer in doc.layers}
        for expected, _color in DXF_LAYERS:
            assert expected in layer_names, f"Missing layer {expected}"

    def test_laser_cut_прямокутник_правильних_розмірів(self, tmp_path: Path) -> None:
        params = _params(leg_a_mm=40, leg_b_mm=80, width_mm=200)
        unf = unfold_l_bracket(params, k_factor=0.4)
        out = export_l_bracket_dxf(unf, tmp_path / "l.dxf", bend_radius_mm=params.bend_radius_mm)
        doc = readfile(out)
        polys = list(doc.modelspace().query("LWPOLYLINE[layer=='LASER_CUT']"))
        assert len(polys) == 1
        pts = list(polys[0].get_points("xy"))
        assert pts[0] == pytest.approx((0.0, 0.0))
        assert pts[1] == pytest.approx((unf.length_mm, 0.0))
        assert pts[2] == pytest.approx((unf.length_mm, unf.width_mm))
        assert pts[3] == pytest.approx((0.0, unf.width_mm))

    def test_bend_line_на_позиції_розрахунку(self, tmp_path: Path) -> None:
        params = _params()
        unf = unfold_l_bracket(params, k_factor=0.4)
        out = export_l_bracket_dxf(unf, tmp_path / "l.dxf", bend_radius_mm=params.bend_radius_mm)
        doc = readfile(out)
        lines = list(doc.modelspace().query("LINE[layer=='BEND_LINES']"))
        assert len(lines) == 1
        line = lines[0]
        assert line.dxf.start.x == pytest.approx(unf.bend_position_mm)
        assert line.dxf.end.x == pytest.approx(unf.bend_position_mm)
        assert line.dxf.start.y == pytest.approx(0.0)
        assert line.dxf.end.y == pytest.approx(unf.width_mm)

    def test_кожен_шар_має_конфігурований_колір(self, tmp_path: Path) -> None:
        params = _params()
        unf = unfold_l_bracket(params, k_factor=0.4)
        out = export_l_bracket_dxf(unf, tmp_path / "l.dxf", bend_radius_mm=params.bend_radius_mm)
        doc = readfile(out)
        for name, expected_color in DXF_LAYERS:
            layer = doc.layers.get(name)
            assert layer.dxf.color == expected_color


def _corner_angle_dxf(tmp_path: Path) -> Path:
    """corner_angle DXF з grid'ом отворів — для перевірки inner-cut шару/кольору."""
    params = CornerAngleBuildParameters.model_validate(
        {
            "leg_a_mm": 60.0,
            "leg_b_mm": 60.0,
            "bend_radius_mm": 2.5,
            "bend_angle_deg": 90,
            "width_mm": 100.0,
            "thickness_mm": 2.0,
            "hole_rows": 2,
            "hole_cols": 2,
            "hole_diameter_mm": 6.0,
            "hole_margin_mm": 15.0,
        }
    )
    unf = unfold_corner_angle(params, k_factor=0.4)
    return export_corner_angle_dxf(unf, tmp_path / "corner.dxf", bend_radius_mm=2.5)


def _build_template_dxf(slug: str, tmp_path: Path) -> Path:
    """Експортує DXF кожного з 5 шаблонів з фіксованими параметрами.

    Один helper → snapshot + structure-перевірки покривають усі шаблони
    однаково. Параметри дзеркалять *_VALID_PARAMS з test_server (camelCase
    аліаси) + thickness_mm."""
    out = tmp_path / f"{slug}.dxf"
    if slug == "l_bracket":
        params = LBracketBuildParameters.model_validate(
            {
                "legA_mm": 60,
                "legB_mm": 60,
                "bend_radius_mm": 2.5,
                "bend_angle_deg": 90,
                "width_mm": 100,
                "thickness_mm": 2.0,
            }
        )
        return export_l_bracket_dxf(
            unfold_l_bracket(params, k_factor=0.4), out, bend_radius_mm=params.bend_radius_mm
        )
    if slug == "z_bracket":
        zparams = ZBracketBuildParameters.model_validate(
            {
                "top_flange_mm": 60,
                "bottom_flange_mm": 60,
                "offset_mm": 40,
                "bend_radius_mm": 2.5,
                "bend_angle_deg": 90,
                "width_mm": 100,
                "thickness_mm": 2.0,
            }
        )
        return export_z_bracket_dxf(
            unfold_z_bracket(zparams, k_factor=0.4), out, bend_radius_mm=zparams.bend_radius_mm
        )
    if slug == "corner_angle":
        cparams = CornerAngleBuildParameters.model_validate(
            {
                "legA_mm": 60,
                "legB_mm": 60,
                "bend_radius_mm": 2.5,
                "bend_angle_deg": 90,
                "width_mm": 80,
                "thickness_mm": 2.0,
                "hole_diameter_mm": 5,
                "hole_rows": 1,
                "hole_cols": 2,
                "hole_margin_mm": 12,
            }
        )
        return export_corner_angle_dxf(
            unfold_corner_angle(cparams, k_factor=0.4), out, bend_radius_mm=cparams.bend_radius_mm
        )
    if slug == "wall_shelf":
        wparams = WallShelfBuildParameters.model_validate(
            {
                "back_height_mm": 80,
                "shelf_depth_mm": 150,
                "front_lip_mm": 20,
                "bend_radius_mm": 2.5,
                "bend_angle_deg": 90,
                "width_mm": 300,
                "thickness_mm": 2.0,
                "mount_hole_diameter_mm": 6,
                "mount_hole_rows": 2,
                "mount_hole_cols": 2,
                "mount_hole_margin_mm": 15,
            }
        )
        return export_wall_shelf_dxf(
            unfold_wall_shelf(wparams, k_factor=0.4), out, bend_radius_mm=wparams.bend_radius_mm
        )
    if slug == "perforated_panel":
        pparams = PerforatedPanelBuildParameters.model_validate(
            {
                "length_mm": 200,
                "width_mm": 150,
                "thickness_mm": 2.0,
                "hole_shape": "square",
                "hole_size_mm": 8,
                "pitch_x_mm": 20,
                "pitch_y_mm": 20,
                "margin_mm": 15,
                "rib_height_mm": 30,
            }
        )
        return export_perforated_panel_dxf(unfold_perforated_panel(pparams), out)
    raise ValueError(f"unknown slug {slug!r}")


_ALL_TEMPLATES = ("l_bracket", "z_bracket", "corner_angle", "wall_shelf", "perforated_panel")


class TestProductionGradeDxf:
    """ADR-024 (Hotfix 2.9.d): production-grade DXF для CAM (Lantek/ESI).

    Інваріант: рівно 2 виробничі шари (LASER_CUT + BEND_LINES), усі cut-paths
    на LASER_CUT (outer ByLayer, inner отвори color 5), жодного TEXT/DIMENSION
    (CAM-noise). Ці 4 тести — RED-діагностика P0-бага «отвори поза LASER_CUT».
    """

    def test_рівно_два_виробничі_шари(self, tmp_path: Path) -> None:
        params = _params()
        unf = unfold_l_bracket(params, k_factor=0.4)
        out = export_l_bracket_dxf(unf, tmp_path / "l.dxf", bend_radius_mm=params.bend_radius_mm)
        doc = readfile(out)
        assert _custom_layer_names(doc) == set(_EXPECTED_CUSTOM_LAYERS)

    def test_отвори_на_laser_cut_з_кольором_5(self, tmp_path: Path) -> None:
        out = _corner_angle_dxf(tmp_path)
        doc = readfile(out)
        circles = list(doc.modelspace().query("CIRCLE"))
        assert circles, "очікували принаймні один отвір (CIRCLE)"
        for circ in circles:
            assert circ.dxf.layer == "LASER_CUT", "отвори мусять бути на LASER_CUT"
            assert int(circ.dxf.color) == 5, "inner-cut отвори — explicit color 5 (blue)"

    def test_зовнішній_контур_на_laser_cut_bylayer(self, tmp_path: Path) -> None:
        params = _params()
        unf = unfold_l_bracket(params, k_factor=0.4)
        out = export_l_bracket_dxf(unf, tmp_path / "l.dxf", bend_radius_mm=params.bend_radius_mm)
        doc = readfile(out)
        polys = list(doc.modelspace().query("LWPOLYLINE[layer=='LASER_CUT']"))
        assert len(polys) == 1
        # 256 = BYLAYER: зовнішній контур успадковує колір шару (white 7).
        assert int(polys[0].dxf.color) == 256

    def test_жодного_text_або_dimension(self, tmp_path: Path) -> None:
        out = _corner_angle_dxf(tmp_path)
        doc = readfile(out)
        types = {e.dxftype() for e in doc.modelspace()}
        assert "TEXT" not in types, "TEXT-анотації заборонені у DXF (CAM-noise)"
        assert "DIMENSION" not in types, "DIMENSION заборонені у DXF (CAM-noise)"
        # "0"/"Defpoints" ezdxf створює автоматично (видалити не можна), але
        # вони мусять лишатись ПОРОЖНІМИ — інакше це CAM-noise.
        for e in doc.modelspace():
            assert e.dxf.layer not in _MANDATORY_LAYERS, (
                f"entity {e.dxftype()} на службовому шарі {e.dxf.layer}"
            )

    @pytest.mark.parametrize("slug", _ALL_TEMPLATES)
    def test_кожен_шаблон_рівно_2_шари_правильні_кольори(self, slug: str, tmp_path: Path) -> None:
        """5 шаблонів × інваріант: рівно 2 виробничі шари з кольорами 7/3."""
        doc = readfile(_build_template_dxf(slug, tmp_path))
        assert _custom_layer_names(doc) == set(_EXPECTED_CUSTOM_LAYERS)
        assert int(doc.layers.get("LASER_CUT").dxf.color) == 7
        assert int(doc.layers.get("BEND_LINES").dxf.color) == 3
        # Жодного TEXT/DIMENSION у жодному шаблоні.
        types = {e.dxftype() for e in doc.modelspace()}
        assert not (types & {"TEXT", "DIMENSION"})

    def test_integration_reopen_corner_angle(self, tmp_path: Path) -> None:
        """Reopen через ezdxf: 2 шари, N CIRCLE color 5 (= к-ть отворів),
        1 LWPOLYLINE ByLayer, нуль entity на службових шарах (ADR-024)."""
        cparams = CornerAngleBuildParameters.model_validate(
            {
                "legA_mm": 60,
                "legB_mm": 60,
                "bend_radius_mm": 2.5,
                "bend_angle_deg": 90,
                "width_mm": 80,
                "thickness_mm": 2.0,
                "hole_diameter_mm": 5,
                "hole_rows": 2,
                "hole_cols": 2,
                "hole_margin_mm": 12,
            }
        )
        unf = unfold_corner_angle(cparams, k_factor=0.4)
        out = export_corner_angle_dxf(unf, tmp_path / "c.dxf", bend_radius_mm=2.5)

        doc = readfile(out)
        msp = doc.modelspace()
        assert _custom_layer_names(doc) == set(_EXPECTED_CUSTOM_LAYERS)

        circles = list(msp.query("CIRCLE"))
        assert len(circles) == len(unf.holes) > 0
        assert all(c.dxf.layer == "LASER_CUT" and int(c.dxf.color) == 5 for c in circles)

        polys = list(msp.query("LWPOLYLINE"))
        assert len(polys) == 1
        assert polys[0].dxf.layer == "LASER_CUT"
        assert int(polys[0].dxf.color) == 256  # BYLAYER

        assert all(e.dxf.layer not in _MANDATORY_LAYERS for e in msp)


class TestDeterminism:
    """Phase 1.8: однакові params → байт-у-байт однакові DXF.

    Перевіряється in-process (одна Python-сесія): post-write нормалізація
    усуває timestamp-и/GUID-и. Між середовищами байти можуть різнитися
    через ezdxf internal handle counter — структурний snapshot стабільний,
    байтовий — лише як safety-net у dev.
    """

    def test_однаковий_вхід_однакові_байти(self, tmp_path: Path) -> None:
        params = _params()
        unf = unfold_l_bracket(params, k_factor=0.4)
        a = export_l_bracket_dxf(
            unf, tmp_path / "a.dxf", bend_radius_mm=params.bend_radius_mm
        ).read_bytes()
        b = export_l_bracket_dxf(
            unf, tmp_path / "b.dxf", bend_radius_mm=params.bend_radius_mm
        ).read_bytes()
        assert a == b

    def test_різний_вхід_різні_байти(self, tmp_path: Path) -> None:
        unf_small = unfold_l_bracket(_params(), k_factor=0.4)
        unf_big = unfold_l_bracket(_params(leg_a_mm=120), k_factor=0.4)
        a = export_l_bracket_dxf(unf_small, tmp_path / "a.dxf", bend_radius_mm=2.5).read_bytes()
        b = export_l_bracket_dxf(unf_big, tmp_path / "b.dxf", bend_radius_mm=2.5).read_bytes()
        assert a != b


class TestSnapshot:
    """Регресія: фіксовані params → фіксована structural-структура DXF.

    Snapshot — це JSON-серіалізована структура (шари + entities). Це
    стабільне між середовищами на відміну від ezdxf-байт (handles auto-
    increment залежить від runtime).

    Якщо тест падає — або змінилася формула розгортки/контур, або
    додали/прибрали entities. У такому випадку:
      1. Перевірити через TestStructural, що зміна геометрично коректна.
      2. Оновити snapshot: `pytest --snapshot-update`.
    """

    @pytest.mark.parametrize(
        ("name", "params_overrides"),
        [
            ("l_bracket_60x60_t2_r25", {}),
            (
                "l_bracket_40x80_t1.5_r2.5",
                {"leg_a_mm": 40, "leg_b_mm": 80, "thickness_mm": 1.5},
            ),
            (
                "l_bracket_120x80_t3_r4",
                {"leg_a_mm": 120, "leg_b_mm": 80, "thickness_mm": 3, "bend_radius_mm": 4},
            ),
        ],
    )
    def test_dxf_structural_snapshot(
        self,
        snapshot: Any,
        tmp_path: Path,
        name: str,
        params_overrides: dict[str, float],
    ) -> None:
        params = _params(**params_overrides)
        unf = unfold_l_bracket(params, k_factor=0.4)
        out = export_l_bracket_dxf(
            unf, tmp_path / f"{name}.dxf", bend_radius_mm=params.bend_radius_mm
        )
        structure = _dxf_structure(out)
        # JSON з відсортованими ключами і indent=2 — diff читабельний.
        json_text = json.dumps(structure, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
        snapshot.snapshot_dir = SNAPSHOTS_DIR
        snapshot.assert_match(json_text, f"{name}.json")

    @pytest.mark.parametrize("slug", _ALL_TEMPLATES)
    def test_всі_шаблони_structural_snapshot(
        self, snapshot: Any, tmp_path: Path, slug: str
    ) -> None:
        """Hotfix 2.9.d: по одному structural-snapshot на кожен з 5 шаблонів —
        фіксує 2 шари + кольори + cut-геометрію (CAM-регресія ADR-024)."""
        structure = _dxf_structure(_build_template_dxf(slug, tmp_path))
        json_text = json.dumps(structure, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
        snapshot.snapshot_dir = SNAPSHOTS_DIR
        snapshot.assert_match(json_text, f"template_{slug}.json")
