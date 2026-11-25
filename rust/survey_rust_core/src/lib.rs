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
    1
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
