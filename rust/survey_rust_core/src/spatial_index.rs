//! 大规模平面测点最近邻空间查询内核。

/// 最近邻匹配结果。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct NearestMatch {
    /// 最近点在输入数组中的下标（0 起）。
    pub index: usize,
    /// 到目标点的平面欧氏距离（m）。
    pub distance: f64,
}

/// 在 `(xs, ys)` 点集中查找距离 `(target_x, target_y)` 最近的测点；点集为空或目标非有限数时返回 `None`。
pub fn find_nearest_point_2d(
    xs: &[f64],
    ys: &[f64],
    target_x: f64,
    target_y: f64,
) -> Option<NearestMatch> {
    if !target_x.is_finite() || !target_y.is_finite() {
        return None;
    }
    let n = xs.len().min(ys.len());
    if n == 0 {
        return None;
    }
    let mut best_idx: Option<usize> = None;
    let mut best_d2 = f64::INFINITY;
    for i in 0..n {
        if !xs[i].is_finite() || !ys[i].is_finite() {
            continue;
        }
        let dx = xs[i] - target_x;
        let dy = ys[i] - target_y;
        let d2 = dx * dx + dy * dy;
        if d2 < best_d2 {
            best_d2 = d2;
            best_idx = Some(i);
        }
    }
    best_idx.map(|index| NearestMatch {
        index,
        distance: best_d2.sqrt(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_nearest_point() {
        let xs = [100.0, 200.0, 103.0];
        let ys = [500.0, 600.0, 504.0];
        let m = find_nearest_point_2d(&xs, &ys, 100.0, 500.0).unwrap();
        assert_eq!(m.index, 0);
        assert!((m.distance - 0.0).abs() < 1e-12);

        let m2 = find_nearest_point_2d(&xs, &ys, 102.9, 504.1).unwrap();
        assert_eq!(m2.index, 2);
    }
}
