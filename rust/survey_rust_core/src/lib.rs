pub mod dxf_parser;
pub mod spatial_index;
pub mod tin_earthwork;

use std::ffi::CStr;
use std::os::raw::c_char;

use dxf_parser::{parse_ascii_dxf, summarize_dxf};
use spatial_index::find_nearest_point_2d;
use tin_earthwork::{compute_tin_volume, TinPoint};

#[repr(C)]
pub struct FfiDxfCounts {
    pub point_count: u32,
    pub line_count: u32,
    pub polyline_count: u32,
    pub total_vertices: u32,
}

#[repr(C)]
pub struct FfiEarthworkResult {
    pub cut_volume: f64,
    pub fill_volume: f64,
    pub net_volume: f64,
    pub plan_area: f64,
}

#[no_mangle]
pub extern "C" fn survey_rust_abi_version() -> u32 {
    5
}

/// Distributes traverse misclosure over interleaved (dx, dy, length) rows.
///
/// # Safety
/// Input and output must be disjoint and valid for count × 3 and count × 2
/// doubles respectively.
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
    if input.is_null() || output.is_null() || count == 0 {
        return;
    }
    let input = unsafe { std::slice::from_raw_parts(input, count as usize * 3) };
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
}

#[repr(C)]
pub struct FfiLevelingStation {
    pub back_distance: f64,
    pub front_distance: f64,
    pub distance_diff: f64,
    pub cumulative_diff: f64,
    pub back_constant: f64,
    pub front_constant: f64,
    pub black_diff: f64,
    pub red_diff: f64,
    pub mean_diff: f64,
    pub issues: u32,
}

/// Calculates a route of dual-face stations (ABI v5).
///
/// Each input row contains 14 doubles:
/// `[back_distance, front_distance, back_black, back_red, front_black, front_red,
///   k_back, k_front, back_upper, back_lower, front_upper, front_lower,
///   has_back_direct, has_front_direct]`.
///
/// `issues` bitmask:
/// - bit 0: back constant failed (`|K+B-R| > 3.0`)
/// - bit 1: front constant failed (`|K+B-R| > 3.0`)
/// - bit 2: distance diff failed (`|d| > distance_limit`)
/// - bit 3: cumulative distance diff failed (`|Σd| > 10.0`)
/// - bit 4: sight distance failed (`distance > sight_limit`)
/// - bit 5: black/red height diff failed
/// - bit 6: sight height too low (`<= min_sight_height_mm`)
/// - bit 7: cumulative stadia warning (`7.0 < |Σd| <= 10.0`)
///
/// # Safety
/// The input and output must be disjoint and valid for count × 14 doubles
/// and count station results respectively.
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
    if input.is_null() || output.is_null() || count == 0 {
        return;
    }
    let input = unsafe { std::slice::from_raw_parts(input, count as usize * 14) };
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
}

/// Counts DXF entities from a UTF-8 C string.
///
/// # Safety
/// `dxf_utf8` must be a valid NUL-terminated UTF-8 pointer.
#[no_mangle]
pub unsafe extern "C" fn survey_dxf_count_entities(dxf_utf8: *const c_char) -> FfiDxfCounts {
    if dxf_utf8.is_null() {
        return FfiDxfCounts {
            point_count: 0,
            line_count: 0,
            polyline_count: 0,
            total_vertices: 0,
        };
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
}

/// Computes TIN earthwork cut/fill/net volume over flat xyz and triangle index buffers.
///
/// # Safety
/// `xyz_ptr` must point to `point_count * 3` `f64` values; `tri_ptr` to `tri_count * 3` `u32` values.
#[no_mangle]
pub unsafe extern "C" fn survey_tin_compute_volume(
    xyz_ptr: *const f64,
    point_count: u32,
    tri_ptr: *const u32,
    tri_count: u32,
    design_z: f64,
) -> FfiEarthworkResult {
    if xyz_ptr.is_null() || tri_ptr.is_null() || point_count == 0 || tri_count == 0 {
        return FfiEarthworkResult {
            cut_volume: 0.0,
            fill_volume: 0.0,
            net_volume: 0.0,
            plan_area: 0.0,
        };
    }
    let xyz = unsafe { std::slice::from_raw_parts(xyz_ptr, point_count as usize * 3) };
    let tris_raw = unsafe { std::slice::from_raw_parts(tri_ptr, tri_count as usize * 3) };

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
}

/// Finds the nearest 2D point index in `(xs, ys)` to `(target_x, target_y)`, or `-1` if empty.
///
/// # Safety
/// `xs_ptr` and `ys_ptr` must point to at least `count` `f64` values.
#[no_mangle]
pub unsafe extern "C" fn survey_spatial_nearest_2d(
    xs_ptr: *const f64,
    ys_ptr: *const f64,
    count: u32,
    target_x: f64,
    target_y: f64,
) -> i32 {
    if xs_ptr.is_null() || ys_ptr.is_null() || count == 0 {
        return -1;
    }
    let xs = unsafe { std::slice::from_raw_parts(xs_ptr, count as usize) };
    let ys = unsafe { std::slice::from_raw_parts(ys_ptr, count as usize) };
    find_nearest_point_2d(xs, ys, target_x, target_y)
        .map(|m| m.index as i32)
        .unwrap_or(-1)
}

/// Returns the parsed ASCII DXF entities as UTF-8 JSON. The caller owns the result
/// and must pass it to `survey_string_free` once.
///
/// # Safety
/// `source` must point to a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn survey_dxf_parse_json(source: *const c_char) -> *mut c_char {
    use dxf_parser::DxfEntity;
    use serde_json::json;
    use std::ffi::CString;
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
}

/// # Safety
/// `value` must be null or a pointer returned by `survey_dxf_parse_json` that
/// has not been freed.
#[no_mangle]
pub unsafe extern "C" fn survey_string_free(value: *mut c_char) {
    if !value.is_null() {
        drop(unsafe { std::ffi::CString::from_raw(value) });
    }
}
