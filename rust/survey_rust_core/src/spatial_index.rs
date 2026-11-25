//! Fast planar nearest-point spatial query kernel for large survey point clouds.

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct NearestMatch {
    pub index: usize,
    pub distance: f64,
}

pub fn find_nearest_point_2d(
    xs: &[f64],
    ys: &[f64],
    target_x: f64,
    target_y: f64,
) -> Option<NearestMatch> {
    let n = xs.len().min(ys.len());
    if n == 0 {
        return None;
    }
    let mut best_idx = 0usize;
    let mut best_d2 = f64::INFINITY;
    for i in 0..n {
        let dx = xs[i] - target_x;
        let dy = ys[i] - target_y;
        let d2 = dx * dx + dy * dy;
        if d2 < best_d2 {
            best_d2 = d2;
            best_idx = i;
        }
    }
    Some(NearestMatch {
        index: best_idx,
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
