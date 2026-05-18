"""Тести PDF-експорту L-bracket."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from pypdf import PdfReader

from flatcraft_cad.export.pdf import compute_bom, export_l_bracket_pdf
from flatcraft_cad.templates.l_bracket import LBracketBuildParameters
from flatcraft_cad.unfold import unfold_l_bracket


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
    return export_l_bracket_pdf(params, unf, tmp_path / name)


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
