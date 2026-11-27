pub mod dxf_parser;
pub mod spatial_index;
pub mod tin_earthwork;

use std::ffi::CStr;
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};

use dxf_parser::{parse_ascii_dxf, summarize_dxf};
use spatial_index::find_nearest_point_2d;
use tin_earthwork::{compute_tin_volume, TinPoint};

/// FFI 返回的 DXF 实体统计结构。
#[repr(C)]
pub struct FfiDxfCounts {
    /// 点实体数量。
    pub point_count: u32,
    /// 直线实体数量。
    pub line_count: u32,
    /// 多段线实体数量。
    pub polyline_count: u32,
    /// 总顶点数。
    pub total_vertices: u32,
}

/// FFI 返回的 TIN 土方量计算结果（单位 m³ / m²）。
#[repr(C)]
pub struct FfiEarthworkResult {
    /// 挖方总量（m³）。
    pub cut_volume: f64,
    /// 填方总量（m³）。
    pub fill_volume: f64,
    /// 净方量（挖方 − 填方，m³）。
    pub net_volume: f64,
    /// 平面投影总面积（m²）。
    pub plan_area: f64,
}

/// 返回当前 Rust FFI 内核的 ABI 版本号（当前为 `5`）。
#[no_mangle]
pub extern "C" fn survey_rust_abi_version() -> u32 {
    5
}

/// 对交错排列的 `(dx, dy, length)` 导线边长行分配坐标闭合差。
///
/// 按边长比例或坐标增量绝对值比例（`by_component != 0` 且两方向总绝对增量均大于 0）分配，
/// 并由最后一条边吸收浮点残差，确保平差后增量之和严格等于 `(target_x, target_y)`。
///
/// # Safety
/// `input` 与 `output` 必须互不重叠，且分别指向至少 `count × 3` 与 `count × 2` 个有效 `f64`。
#[no_mangle]
pub unsafe extern "C" fn survey_traverse_distribute(
    input: *const f64,
    output: *mut f64,
    count: u32,
    fx: f64,
    fy: f64,
    target_x: f64,
    target_y: f64,
    by_component: u32,
) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if input.is_null() || output.is_null() || count == 0 {
            return;
        }
        let Some(input_len) = (count as usize).checked_mul(3) else {
            return;
        };
        if (count as usize).checked_mul(2).is_none() {
            return;
        }
        let input = unsafe { std::slice::from_raw_parts(input, input_len) };
        let (sum_x, sum_y, sum_length) = input
            .chunks_exact(3)
            .fold((0.0, 0.0, 0.0), |(x, y, length), row| {
                (x + row[0].abs(), y + row[1].abs(), length + row[2])
            });
        let use_component = by_component != 0 && sum_x > 0.0 && sum_y > 0.0;
        let mut placed_x = 0.0;
        let mut placed_y = 0.0;
        for (index, row) in input.chunks_exact(3).take(count as usize - 1).enumerate() {
            let share = if sum_length <= 0.0 {
                0.0
            } else {
                row[2] / sum_length
            };
            let x = row[0]
                - fx * if use_component {
                    row[0].abs() / sum_x
                } else {
                    share
                };
            let y = row[1]
                - fy * if use_component {
                    row[1].abs() / sum_y
                } else {
                    share
                };
            unsafe {
                output.add(index * 2).write(x);
                output.add(index * 2 + 1).write(y);
            }
            placed_x += x;
            placed_y += y;
        }
        let last = (count as usize - 1) * 2;
        unsafe {
            output.add(last).write(target_x - placed_x);
            output.add(last + 1).write(target_y - placed_y);
        }
    }));
}

/// FFI 返回的单个双面尺水准测站计算与检核结果。
#[repr(C)]
pub struct FfiLevelingStation {
    /// 后视距（m）。
    pub back_distance: f64,
    /// 前视距（m）。
    pub front_distance: f64,
    /// 本站视距差（m）。
    pub distance_diff: f64,
    /// 累计视距差（m）。
    pub cumulative_diff: f64,
    /// 后尺常数差 `K + 黑 − 红`（mm）。
    pub back_constant: f64,
    /// 前尺常数差 `K + 黑 − 红`（mm）。
    pub front_constant: f64,
    /// 黑面高差（mm）。
    pub black_diff: f64,
    /// 红面高差（mm）。
    pub red_diff: f64,
    /// 高差中数（mm）。
    pub mean_diff: f64,
    /// 超限标志位掩码（见 `survey_leveling_check`）。
    pub issues: u32,
}

/// 计算并检核四等水准双面尺整条路线（ABI v5）。
///
/// 每行输入包含 14 个 `f64`：
/// `[back_distance, front_distance, back_black, back_red, front_black, front_red,
///   k_back, k_front, back_upper, back_lower, front_upper, front_lower,
///   has_back_direct, has_front_direct]`。
///
/// `issues` 位掩码含义：
/// - bit 0：后尺 `|K+黑−红| > 3.0 mm`
/// - bit 1：前尺 `|K+黑−红| > 3.0 mm`
/// - bit 2：单站视距差 `|d| > distance_limit`
/// - bit 3：累计视距差 `|Σd| > 10.0 m`
/// - bit 4：视线长度超限（`> sight_limit`）
/// - bit 5：红黑面高差之差超限（`> height_limit`）
/// - bit 6：视线高过低（`<= min_sight_height_mm`，默认 `200 mm` 即 `0.2 m`）
/// - bit 7：累计视距差接近限差预警（`7.0 < |Σd| <= 10.0`）
///
/// # Safety
/// `input` 与 `output` 必须互不重叠，且分别指向至少 `count × 14` 个 `f64` 与 `count` 个 `FfiLevelingStation`。
#[no_mangle]
pub unsafe extern "C" fn survey_leveling_check(
    input: *const f64,
    output: *mut FfiLevelingStation,
    count: u32,
    distance_limit: f64,
    sight_limit: f64,
    height_limit: f64,
    min_sight_height_mm: f64,
) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if input.is_null() || output.is_null() || count == 0 {
            return;
        }
        let Some(input_len) = (count as usize).checked_mul(14) else {
            return;
        };
        let input = unsafe { std::slice::from_raw_parts(input, input_len) };
        let mut cumulative_diff = 0.0;
        for (index, values) in input.chunks_exact(14).enumerate() {
            let [back_distance, front_distance, back_black, back_red, front_black, front_red, k_back, k_front, back_upper, back_lower, front_upper, front_lower, has_back_direct, has_front_direct] =
                values
            else {
                unreachable!()
            };
            let distance_diff = back_distance - front_distance;
            cumulative_diff += distance_diff;
            let back_constant = k_back + back_black - back_red;
            let front_constant = k_front + front_black - front_red;
            let black_diff = back_black - front_black;
            let red_diff = back_red - front_red;
            let mean_diff = (black_diff + red_diff - (k_back - k_front)) / 2.0;

            let back_sight_height_ok = *back_black > min_sight_height_mm
                && *back_red > min_sight_height_mm
                && (*has_back_direct > 0.5
                    || (*back_lower > min_sight_height_mm && *back_upper > min_sight_height_mm));
            let front_sight_height_ok = *front_black > min_sight_height_mm
                && *front_red > min_sight_height_mm
                && (*has_front_direct > 0.5
                    || (*front_lower > min_sight_height_mm && *front_upper > min_sight_height_mm));

            let cumulative_ok = cumulative_diff.abs() <= 10.0 + 1e-9;
            let cum_stadia_warning = cumulative_ok && cumulative_diff.abs() > 7.0;

            let limits = [
                back_constant.abs() <= 3.0,
                front_constant.abs() <= 3.0,
                distance_diff.abs() <= distance_limit + 1e-9,
                cumulative_ok,
                *back_distance <= sight_limit + 1e-9 && *front_distance <= sight_limit + 1e-9,
                (black_diff - red_diff + k_back - k_front).abs() <= height_limit,
                back_sight_height_ok && front_sight_height_ok,
            ];
            let mut issues = limits.iter().enumerate().fold(
                0u32,
                |mask, (bit, ok)| if *ok { mask } else { mask | (1 << bit) },
            );
            if cum_stadia_warning {
                issues |= 1 << 7;
            }
            unsafe {
                output.add(index).write(FfiLevelingStation {
                    back_distance: *back_distance,
                    front_distance: *front_distance,
                    distance_diff,
                    cumulative_diff,
                    back_constant,
                    front_constant,
                    black_diff,
                    red_diff,
                    mean_diff,
                    issues,
                })
            };
        }
    }));
}

/// 统计 UTF-8 编码的 ASCII DXF 文本中的实体数量。
///
/// # Safety
/// `dxf_utf8` 为空指针时返回全零；非空时必须是以 NUL 结尾的有效 C 字符串指针。
#[no_mangle]
pub unsafe extern "C" fn survey_dxf_count_entities(dxf_utf8: *const c_char) -> FfiDxfCounts {
    let zero = FfiDxfCounts {
        point_count: 0,
        line_count: 0,
        polyline_count: 0,
        total_vertices: 0,
    };
    catch_unwind(AssertUnwindSafe(|| {
        if dxf_utf8.is_null() {
            return zero;
        }
        let text = unsafe { CStr::from_ptr(dxf_utf8) }.to_string_lossy();
        let entities = parse_ascii_dxf(&text);
        let summary = summarize_dxf(&entities);
        FfiDxfCounts {
            point_count: summary.point_count as u32,
            line_count: summary.line_count as u32,
            polyline_count: summary.polyline_count as u32,
            total_vertices: summary.total_vertices as u32,
        }
    }))
    .unwrap_or(FfiDxfCounts {
        point_count: 0,
        line_count: 0,
        polyline_count: 0,
        total_vertices: 0,
    })
}

/// 计算平坦 `xyz` 点集与三角形索引缓冲区构成的不规则三角网（TIN）挖填方量。
///
/// # Safety
/// `xyz_ptr` 须指向至少 `point_count * 3` 个 `f64`，`tri_ptr` 须指向至少 `tri_count * 3` 个 `u32`。
#[no_mangle]
pub unsafe extern "C" fn survey_tin_compute_volume(
    xyz_ptr: *const f64,
    point_count: u32,
    tri_ptr: *const u32,
    tri_count: u32,
    design_z: f64,
) -> FfiEarthworkResult {
    let zero = FfiEarthworkResult {
        cut_volume: 0.0,
        fill_volume: 0.0,
        net_volume: 0.0,
        plan_area: 0.0,
    };
    catch_unwind(AssertUnwindSafe(|| {
        if xyz_ptr.is_null() || tri_ptr.is_null() || point_count == 0 || tri_count == 0 {
            return zero;
        }
        let (Some(xyz_len), Some(tri_len)) = (
            (point_count as usize).checked_mul(3),
            (tri_count as usize).checked_mul(3),
        ) else {
            return zero;
        };
        let xyz = unsafe { std::slice::from_raw_parts(xyz_ptr, xyz_len) };
        let tris_raw = unsafe { std::slice::from_raw_parts(tri_ptr, tri_len) };

        let points: Vec<TinPoint> = xyz
            .chunks_exact(3)
            .map(|c| TinPoint {
                x: c[0],
                y: c[1],
                z: c[2],
            })
            .collect();
        let tris: Vec<[usize; 3]> = tris_raw
            .chunks_exact(3)
            .map(|t| [t[0] as usize, t[1] as usize, t[2] as usize])
            .collect();

        let res = compute_tin_volume(&points, &tris, design_z);
        FfiEarthworkResult {
            cut_volume: res.cut_volume,
            fill_volume: res.fill_volume,
            net_volume: res.net_volume,
            plan_area: res.plan_area,
        }
    }))
    .unwrap_or(FfiEarthworkResult {
        cut_volume: 0.0,
        fill_volume: 0.0,
        net_volume: 0.0,
        plan_area: 0.0,
    })
}

/// 在 `(xs, ys)` 平面点集中查找距离 `(target_x, target_y)` 最近的点下标；为空或超限时返回 `-1`。
///
/// # Safety
/// `xs_ptr` 与 `ys_ptr` 必须至少指向 `count` 个 `f64`。
#[no_mangle]
pub unsafe extern "C" fn survey_spatial_nearest_2d(
    xs_ptr: *const f64,
    ys_ptr: *const f64,
    count: u32,
    target_x: f64,
    target_y: f64,
) -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        if xs_ptr.is_null() || ys_ptr.is_null() || count == 0 {
            return -1;
        }
        let xs = unsafe { std::slice::from_raw_parts(xs_ptr, count as usize) };
        let ys = unsafe { std::slice::from_raw_parts(ys_ptr, count as usize) };
        find_nearest_point_2d(xs, ys, target_x, target_y)
            .and_then(|m| i32::try_from(m.index).ok())
            .unwrap_or(-1)
    }))
    .unwrap_or(-1)
}

/// 解析 ASCII DXF 实体并返回 UTF-8 JSON 字符串。调用方负责且仅可调用一次 `survey_string_free` 释放。
///
/// # Safety
/// `source` 必须是指向以 NUL 结尾的有效 UTF-8 字符串的指针（可为空指针）。
#[no_mangle]
pub unsafe extern "C" fn survey_dxf_parse_json(source: *const c_char) -> *mut c_char {
    use dxf_parser::DxfEntity;
    use serde_json::json;
    use std::ffi::CString;

    catch_unwind(AssertUnwindSafe(|| {
        if source.is_null() {
            return std::ptr::null_mut();
        }
        let Ok(source) = unsafe { CStr::from_ptr(source) }.to_str() else {
            return std::ptr::null_mut();
        };
        let rows: Vec<_> = parse_ascii_dxf(source)
            .into_iter()
            .map(|entity| match entity {
                DxfEntity::Point { layer, x, y, z } => json!(["point", layer, x, y, z]),
                DxfEntity::Line {
                    layer,
                    x1,
                    y1,
                    z1,
                    x2,
                    y2,
                    z2,
                } => json!(["line", layer, x1, y1, z1, x2, y2, z2]),
                DxfEntity::LwPolyline {
                    layer,
                    closed,
                    vertices,
                } => json!(["polyline", layer, closed, vertices]),
            })
            .collect();
        CString::new(serde_json::Value::Array(rows).to_string())
            .map(CString::into_raw)
            .unwrap_or(std::ptr::null_mut())
    }))
    .unwrap_or(std::ptr::null_mut())
}

/// 释放由 `survey_dxf_parse_json` 分配并返回的 C 字符串。
///
/// # Safety
/// `value` 必须为空指针，或由 `survey_dxf_parse_json` 返回且尚未释放的指针。
#[no_mangle]
pub unsafe extern "C" fn survey_string_free(value: *mut c_char) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if !value.is_null() {
            drop(unsafe { std::ffi::CString::from_raw(value) });
        }
    }));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ffi_null_and_zero_count_guards() {
        unsafe {
            survey_traverse_distribute(std::ptr::null(), std::ptr::null_mut(), 0, 0.0, 0.0, 0.0, 0.0, 0);
            survey_leveling_check(std::ptr::null(), std::ptr::null_mut(), 0, 5.0, 100.0, 5.0, 200.0);
            let counts = survey_dxf_count_entities(std::ptr::null());
            assert_eq!(counts.total_vertices, 0);
            let tin = survey_tin_compute_volume(std::ptr::null(), 0, std::ptr::null(), 0, 10.0);
            assert_eq!(tin.plan_area, 0.0);
            assert_eq!(survey_spatial_nearest_2d(std::ptr::null(), std::ptr::null(), 0, 0.0, 0.0), -1);
            assert!(survey_dxf_parse_json(std::ptr::null()).is_null());
            survey_string_free(std::ptr::null_mut());
        }
    }

    #[test]
    fn ffi_tin_skips_degenerate_and_out_of_bounds() {
        let xyz = [0.0, 0.0, 10.0, 10.0, 0.0, 12.0, 20.0, 0.0, 14.0];
        let tris = [0u32, 1, 2, 0, 1, 99];
        let res = unsafe { survey_tin_compute_volume(xyz.as_ptr(), 3, tris.as_ptr(), 2, 10.0) };
        assert_eq!(res.plan_area, 0.0);
        assert_eq!(res.net_volume, 0.0);
    }
}
