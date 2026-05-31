/**
 * Re-export набору lucide-іконок, що використовуються у UI. Тримаємо
 * вибірковий перелік (а не `export *`), щоб apps/web не платив за tree-
 * shaking lucide-react: ESM-резолвер тягне рівно ці.
 */
export {
  Activity,
  AlertCircle,
  ArrowRight,
  Check,
  ChevronDown,
  Download,
  Edit3,
  FileDown,
  Gift,
  Github,
  Heart,
  Info,
  LayoutGrid,
  Minus,
  Plus,
  RotateCcw,
  Settings,
  Sliders,
  Square,
  Trash2,
  Undo2,
  X,
  XCircle,
} from "lucide-react";

export type { LucideIcon } from "lucide-react";
