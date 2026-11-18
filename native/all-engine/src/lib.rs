//! ALL (ALMIGHTY) Universal Polyglot Runtime & PHP 8.5.12 Native Engine (Rust)
//!
//! Provides:
//! 1. [A] Universal Polyglot Value & Shared Scope Bus (`PolyglotValue`, `PolyglotStore`)
//! 2. [B] High-speed Native Standard Library & Zend 8.5.12 C ABI structures (`#[repr(C)]`)
//! 3. C ABI exports (`#[no_mangle] pub extern "C"`) for zero-spawn in-process calls from ALL/PHP hosts.

use std::collections::HashMap;
use std::ffi::CStr;
use std::os::raw::{c_char, c_int, c_longlong, c_uchar};
use std::ptr;
use std::slice;
use std::sync::{Mutex, OnceLock};

// ============================================================================
// 1. Zend Engine 8.5.12 (API 20250925) Binary-Compatible C ABI Layout
// ============================================================================

pub const ZEND_MODULE_API_NO_8_5: u32 = 20250925;

#[repr(C)]
#[derive(Copy, Clone)]
pub union ZendValueUnion {
    pub lval: i64,
    pub dval: f64,
    pub ptr: *mut std::ffi::c_void,
}

#[repr(C)]
#[derive(Copy, Clone)]
pub struct Zval {
    pub value: ZendValueUnion,
    pub u1_type_info: u32,
    pub u2_aux: u32,
}

#[repr(C)]
pub struct ZendFunctionEntry {
    pub fname: *const c_char,
    pub handler: Option<unsafe extern "C" fn(*mut std::ffi::c_void, *mut Zval)>,
    pub arg_info: *const std::ffi::c_void,
    pub num_args: u32,
    pub flags: u32,
    pub doc_comment: *const c_char,
    pub frameless_function_infos: *const std::ffi::c_void,
}

#[repr(C)]
pub struct ZendModuleEntry {
    pub size: u16,
    pub zend_api: u32,
    pub zend_debug: u8,
    pub zts: u8,
    pub ini_entry: *const std::ffi::c_void,
    pub deps: *const std::ffi::c_void,
    pub name: *const c_char,
    pub functions: *const ZendFunctionEntry,
    pub module_startup_func: Option<unsafe extern "C" fn(c_int, c_int) -> c_int>,
    pub module_shutdown_func: Option<unsafe extern "C" fn(c_int, c_int) -> c_int>,
    pub request_startup_func: Option<unsafe extern "C" fn(c_int, c_int) -> c_int>,
    pub request_shutdown_func: Option<unsafe extern "C" fn(c_int, c_int) -> c_int>,
    pub info_func: Option<unsafe extern "C" fn(*mut ZendModuleEntry)>,
    pub version: *const c_char,
    pub globals_size: usize,
    pub globals_id_ptr: *mut std::ffi::c_void,
    pub globals_ctor: Option<unsafe extern "C" fn(*mut std::ffi::c_void)>,
    pub globals_dtor: Option<unsafe extern "C" fn(*mut std::ffi::c_void)>,
    pub post_deactivate_func: Option<unsafe extern "C" fn() -> c_int>,
    pub module_started: c_int,
    pub type_: c_uchar,
    pub handle: *mut std::ffi::c_void,
    pub module_number: c_int,
    pub build_id: *const c_char,
}

// ============================================================================
// 2. Universal Polyglot Value & Shared State Bus ([A] ALL <-> PHP <-> Future Languages)
// ============================================================================

#[derive(Clone, Debug, PartialEq)]
pub enum PolyglotValue {
    Null,
    Bool(bool),
    Int(i64),
    Float(f64),
    Bytes(Vec<u8>),
    Json(String),
}

pub struct PolyglotStore {
    pub variables: HashMap<String, PolyglotValue>,
    pub registered_languages: Vec<String>,
}

impl PolyglotStore {
    fn new() -> Self {
        Self {
            variables: HashMap::new(),
            registered_languages: vec!["ALL".to_string(), "PHP".to_string()],
        }
    }
}

static POLYGLOT_STORE: OnceLock<Mutex<PolyglotStore>> = OnceLock::new();

fn store() -> &'static Mutex<PolyglotStore> {
    POLYGLOT_STORE.get_or_init(|| Mutex::new(PolyglotStore::new()))
}

#[no_mangle]
pub extern "C" fn all_engine_version() -> c_int {
    100 // v1.0.0 Rust Polyglot Engine
}

#[no_mangle]
pub unsafe extern "C" fn all_polyglot_set_json(name_ptr: *const c_char, json_ptr: *const c_char) -> c_int {
    if name_ptr.is_null() || json_ptr.is_null() {
        return -1;
    }
    let name = match CStr::from_ptr(name_ptr).to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return -2,
    };
    let json = match CStr::from_ptr(json_ptr).to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return -3,
    };
    if let Ok(mut guard) = store().lock() {
        guard.variables.insert(name, PolyglotValue::Json(json));
        0
    } else {
        -4
    }
}

#[no_mangle]
pub unsafe extern "C" fn all_polyglot_get_json(
    name_ptr: *const c_char,
    out_buf: *mut c_uchar,
    buf_cap: c_int,
) -> c_int {
    if name_ptr.is_null() {
        return -1;
    }
    let name = match CStr::from_ptr(name_ptr).to_str() {
        Ok(s) => s,
        Err(_) => return -2,
    };
    if let Ok(guard) = store().lock() {
        if let Some(PolyglotValue::Json(s)) = guard.variables.get(name) {
            let bytes = s.as_bytes();
            let len = bytes.len() as c_int;
            if out_buf.is_null() || buf_cap < len {
                return len;
            }
            ptr::copy_nonoverlapping(bytes.as_ptr(), out_buf, bytes.len());
            return len;
        }
    }
    -1
}

#[no_mangle]
pub extern "C" fn all_polyglot_clear() {
    if let Ok(mut guard) = store().lock() {
        guard.variables.clear();
    }
}

// ============================================================================
// 3. High-Speed Native Standard Library Algorithms ([B] Crypto, Hashes, Codecs, Strings)
// ============================================================================

/// Pure-Rust RFC 1321 MD5 implementation (zero external dependencies)
pub fn compute_md5(input: &[u8]) -> [u8; 16] {
    const S: [u32; 64] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    ];
    const K: [u32; 64] = [
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
        0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
        0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
        0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
        0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
        0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
        0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
        0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
        0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
        0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
        0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
        0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
        0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
    ];

    let mut a0: u32 = 0x67452301;
    let mut b0: u32 = 0xefcdab89;
    let mut c0: u32 = 0x98badcfe;
    let mut d0: u32 = 0x10325476;

    let bit_len = (input.len() as u64).wrapping_mul(8);
    let mut msg = input.to_vec();
    msg.push(0x80);
    while (msg.len() % 64) != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&bit_len.to_le_bytes());

    for chunk in msg.chunks_exact(64) {
        let mut m = [0u32; 16];
        for (i, word) in m.iter_mut().enumerate() {
            let b = &chunk[i * 4..i * 4 + 4];
            *word = u32::from_le_bytes([b[0], b[1], b[2], b[3]]);
        }
        let mut a = a0;
        let mut b = b0;
        let mut c = c0;
        let mut d = d0;
        for i in 0..64 {
            let (f, g) = match i {
                0..=15 => ((b & c) | ((!b) & d), i),
                16..=31 => ((d & b) | ((!d) & c), (5 * i + 1) % 16),
                32..=47 => (b ^ c ^ d, (3 * i + 5) % 16),
                _ => (c ^ (b | (!d)), (7 * i) % 16),
            };
            let temp = d;
            d = c;
            c = b;
            b = b.wrapping_add(
                a.wrapping_add(f)
                    .wrapping_add(K[i])
                    .wrapping_add(m[g])
                    .rotate_left(S[i]),
            );
            a = temp;
        }
        a0 = a0.wrapping_add(a);
        b0 = b0.wrapping_add(b);
        c0 = c0.wrapping_add(c);
        d0 = d0.wrapping_add(d);
    }

    let mut out = [0u8; 16];
    out[0..4].copy_from_slice(&a0.to_le_bytes());
    out[4..8].copy_from_slice(&b0.to_le_bytes());
    out[8..12].copy_from_slice(&c0.to_le_bytes());
    out[12..16].copy_from_slice(&d0.to_le_bytes());
    out
}

/// Pure-Rust FIPS 180-1 SHA-1 implementation
pub fn compute_sha1(input: &[u8]) -> [u8; 20] {
    let mut h0: u32 = 0x67452301;
    let mut h1: u32 = 0xEFCDAB89;
    let mut h2: u32 = 0x98BADCFE;
    let mut h3: u32 = 0x10325476;
    let mut h4: u32 = 0xC3D2E1F0;

    let bit_len = (input.len() as u64).wrapping_mul(8);
    let mut msg = input.to_vec();
    msg.push(0x80);
    while (msg.len() % 64) != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&bit_len.to_be_bytes());

    for chunk in msg.chunks_exact(64) {
        let mut w = [0u32; 80];
        for i in 0..16 {
            let b = &chunk[i * 4..i * 4 + 4];
            w[i] = u32::from_be_bytes([b[0], b[1], b[2], b[3]]);
        }
        for i in 16..80 {
            w[i] = (w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]).rotate_left(1);
        }
        let mut a = h0;
        let mut b = h1;
        let mut c = h2;
        let mut d = h3;
        let mut e = h4;

        for i in 0..80 {
            let (f, k) = match i {
                0..=19 => ((b & c) | ((!b) & d), 0x5A827999u32),
                20..=39 => (b ^ c ^ d, 0x6ED9EBA1u32),
                40..=59 => ((b & c) | (b & d) | (c & d), 0x8F1BBCDCu32),
                _ => (b ^ c ^ d, 0xCA62C1D6u32),
            };
            let temp = a
                .rotate_left(5)
                .wrapping_add(f)
                .wrapping_add(e)
                .wrapping_add(k)
                .wrapping_add(w[i]);
            e = d;
            d = c;
            c = b.rotate_left(30);
            b = a;
            a = temp;
        }
        h0 = h0.wrapping_add(a);
        h1 = h1.wrapping_add(b);
        h2 = h2.wrapping_add(c);
        h3 = h3.wrapping_add(d);
        h4 = h4.wrapping_add(e);
    }

    let mut out = [0u8; 20];
    out[0..4].copy_from_slice(&h0.to_be_bytes());
    out[4..8].copy_from_slice(&h1.to_be_bytes());
    out[8..12].copy_from_slice(&h2.to_be_bytes());
    out[12..16].copy_from_slice(&h3.to_be_bytes());
    out[16..20].copy_from_slice(&h4.to_be_bytes());
    out
}

/// Pure-Rust FIPS 180-4 SHA-256 implementation
pub fn compute_sha256(input: &[u8]) -> [u8; 32] {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ];

    let bit_len = (input.len() as u64).wrapping_mul(8);
    let mut msg = input.to_vec();
    msg.push(0x80);
    while (msg.len() % 64) != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&bit_len.to_be_bytes());

    for chunk in msg.chunks_exact(64) {
        let mut w = [0u32; 64];
        for i in 0..16 {
            let b = &chunk[i * 4..i * 4 + 4];
            w[i] = u32::from_be_bytes([b[0], b[1], b[2], b[3]]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16].wrapping_add(s0).wrapping_add(w[i - 7]).wrapping_add(s1);
        }
        let mut a = h[0];
        let mut b = h[1];
        let mut c = h[2];
        let mut d = h[3];
        let mut e = h[4];
        let mut f = h[5];
        let mut g = h[6];
        let mut hh = h[7];

        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let temp1 = hh.wrapping_add(s1).wrapping_add(ch).wrapping_add(K[i]).wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = s0.wrapping_add(maj);

            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(temp1);
            d = c;
            c = b;
            b = a;
            a = temp1.wrapping_add(temp2);
        }
        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
        h[5] = h[5].wrapping_add(f);
        h[6] = h[6].wrapping_add(g);
        h[7] = h[7].wrapping_add(hh);
    }

    let mut out = [0u8; 32];
    for (i, word) in h.iter().enumerate() {
        out[i * 4..i * 4 + 4].copy_from_slice(&word.to_be_bytes());
    }
    out
}

/// Pure-Rust IEEE 802.3 CRC32 implementation (PHP `crc32()`)
pub fn compute_crc32(input: &[u8]) -> u32 {
    let mut crc: u32 = 0xFFFF_FFFF;
    for &byte in input {
        crc ^= byte as u32;
        for _ in 0..8 {
            if (crc & 1) != 0 {
                crc = (crc >> 1) ^ 0xEDB8_8320;
            } else {
                crc >>= 1;
            }
        }
    }
    !crc
}

/// Levenshtein edit distance on raw bytes (PHP `levenshtein()`)
pub fn compute_levenshtein(s1: &[u8], s2: &[u8]) -> i64 {
    let m = s1.len();
    let n = s2.len();
    if m == 0 {
        return n as i64;
    }
    if n == 0 {
        return m as i64;
    }
    let mut prev: Vec<usize> = (0..=n).collect();
    let mut curr = vec![0usize; n + 1];
    for i in 1..=m {
        curr[0] = i;
        for j in 1..=n {
            let cost = if s1[i - 1] == s2[j - 1] { 0 } else { 1 };
            curr[j] = (prev[j] + 1).min(curr[j - 1] + 1).min(prev[j - 1] + cost);
        }
        std::mem::swap(&mut prev, &mut curr);
    }
    prev[n] as i64
}

fn to_hex_lower(bytes: &[u8]) -> Vec<u8> {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = Vec::with_capacity(bytes.len() * 2);
    for &b in bytes {
        out.push(HEX[(b >> 4) as usize]);
        out.push(HEX[(b & 0x0F) as usize]);
    }
    out
}

#[no_mangle]
pub unsafe extern "C" fn all_stdlib_md5(
    input_ptr: *const c_uchar,
    input_len: c_int,
    raw_output: c_int,
    out_buf: *mut c_uchar,
) -> c_int {
    let slice = if input_ptr.is_null() || input_len <= 0 {
        &[][..]
    } else {
        slice::from_raw_parts(input_ptr, input_len as usize)
    };
    let digest = compute_md5(slice);
    if raw_output != 0 {
        if !out_buf.is_null() {
            ptr::copy_nonoverlapping(digest.as_ptr(), out_buf, 16);
        }
        16
    } else {
        let hex = to_hex_lower(&digest);
        if !out_buf.is_null() {
            ptr::copy_nonoverlapping(hex.as_ptr(), out_buf, 32);
        }
        32
    }
}

#[no_mangle]
pub unsafe extern "C" fn all_stdlib_sha1(
    input_ptr: *const c_uchar,
    input_len: c_int,
    raw_output: c_int,
    out_buf: *mut c_uchar,
) -> c_int {
    let slice = if input_ptr.is_null() || input_len <= 0 {
        &[][..]
    } else {
        slice::from_raw_parts(input_ptr, input_len as usize)
    };
    let digest = compute_sha1(slice);
    if raw_output != 0 {
        if !out_buf.is_null() {
            ptr::copy_nonoverlapping(digest.as_ptr(), out_buf, 20);
        }
        20
    } else {
        let hex = to_hex_lower(&digest);
        if !out_buf.is_null() {
            ptr::copy_nonoverlapping(hex.as_ptr(), out_buf, 40);
        }
        40
    }
}

#[no_mangle]
pub unsafe extern "C" fn all_stdlib_sha256(
    input_ptr: *const c_uchar,
    input_len: c_int,
    raw_output: c_int,
    out_buf: *mut c_uchar,
) -> c_int {
    let slice = if input_ptr.is_null() || input_len <= 0 {
        &[][..]
    } else {
        slice::from_raw_parts(input_ptr, input_len as usize)
    };
    let digest = compute_sha256(slice);
    if raw_output != 0 {
        if !out_buf.is_null() {
            ptr::copy_nonoverlapping(digest.as_ptr(), out_buf, 32);
        }
        32
    } else {
        let hex = to_hex_lower(&digest);
        if !out_buf.is_null() {
            ptr::copy_nonoverlapping(hex.as_ptr(), out_buf, 64);
        }
        64
    }
}

#[no_mangle]
pub unsafe extern "C" fn all_stdlib_crc32(input_ptr: *const c_uchar, input_len: c_int) -> c_longlong {
    let slice = if input_ptr.is_null() || input_len <= 0 {
        &[][..]
    } else {
        slice::from_raw_parts(input_ptr, input_len as usize)
    };
    compute_crc32(slice) as c_longlong
}

#[no_mangle]
pub unsafe extern "C" fn all_stdlib_levenshtein(
    s1_ptr: *const c_uchar,
    s1_len: c_int,
    s2_ptr: *const c_uchar,
    s2_len: c_int,
) -> c_longlong {
    let s1 = if s1_ptr.is_null() || s1_len <= 0 {
        &[][..]
    } else {
        slice::from_raw_parts(s1_ptr, s1_len as usize)
    };
    let s2 = if s2_ptr.is_null() || s2_len <= 0 {
        &[][..]
    } else {
        slice::from_raw_parts(s2_ptr, s2_len as usize)
    };
    compute_levenshtein(s1, s2) as c_longlong
}
