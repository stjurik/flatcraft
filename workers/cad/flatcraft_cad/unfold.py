"""Розгортка sheet-metal моделі у плоский патерн.

Формула bend allowance (BA) — це довжина матеріалу по нейтральній осі гиба:
    BA = (π/180) · angle_deg · (R + K · t)
де R — внутрішній радіус, t — товщина, K — K-фактор (з cad-engine).

Для L-кронштейна з одним 90° гибом розгортка — це смужка довжиною
    L = (leg_a − t − R) + BA + (leg_b − t − R)
з лінією гиба у центрі BA-сегмента.

Для Z-кронштейна (Phase 2.10) — два 90° гиби, 3 плоских сегменти,
2 лінії гиба:
    L = (bottom − t − R) + BA + (offset − t − R) + BA + (top − t − R)

CadQuery-розгортка через `Workplane.shell()` поки не використовується —
формула достатня для регулярних гнутих профілів.
"""

import math
from dataclasses import dataclass, field
from typing import Literal

from flatcraft_cad.templates.corner_angle import CornerAngleBuildParameters
from flatcraft_cad.templates.enclosed_shelf import EnclosedShelfBuildParameters
from flatcraft_cad.templates.l_bracket import LBracketBuildParameters
from flatcraft_cad.templates.perforated_panel import PerforatedPanelBuildParameters
from flatcraft_cad.templates.perforated_panel_square import PerforatedPanelSquareBuildParameters
from flatcraft_cad.templates.wall_shelf import WallShelfBuildParameters
from flatcraft_cad.templates.z_bracket import ZBracketBuildParameters

HoleShape = Literal["circle", "square"]


@dataclass(frozen=True)
class Hole2D:
    """Отвір у плоскій розгортці. Центр у координатах (x, y) від
    нижнього-лівого кута заготовки, обидва у мм.

    Phase 3.0 PR 5 (ADR-027 Рішення 6): додано поле `shape` для розрізнення
    круглих vs квадратних отворів. Default 'circle' — backward-compat для
    existing шаблонів (l_bracket, z_bracket, corner_angle, wall_shelf,
    perforated_panel). Для квадратів `diameter_mm` означає side length.
    """

    x_mm: float
    y_mm: float
    diameter_mm: float
    shape: HoleShape = field(default="circle")


@dataclass(frozen=True)
class UnfoldedLBracket:
    """Результат розгортки L-кронштейна."""

    length_mm: float
    """Повна розгорнута довжина (від лівого до правого краю)."""

    width_mm: float
    """= params.width_mm — не змінюється при розгортці."""

    thickness_mm: float
    """= params.thickness_mm — товщина листа."""

    bend_position_mm: float
    """Відстань від лівого краю до лінії гиба (центр BA-сегмента)."""

    bend_allowance_mm: float
    """Довжина матеріалу у bend region (по нейтральній осі)."""


@dataclass(frozen=True)
class UnfoldedZBracket:
    """Результат розгортки Z-кронштейна. 2 bends → 2 bend positions."""

    length_mm: float
    width_mm: float
    thickness_mm: float
    bend_positions_mm: tuple[float, float]
    """Відстані від лівого краю до кожної з двох ліній гиба."""

    bend_allowance_mm: float
    """Однаковий BA для обох гибів (однаковий angle/R/t/K)."""


@dataclass(frozen=True)
class UnfoldedCornerAngle:
    """Розгортка corner_angle = L-bracket + auto-grid отвори.

    holes — у системі координат заготовки (0..length_mm × 0..width_mm).
    """

    length_mm: float
    width_mm: float
    thickness_mm: float
    bend_position_mm: float
    bend_allowance_mm: float
    holes: tuple[Hole2D, ...]


@dataclass(frozen=True)
class UnfoldedPerforatedPanel:
    """Розгортка perforated_panel = просто плоский лист + grid отворів.

    Без bends → length_mm = params.length_mm. bend_allowance_mm = 0.
    """

    length_mm: float
    width_mm: float
    thickness_mm: float
    holes: tuple[Hole2D, ...]
    grid_cols: int
    """Кількість колонок отворів."""

    grid_rows: int
    """Кількість рядів отворів."""


@dataclass(frozen=True)
class UnfoldedPerforatedPanelSquare:
    """Розгортка perforated_panel_square (Phase 3.0 PR 5).

    Структурно ідентична UnfoldedPerforatedPanel, але holes мають
    shape='square' (`diameter_mm` = side length). Окремий тип, щоб
    type-checker'и розрізняли два шаблони — попри однакову shape data,
    consumer'и (server/exporters) routing'аються через template_slug.
    """

    length_mm: float
    width_mm: float
    thickness_mm: float
    holes: tuple[Hole2D, ...]
    grid_cols: int
    grid_rows: int


@dataclass(frozen=True)
class Rectangle2D:
    """Прямокутний сегмент розгортки. (x, y) — нижній-лівий кут, w/h — розміри.

    Використовується у `UnfoldedEnclosedShelf` для опису кожної з 4-5 граней
    cross-розгортки (Phase 3.0 PR 7b, ADR-027 Рішення 5).
    """

    x_mm: float
    y_mm: float
    w_mm: float
    h_mm: float


@dataclass(frozen=True)
class BendLine2D:
    """Лінія гибу як відрізок у XY-площині розгортки.

    На відміну від `bend_positions_mm: tuple[float, ...]` у лінійних розгортках,
    enclosed_shelf має cross-shape з гибами вздовж 2 осей: back/rib (X-axis)
    і left/right (Y-axis). Тому bend representation — повноцінні 2-точкові
    відрізки.
    """

    x1_mm: float
    y1_mm: float
    x2_mm: float
    y2_mm: float


@dataclass(frozen=True)
class UnfoldedEnclosedShelf:
    """Cross-розгортка enclosed_shelf (Phase 3.0 PR 7b, ADR-027 Рішення 5).

    Структура:
    - `bottom`/`back`/`left`/`right` — обов'язкові сегменти.
    - `rib` — опційний 5-й сегмент (front-lip stiffening).
    - `outline_vertices` — clockwise vertex list для cross-shape LWPOLYLINE.
    - `bend_lines` — 3 або 4 BendLine2D (back↔bottom, left↔bottom, right↔bottom, [rib↔bottom]).
    - `side_holes` — отвори декоративної перфорації на left+right (координати
      у системі розгортки, не локально-сегментні).

    Inner-corner relief cuts (між back↔left/right і rib↔left/right) поки
    не моделюються — для типових (t, R, BA) маленький артефакт ≤1мм, прийнятно
    для MVP.
    """

    bottom: Rectangle2D
    back: Rectangle2D
    left: Rectangle2D
    right: Rectangle2D
    rib: Rectangle2D | None

    outline_vertices: tuple[tuple[float, float], ...]
    bend_lines: tuple[BendLine2D, ...]

    bend_allowance_mm: float
    thickness_mm: float

    bbox_min_x_mm: float
    bbox_max_x_mm: float
    bbox_min_y_mm: float
    bbox_max_y_mm: float

    side_holes: tuple[Hole2D, ...]


@dataclass(frozen=True)
class UnfoldedWallShelf:
    """Розгортка wall_shelf U-channel: back + shelf + (optional) lip.

    Конвенція: розгортка починається з back, далі bend, shelf, bend, lip.
    Якщо front_lip_mm=0 → один bend, lip_length=0.
    """

    length_mm: float
    width_mm: float
    thickness_mm: float
    bend_positions_mm: tuple[float, ...]
    """1 або 2 bend lines залежно від lip."""

    bend_allowance_mm: float
    holes: tuple[Hole2D, ...]
    """Mounting holes на back-секції (x ∈ [0, flat_back])."""


def compute_bend_allowance(
    angle_deg: float,
    inner_radius_mm: float,
    thickness_mm: float,
    k_factor: float,
) -> float:
    """BA = (π/180) · angle · (R + K·t).

    Невалідні діапазони — ValueError (мають відсіюватись TS-валідатором
    до виклику воркера).
    """
    if not 0.0 < angle_deg <= 180.0:
        raise ValueError(f"angle_deg must be in (0, 180]; got {angle_deg}")
    if inner_radius_mm < 0.0:
        raise ValueError(f"inner_radius_mm must be >= 0; got {inner_radius_mm}")
    if thickness_mm <= 0.0:
        raise ValueError(f"thickness_mm must be > 0; got {thickness_mm}")
    if not 0.0 < k_factor <= 1.0:
        raise ValueError(f"k_factor must be in (0, 1]; got {k_factor}")

    return math.radians(angle_deg) * (inner_radius_mm + k_factor * thickness_mm)


def unfold_l_bracket(params: LBracketBuildParameters, k_factor: float) -> UnfoldedLBracket:
    """Розгортає L-кронштейн у плоский патерн.

    K-фактор обчислюється у TypeScript (packages/cad-engine/k-factor.ts)
    і передається сюди — воркер не дублює довідник.
    """
    t = params.thickness_mm
    r = params.bend_radius_mm
    flat_a = params.leg_a_mm - t - r
    flat_b = params.leg_b_mm - t - r

    if flat_a <= 0 or flat_b <= 0:
        raise ValueError(
            f"L-bracket legs too short for bend (leg_a={params.leg_a_mm}, "
            f"leg_b={params.leg_b_mm}, t={t}, R={r}): flat segments would be non-positive"
        )

    ba = compute_bend_allowance(
        angle_deg=float(params.bend_angle_deg),
        inner_radius_mm=r,
        thickness_mm=t,
        k_factor=k_factor,
    )

    return UnfoldedLBracket(
        length_mm=flat_b + ba + flat_a,
        width_mm=params.width_mm,
        thickness_mm=t,
        bend_position_mm=flat_b + ba / 2,
        bend_allowance_mm=ba,
    )


def unfold_z_bracket(params: ZBracketBuildParameters, k_factor: float) -> UnfoldedZBracket:
    """Розгортає Z-кронштейн у смужку з 3 плоских сегментів + 2 BA.

    Конвенція ordering: bottom → bend1 → middle → bend2 → top.
    Позиції bend lines — центри BA-сегментів.
    """
    t = params.thickness_mm
    r = params.bend_radius_mm
    flat_bottom = params.bottom_flange_mm - t - r
    flat_middle = params.offset_mm - t - r
    flat_top = params.top_flange_mm - t - r

    if flat_bottom <= 0 or flat_middle <= 0 or flat_top <= 0:
        raise ValueError(
            f"Z-bracket segments too short for bend (top={params.top_flange_mm}, "
            f"bottom={params.bottom_flange_mm}, offset={params.offset_mm}, t={t}, R={r}): "
            "one or more flat segments would be non-positive"
        )

    ba = compute_bend_allowance(
        angle_deg=float(params.bend_angle_deg),
        inner_radius_mm=r,
        thickness_mm=t,
        k_factor=k_factor,
    )

    bend1 = flat_bottom + ba / 2
    bend2 = flat_bottom + ba + flat_middle + ba / 2

    return UnfoldedZBracket(
        length_mm=flat_bottom + ba + flat_middle + ba + flat_top,
        width_mm=params.width_mm,
        thickness_mm=t,
        bend_positions_mm=(bend1, bend2),
        bend_allowance_mm=ba,
    )


def _distribute(n: int, start: float, end: float, margin: float) -> tuple[float, ...]:
    """N точок, рівномірно розподілених у [start+margin, end-margin].

    n=0 → повертає порожній кортеж.
    n=1 → одна точка у центрі сегмента (без margin). n>1 → рівні
    інтервали між крайніми точками з відступом margin від країв.
    """
    if n <= 0:
        return ()
    if n == 1:
        return ((start + end) / 2.0,)
    lo = start + margin
    hi = end - margin
    if hi <= lo:
        raise ValueError(
            f"hole_margin {margin} занадто великий для сегмента "
            f"[{start:.2f}, {end:.2f}]: ефективний span={(end - start):.2f}",
        )
    step = (hi - lo) / (n - 1)
    return tuple(lo + i * step for i in range(n))


def unfold_corner_angle(
    params: CornerAngleBuildParameters,
    k_factor: float,
) -> UnfoldedCornerAngle:
    """Розгортає corner_angle і генерує grid отворів.

    Layout: flat_b (полиця B горизонтальна) → BA → flat_a (полиця A вертикальна).
    Отвори grid'у hole_rows × hole_cols заповнюють кожну полицю окремо.
    """
    t = params.thickness_mm
    r = params.bend_radius_mm
    flat_a = params.leg_a_mm - t - r
    flat_b = params.leg_b_mm - t - r

    if flat_a <= 0 or flat_b <= 0:
        raise ValueError(
            f"corner_angle legs too short for bend (leg_a={params.leg_a_mm}, "
            f"leg_b={params.leg_b_mm}, t={t}, R={r}): flat segments would be non-positive"
        )

    ba = compute_bend_allowance(
        angle_deg=float(params.bend_angle_deg),
        inner_radius_mm=r,
        thickness_mm=t,
        k_factor=k_factor,
    )

    # Сегмент B: 0..flat_b. Сегмент A: flat_b+ba..flat_b+ba+flat_a.
    xs_b = _distribute(params.hole_cols, 0.0, flat_b, params.hole_margin_mm)
    xs_a = _distribute(
        params.hole_cols,
        flat_b + ba,
        flat_b + ba + flat_a,
        params.hole_margin_mm,
    )
    ys = _distribute(params.hole_rows, 0.0, params.width_mm, params.hole_margin_mm)

    holes: list[Hole2D] = []
    for xs in (xs_b, xs_a):
        for x in xs:
            for y in ys:
                holes.append(Hole2D(x_mm=x, y_mm=y, diameter_mm=params.hole_diameter_mm))

    return UnfoldedCornerAngle(
        length_mm=flat_b + ba + flat_a,
        width_mm=params.width_mm,
        thickness_mm=t,
        bend_position_mm=flat_b + ba / 2,
        bend_allowance_mm=ba,
        holes=tuple(holes),
    )


def unfold_wall_shelf(params: WallShelfBuildParameters, k_factor: float) -> UnfoldedWallShelf:
    """Розгортка U-channel: back + (BA) + shelf + (BA) + lip.

    Mount holes — auto-grid на back-секції (x ∈ [0, flat_back]).
    Якщо front_lip_mm=0, lip-сегмент пропускаємо, лишається 1 bend.
    """
    t = params.thickness_mm
    r = params.bend_radius_mm
    lip_present = params.front_lip_mm > 0

    flat_back = params.back_height_mm - t - r
    # Shelf має 1 або 2 bends: якщо є lip → віднімаємо t+r з обох країв.
    flat_shelf = params.shelf_depth_mm - (t + r) - (t + r if lip_present else 0)
    flat_lip = (params.front_lip_mm - t - r) if lip_present else 0.0

    if flat_back <= 0 or flat_shelf <= 0 or (lip_present and flat_lip <= 0):
        raise ValueError(
            f"wall_shelf segments too short for bend (back={params.back_height_mm}, "
            f"shelf={params.shelf_depth_mm}, lip={params.front_lip_mm}, t={t}, R={r}): "
            "one or more flat segments would be non-positive"
        )

    ba = compute_bend_allowance(
        angle_deg=float(params.bend_angle_deg),
        inner_radius_mm=r,
        thickness_mm=t,
        k_factor=k_factor,
    )

    bend_positions: list[float] = [flat_back + ba / 2]
    length = flat_back + ba + flat_shelf
    if lip_present:
        bend_positions.append(flat_back + ba + flat_shelf + ba / 2)
        length += ba + flat_lip

    # Auto-grid mount holes на back-секції.
    xs = _distribute(params.mount_hole_cols, 0.0, flat_back, params.mount_hole_margin_mm)
    ys = _distribute(params.mount_hole_rows, 0.0, params.width_mm, params.mount_hole_margin_mm)
    holes = tuple(
        Hole2D(x_mm=x, y_mm=y, diameter_mm=params.mount_hole_diameter_mm) for x in xs for y in ys
    )

    return UnfoldedWallShelf(
        length_mm=length,
        width_mm=params.width_mm,
        thickness_mm=t,
        bend_positions_mm=tuple(bend_positions),
        bend_allowance_mm=ba,
        holes=holes,
    )


def unfold_perforated_panel(
    params: PerforatedPanelBuildParameters,
) -> UnfoldedPerforatedPanel:
    """Обчислює centered grid отворів на плоскому листі.

    Не приймає k_factor: без bends — без bend allowance.

    Layout: для кожного виміру обчислюємо max кількість отворів, що
    влізе з відступом ≥margin, потім перераховуємо effective_margin
    щоб grid опинився симетрично відносно центра листа.
    """
    if params.length_mm - 2 * params.margin_mm < 0:
        raise ValueError(
            f"length_mm ({params.length_mm}) < 2 * margin_mm ({params.margin_mm}): "
            "no room for holes"
        )
    if params.width_mm - 2 * params.margin_mm < 0:
        raise ValueError(
            f"width_mm ({params.width_mm}) < 2 * margin_mm ({params.margin_mm}): no room for holes"
        )

    # Кількість отворів вдовж кожного виміру.
    avail_x = params.length_mm - 2 * params.margin_mm
    avail_y = params.width_mm - 2 * params.margin_mm
    n_cols = max(1, int(avail_x // params.pitch_x_mm) + 1)
    n_rows = max(1, int(avail_y // params.pitch_y_mm) + 1)

    # Centered effective margins.
    eff_margin_x = (params.length_mm - (n_cols - 1) * params.pitch_x_mm) / 2.0
    eff_margin_y = (params.width_mm - (n_rows - 1) * params.pitch_y_mm) / 2.0

    holes: list[Hole2D] = []
    for i in range(n_cols):
        x = eff_margin_x + i * params.pitch_x_mm
        for j in range(n_rows):
            y = eff_margin_y + j * params.pitch_y_mm
            holes.append(Hole2D(x_mm=x, y_mm=y, diameter_mm=params.hole_diameter_mm))

    return UnfoldedPerforatedPanel(
        length_mm=params.length_mm,
        width_mm=params.width_mm,
        thickness_mm=params.thickness_mm,
        holes=tuple(holes),
        grid_cols=n_cols,
        grid_rows=n_rows,
    )


def unfold_perforated_panel_square(
    params: PerforatedPanelSquareBuildParameters,
) -> UnfoldedPerforatedPanelSquare:
    """Розгортка perforated_panel_square (Phase 3.0 PR 5).

    Алгоритм layout identical до unfold_perforated_panel: centered grid
    holes. Різниця тільки у `Hole2D.shape='square'` (для DXF емітитиме
    LWPOLYLINE 4 vertices замість CIRCLE).
    """
    if params.length_mm - 2 * params.margin_mm < 0:
        raise ValueError(
            f"length_mm ({params.length_mm}) < 2 * margin_mm ({params.margin_mm}): "
            "no room for holes"
        )
    if params.width_mm - 2 * params.margin_mm < 0:
        raise ValueError(
            f"width_mm ({params.width_mm}) < 2 * margin_mm ({params.margin_mm}): no room for holes"
        )

    avail_x = params.length_mm - 2 * params.margin_mm
    avail_y = params.width_mm - 2 * params.margin_mm
    n_cols = max(1, int(avail_x // params.pitch_x_mm) + 1)
    n_rows = max(1, int(avail_y // params.pitch_y_mm) + 1)

    eff_margin_x = (params.length_mm - (n_cols - 1) * params.pitch_x_mm) / 2.0
    eff_margin_y = (params.width_mm - (n_rows - 1) * params.pitch_y_mm) / 2.0

    holes: list[Hole2D] = []
    for i in range(n_cols):
        x = eff_margin_x + i * params.pitch_x_mm
        for j in range(n_rows):
            y = eff_margin_y + j * params.pitch_y_mm
            # diameter_mm тут означає side length (Phase 3.0 PR 5 інваріант).
            holes.append(
                Hole2D(
                    x_mm=x,
                    y_mm=y,
                    diameter_mm=params.hole_size_mm,
                    shape="square",
                )
            )

    return UnfoldedPerforatedPanelSquare(
        length_mm=params.length_mm,
        width_mm=params.width_mm,
        thickness_mm=params.thickness_mm,
        holes=tuple(holes),
        grid_cols=n_cols,
        grid_rows=n_rows,
    )


def _enclosed_shelf_side_holes(
    side_rect: Rectangle2D,
    perforation: object,  # EnclosedShelfSidePerforation; avoid typing-cycle here
) -> tuple[Hole2D, ...]:
    """Centered square-hole grid на одній боковій стінці (left або right).

    Layout — той самий що `unfold_perforated_panel_square`: centered grid з
    effective margin, square holes (shape='square', diameter_mm = side length).
    Координати absolute (відносно бази розгортки), щоб DXF emit'тер міг писати
    LWPOLYLINEs без додаткового зсуву.
    """
    # Imported lazily to avoid circular import with templates.
    from flatcraft_cad.templates.enclosed_shelf import (  # noqa: PLC0415
        EnclosedShelfSidePerforation,
    )

    if not isinstance(perforation, EnclosedShelfSidePerforation):
        raise TypeError("perforation must be EnclosedShelfSidePerforation")
    p = perforation
    avail_x = side_rect.w_mm - 2 * p.margin_mm
    avail_y = side_rect.h_mm - 2 * p.margin_mm
    if avail_x < 0 or avail_y < 0:
        return ()
    n_cols = max(1, int(avail_x // p.pitch_x_mm) + 1)
    n_rows = max(1, int(avail_y // p.pitch_y_mm) + 1)
    eff_margin_x = (side_rect.w_mm - (n_cols - 1) * p.pitch_x_mm) / 2.0
    eff_margin_y = (side_rect.h_mm - (n_rows - 1) * p.pitch_y_mm) / 2.0
    holes: list[Hole2D] = []
    for i in range(n_cols):
        x = side_rect.x_mm + eff_margin_x + i * p.pitch_x_mm
        for j in range(n_rows):
            y = side_rect.y_mm + eff_margin_y + j * p.pitch_y_mm
            holes.append(Hole2D(x_mm=x, y_mm=y, diameter_mm=p.hole_size_mm, shape="square"))
    return tuple(holes)


def _compute_enclosed_shelf_outline(
    bottom: Rectangle2D,
    back: Rectangle2D,
    left: Rectangle2D,
    right: Rectangle2D,
    rib: Rectangle2D | None,
) -> tuple[tuple[float, float], ...]:
    """Будує clockwise vertex list cross-shape outline.

    Інваріант: сегменти axis-aligned, центровані відносно bottom (back/rib
    мають той же x-center, left/right — той же y-center). Алгоритм рухається
    по периметру, додаючи "сходинки" (notches) на стиках сегментів через
    різницю розмірів (e.g., back ширший за flat_bottom_x → step inward).
    """
    b_l, b_r = bottom.x_mm, bottom.x_mm + bottom.w_mm
    b_b, b_t = bottom.y_mm, bottom.y_mm + bottom.h_mm
    bk_l, bk_r = back.x_mm, back.x_mm + back.w_mm
    bk_b, bk_t = back.y_mm, back.y_mm + back.h_mm
    lf_l, lf_r = left.x_mm, left.x_mm + left.w_mm
    lf_b, lf_t = left.y_mm, left.y_mm + left.h_mm
    rt_l, rt_r = right.x_mm, right.x_mm + right.w_mm
    rt_b, rt_t = right.y_mm, right.y_mm + right.h_mm

    pts: list[tuple[float, float]] = []
    # 1. back-top-left → back-top-right → back-bottom-right
    pts.append((bk_l, bk_t))
    pts.append((bk_r, bk_t))
    pts.append((bk_r, bk_b))
    # 2. step inward to bottom's right if back wider than bottom
    if bk_r > b_r:
        pts.append((b_r, bk_b))
    # 3. step down to bottom's top edge
    pts.append((b_r, b_t))
    # 4. across bottom's top edge into right's bend area → right top-left
    pts.append((rt_l, b_t))
    # 5. step up to right's top if right taller than bottom flat-y
    if rt_t > b_t:
        pts.append((rt_l, rt_t))
    # 6. right top-right
    pts.append((rt_r, rt_t))
    # 7. right bottom-right
    pts.append((rt_r, rt_b))
    # 8. step left across right's bottom + back along bottom's bottom edge
    if rt_b < b_b:
        pts.append((rt_l, rt_b))
        pts.append((rt_l, b_b))
    pts.append((b_r, b_b))
    # 9. if rib: descend into rib bend region; else cut straight across to left
    if rib is not None:
        rb_l, rb_r = rib.x_mm, rib.x_mm + rib.w_mm
        rb_b, rb_t = rib.y_mm, rib.y_mm + rib.h_mm
        # step down to rib bend top
        pts.append((b_r, rb_t))
        # step outward (notch) if rib wider than bottom on right
        if rb_r > b_r:
            pts.append((rb_r, rb_t))
        # down rib's right edge to rib bottom
        pts.append((rb_r, rb_b))
        # along rib's bottom edge leftward
        pts.append((rb_l, rb_b))
        # up rib's left edge to bend top
        pts.append((rb_l, rb_t))
        # step inward if rib wider than bottom on left
        if rb_l < b_l:
            pts.append((b_l, rb_t))
        # back up to bottom's bottom edge
        pts.append((b_l, b_b))
    # 10. across bottom's bottom edge into left bend area
    pts.append((lf_r, b_b))
    # 11. step down if left lower than bottom flat-y bottom
    if lf_b < b_b:
        pts.append((lf_r, lf_b))
    # 12. left bottom-left
    pts.append((lf_l, lf_b))
    # 13. left top-left
    pts.append((lf_l, lf_t))
    # 14. left top-right (only if left taller than bottom flat-y)
    if lf_t > b_t:
        pts.append((lf_r, lf_t))
    # 15. step down to bottom's top edge level
    pts.append((lf_r, b_t))
    # 16. across to bottom's top-left
    pts.append((b_l, b_t))
    # 17. up to back bend bottom
    pts.append((b_l, bk_b))
    # 18. step outward to back left if back wider than bottom on left
    if bk_l < b_l:
        pts.append((bk_l, bk_b))
    # close polygon (LWPOLYLINE close=True handles it; first vertex implicit close)
    return tuple(pts)


def unfold_enclosed_shelf(
    params: EnclosedShelfBuildParameters,
    k_factor: float,
) -> UnfoldedEnclosedShelf:
    """Cross-розгортка enclosed_shelf (Phase 3.0 PR 7b, ADR-027 Рішення 5).

    Координатна система: bottom-bottom-left у (0, 0). Bottom flat extent:
    - X: [0, width_mm - 2*(t+r)] (left+right bends відсікають по (t+r) з кожного боку)
    - Y: [0, depth_mm - (t+r) - (rib?(t+r):0)] (back bend + опц. rib bend)

    Back, left, right, rib центруються відносно bottom.
    """
    t = params.thickness_mm
    r = params.bend_radius_mm
    tr = t + r
    rib_present = params.stiffening_rib is not None

    flat_bottom_x = params.width_mm - 2 * tr
    flat_bottom_y = params.depth_mm - tr - (tr if rib_present else 0.0)
    flat_back_y = params.depth_mm - tr
    flat_left_x = params.depth_mm - tr
    flat_right_x = flat_left_x  # симетрично
    if flat_bottom_x <= 0 or flat_bottom_y <= 0 or flat_back_y <= 0 or flat_left_x <= 0:
        raise ValueError(
            f"enclosed_shelf segments too short for bend (width={params.width_mm}, "
            f"depth={params.depth_mm}, t={t}, R={r}): one or more flat dimensions non-positive"
        )

    ba = compute_bend_allowance(
        angle_deg=float(params.bend_angle_deg),
        inner_radius_mm=r,
        thickness_mm=t,
        k_factor=k_factor,
    )

    # Bottom at origin.
    bottom = Rectangle2D(x_mm=0.0, y_mm=0.0, w_mm=flat_bottom_x, h_mm=flat_bottom_y)

    # Back centered на X above bottom: back has full width_mm, offset to center.
    back_x_offset = (flat_bottom_x - params.width_mm) / 2.0
    back = Rectangle2D(
        x_mm=back_x_offset,
        y_mm=flat_bottom_y + ba,
        w_mm=params.width_mm,
        h_mm=flat_back_y,
    )

    # Left: at -BA to left of bottom, y range = full depth_mm (centered on bottom y).
    # Bottom flat-y може бути меншим за depth_mm (через bend(s)); left's y центрується.
    left_y_offset = (flat_bottom_y - params.depth_mm) / 2.0
    left = Rectangle2D(
        x_mm=-ba - flat_left_x,
        y_mm=left_y_offset,
        w_mm=flat_left_x,
        h_mm=params.depth_mm,
    )
    right = Rectangle2D(
        x_mm=flat_bottom_x + ba,
        y_mm=left_y_offset,
        w_mm=flat_right_x,
        h_mm=params.depth_mm,
    )

    rib: Rectangle2D | None = None
    if params.stiffening_rib is not None:
        flat_rib_y = params.stiffening_rib.height_mm - tr
        if flat_rib_y <= 0:
            raise ValueError(
                f"stiffening_rib.height_mm {params.stiffening_rib.height_mm} too small "
                f"for bend (t+r={tr}); minimum height > {tr}"
            )
        rib = Rectangle2D(
            x_mm=back_x_offset,
            y_mm=-ba - flat_rib_y,
            w_mm=params.width_mm,
            h_mm=flat_rib_y,
        )

    outline = _compute_enclosed_shelf_outline(bottom, back, left, right, rib)

    # Bend lines (внутрішні лінії між сегментами)
    bend_lines: list[BendLine2D] = []
    # back↔bottom: горизонтальна лінія на y = flat_bottom_y + ba/2, x ∈ [0, flat_bottom_x]
    bend_lines.append(
        BendLine2D(
            x1_mm=0.0,
            y1_mm=flat_bottom_y + ba / 2.0,
            x2_mm=flat_bottom_x,
            y2_mm=flat_bottom_y + ba / 2.0,
        )
    )
    # left↔bottom: вертикальна лінія на x = -ba/2, y ∈ [0, flat_bottom_y]
    bend_lines.append(
        BendLine2D(
            x1_mm=-ba / 2.0,
            y1_mm=0.0,
            x2_mm=-ba / 2.0,
            y2_mm=flat_bottom_y,
        )
    )
    # right↔bottom: вертикальна на x = flat_bottom_x + ba/2
    bend_lines.append(
        BendLine2D(
            x1_mm=flat_bottom_x + ba / 2.0,
            y1_mm=0.0,
            x2_mm=flat_bottom_x + ba / 2.0,
            y2_mm=flat_bottom_y,
        )
    )
    # rib↔bottom (опц.): горизонтальна на y = -ba/2
    if rib is not None:
        bend_lines.append(
            BendLine2D(
                x1_mm=0.0,
                y1_mm=-ba / 2.0,
                x2_mm=flat_bottom_x,
                y2_mm=-ba / 2.0,
            )
        )

    # Bounding box (для DXF layout + PDF scaling).
    xs = [p[0] for p in outline]
    ys = [p[1] for p in outline]
    bbox_min_x, bbox_max_x = min(xs), max(xs)
    bbox_min_y, bbox_max_y = min(ys), max(ys)

    # Side perforation holes (опц.) — на left+right сегментах, координати absolute.
    side_holes: tuple[Hole2D, ...] = ()
    if params.side_perforation is not None:
        side_holes = _enclosed_shelf_side_holes(
            left, params.side_perforation
        ) + _enclosed_shelf_side_holes(right, params.side_perforation)

    return UnfoldedEnclosedShelf(
        bottom=bottom,
        back=back,
        left=left,
        right=right,
        rib=rib,
        outline_vertices=outline,
        bend_lines=tuple(bend_lines),
        bend_allowance_mm=ba,
        thickness_mm=t,
        bbox_min_x_mm=bbox_min_x,
        bbox_max_x_mm=bbox_max_x,
        bbox_min_y_mm=bbox_min_y,
        bbox_max_y_mm=bbox_max_y,
        side_holes=side_holes,
    )
