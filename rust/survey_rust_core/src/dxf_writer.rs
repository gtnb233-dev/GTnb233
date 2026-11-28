//! 分层 ASCII DXF 生成器（AutoCAD R14 / AC1014）。
//!
//! 工程测量坐标约定：输入 `x` 为北坐标（N）、`y` 为东坐标（E）、`z` 为高程（H）；
//! 写入 DXF 时自动交换为 CAD 平面横轴东坐标（10 组码 = y）与纵轴北坐标（20 组码 = x）。

use std::collections::BTreeSet;
use std::fmt::Write as _;

/// 标准工程测量图层集合。
pub const STANDARD_LAYERS: &[&str] = &[
    "0",
    "POINTS",
    "ELEVATIONS",
    "TRAVERSE",
    "LEVELING",
    "CURVES",
];

/// 待导出的 DXF 点位（工程测量坐标系：`x` 北、`y` 东、`z` 高程）。
#[derive(Debug, Clone)]
pub struct DxfPointSpec {
    pub name: String,
    pub x: f64,
    pub y: f64,
    pub z: Option<f64>,
    pub layer: String,
}

/// 待导出的 DXF 多段线（工程测量坐标系：顶点 `(x_north, y_east)`）。
#[derive(Debug, Clone)]
pub struct DxfPolylineSpec {
    pub vertices: Vec<(f64, f64)>,
    pub closed: bool,
    pub layer: String,
}

fn single_line(value: &str) -> String {
    value.replace(['\r', '\n', '\0'], "").trim().to_owned()
}

fn sanitize_layer(layer: &str) -> String {
    let name = single_line(layer);
    if name.is_empty() {
        "0".to_owned()
    } else {
        name
    }
}

fn layer_color(layer: &str) -> u16 {
    match layer {
        "POINTS" => 7,     // 白/黑
        "ELEVATIONS" => 3, // 绿
        "TRAVERSE" => 1,   // 红
        "LEVELING" => 5,   // 蓝
        "CURVES" => 4,     // 青
        _ => 7,
    }
}

/// 生成包含 `HEADER`、`TABLES`（`LAYER` 表）与 `ENTITIES` 段的完整 ASCII DXF 文本。
pub fn generate_layered_dxf(points: &[DxfPointSpec], polylines: &[DxfPolylineSpec]) -> String {
    let mut layers: BTreeSet<String> = STANDARD_LAYERS.iter().map(|s| (*s).to_owned()).collect();
    for p in points {
        layers.insert(sanitize_layer(&p.layer));
    }
    for pl in polylines {
        layers.insert(sanitize_layer(&pl.layer));
    }

    let mut out = String::with_capacity(1024 + points.len() * 128 + polylines.len() * 128);
    // HEADER
    out.push_str("0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1014\n0\nENDSEC\n");

    // TABLES -> LAYER
    let _ = writeln!(
        out,
        "0\nSECTION\n2\nTABLES\n0\nTABLE\n2\nLAYER\n5\n2\n100\nAcDbSymbolTable\n70\n{}",
        layers.len()
    );
    for layer in &layers {
        let _ = writeln!(
            out,
            "0\nLAYER\n100\nAcDbSymbolTableRecord\n100\nAcDbLayerTableRecord\n2\n{}\n70\n0\n62\n{}\n6\nCONTINUOUS",
            layer,
            layer_color(layer)
        );
    }
    out.push_str("0\nENDTAB\n0\nENDSEC\n");

    // ENTITIES
    out.push_str("0\nSECTION\n2\nENTITIES\n");

    for p in points {
        if !p.x.is_finite() || !p.y.is_finite() {
            continue;
        }
        let z = p.z.filter(|v| v.is_finite()).unwrap_or(0.0);
        let layer = sanitize_layer(&p.layer);
        // 工程测量 (X=北, Y=东) -> CAD (10=东=Y, 20=北=X)
        let _ = writeln!(
            out,
            "0\nPOINT\n100\nAcDbEntity\n8\n{}\n100\nAcDbPoint\n10\n{:.6}\n20\n{:.6}\n30\n{:.6}",
            layer, p.y, p.x, z
        );
        let name = single_line(&p.name);
        if !name.is_empty() {
            let _ = writeln!(
                out,
                "0\nTEXT\n100\nAcDbEntity\n8\n{}\n100\nAcDbText\n10\n{:.6}\n20\n{:.6}\n30\n{:.6}\n40\n1.5\n1\n{}\n100\nAcDbText",
                layer,
                p.y + 0.5,
                p.x + 0.5,
                z,
                name
            );
        }
        if let Some(zv) = p.z.filter(|v| v.is_finite()) {
            let _ = writeln!(
                out,
                "0\nTEXT\n100\nAcDbEntity\n8\nELEVATIONS\n100\nAcDbText\n10\n{:.6}\n20\n{:.6}\n30\n{:.6}\n40\n1.2\n1\n{:.3}\n100\nAcDbText",
                p.y + 0.5,
                p.x - 1.2,
                zv,
                zv
            );
        }
    }

    for pl in polylines {
        let valid: Vec<(f64, f64)> = pl
            .vertices
            .iter()
            .copied()
            .filter(|(x, y)| x.is_finite() && y.is_finite())
            .collect();
        if valid.is_empty() {
            continue;
        }
        let layer = sanitize_layer(&pl.layer);
        let flag = if pl.closed { 1 } else { 0 };
        let _ = writeln!(
            out,
            "0\nLWPOLYLINE\n100\nAcDbEntity\n8\n{}\n100\nAcDbPolyline\n90\n{}\n70\n{}",
            layer,
            valid.len(),
            flag
        );
        for (x, y) in valid {
            // 工程测量 (X=北, Y=东) -> CAD (10=东=Y, 20=北=X)
            let _ = writeln!(out, "10\n{:.6}\n20\n{:.6}", y, x);
        }
    }

    out.push_str("0\nENDSEC\n0\nEOF\n");
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dxf_parser::{parse_ascii_dxf, DxfEntity};

    #[test]
    fn r14_labels_and_layer_references_are_single_line() {
        let dxf = generate_layered_dxf(
            &[DxfPointSpec { name: " P\r\n1 ".into(), x: 3., y: 4., z: None, layer: "A\nB".into() }],
            &[DxfPolylineSpec { vertices: vec![(3., 4.), (5., 6.)], closed: false, layer: "A\rB".into() }],
        );
        assert!(dxf.contains("9\n$ACADVER\n1\nAC1014\n"));
        assert!(dxf.contains("1\nP1\n"));
        assert!(!dxf.contains('\r'));
        assert_eq!(dxf.matches("2\nAB\n").count(), 1);
        assert_eq!(dxf.matches("8\nAB\n").count(), 3);
        assert!(dxf.contains("100\nAcDbPolyline\n90\n2\n"));
        let lines: Vec<_> = dxf.lines().collect();
        assert_eq!(lines.len() % 2, 0);
        assert!(lines.chunks_exact(2).all(|pair| pair[0].parse::<u16>().is_ok()));
    }

    #[test]
    fn generates_layered_dxf_and_swaps_xy() {
        let dxf = generate_layered_dxf(
            &[DxfPointSpec {
                name: "K1".to_string(),
                x: 3456789.123, // North
                y: 512345.678,  // East
                z: Some(45.678),
                layer: "POINTS".to_string(),
            }],
            &[DxfPolylineSpec {
                vertices: vec![(100.0, 200.0), (150.0, 250.0)],
                closed: true,
                layer: "TRAVERSE".to_string(),
            }],
        );
        assert!(dxf.contains("ELEVATIONS"));
        assert!(dxf.contains("LEVELING"));
        assert!(dxf.contains("CURVES"));

        let parsed = parse_ascii_dxf(&dxf);
        assert_eq!(parsed.len(), 2);
        match &parsed[0] {
            DxfEntity::Point { layer, x, y, z } => {
                assert_eq!(layer, "POINTS");
                assert!((x - 512345.678).abs() < 1e-5);
                assert!((y - 3456789.123).abs() < 1e-5);
                assert!((z - 45.678).abs() < 1e-5);
            }
            _ => panic!("expected Point"),
        }
        match &parsed[1] {
            DxfEntity::LwPolyline {
                layer,
                closed,
                vertices,
            } => {
                assert_eq!(layer, "TRAVERSE");
                assert!(*closed);
                assert_eq!(vertices, &vec![(200.0, 100.0), (250.0, 150.0)]);
            }
            _ => panic!("expected LwPolyline"),
        }
    }
}
