"""Тести pick_annotation_corner — авто-вибір кута для блоку анотацій (Phase 2.9.b E).

Аркуш A4-landscape у мм: 297 × 210. Геометрію зміщуємо в один кут, щоб
найбільший вільний прямокутник був у протилежному — детерміновано.
"""

from __future__ import annotations

import pytest

from flatcraft_cad.export.layout.corner_picker import (
    BBox2D,
    Corner,
    Size2D,
    pick_annotation_corner,
)

_PAGE = BBox2D(0.0, 0.0, 297.0, 210.0)
_ANNOT = Size2D(width_mm=50.0, height_mm=40.0)


class TestFourCorners:
    def test_геометрія_внизу_справа_дає_tl(self) -> None:
        geom = BBox2D(180.0, 0.0, 297.0, 90.0)
        assert pick_annotation_corner(geom, _PAGE, _ANNOT) is Corner.TL

    def test_геометрія_внизу_зліва_дає_tr(self) -> None:
        geom = BBox2D(0.0, 0.0, 120.0, 90.0)
        assert pick_annotation_corner(geom, _PAGE, _ANNOT) is Corner.TR

    def test_геометрія_вгорі_справа_дає_bl(self) -> None:
        geom = BBox2D(180.0, 120.0, 297.0, 210.0)
        assert pick_annotation_corner(geom, _PAGE, _ANNOT) is Corner.BL

    def test_геометрія_вгорі_зліва_дає_br(self) -> None:
        geom = BBox2D(0.0, 120.0, 120.0, 210.0)
        assert pick_annotation_corner(geom, _PAGE, _ANNOT) is Corner.BR


class TestSlackPreference:
    def test_вибирає_кут_з_більшим_запасом(self) -> None:
        # Геометрія зміщена ліворуч-донизу → найбільший вільний прямокутник
        # у верхньому-правому куті.
        geom = BBox2D(0.0, 0.0, 100.0, 80.0)
        assert pick_annotation_corner(geom, _PAGE, _ANNOT) is Corner.TR


class TestDegenerate:
    def test_геометрія_заповнює_аркуш_fallback_br(self) -> None:
        geom = BBox2D(0.0, 0.0, 297.0, 210.0)
        assert pick_annotation_corner(geom, _PAGE, _ANNOT) is Corner.BR

    def test_жоден_кут_не_вміщає_fallback_br(self) -> None:
        # Велика анотація + геометрія по центру: ніде не влазить, але ≤ аркуша.
        geom = BBox2D(40.0, 30.0, 257.0, 180.0)
        big = Size2D(width_mm=120.0, height_mm=120.0)
        assert pick_annotation_corner(geom, _PAGE, big) is Corner.BR


class TestErrors:
    def test_анотація_ширша_за_аркуш_raises(self) -> None:
        with pytest.raises(ValueError, match="не влазить"):
            pick_annotation_corner(
                BBox2D(0, 0, 10, 10), _PAGE, Size2D(width_mm=400.0, height_mm=40.0)
            )

    def test_анотація_вища_за_аркуш_raises(self) -> None:
        with pytest.raises(ValueError, match="не влазить"):
            pick_annotation_corner(
                BBox2D(0, 0, 10, 10), _PAGE, Size2D(width_mm=50.0, height_mm=300.0)
            )


class TestPdfGlue:
    """Маппінг кута у координати BOM-блоку (_choose_bom_origin у pdf.py)."""

    def test_більше_рядків_таблиці_опускає_bom_нижче(self) -> None:
        from flatcraft_cad.export.pdf import _choose_bom_origin

        one = _choose_bom_origin(1)
        two = _choose_bom_origin(2)
        assert one[0] == two[0] == 175.0  # та сама колонка
        assert two[1] < one[1]  # 2 гиби → BOM нижче (слідує за таблицею)


class TestMargin:
    def test_margin_зменшує_вільний_простір(self) -> None:
        # Геометрія лишає рівно 55мм ліворуч; з margin=10 вільна ширина=45 < 50 → TL не вміщає.
        geom = BBox2D(55.0, 0.0, 297.0, 210.0)
        # Зверху/знизу місця нема (геометрія на всю висоту) → ніде не влазить → BR fallback.
        assert pick_annotation_corner(geom, _PAGE, _ANNOT, margin_mm=10.0) is Corner.BR

    def test_менший_margin_дозволяє_влізти(self) -> None:
        geom = BBox2D(65.0, 0.0, 297.0, 100.0)
        # margin=0 → ліворуч вільно 65 ≥ 50, зверху 110 ≥ 40 → TL вміщає.
        assert pick_annotation_corner(geom, _PAGE, _ANNOT, margin_mm=0.0) is Corner.TL
