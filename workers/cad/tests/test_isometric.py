"""Тести векторної ізометрії (HLR-проєкція) для PDF — Phase 2.9.e, ADR-025."""

from __future__ import annotations

import cadquery as cq

from flatcraft_cad.export.isometric import fit_to_box, project_isometric
from flatcraft_cad.export.isometry_solid import with_isometry_holes
from flatcraft_cad.templates.corner_angle import CornerAngleBuildParameters, build_corner_angle
from flatcraft_cad.templates.l_bracket import LBracketBuildParameters, build_l_bracket
from flatcraft_cad.unfold import unfold_corner_angle


def _l_solid() -> cq.Workplane:
    params = LBracketBuildParameters.model_validate(
        {
            "leg_a_mm": 60.0,
            "leg_b_mm": 60.0,
            "bend_radius_mm": 2.5,
            "bend_angle_deg": 90,
            "width_mm": 100.0,
            "thickness_mm": 2.0,
        }
    )
    return build_l_bracket(params)


def _corner_params() -> CornerAngleBuildParameters:
    return CornerAngleBuildParameters.model_validate(
        {
            "leg_a_mm": 60.0,
            "leg_b_mm": 60.0,
            "bend_radius_mm": 2.5,
            "bend_angle_deg": 90,
            "width_mm": 100.0,
            "thickness_mm": 2.0,
            "hole_diameter_mm": 6.0,
            "hole_rows": 2,
            "hole_cols": 2,
            "hole_margin_mm": 10.0,
        }
    )


def _corner_solid() -> cq.Workplane:
    return build_corner_angle(_corner_params())


def _corner_holed_solid() -> cq.Shape:
    params = _corner_params()
    unfolded = unfold_corner_angle(params, 0.4)
    return with_isometry_holes(params, unfolded, build_corner_angle(params))


class TestProjectIsometric:
    def test_видимі_і_приховані_ребра_непорожні(self) -> None:
        visible, hidden = project_isometric(_l_solid())
        assert len(visible) > 0, "очікуємо видимі ребра"
        assert len(hidden) > 0, "згорнута деталь має приховані ребра"

    def test_кожен_полілайн_має_щонайменше_дві_точки(self) -> None:
        visible, hidden = project_isometric(_l_solid())
        for poly in (*visible, *hidden):
            assert len(poly) >= 2
            assert all(len(pt) == 2 for pt in poly)

    def test_детермінізм_однаковий_solid_однакові_координати(self) -> None:
        a_vis, a_hid = project_isometric(_l_solid())
        b_vis, b_hid = project_isometric(_l_solid())
        assert a_vis == b_vis
        assert a_hid == b_hid

    def test_отвори_додають_полілайни(self) -> None:
        base_vis, base_hid = project_isometric(_corner_solid())
        holed_vis, holed_hid = project_isometric(_corner_holed_solid())
        # Вирізані отвори → більше кромок (кола) у проєкції.
        assert (len(holed_vis) + len(holed_hid)) > (len(base_vis) + len(base_hid))


class TestFitToBox:
    def test_точки_вписуються_в_межі_бокса(self) -> None:
        visible, hidden = project_isometric(_l_solid())
        polys = (*visible, *hidden)
        box_w, box_h = 100.0, 48.0
        scale, tx, ty = fit_to_box(polys, box_w, box_h)
        for poly in polys:
            for x, y in poly:
                bx, by = x * scale + tx, y * scale + ty
                assert -1e-6 <= bx <= box_w + 1e-6
                assert -1e-6 <= by <= box_h + 1e-6

    def test_порожній_вхід_дає_identity(self) -> None:
        assert fit_to_box((), 100.0, 48.0) == (1.0, 0.0, 0.0)
