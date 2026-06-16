"""Векторна ізометрія виробу для PDF-креслення (Phase 2.9.e, ADR-025).

Замість ручної 3D→2D проєкції згорнутої геометрії (крихко для гибів + отворів)
використовуємо вбудований OpenCascade hidden-line-removal (`HLRBRep_Algo`), яким
CadQuery уже володіє (`cadquery/occ_impl/exporters/svg.py:getSVG`). Worker будує
3D-solid через `build_*(params)` для кожного шаблону — проганяємо його через HLR і
отримуємо два набори 2D-полілайнів:

  • visible — ребра, видимі з камери (малюємо суцільними);
  • hidden  — приховані ребра (малюємо пунктиром).

Holes — частина solid, тож їхні кромки класифікуються visible/hidden автоматично.

Детермінізм (CLAUDE.md §2.4): OCC HLR детермінований для фіксованого input + версії
OCP; дискретизація з фіксованим tolerance → фіксовані точки. Геометрія — чиста
функція params, тому результат байт-у-байт стабільний.
"""

from __future__ import annotations

import cadquery as cq
from cadquery.occ_impl.shapes import TOLERANCE, Shape
from OCP.BRepLib import BRepLib
from OCP.GCPnts import GCPnts_QuasiUniformDeflection
from OCP.gp import gp_Ax2, gp_Dir, gp_Pnt
from OCP.HLRAlgo import HLRAlgo_Projector
from OCP.HLRBRep import HLRBRep_Algo, HLRBRep_HLRToShape
from OCP.TopoDS import TopoDS_Shape

# Точність дискретизації кривих у точки (мм у проєкційній площині). Те саме
# значення, що cadquery використовує у getSVG → стабільна кількість точок.
_DISCRETIZATION_TOLERANCE = 1e-3

# Справжня ізометрія: камера дивиться вздовж (1, 1, 1) — три осі симетричні.
_DEFAULT_DIRECTION: tuple[float, float, float] = (1.0, 1.0, 1.0)

# Полілайн = впорядкована послідовність 2D-точок у проєкційній площині (мм).
IsoPolyline = tuple[tuple[float, float], ...]


def _discretize_edge(edge: Shape) -> IsoPolyline:
    """Розбиває одне OCC-ребро на полілайн 2D-точок (на базі svg.makeSVGedge)."""
    curve = edge._geomAdaptor()  # type: ignore[attr-defined]
    points = GCPnts_QuasiUniformDeflection(
        curve,
        _DISCRETIZATION_TOLERANCE,
        curve.FirstParameter(),
        curve.LastParameter(),
    )
    if not points.IsDone():
        return ()
    return tuple(
        (points.Value(i + 1).X(), points.Value(i + 1).Y()) for i in range(points.NbPoints())
    )


def _edges_to_polylines(compounds: list[TopoDS_Shape]) -> tuple[IsoPolyline, ...]:
    """Дискретизує всі ребра набору OCC-компаундів у полілайни."""
    polylines: list[IsoPolyline] = []
    for compound in compounds:
        for edge in Shape(compound).Edges():
            poly = _discretize_edge(edge)
            if len(poly) >= 2:
                polylines.append(poly)
    return tuple(polylines)


def project_isometric(
    shape: cq.Workplane | Shape,
    *,
    direction: tuple[float, float, float] = _DEFAULT_DIRECTION,
) -> tuple[tuple[IsoPolyline, ...], tuple[IsoPolyline, ...]]:
    """Проєктує 3D-solid у 2D через HLR → (visible, hidden) полілайни.

    Повторює pipeline `cadquery.occ_impl.exporters.svg.getSVG`: HLR-алгоритм
    рахує видимі (`VCompound`/`OutLineVCompound`) і приховані
    (`HCompound`/`OutLineHCompound`) ребра, після чого ми їх дискретизуємо.
    `BuildCurves3d_s` обов'язковий перед дискретизацією (інакше segfault).
    """
    if isinstance(shape, cq.Workplane):
        solid = shape.val()
        assert isinstance(solid, Shape), "Workplane.val() має повертати Shape"
    else:
        solid = shape

    hlr = HLRBRep_Algo()
    hlr.Add(solid.wrapped)
    projector = HLRAlgo_Projector(gp_Ax2(gp_Pnt(), gp_Dir(*direction)))
    hlr.Projector(projector)
    hlr.Update()
    hlr.Hide()

    to_shape = HLRBRep_HLRToShape(hlr)

    visible: list[TopoDS_Shape] = [
        c
        for c in (to_shape.VCompound(), to_shape.Rg1LineVCompound(), to_shape.OutLineVCompound())
        if not c.IsNull()
    ]
    hidden: list[TopoDS_Shape] = [
        c for c in (to_shape.HCompound(), to_shape.OutLineHCompound()) if not c.IsNull()
    ]

    for compound in (*visible, *hidden):
        BRepLib.BuildCurves3d_s(compound, TOLERANCE)

    return _edges_to_polylines(visible), _edges_to_polylines(hidden)


def fit_to_box(
    polylines: tuple[IsoPolyline, ...],
    box_w_mm: float,
    box_h_mm: float,
) -> tuple[float, float, float]:
    """Повертає (scale, tx, ty) для вписування полілайнів у бокс зі збереженням
    пропорцій і центруванням.

    Трансформація точки (у координатах бокса, нуль = лівий-нижній кут):
    `x_box = x * scale + tx`, аналогічно для y. Порожній вхід → identity
    (scale=1, tx=ty=0), щоб виклик не падав.
    """
    xs = [x for poly in polylines for x, _ in poly]
    ys = [y for poly in polylines for _, y in poly]
    if not xs or not ys:
        return 1.0, 0.0, 0.0

    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    span_x = max(max_x - min_x, 1e-9)
    span_y = max(max_y - min_y, 1e-9)

    scale = min(box_w_mm / span_x, box_h_mm / span_y)
    # Центрування лишку всередині бокса + зсув bbox-мінімуму в нуль.
    tx = (box_w_mm - span_x * scale) / 2.0 - min_x * scale
    ty = (box_h_mm - span_y * scale) / 2.0 - min_y * scale
    return scale, tx, ty
