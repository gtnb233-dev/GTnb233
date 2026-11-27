//! 零依赖轻量 ASCII DXF 实体解析器（用于 CAD 放样与图形预览）。
//! 支持 `POINT`、`LINE` 与 `LWPOLYLINE` 实体，坐标保持工程测量级 `f64` 精度。

/// 解析后的 DXF 几何实体。
#[derive(Debug, Clone, PartialEq)]
pub enum DxfEntity {
    /// 单点实体（DXF `POINT`）。
    Point {
        /// 图层名称。
        layer: String,
        /// DXF X 坐标（工程测量中通常对应东坐标 Y）。
        x: f64,
        /// DXF Y 坐标（工程测量中通常对应北坐标 X）。
        y: f64,
        /// 高程 Z。
        z: f64,
    },
    /// 直线段实体（DXF `LINE`）。
    Line {
        /// 图层名称。
        layer: String,
        x1: f64,
        y1: f64,
        z1: f64,
        x2: f64,
        y2: f64,
        z2: f64,
    },
    /// 二维轻量多段线实体（DXF `LWPOLYLINE`）。
    LwPolyline {
        /// 图层名称。
        layer: String,
        /// 是否闭合（组码 70 最低位）。
        closed: bool,
        /// 顶点 `(x, y)` 序列。
        vertices: Vec<(f64, f64)>,
    },
}

/// DXF 实体统计摘要。
#[derive(Debug, Default)]
pub struct DxfSummary {
    /// 点实体数量。
    pub point_count: usize,
    /// 直线实体数量。
    pub line_count: usize,
    /// 多段线实体数量。
    pub polyline_count: usize,
    /// 总顶点数（含点、线端点与多段线顶点）。
    pub total_vertices: usize,
}

/// 解析 ASCII DXF 文本中的 `ENTITIES` 段，提取 `POINT`、`LINE`、`LWPOLYLINE`。
pub fn parse_ascii_dxf(content: &str) -> Vec<DxfEntity> {
    let mut lines = content.lines();
    let mut in_entities = false;
    let mut current_type: Option<String> = None;
    let mut layer = String::from("0");
    let mut x = 0.0_f64;
    let mut y = 0.0_f64;
    let mut z = 0.0_f64;
    let mut x2 = 0.0_f64;
    let mut y2 = 0.0_f64;
    let mut z2 = 0.0_f64;
    let mut closed = false;
    let mut vertices: Vec<(f64, f64)> = Vec::new();
    let mut pending_vx: Option<f64> = None;
    let mut out = Vec::new();

    let flush = |etype: &Option<String>,
                 layer: &str,
                 x: f64,
                 y: f64,
                 z: f64,
                 x2: f64,
                 y2: f64,
                 z2: f64,
                 closed: bool,
                 vertices: &mut Vec<(f64, f64)>,
                 out: &mut Vec<DxfEntity>| {
        if let Some(kind) = etype {
            match kind.as_str() {
                "POINT" => out.push(DxfEntity::Point {
                    layer: layer.to_string(),
                    x,
                    y,
                    z,
                }),
                "LINE" => out.push(DxfEntity::Line {
                    layer: layer.to_string(),
                    x1: x,
                    y1: y,
                    z1: z,
                    x2,
                    y2,
                    z2,
                }),
                "LWPOLYLINE" => out.push(DxfEntity::LwPolyline {
                    layer: layer.to_string(),
                    closed,
                    vertices: std::mem::take(vertices),
                }),
                _ => {}
            }
        }
    };

    while let Some(code_raw) = lines.next() {
        let code = code_raw.trim();
        let val = match lines.next() {
            Some(v) => v.trim(),
            None => break,
        };

        if code == "2" && val == "ENTITIES" {
            in_entities = true;
            continue;
        }
        if !in_entities {
            continue;
        }
        if code == "0" && val == "ENDSEC" {
            flush(
                &current_type,
                &layer,
                x,
                y,
                z,
                x2,
                y2,
                z2,
                closed,
                &mut vertices,
                &mut out,
            );
            break;
        }
        if code == "0" {
            flush(
                &current_type,
                &layer,
                x,
                y,
                z,
                x2,
                y2,
                z2,
                closed,
                &mut vertices,
                &mut out,
            );
            current_type = Some(val.to_string());
            layer = String::from("0");
            x = 0.0;
            y = 0.0;
            z = 0.0;
            x2 = 0.0;
            y2 = 0.0;
            z2 = 0.0;
            closed = false;
            vertices.clear();
            pending_vx = None;
            continue;
        }

        match code {
            "8" => layer = val.to_string(),
            "10" => {
                if let Ok(v) = val.parse::<f64>() {
                    if current_type.as_deref() == Some("LWPOLYLINE") {
                        pending_vx = Some(v);
                    } else {
                        x = v;
                    }
                }
            }
            "20" => {
                if let Ok(v) = val.parse::<f64>() {
                    if current_type.as_deref() == Some("LWPOLYLINE") {
                        if let Some(vx) = pending_vx.take() {
                            vertices.push((vx, v));
                        }
                    } else {
                        y = v;
                    }
                }
            }
            "30" => {
                if let Ok(v) = val.parse::<f64>() {
                    z = v;
                }
            }
            "11" => {
                if let Ok(v) = val.parse::<f64>() {
                    x2 = v;
                }
            }
            "21" => {
                if let Ok(v) = val.parse::<f64>() {
                    y2 = v;
                }
            }
            "31" => {
                if let Ok(v) = val.parse::<f64>() {
                    z2 = v;
                }
            }
            "70" => {
                if let Ok(flags) = val.parse::<i32>() {
                    closed = (flags & 1) != 0;
                }
            }
            _ => {}
        }
    }

    out
}

pub fn summarize_dxf(entities: &[DxfEntity]) -> DxfSummary {
    let mut s = DxfSummary::default();
    for e in entities {
        match e {
            DxfEntity::Point { .. } => {
                s.point_count += 1;
                s.total_vertices += 1;
            }
            DxfEntity::Line { .. } => {
                s.line_count += 1;
                s.total_vertices += 2;
            }
            DxfEntity::LwPolyline { vertices, .. } => {
                s.polyline_count += 1;
                s.total_vertices += vertices.len();
            }
        }
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_point_line_and_polyline() {
        let dxf = "\
0\nSECTION\n2\nENTITIES\n\
0\nPOINT\n8\nCTRL\n10\n100.5\n20\n200.25\n30\n12.34\n\
0\nLINE\n8\nROAD\n10\n0.0\n20\n0.0\n11\n10.0\n21\n0.0\n\
0\nLWPOLYLINE\n8\nBOUND\n70\n1\n10\n0\n20\n0\n10\n10\n20\n0\n10\n10\n20\n10\n\
0\nENDSEC\n0\nEOF\n";
        let entities = parse_ascii_dxf(dxf);
        let summary = summarize_dxf(&entities);
        assert_eq!(summary.point_count, 1);
        assert_eq!(summary.line_count, 1);
        assert_eq!(summary.polyline_count, 1);
        assert_eq!(summary.total_vertices, 6);
    }
}
