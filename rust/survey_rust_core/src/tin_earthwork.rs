//! 不规则三角网（TIN）棱柱体法土方计算内核。

/// TIN 三维测点（平面坐标 X/Y 及高程 Z，单位 m）。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TinPoint {
    /// 纵坐标 X（北方向，m）。
    pub x: f64,
    /// 横坐标 Y（东方向，m）。
    pub y: f64,
    /// 高程 Z（m）。
    pub z: f64,
}

/// TIN 土方量计算结果（单位 m³ / m²）。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct EarthworkResult {
    /// 挖方总量（m³，非负）。
    pub cut_volume: f64,
    /// 填方总量（m³，非负）。
    pub fill_volume: f64,
    /// 净方量（挖方 − 填方，m³）。
    pub net_volume: f64,
    /// 有效三角网平面投影总面积（m²）。
    pub plan_area: f64,
}

/// 基于三角网棱柱体法计算相对设计高程 `design_z` 的挖方、填方与平面投影面积。
///
/// 自动跳过越界三角形索引、共线/零面积退化三角形（`area <= 1e-12`）以及含非有限值的顶点。
pub fn compute_tin_volume(
    points: &[TinPoint],
    triangles: &[[usize; 3]],
    design_z: f64,
) -> EarthworkResult {
    if !design_z.is_finite() {
        return EarthworkResult {
            cut_volume: 0.0,
            fill_volume: 0.0,
            net_volume: 0.0,
            plan_area: 0.0,
        };
    }

    let mut cut_volume = 0.0_f64;
    let mut fill_volume = 0.0_f64;
    let mut plan_area = 0.0_f64;

    for &[i0, i1, i2] in triangles {
        if i0 >= points.len() || i1 >= points.len() || i2 >= points.len() {
            continue;
        }
        let p0 = points[i0];
        let p1 = points[i1];
        let p2 = points[i2];
        if !p0.x.is_finite()
            || !p0.y.is_finite()
            || !p0.z.is_finite()
            || !p1.x.is_finite()
            || !p1.y.is_finite()
            || !p1.z.is_finite()
            || !p2.x.is_finite()
            || !p2.y.is_finite()
            || !p2.z.is_finite()
        {
            continue;
        }
        let area = 0.5 * ((p1.x - p0.x) * (p2.y - p0.y) - (p2.x - p0.x) * (p1.y - p0.y)).abs();
        if !area.is_finite() || area <= 1e-12 {
            continue;
        }
        plan_area += area;
        let dz_avg = ((p0.z - design_z) + (p1.z - design_z) + (p2.z - design_z)) / 3.0;
        let vol = area * dz_avg;
        if vol >= 0.0 {
            cut_volume += vol;
        } else {
            fill_volume += -vol;
        }
    }

    EarthworkResult {
        cut_volume,
        fill_volume,
        net_volume: cut_volume - fill_volume,
        plan_area,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn computes_prismoid_cut_and_fill() {
        let pts = [
            TinPoint { x: 0.0, y: 0.0, z: 12.0 },
            TinPoint { x: 10.0, y: 0.0, z: 12.0 },
            TinPoint { x: 0.0, y: 10.0, z: 12.0 },
            TinPoint { x: 10.0, y: 10.0, z: 8.0 },
        ];
        let tris = [[0, 1, 2], [1, 3, 2]];
        let res = compute_tin_volume(&pts, &tris, 10.0);
        assert!((res.plan_area - 100.0).abs() < 1e-9);
        assert!((res.cut_volume - 133.3333333333).abs() < 1e-6);
        assert!((res.fill_volume - 0.0).abs() < 1e-9);
    }

    #[test]
    fn skips_collinear_degenerate_out_of_bounds_and_nan_triangles() {
        let pts = [
            TinPoint { x: 0.0, y: 0.0, z: 10.0 },
            TinPoint { x: 5.0, y: 0.0, z: 12.0 },
            TinPoint { x: 10.0, y: 0.0, z: 14.0 }, // 与 0、1 共线
            TinPoint { x: 0.0, y: 10.0, z: f64::NAN },
        ];
        let tris = [
            [0, 1, 2],   // 共线退化（面积为 0）
            [0, 1, 3],   // 含 NaN 顶点
            [0, 1, 99],  // 索引越界
        ];
        let res = compute_tin_volume(&pts, &tris, 10.0);
        assert_eq!(res.plan_area, 0.0);
        assert_eq!(res.cut_volume, 0.0);
        assert_eq!(res.fill_volume, 0.0);
        assert_eq!(res.net_volume, 0.0);

        // 非有限设计高程返回全零结果
        let res_nan = compute_tin_volume(&pts, &[[0, 1, 2]], f64::NAN);
        assert_eq!(res_nan.plan_area, 0.0);
    }
}
