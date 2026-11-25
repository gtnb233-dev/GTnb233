//! TIN (Triangulated Irregular Network) prismoid earthwork volume kernel.

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TinPoint {
    pub x: f64,
    pub y: f64,
    pub z: f64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct EarthworkResult {
    pub cut_volume: f64,
    pub fill_volume: f64,
    pub net_volume: f64,
    pub plan_area: f64,
}

/// Computes exact prismoid cut/fill volume across a list of triangle index triples
/// relative to a horizontal datum elevation `design_z`.
pub fn compute_tin_volume(
    points: &[TinPoint],
    triangles: &[[usize; 3]],
    design_z: f64,
) -> EarthworkResult {
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
        let area = 0.5 * ((p1.x - p0.x) * (p2.y - p0.y) - (p2.x - p0.x) * (p1.y - p0.y)).abs();
        if area <= 1e-12 {
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
}
