"""Тести довідника industry-назв матеріалів (Hotfix 2.9.d)."""

from __future__ import annotations

import logging

import pytest

from flatcraft_cad.materials.industry_names import (
    MaterialIndustryName,
    format_material_label,
    industry_name,
)

# (slug, очікувана марка, очікуваний стандарт) — усі матеріали з CLAUDE.md §7.
_EXPECTED: list[tuple[str, str, str]] = [
    ("cold_rolled_steel", "DC01", "ДСТУ EN 10130"),
    ("hot_rolled_steel", "S235JR", "ДСТУ EN 10025-2"),
    ("galvanized_steel", "DX51D+Z", "ДСТУ EN 10346"),
    ("stainless_304", "AISI 304", "ДСТУ EN 10088-2"),
    ("stainless_430", "AISI 430", "ДСТУ EN 10088-2"),
    ("aluminum_amg3", "АМг3", "ДСТУ 4400-86"),
    ("aluminum_5754", "5754-H22", "EN 573-3"),
    ("copper", "М1", "ДСТУ ГОСТ 859"),
    ("brass", "Л63", "ДСТУ ГОСТ 15527"),
]


class TestIndustryName:
    @pytest.mark.parametrize(("code", "name", "standard"), _EXPECTED)
    def test_кожен_матеріал_має_коректну_марку_і_стандарт(
        self, code: str, name: str, standard: str
    ) -> None:
        info = industry_name(code)
        assert info is not None
        assert isinstance(info, MaterialIndustryName)
        assert info.name == name
        assert info.standard == standard
        assert info.ukrainian_name  # непорожня українська назва

    def test_невідомий_код_дає_none(self) -> None:
        assert industry_name("unobtanium") is None

    def test_dataclass_незмінний(self) -> None:
        info = industry_name("cold_rolled_steel")
        assert info is not None
        with pytest.raises((AttributeError, TypeError)):
            info.name = "X"  # type: ignore[misc]


class TestFormatMaterialLabel:
    def test_формат_марка_стандарт_назва(self) -> None:
        assert (
            format_material_label("cold_rolled_steel")
            == "DC01 (ДСТУ EN 10130) — холоднокатана сталь"
        )

    def test_нержавійка(self) -> None:
        assert (
            format_material_label("stainless_304")
            == "AISI 304 (ДСТУ EN 10088-2) — нержавіюча сталь"
        )

    def test_невідомий_код_fallback_на_сирий_код(self, caplog: pytest.LogCaptureFixture) -> None:
        with caplog.at_level(logging.WARNING):
            label = format_material_label("mystery_alloy")
        assert label == "mystery_alloy"
        assert any("mystery_alloy" in rec.message for rec in caplog.records)
