"""Тести для pure-функції розміщення badge'ів з номерами гибів.

Phase 2.9.b Block B: маленьке коло з номером гибу ПОСЕРЕДИНІ лінії гибу
(на додачу до повного callout збоку). Чиста геометрія у model-space мм —
тестується без рендерингу PDF/DXF.
"""

from __future__ import annotations

from flatcraft_cad.export.layout.bend_badges import (
    BADGE_DIAMETER_MM,
    MIN_LINE_LEN_FOR_INLINE_MM,
    BendBadge,
    BendLine2D,
    place_bend_badges,
)


class TestSingleBend:
    def test_badge_на_midpoint_довгої_лінії(self) -> None:
        lines = (BendLine2D(number=1, x_mm=50.0, y_start_mm=0.0, y_end_mm=100.0),)
        badges = place_bend_badges(lines)
        assert len(badges) == 1
        b = badges[0]
        assert b.number == 1
        assert b.x_mm == 50.0
        assert b.y_mm == 50.0  # midpoint
        assert b.has_leader is False

    def test_порожній_вхід_дає_порожній_вихід(self) -> None:
        assert place_bend_badges(()) == ()


class TestShortLine:
    def test_коротка_лінія_зміщує_badge_з_виноскою(self) -> None:
        # Лінія коротша за поріг → badge не вміщається інлайн.
        short = BendLine2D(number=1, x_mm=20.0, y_start_mm=0.0, y_end_mm=5.0)
        assert (short.y_end_mm - short.y_start_mm) < MIN_LINE_LEN_FOR_INLINE_MM
        badges = place_bend_badges((short,))
        b = badges[0]
        assert b.has_leader is True
        # Виноска веде до midpoint лінії.
        assert b.leader_to_x_mm == 20.0
        assert b.leader_to_y_mm == 2.5
        # Сам badge зміщено вище краю лінії (не на лінії).
        assert b.y_mm > short.y_end_mm

    def test_рівно_на_порозі_лишається_інлайн(self) -> None:
        line = BendLine2D(number=1, x_mm=0.0, y_start_mm=0.0, y_end_mm=MIN_LINE_LEN_FOR_INLINE_MM)
        badges = place_bend_badges((line,))
        assert badges[0].has_leader is False


class TestMultipleBends:
    def test_дві_далекі_лінії_обидві_інлайн(self) -> None:
        lines = (
            BendLine2D(number=1, x_mm=20.0, y_start_mm=0.0, y_end_mm=100.0),
            BendLine2D(number=2, x_mm=80.0, y_start_mm=0.0, y_end_mm=100.0),
        )
        badges = place_bend_badges(lines)
        assert len(badges) == 2
        assert all(not b.has_leader for b in badges)
        assert badges[0].number == 1
        assert badges[1].number == 2

    def test_номери_зберігають_порядок_вхідних_ліній(self) -> None:
        lines = (
            BendLine2D(number=3, x_mm=10.0, y_start_mm=0.0, y_end_mm=50.0),
            BendLine2D(number=7, x_mm=90.0, y_start_mm=0.0, y_end_mm=50.0),
        )
        badges = place_bend_badges(lines)
        assert [b.number for b in badges] == [3, 7]


class TestOverlapAvoidance:
    def test_близькі_лінії_зміщують_другий_badge(self) -> None:
        # Дві лінії ближче за діаметр badge по X на однаковій Y → накладка.
        lines = (
            BendLine2D(number=1, x_mm=50.0, y_start_mm=0.0, y_end_mm=100.0),
            BendLine2D(
                number=2,
                x_mm=50.0 + BADGE_DIAMETER_MM * 0.5,
                y_start_mm=0.0,
                y_end_mm=100.0,
            ),
        )
        badges = place_bend_badges(lines)
        # Перший на midpoint; другий зсунутий по Y, щоб не перекривати.
        assert badges[0].y_mm == 50.0
        assert badges[1].y_mm != badges[0].y_mm
        assert abs(badges[1].y_mm - badges[0].y_mm) >= BADGE_DIAMETER_MM

    def test_зсунутий_через_overlap_badge_отримує_виноску(self) -> None:
        lines = (
            BendLine2D(number=1, x_mm=50.0, y_start_mm=0.0, y_end_mm=100.0),
            BendLine2D(number=2, x_mm=51.0, y_start_mm=0.0, y_end_mm=100.0),
        )
        badges = place_bend_badges(lines)
        # Зсунутий badge має виноску назад до своєї лінії midpoint.
        assert badges[1].has_leader is True
        assert badges[1].leader_to_x_mm == 51.0
        assert badges[1].leader_to_y_mm == 50.0


class TestPdfGlue:
    """Перевіряє обгортку _bend_badges_for у pdf.py: будує лінії з позицій гибів."""

    def test_позиції_гибів_перетворюються_на_badge_за_номерами(self) -> None:
        from flatcraft_cad.export.pdf import _bend_badges_for

        badges = _bend_badges_for((30.0, 70.0), width_mm=100.0)
        assert [b.number for b in badges] == [1, 2]
        # Кожен badge на midpoint своєї лінії (width=100 → y=50).
        assert all(b.y_mm == 50.0 for b in badges)
        assert [b.x_mm for b in badges] == [30.0, 70.0]

    def test_без_гибів_дає_порожньо(self) -> None:
        from flatcraft_cad.export.pdf import _bend_badges_for

        assert _bend_badges_for((), width_mm=100.0) == ()


class TestBadgeDataclass:
    def test_badge_immutable(self) -> None:
        b = BendBadge(
            number=1, x_mm=1.0, y_mm=2.0, has_leader=False, leader_to_x_mm=1.0, leader_to_y_mm=2.0
        )
        import pytest

        with pytest.raises((AttributeError, TypeError)):
            b.number = 2  # type: ignore[misc]
