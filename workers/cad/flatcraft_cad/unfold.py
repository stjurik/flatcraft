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
