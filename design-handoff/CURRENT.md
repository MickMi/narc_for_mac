# Design Handoff — 2026-06-18

## 变更列表
- [x] 创建 `DESIGN.md`（完整设计 token 与组件规格文档，OD 项目目录下）
- [x] 更新 `DesignTokens.swift` — 圆角阶梯重调、新增 `SoftRowBackground`/`SoftShadow` modifier、新增 40pt/48pt 间距 token
- [x] 修改 `DashboardView.swift` — 核心视觉软化（圆角行背景、间距替代分隔线、选中态蓝色竖条、毛玻璃工具栏）

## 视觉变更要点

### Dashboard 标签行
- **圆角**：从无圆角平面 → 10pt 连续曲率（`NarcRadius.sm` + `.continuous`）
- **行间距**：从可见 `Divider()` → 2pt 间隙（`LazyVStack(spacing: .xxs)`）
- **选中态**：新增 3pt 蓝色左侧竖条（与红色需关注竖条镜像设计）
- **背景**：扁平纯色块 → 圆角 + 半透明描边（`SoftRowBackground` modifier）
- **需关注态**：竖条增加 6pt 上下内缩，不再贴边

### 工具栏
- 新增 `.regularMaterial` 毛玻璃背景

### Design Token 值变更
| Token | Old | New |
|-------|-----|-----|
| NarcRadius.xs | 4 | **6** |
| NarcRadius.sm | 8 | **10** |
| NarcRadius.md | 10 | **14** |
| NarcRadius.lg | 14 | **20** |
| NarcRadius.xl | 18 | **24** |

### 新增 Token / Modifier
- `NarcSpacing.xxxxl` (40pt), `NarcSpacing.xxxxxl` (48pt)
- `.softRowBackground(isSelected:needsAttention:isHovering:)` — 标签行圆角背景 + 描边
- `.softShadow("xs"|"sm"|"md"|"lg")` — CSS 多层阴影的 SwiftUI 近似

## 依赖说明
- 无新增 SPM 依赖
- 无新增系统权限
- 无新增 Model/Service 需求
- 编译通过 ✅（两个预存的 deprecation warning 与此手交无关）

## 参考文件
- **设计规格文档**：OD 项目 `DESIGN.md`
- **高保真原型**：OD 项目 `narc-dashboard-soft-v5-5.html`
