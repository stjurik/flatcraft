"""Тести PDF-експорту L-bracket."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from pypdf import PdfReader

from flatcraft_cad.export.pdf import (
    bom_text_lines,
    compute_bom,
    export_l_bracket_pdf,
    export_z_bracket_pdf,
)
from flatcraft_cad.templates.l_bracket import LBracketBuildParameters, build_l_bracket
from flatcraft_cad.templates.z_bracket import ZBracketBuildParameters, build_z_bracket
from flatcraft_cad.unfold import unfold_l_bracket, unfold_z_bracket


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


def _generate(tmp_path: Path, *, name: str = "out.pdf", **overrides: Any) -> Path:
    params = _params(**overrides)
    unf = unfold_l_bracket(params, k_factor=0.4)
    solid = build_l_bracket(params)
    return export_l_bracket_pdf(params, unf, tmp_path / name, solid=solid)


class TestBetaWatermark:
    """Phase X.1 B: footer watermark «BETA · feedback» на кожній сторінці."""

    def test_l_bracket_pdf_містить_beta_watermark(self, tmp_path: Path) -> None:
        out = _generate(tmp_path)
        text = PdfReader(str(out)).pages[0].extract_text() or ""
        assert "BETA" in text
        assert "feedback@hart.crimea.ua" in text

    def test_z_bracket_max_params_не_ламає_watermark(self, tmp_path: Path) -> None:
        # Найдовша деталь (max полиці/offset/width) — watermark все одно у footer.
        params = ZBracketBuildParameters.model_validate(
            {
                "top_flange_mm": 500,
                "bottom_flange_mm": 500,
                "offset_mm": 500,
                "bend_radius_mm": 2.5,
                "width_mm": 3000,
                "thickness_mm": 2.0,
            }
        )
        unf = unfold_z_bracket(params, k_factor=0.4)
        solid = build_z_bracket(params)
        out = export_z_bracket_pdf(params, unf, tmp_path / "z-max.pdf", solid=solid)
        text = PdfReader(str(out)).pages[0].extract_text() or ""
        assert "BETA" in text

    def test_watermark_прапор_вимикається(self, tmp_path: Path) -> None:
        import flatcraft_cad.export.pdf as pdf_mod

        original = pdf_mod.BETA_WATERMARK
        try:
            pdf_mod.BETA_WATERMARK = False
            out = _generate(tmp_path, name="no-beta.pdf")
            text = PdfReader(str(out)).pages[0].extract_text() or ""
            assert "feedback@hart.crimea.ua" not in text
        finally:
            pdf_mod.BETA_WATERMARK = original


class TestStructure:
    def test_файл_створено_і_починається_з_pdf_magic(self, tmp_path: Path) -> None:
        out = _generate(tmp_path)
        assert out.exists()
        assert out.stat().st_size > 1000
        with out.open("rb") as f:
            assert f.read(4) == b"%PDF"

    def test_metadata_містить_очікувані_поля(self, tmp_path: Path) -> None:
        out = _generate(tmp_path)
        reader = PdfReader(str(out))
        meta = reader.metadata
        assert meta is not None
        assert "L-bracket" in str(meta.title)
        assert "flatcraft" in str(meta.author).lower()

    def test_одна_сторінка_landscape_a4(self, tmp_path: Path) -> None:
        out = _generate(tmp_path)
        reader = PdfReader(str(out))
        assert len(reader.pages) == 1
        page = reader.pages[0]
        # A4 landscape = 297mm × 210mm = 841.89 × 595.28 points.
        w = float(page.mediabox.width)
        h = float(page.mediabox.height)
        assert w > h, "landscape: width > height"
        assert abs(w - 841.89) < 1
        assert abs(h - 595.28) < 1

    def test_текст_сторінки_містить_ключові_секції(self, tmp_path: Path) -> None:
        out = _generate(tmp_path)
        reader = PdfReader(str(out))
        text = reader.pages[0].extract_text() or ""
        # Розгортка: "L = ... мм"
        assert "BEND" in text
        # Bend table
        assert "K-" in text or "K­" in text or "0.40" in text
        # BOM
        assert "Bill of materials" in text or "BOM" in text or "Матеріал" in text


class TestMaterialIndustryName:
    """Hotfix 2.9.d: BOM показує industry-марку матеріалу, не сирий slug."""

    def test_bom_містить_industry_назву_за_замовчуванням(self, tmp_path: Path) -> None:
        # Дефолт material_label="cold_rolled_steel" → DC01.
        out = _generate(tmp_path)
        text = PdfReader(str(out)).pages[0].extract_text() or ""
        assert "DC01 (ДСТУ EN 10130)" in text
        assert "холоднокатана сталь" in text
        # Сирий slug у BOM більше не з'являється.
        assert "cold_rolled_steel" not in text

    def test_передана_марка_нержавійки(self, tmp_path: Path) -> None:
        params = _params()
        unf = unfold_l_bracket(params, k_factor=0.4)
        out = export_l_bracket_pdf(params, unf, tmp_path / "ss.pdf", material_label="stainless_304")
        text = PdfReader(str(out)).pages[0].extract_text() or ""
        assert "AISI 304 (ДСТУ EN 10088-2)" in text


class TestParameters:
    def test_різні_розміри_дають_різні_pdf(self, tmp_path: Path) -> None:
        a = _generate(tmp_path, name="a.pdf", leg_a_mm=60).read_bytes()
        b = _generate(tmp_path, name="b.pdf", leg_a_mm=120).read_bytes()
        assert a != b
        assert len(a) > 1000
        assert len(b) > 1000


class TestDeterminism:
    def test_однаковий_вхід_однакові_байти(self, tmp_path: Path) -> None:
        """Однакові params → байт-у-байт ідентичний PDF
        (timestamp/ID нормалізуються post-write)."""
        a = _generate(tmp_path, name="a.pdf").read_bytes()
        b = _generate(tmp_path, name="b.pdf").read_bytes()
        assert a == b


class TestComputeBOM:
    """Pure-функція BOM, без PDF (Cyrillic не екстрактується з Helvetica)."""

    def test_60x60_t2_w100_cold_rolled_about_182g(self) -> None:
        unf = unfold_l_bracket(_params(), k_factor=0.4)
        bom = compute_bom(unf)
        # length ≈ 116.18 мм, width=100, thickness=2.
        # area = 116.18×100 ≈ 11618 мм²
        # volume = area·thickness / 1e9 ≈ 2.32e-5 м³; mass = 7850·V ≈ 182 г.
        assert 11500 <= bom["area_mm2"] <= 11700
        assert abs(bom["mass_g"] - 182.0) < 5

    def test_густина_алюмінію_дає_меншу_масу(self) -> None:
        unf = unfold_l_bracket(_params(), k_factor=0.33)
        steel = compute_bom(unf, density_kg_m3=7850)
        alu = compute_bom(unf, density_kg_m3=2660)
        # Площа однакова, маса алюмінію ≈ 1/3 від сталі.
        assert steel["area_mm2"] == alu["area_mm2"]
        assert alu["mass_g"] < steel["mass_g"] / 2.8

    def test_більший_аркуш_більша_маса(self) -> None:
        small = compute_bom(unfold_l_bracket(_params(width_mm=50), k_factor=0.4))
        big = compute_bom(unfold_l_bracket(_params(width_mm=200), k_factor=0.4))
        assert big["mass_g"] > small["mass_g"] * 3.9  # ~4× per width.

    def test_mass_kg_дорівнює_mass_g_поділеному_1000(self) -> None:
        bom = compute_bom(unfold_l_bracket(_params(), k_factor=0.4))
        assert bom["mass_kg"] == bom["mass_g"] / 1000.0

    def test_площа_фарбування_удвічі_більша_за_заготовку(self) -> None:
        # Фарбування з обох боків листа.
        bom = compute_bom(unfold_l_bracket(_params(), k_factor=0.4))
        assert bom["area_paint_m2"] == _pytest_approx(bom["area_m2"] * 2.0)


class TestBomTextLines:
    """Pure-рядки BOM: UA-лейбли, нові одиниці (кг, площа фарбування), no-English."""

    _BOM = {
        "area_mm2": 17618.0,
        "area_m2": 0.017618,
        "area_paint_m2": 0.035236,
        "volume_m3": 3.5236e-05,
        "mass_g": 276.6,
        "mass_kg": 0.2766,
    }

    def test_включає_volume_шість_рядків(self) -> None:
        lines = bom_text_lines(material_label="cold_rolled_steel", thickness_mm=2.0, bom=self._BOM)
        assert len(lines) == 6

    def test_без_volume_5_рядків(self) -> None:
        lines = bom_text_lines(
            material_label="cold_rolled_steel",
            thickness_mm=2.0,
            bom=self._BOM,
            include_volume=False,
        )
        assert len(lines) == 5
        assert not any("Об'єм" in ln for ln in lines)

    def test_маса_у_кг_площа_фарбування_присутні(self) -> None:
        lines = bom_text_lines(material_label="aisi_304", thickness_mm=1.5, bom=self._BOM)
        joined = "\n".join(lines)
        assert "Маса: 0.28 кг" in joined  # 0.2766 → 0.28
        assert "Площа фарбування: 0.035 м²" in joined

    def test_лейбли_без_англійських_слів(self) -> None:
        # Лейбл (до ":") — суто український; англійською лишається лише значення.
        import re

        lines = bom_text_lines(material_label="cold_rolled_steel", thickness_mm=2.0, bom=self._BOM)
        for ln in lines:
            label = ln.split(":", 1)[0]
            assert not re.search(r"[A-Za-z]{4,}", label), f"англ. у лейблі: {label!r}"


def _pytest_approx(value: float) -> Any:
    import pytest

    return pytest.approx(value)
