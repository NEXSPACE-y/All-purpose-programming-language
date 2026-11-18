//! [C] ALL Rust Multi-threaded PHPT & Differential Regression Runner
//!
//! Parses official PHP `.phpt` test files (--TEST--, --FILE--, --EXPECT--, --EXPECTF--, etc.)
//! and runs expectation / differential checks across worker threads using ALL's PHP adapter.

use std::collections::{BTreeMap, HashMap};
use std::env;
use std::fs;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Instant;

#[derive(Debug, Clone)]
pub struct PhptCase {
    pub path: PathBuf,
    pub title: String,
    pub code: String,
    pub expect: Option<String>,
    pub expectf: Option<String>,
    pub expect_regex: Option<String>,
    pub skipif: Option<String>,
    pub ini: Option<String>,
    pub args: Option<String>,
    pub stdin: Option<String>,
    pub clean: Option<String>,
    pub unsupported_section: Option<String>,
}

const UNSUPPORTED_SECTIONS: &[&str] = &[
    "POST",
    "PUT",
    "GET",
    "COOKIE",
    "CGI",
    "UPLOAD",
    "FILE_EXTERNAL",
    "REDIRECTTEST",
    "PHPDBG",
    "POST_RAW",
    "GZIP_POST",
    "DEFLATE_POST",
];

pub fn parse_phpt(path: &Path) -> Option<PhptCase> {
    let raw = fs::read(path).ok()?;
    let text = String::from_utf8_lossy(&raw).replace("\r\n", "\n");
    let mut current_sec = String::new();
    let mut sections: HashMap<String, String> = HashMap::new();
    let mut has_lines: HashMap<String, bool> = HashMap::new();

    for line in text.lines() {
        if line.starts_with("--") && line.ends_with("--") && line.len() >= 6 {
            let tag = &line[2..line.len() - 2];
            if !tag.is_empty() && tag.chars().all(|c| c.is_ascii_uppercase() || c == '_') {
                current_sec = tag.to_string();
                sections.entry(current_sec.clone()).or_default();
                has_lines.entry(current_sec.clone()).or_insert(false);
                continue;
            }
        }
        if !current_sec.is_empty() {
            if let Some(buf) = sections.get_mut(&current_sec) {
                let had = has_lines.get(&current_sec).copied().unwrap_or(false);
                if had {
                    buf.push('\n');
                }
                buf.push_str(line);
                has_lines.insert(current_sec.clone(), true);
            }
        }
    }

    let code = sections
        .get("FILE")
        .or_else(|| sections.get("FILEEOF"))?
        .clone();
    let title = sections.get("TEST").cloned().unwrap_or_default();
    let mut unsupported_section = None;
    for sec in UNSUPPORTED_SECTIONS {
        if sections.contains_key(*sec) {
            unsupported_section = Some((*sec).to_string());
            break;
        }
    }

    Some(PhptCase {
        path: path.to_path_buf(),
        title,
        code,
        expect: sections.get("EXPECT").cloned(),
        expectf: sections.get("EXPECTF").cloned(),
        expect_regex: sections.get("EXPECTREGEX").cloned(),
        skipif: sections.get("SKIPIF").cloned(),
        ini: sections.get("INI").cloned(),
        args: sections.get("ARGS").cloned(),
        stdin: sections.get("STDIN").cloned(),
        clean: sections.get("CLEAN").cloned(),
        unsupported_section,
    })
}

fn collect_phpt_files(dir: &Path, out: &mut Vec<PathBuf>) {
    if let Ok(entries) = fs::read_dir(dir) {
        let mut children: Vec<PathBuf> = entries.flatten().map(|e| e.path()).collect();
        children.sort();
        for p in children {
            if p.is_dir() {
                collect_phpt_files(&p, out);
            } else if p.extension().and_then(|e| e.to_str()) == Some("phpt") {
                out.push(p);
            }
        }
    }
}

// ============================================================================
// EXPECT / EXPECTF Matcher (Zero external dependencies, memoized non-recursive)
// ============================================================================

#[derive(Debug, Clone)]
enum ExpectToken {
    Literal(Vec<char>),
    SingleChar,
    OneNonNl,
    DirSep,
    StarNonNl,
    StarAny,
    StarWs,
    SignedInt,
    UnsignedInt,
    Hex,
    Float,
}

fn compile_expectf(pattern: &str) -> Vec<ExpectToken> {
    let chars: Vec<char> = pattern.chars().collect();
    let mut tokens = Vec::new();
    let mut lit = Vec::new();
    let mut i = 0;

    let flush_lit = |lit: &mut Vec<char>, tokens: &mut Vec<ExpectToken>| {
        if !lit.is_empty() {
            tokens.push(ExpectToken::Literal(std::mem::take(lit)));
        }
    };

    while i < chars.len() {
        if chars[i] == '%' && i + 1 < chars.len() {
            let next = chars[i + 1];
            match next {
                '%' => {
                    lit.push('%');
                    i += 2;
                }
                'e' => {
                    flush_lit(&mut lit, &mut tokens);
                    tokens.push(ExpectToken::DirSep);
                    i += 2;
                }
                's' => {
                    flush_lit(&mut lit, &mut tokens);
                    tokens.push(ExpectToken::OneNonNl);
                    tokens.push(ExpectToken::StarNonNl);
                    i += 2;
                }
                'S' => {
                    flush_lit(&mut lit, &mut tokens);
                    tokens.push(ExpectToken::StarNonNl);
                    i += 2;
                }
                'a' => {
                    flush_lit(&mut lit, &mut tokens);
                    tokens.push(ExpectToken::SingleChar);
                    tokens.push(ExpectToken::StarAny);
                    i += 2;
                }
                'A' => {
                    flush_lit(&mut lit, &mut tokens);
                    tokens.push(ExpectToken::StarAny);
                    i += 2;
                }
                'w' => {
                    flush_lit(&mut lit, &mut tokens);
                    tokens.push(ExpectToken::StarWs);
                    i += 2;
                }
                'i' => {
                    flush_lit(&mut lit, &mut tokens);
                    tokens.push(ExpectToken::SignedInt);
                    i += 2;
                }
                'd' => {
                    flush_lit(&mut lit, &mut tokens);
                    tokens.push(ExpectToken::UnsignedInt);
                    i += 2;
                }
                'x' => {
                    flush_lit(&mut lit, &mut tokens);
                    tokens.push(ExpectToken::Hex);
                    i += 2;
                }
                'f' => {
                    flush_lit(&mut lit, &mut tokens);
                    tokens.push(ExpectToken::Float);
                    i += 2;
                }
                'c' => {
                    flush_lit(&mut lit, &mut tokens);
                    tokens.push(ExpectToken::SingleChar);
                    i += 2;
                }
                _ => {
                    lit.push('%');
                    i += 1;
                }
            }
        } else {
            lit.push(chars[i]);
            i += 1;
        }
    }
    flush_lit(&mut lit, &mut tokens);
    tokens
}

fn valid_float_ends(chars: &[char], start: usize) -> Vec<usize> {
    let mut ends = Vec::new();
    let n = chars.len();
    if start >= n {
        return ends;
    }
    let mut pos = start;
    if chars[pos] == '+' || chars[pos] == '-' {
        pos += 1;
    }
    let num_start = pos;
    let mut int_digits = 0usize;
    while pos < n && chars[pos].is_ascii_digit() {
        int_digits += 1;
        pos += 1;
        if int_digits > 0 {
            ends.push(pos);
        }
    }
    if pos < n && chars[pos] == '.' {
        pos += 1;
        let mut frac_digits = 0usize;
        if int_digits > 0 {
            ends.push(pos);
        }
        while pos < n && chars[pos].is_ascii_digit() {
            frac_digits += 1;
            pos += 1;
            if int_digits > 0 || frac_digits > 0 {
                ends.push(pos);
            }
        }
        if int_digits == 0 && frac_digits == 0 {
            return ends;
        }
    } else if int_digits == 0 || pos == num_start {
        return ends;
    }

    if pos < n && (chars[pos] == 'e' || chars[pos] == 'E') {
        let mut epos = pos + 1;
        if epos < n && (chars[epos] == '+' || chars[epos] == '-') {
            epos += 1;
        }
        let mut edigits = 0usize;
        while epos < n && chars[epos].is_ascii_digit() {
            edigits += 1;
            epos += 1;
            if edigits > 0 {
                ends.push(epos);
            }
        }
    }
    ends
}

fn normalize_diag_newlines(s: &str) -> String {
    let prefixes = [
        "\nWarning: ",
        "\nNotice: ",
        "\nDeprecated: ",
        "\nFatal error: ",
        "\nParse error: ",
    ];
    let mut out = s.replace("\r\n", "\n");
    for prefix in prefixes {
        let doubled = format!("\n{}", prefix);
        while out.contains(&doubled) {
            out = out.replace(&doubled, prefix);
        }
    }
    out
}

pub fn match_expectf(pattern: &str, actual: &str) -> bool {
    let norm_pat_owned = normalize_diag_newlines(pattern);
    let norm_pat = norm_pat_owned.trim();
    let norm_act_owned = normalize_diag_newlines(actual);
    let mut norm_act = norm_act_owned.trim();
    if !norm_pat.contains("Stack trace:") {
        if let Some(stripped) = norm_act.strip_suffix("\nStack trace:\n#0 {main}") {
            norm_act = stripped.trim_end();
        }
    }

    let tokens = compile_expectf(norm_pat);
    let chars: Vec<char> = norm_act.chars().collect();
    let tlen = tokens.len();
    let clen = chars.len();
    let stride = clen + 1;

    // Guard against extreme memory allocation on multi-megabyte outputs
    if (tlen + 1).saturating_mul(stride) > 20_000_000 {
        return norm_pat == norm_act;
    }

    let mut visited = vec![false; (tlen + 1) * stride];
    let mut stack: Vec<(usize, usize)> = Vec::with_capacity(64);
    stack.push((0, 0));

    while let Some((ti, ci)) = stack.pop() {
        let idx = ti * stride + ci;
        if visited[idx] {
            continue;
        }
        visited[idx] = true;

        if ti == tlen {
            if ci == clen {
                return true;
            }
            continue;
        }

        match &tokens[ti] {
            ExpectToken::Literal(lit) => {
                if ci + lit.len() <= clen && &chars[ci..ci + lit.len()] == lit.as_slice() {
                    stack.push((ti + 1, ci + lit.len()));
                }
            }
            ExpectToken::SingleChar => {
                if ci < clen {
                    stack.push((ti + 1, ci + 1));
                }
            }
            ExpectToken::OneNonNl => {
                if ci < clen && chars[ci] != '\n' && chars[ci] != '\r' {
                    stack.push((ti + 1, ci + 1));
                }
            }
            ExpectToken::DirSep => {
                if ci < clen && (chars[ci] == '/' || chars[ci] == '\\') {
                    stack.push((ti + 1, ci + 1));
                }
            }
            ExpectToken::StarNonNl => {
                stack.push((ti + 1, ci));
                if ci < clen && chars[ci] != '\n' && chars[ci] != '\r' {
                    stack.push((ti, ci + 1));
                }
            }
            ExpectToken::StarAny => {
                stack.push((ti + 1, ci));
                if ci < clen {
                    stack.push((ti, ci + 1));
                }
            }
            ExpectToken::StarWs => {
                stack.push((ti + 1, ci));
                if ci < clen && chars[ci].is_ascii_whitespace() {
                    stack.push((ti, ci + 1));
                }
            }
            ExpectToken::SignedInt => {
                let mut pos = ci;
                if pos < clen && (chars[pos] == '+' || chars[pos] == '-') {
                    pos += 1;
                }
                while pos < clen && chars[pos].is_ascii_digit() {
                    pos += 1;
                    stack.push((ti + 1, pos));
                }
            }
            ExpectToken::UnsignedInt => {
                let mut pos = ci;
                while pos < clen && chars[pos].is_ascii_digit() {
                    pos += 1;
                    stack.push((ti + 1, pos));
                }
            }
            ExpectToken::Hex => {
                let mut pos = ci;
                while pos < clen && chars[pos].is_ascii_hexdigit() {
                    pos += 1;
                    stack.push((ti + 1, pos));
                }
            }
            ExpectToken::Float => {
                for end in valid_float_ends(&chars, ci) {
                    stack.push((ti + 1, end));
                }
            }
        }
    }

    false
}

#[derive(Debug, Clone)]
enum RxAtomClass {
    AnyNonNl,
    AnyChar,
    Literal(char),
    Digit(bool),
    Word(bool),
    Space(bool),
    Set { negated: bool, ranges: Vec<(char, char)>, specials: Vec<RxAtomClass> },
}

impl RxAtomClass {
    fn matches(&self, ch: char) -> bool {
        match self {
            RxAtomClass::AnyNonNl => ch != '\n' && ch != '\r',
            RxAtomClass::AnyChar => true,
            RxAtomClass::Literal(c) => ch == *c,
            RxAtomClass::Digit(neg) => (ch.is_ascii_digit()) ^ *neg,
            RxAtomClass::Word(neg) => (ch.is_ascii_alphanumeric() || ch == '_') ^ *neg,
            RxAtomClass::Space(neg) => ch.is_ascii_whitespace() ^ *neg,
            RxAtomClass::Set { negated, ranges, specials } => {
                let mut hit = false;
                for &(lo, hi) in ranges {
                    if ch >= lo && ch <= hi {
                        hit = true;
                        break;
                    }
                }
                if !hit {
                    for sp in specials {
                        if sp.matches(ch) {
                            hit = true;
                            break;
                        }
                    }
                }
                hit ^ *negated
            }
        }
    }
}

#[derive(Debug, Clone)]
enum RxInst {
    Class(RxAtomClass),
    StartAnchor,
    EndAnchor,
    Jmp(usize),
    Split(usize, usize),
    Match,
}

fn compile_regex_seq(p: &[char], pos: &mut usize, prog: &mut Vec<RxInst>, stop_on_rparen: bool) -> bool {
    let mut branches: Vec<Vec<RxInst>> = vec![Vec::new()];

    let parse_escape = |p: &[char], idx: &mut usize| -> RxAtomClass {
        if *idx >= p.len() {
            return RxAtomClass::Literal('\\');
        }
        let esc = p[*idx];
        *idx += 1;
        match esc {
            'd' => RxAtomClass::Digit(false),
            'D' => RxAtomClass::Digit(true),
            'w' => RxAtomClass::Word(false),
            'W' => RxAtomClass::Word(true),
            's' => RxAtomClass::Space(false),
            'S' => RxAtomClass::Space(true),
            'n' => RxAtomClass::Literal('\n'),
            'r' => RxAtomClass::Literal('\r'),
            't' => RxAtomClass::Literal('\t'),
            other => RxAtomClass::Literal(other),
        }
    };

    while *pos < p.len() {
        let ch = p[*pos];
        if stop_on_rparen && ch == ')' {
            *pos += 1;
            break;
        }
        if ch == '|' {
            *pos += 1;
            branches.push(Vec::new());
            continue;
        }

        let mut item_insts: Vec<RxInst> = Vec::new();
        if ch == '^' {
            *pos += 1;
            item_insts.push(RxInst::StartAnchor);
        } else if ch == '$' {
            *pos += 1;
            item_insts.push(RxInst::EndAnchor);
        } else if ch == '(' {
            *pos += 1;
            if *pos + 1 < p.len() && p[*pos] == '?' && (p[*pos + 1] == ':' || p[*pos + 1] == '=' || p[*pos + 1] == '!') {
                if p[*pos + 1] == ':' {
                    *pos += 2;
                }
            }
            if !compile_regex_seq(p, pos, &mut item_insts, true) {
                return false;
            }
        } else if ch == '[' {
            *pos += 1;
            let mut negated = false;
            if *pos < p.len() && p[*pos] == '^' {
                negated = true;
                *pos += 1;
            }
            let mut ranges: Vec<(char, char)> = Vec::new();
            let mut specials: Vec<RxAtomClass> = Vec::new();
            let mut first = true;
            while *pos < p.len() && (first || p[*pos] != ']') {
                first = false;
                let item_start = if p[*pos] == '\\' {
                    *pos += 1;
                    match parse_escape(p, pos) {
                        RxAtomClass::Literal(c) => Some(c),
                        sp => {
                            specials.push(sp);
                            None
                        }
                    }
                } else {
                    let c = p[*pos];
                    *pos += 1;
                    Some(c)
                };
                if let Some(lo) = item_start {
                    if *pos + 1 < p.len() && p[*pos] == '-' && p[*pos + 1] != ']' {
                        *pos += 1;
                        let hi = if p[*pos] == '\\' {
                            *pos += 1;
                            match parse_escape(p, pos) {
                                RxAtomClass::Literal(c) => c,
                                _ => p[*pos - 1],
                            }
                        } else {
                            let c = p[*pos];
                            *pos += 1;
                            c
                        };
                        ranges.push((lo, hi));
                    } else {
                        ranges.push((lo, lo));
                    }
                }
            }
            if *pos < p.len() && p[*pos] == ']' {
                *pos += 1;
            }
            item_insts.push(RxInst::Class(RxAtomClass::Set { negated, ranges, specials }));
        } else if ch == '.' {
            *pos += 1;
            item_insts.push(RxInst::Class(RxAtomClass::AnyNonNl));
        } else if ch == '\\' {
            *pos += 1;
            item_insts.push(RxInst::Class(parse_escape(p, pos)));
        } else {
            *pos += 1;
            item_insts.push(RxInst::Class(RxAtomClass::Literal(ch)));
        }

        // Quantifier parsing: ?, *, +, {m,n}
        let mut q_min = 1usize;
        let mut q_max: Option<usize> = Some(1usize);
        if *pos < p.len() {
            match p[*pos] {
                '?' => {
                    q_min = 0;
                    q_max = Some(1);
                    *pos += 1;
                }
                '*' => {
                    q_min = 0;
                    q_max = None;
                    *pos += 1;
                }
                '+' => {
                    q_min = 1;
                    q_max = None;
                    *pos += 1;
                }
                '{' => {
                    let save = *pos;
                    *pos += 1;
                    let mut m_str = String::new();
                    while *pos < p.len() && p[*pos].is_ascii_digit() {
                        m_str.push(p[*pos]);
                        *pos += 1;
                    }
                    if let Ok(m_val) = m_str.parse::<usize>() {
                        if *pos < p.len() && p[*pos] == '}' {
                            *pos += 1;
                            q_min = m_val;
                            q_max = Some(m_val);
                        } else if *pos < p.len() && p[*pos] == ',' {
                            *pos += 1;
                            let mut n_str = String::new();
                            while *pos < p.len() && p[*pos].is_ascii_digit() {
                                n_str.push(p[*pos]);
                                *pos += 1;
                            }
                            if *pos < p.len() && p[*pos] == '}' {
                                *pos += 1;
                                q_min = m_val;
                                if n_str.is_empty() {
                                    q_max = None;
                                } else if let Ok(n_val) = n_str.parse::<usize>() {
                                    q_max = Some(n_val);
                                } else {
                                    *pos = save;
                                }
                            } else {
                                *pos = save;
                            }
                        } else {
                            *pos = save;
                        }
                    } else {
                        *pos = save;
                    }
                }
                _ => {}
            }
            if *pos < p.len() && (p[*pos] == '?' || p[*pos] == '+') && (q_max != Some(1) || q_min != 1) {
                *pos += 1;
            }
        }

        let cur = branches.last_mut().unwrap();
        let append_shifted = |dst: &mut Vec<RxInst>, src: &[RxInst]| {
            let offset = dst.len();
            for inst in src {
                let shifted = match inst {
                    RxInst::Jmp(t) => RxInst::Jmp(t + offset),
                    RxInst::Split(a, b) => RxInst::Split(a + offset, b + offset),
                    other => other.clone(),
                };
                dst.push(shifted);
            }
        };

        for _ in 0..q_min.min(64) {
            append_shifted(cur, &item_insts);
        }
        match q_max {
            Some(max_val) if max_val > q_min => {
                let rem = (max_val - q_min).min(64);
                for _ in 0..rem {
                    let split_pos = cur.len();
                    let body_start = split_pos + 1;
                    let next_pos = body_start + item_insts.len();
                    cur.push(RxInst::Split(body_start, next_pos));
                    append_shifted(cur, &item_insts);
                }
            }
            None => {
                let split_pos = cur.len();
                let body_start = split_pos + 1;
                let after_loop = body_start + item_insts.len() + 1;
                cur.push(RxInst::Split(body_start, after_loop));
                append_shifted(cur, &item_insts);
                cur.push(RxInst::Jmp(split_pos));
            }
            _ => {}
        }
    }

    if branches.len() == 1 {
        let base = prog.len();
        for inst in branches.into_iter().next().unwrap() {
            let shifted = match inst {
                RxInst::Jmp(t) => RxInst::Jmp(t + base),
                RxInst::Split(a, b) => RxInst::Split(a + base, b + base),
                other => other,
            };
            prog.push(shifted);
        }
        return true;
    }

    // Emit N-way alternation cleanly
    let base = prog.len();
    let n = branches.len();
    // Reserve N-1 splits at front if we chain splits: Split(branch_i, next_split_or_last)
    let mut branch_starts = Vec::with_capacity(n);
    let mut split_positions = Vec::with_capacity(n - 1);
    for i in 0..(n - 1) {
        split_positions.push(prog.len());
        prog.push(RxInst::Split(0, 0)); // placeholder
        let _ = i;
    }
    let mut jmp_to_end_positions = Vec::with_capacity(n - 1);
    for (i, b) in branches.into_iter().enumerate() {
        let b_start = prog.len();
        branch_starts.push(b_start);
        for inst in b {
            let shifted = match inst {
                RxInst::Jmp(t) => RxInst::Jmp(t + b_start),
                RxInst::Split(a, tgt) => RxInst::Split(a + b_start, tgt + b_start),
                other => other,
            };
            prog.push(shifted);
        }
        if i + 1 < n {
            jmp_to_end_positions.push(prog.len());
            prog.push(RxInst::Jmp(0)); // placeholder to end
        }
    }
    let end_pos = prog.len();
    for j in jmp_to_end_positions {
        prog[j] = RxInst::Jmp(end_pos);
    }
    for i in 0..(n - 1) {
        let alt = if i + 1 < n - 1 { split_positions[i + 1] } else { branch_starts[i + 1] };
        prog[split_positions[i]] = RxInst::Split(branch_starts[i], alt);
    }
    let _ = base;
    true
}

pub fn match_expect_regex(pattern: &str, actual: &str) -> bool {
    let norm_pat_owned = normalize_diag_newlines(pattern);
    let norm_pat = norm_pat_owned.trim();
    let norm_act_owned = normalize_diag_newlines(actual);
    let mut norm_act = norm_act_owned.trim();
    if !norm_pat.contains("Stack trace:") {
        if let Some(stripped) = norm_act.strip_suffix("\nStack trace:\n#0 {main}") {
            norm_act = stripped.trim_end();
        }
    }

    let pchars: Vec<char> = norm_pat.chars().collect();
    let mut pos = 0usize;
    let mut prog: Vec<RxInst> = Vec::new();
    if !compile_regex_seq(&pchars, &mut pos, &mut prog, false) {
        return false;
    }
    prog.push(RxInst::Match);

    let chars: Vec<char> = norm_act.chars().collect();
    let plen = prog.len();
    let clen = chars.len();
    let stride = clen + 1;
    if plen.saturating_mul(stride) > 20_000_000 {
        return norm_pat == norm_act;
    }

    let mut visited = vec![false; plen * stride];
    let mut stack: Vec<(usize, usize)> = Vec::with_capacity(64);
    stack.push((0, 0));

    while let Some((pc, ci)) = stack.pop() {
        let idx = pc * stride + ci;
        if visited[idx] {
            continue;
        }
        visited[idx] = true;

        match &prog[pc] {
            RxInst::Match => {
                if ci == clen {
                    return true;
                }
            }
            RxInst::Jmp(target) => {
                stack.push((*target, ci));
            }
            RxInst::Split(a, b) => {
                stack.push((*b, ci));
                stack.push((*a, ci));
            }
            RxInst::StartAnchor => {
                if ci == 0 || chars[ci - 1] == '\n' {
                    stack.push((pc + 1, ci));
                }
            }
            RxInst::EndAnchor => {
                if ci == clen || chars[ci] == '\n' {
                    stack.push((pc + 1, ci));
                }
            }
            RxInst::Class(cls) => {
                if ci < clen && cls.matches(chars[ci]) {
                    stack.push((pc + 1, ci + 1));
                }
            }
        }
    }
    false
}

pub fn match_phpt_output(actual: &str, case: &PhptCase) -> bool {
    let actual_norm = actual.replace("\r\n", "\n");
    let actual_trim = actual_norm.trim();
    if let Some(ref exp) = case.expect {
        let exp_norm = exp.replace("\r\n", "\n");
        return actual_trim == exp_norm.trim();
    }
    if let Some(ref pat) = case.expectf {
        return match_expectf(pat, actual);
    }
    if let Some(ref rx) = case.expect_regex {
        return match_expect_regex(rx, actual);
    }
    false
}

// ============================================================================
// Pure-Rust Base64 & Minimal JSON Helpers
// ============================================================================

const B64_ALPHA: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

fn base64_encode(data: &[u8]) -> String {
    let mut out = String::with_capacity(((data.len() + 2) / 3) * 4);
    let mut i = 0;
    while i < data.len() {
        let b0 = data[i] as u32;
        let b1 = if i + 1 < data.len() {
            data[i + 1] as u32
        } else {
            0
        };
        let b2 = if i + 2 < data.len() {
            data[i + 2] as u32
        } else {
            0
        };
        let triple = (b0 << 16) | (b1 << 8) | b2;
        out.push(B64_ALPHA[((triple >> 18) & 0x3F) as usize] as char);
        out.push(B64_ALPHA[((triple >> 12) & 0x3F) as usize] as char);
        if i + 1 < data.len() {
            out.push(B64_ALPHA[((triple >> 6) & 0x3F) as usize] as char);
        } else {
            out.push('=');
        }
        if i + 2 < data.len() {
            out.push(B64_ALPHA[(triple & 0x3F) as usize] as char);
        } else {
            out.push('=');
        }
        i += 3;
    }
    out
}

fn base64_decode(s: &str) -> Vec<u8> {
    let mut table = [255u8; 256];
    for (idx, &ch) in B64_ALPHA.iter().enumerate() {
        table[ch as usize] = idx as u8;
    }
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity((bytes.len() / 4) * 3);
    let mut buf: u32 = 0;
    let mut bits: u8 = 0;
    for &b in bytes {
        if b == b'=' || b.is_ascii_whitespace() {
            continue;
        }
        let val = table[b as usize];
        if val == 255 {
            continue;
        }
        buf = (buf << 6) | (val as u32);
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push(((buf >> bits) & 0xFF) as u8);
        }
    }
    out
}

fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for ch in s.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\x08' => out.push_str("\\b"),
            '\x0c' => out.push_str("\\f"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                out.push_str(&format!("\\u{:04x}", c as u32));
            }
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn extract_json_str_field(json_line: &str, field: &str) -> Option<String> {
    let needle = format!("\"{}\":", field);
    let start = json_line.find(&needle)? + needle.len();
    let rest = json_line[start..].trim_start();
    if !rest.starts_with('"') {
        return None;
    }
    let chars: Vec<char> = rest.chars().collect();
    let mut out = String::new();
    let mut i = 1;
    while i < chars.len() {
        match chars[i] {
            '"' => return Some(out),
            '\\' if i + 1 < chars.len() => {
                i += 1;
                match chars[i] {
                    '"' => out.push('"'),
                    '\\' => out.push('\\'),
                    '/' => out.push('/'),
                    'b' => out.push('\x08'),
                    'f' => out.push('\x0c'),
                    'n' => out.push('\n'),
                    'r' => out.push('\r'),
                    't' => out.push('\t'),
                    'u' if i + 4 < chars.len() => {
                        let hex: String = chars[i + 1..i + 5].iter().collect();
                        if let Ok(code) = u32::from_str_radix(&hex, 16) {
                            if let Some(c) = char::from_u32(code) {
                                out.push(c);
                            }
                        }
                        i += 4;
                    }
                    other => out.push(other),
                }
            }
            c => out.push(c),
        }
        i += 1;
    }
    None
}

fn extract_json_usize_field(json_line: &str, field: &str) -> Option<usize> {
    let needle = format!("\"{}\":", field);
    let start = json_line.find(&needle)? + needle.len();
    let rest = json_line[start..].trim_start();
    let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
    digits.parse::<usize>().ok()
}

// ============================================================================
// PowerShell Batch Worker & Oracle Helper
// ============================================================================

const WORKER_PS1: &str = r#"$ErrorActionPreference = 'Stop'
$manifestPath = $args[0]
$adapterPath = $args[1]

$adapter = & $adapterPath
if ($null -eq $adapter -or $adapter.Run -isnot [scriptblock]) {
    throw "Failed to load PHP adapter from $adapterPath"
}

function Parse-PhptErrorReporting([string]$expr) {
    $map = @{
        'E_ERROR'=1; 'E_WARNING'=2; 'E_PARSE'=4; 'E_NOTICE'=8;
        'E_CORE_ERROR'=16; 'E_CORE_WARNING'=32; 'E_COMPILE_ERROR'=64; 'E_COMPILE_WARNING'=128;
        'E_USER_ERROR'=256; 'E_USER_WARNING'=512; 'E_USER_NOTICE'=1024; 'E_STRICT'=2048;
        'E_RECOVERABLE_ERROR'=4096; 'E_DEPRECATED'=8192; 'E_USER_DEPRECATED'=16384;
        'E_ALL'=30719
    }
    $val = [long]0
    if ([long]::TryParse($expr.Trim(), [ref]$val)) { return [string]$val }
    try {
        $tokens = [regex]::Matches($expr, '[~&|^()]|[A-Za-z_0-9]+') | ForEach-Object { $_.Value }
        $acc = [long]0
        $op = '|'
        $neg = $false
        foreach ($tok in $tokens) {
            if ($tok -eq '~') { $neg = -not $neg; continue }
            if ($tok -in @('&','|','^')) { $op = $tok; continue }
            if ($tok -in @('(',')')) { continue }
            $num = [long]0
            if ($map.ContainsKey($tok)) { $num = [long]$map[$tok] }
            elseif (-not [long]::TryParse($tok, [ref]$num)) { return '30719' }
            if ($neg) { $num = -bnot $num; $neg = $false }
            if ($op -eq '|') { $acc = $acc -bor $num }
            elseif ($op -eq '&') { $acc = $acc -band $num }
            elseif ($op -eq '^') { $acc = $acc -bxor $num }
        }
        return [string]$acc
    } catch {
        return '30719'
    }
}

function Parse-PhptIni([string]$iniText) {
    $tbl = @{}
    if ([string]::IsNullOrWhiteSpace($iniText)) { return $tbl }
    foreach ($rawLine in ($iniText -split "`r?`n")) {
        $line = $rawLine.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith(';') -or $line.StartsWith('#')) { continue }
        $eq = $line.IndexOf('=')
        if ($eq -le 0) { continue }
        $k = $line.Substring(0, $eq).Trim()
        $v = $line.Substring($eq + 1).Trim()
        if (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'"))) {
            if ($v.Length -ge 2) { $v = $v.Substring(1, $v.Length - 2) }
        }
        if ($k -ceq 'error_reporting') { $v = Parse-PhptErrorReporting $v }
        elseif ($v -ieq 'On' -or $v -ieq 'True') { $v = '1' }
        elseif ($v -ieq 'Off' -or $v -ieq 'False') { $v = '0' }
        $tbl[$k] = $v
    }
    return $tbl
}

function Parse-PhptArgs([string]$argsText) {
    $list = [System.Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace($argsText)) { return @() }
    foreach ($m in [regex]::Matches($argsText, '"([^"]*)"|''([^'']*)''|(\S+)')) {
        if ($m.Groups[1].Success) { [void]$list.Add($m.Groups[1].Value) }
        elseif ($m.Groups[2].Success) { [void]$list.Add($m.Groups[2].Value) }
        else { [void]$list.Add($m.Groups[3].Value) }
    }
    return @($list.ToArray())
}

function Invoke-PhptSnippet([string]$code, [string]$sourcePath, $iniMap, [string[]]$scriptArgs, [string]$stdinText = '') {
    $mem = [System.IO.MemoryStream]::new()
    $swOut = [System.IO.StringWriter]::new([System.Globalization.CultureInfo]::InvariantCulture)
    $swErr = [System.IO.StringWriter]::new([System.Globalization.CultureInfo]::InvariantCulture)
    $oldOut = [Console]::Out
    $oldErr = [Console]::Error
    $oldIn = [Console]::In
    $oldLoc = Get-Location
    $ctx = @{
        SourceMode = 'file'
        SourcePath = $sourcePath
        OutputByteStream = $mem
        ErrorByteStream = $mem
        InitialIni = $iniMap
        ScriptArguments = $scriptArgs
        MaxSteps = 25000
    }
    if ($stdinText.Length -gt 0) {
        $ctx['StdinText'] = $stdinText
    }
    $errMsg = $null
    try {
        $dir = [System.IO.Path]::GetDirectoryName($sourcePath)
        if (-not [string]::IsNullOrEmpty($dir) -and [System.IO.Directory]::Exists($dir)) {
            Set-Location -LiteralPath $dir
        }
        [Console]::SetOut($swOut)
        [Console]::SetError($swErr)
        if ($stdinText.Length -gt 0) {
            [Console]::SetIn([System.IO.StringReader]::new($stdinText))
        }
        $global:AllPolyglotContext = $null
        [void](& $adapter.Run -Code $code -PhpDiagnostics -CliContext $ctx)
    } catch {
        $errMsg = $_.Exception.Message
    } finally {
        [Console]::SetIn($oldIn)
        [Console]::SetOut($oldOut)
        [Console]::SetError($oldErr)
        Set-Location -LiteralPath $oldLoc
    }
    $rawBytes = $mem.ToArray()
    $mem.Dispose()
    $consoleOut = $swOut.ToString()
    $consoleErr = $swErr.ToString()
    $swOut.Dispose()
    $swErr.Dispose()
    $combined = [System.Text.Encoding]::UTF8.GetString($rawBytes)
    if ($consoleOut.Length -gt 0) { $combined += $consoleOut }
    if ($consoleErr.Length -gt 0) { $combined += $consoleErr }
    return [pscustomobject]@{
        Output = $combined
        Error = $errMsg
    }
}

$rawJson = [System.IO.File]::ReadAllText($manifestPath, [System.Text.Encoding]::UTF8)
$cases = ConvertFrom-Json -InputObject $rawJson
if (($cases -is [array]) -and $cases.Count -eq 1 -and ($cases[0] -is [array])) {
    $cases = $cases[0]
}

foreach ($c in @($cases)) {
    $idx = [int]$c.index
    $sourcePath = [string]$c.source_path
    $unsupportedSec = [string]$c.unsupported_section
    if ($unsupportedSec.Length -gt 0) {
        $obj = @{ index=$idx; status='skipif'; output_b64=''; error_b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("Unsupported PHPT section: --$unsupportedSec--")) }
        [Console]::Out.WriteLine('__PHPT_RES__:' + ($obj | ConvertTo-Json -Compress))
        [Console]::Out.Flush()
        continue
    }
    $iniText = if ($c.ini_b64) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$c.ini_b64)) } else { '' }
    $iniMap = Parse-PhptIni $iniText
    $argsText = if ($c.args_b64) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$c.args_b64)) } else { '' }
    $extraArgs = Parse-PhptArgs $argsText
    $scriptArgs = [string[]]@(@($sourcePath) + @($extraArgs))

    $skipifCode = if ($c.skipif_b64) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$c.skipif_b64)) } else { '' }
    if ($skipifCode.Length -gt 0) {
        $skipRes = Invoke-PhptSnippet $skipifCode $sourcePath $iniMap $scriptArgs
        $trimmedSkip = $skipRes.Output.Trim()
        if ($trimmedSkip -imatch '^skip') {
            $obj = @{ index=$idx; status='skipif'; output_b64=''; error_b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($trimmedSkip)) }
            [Console]::Out.WriteLine('__PHPT_RES__:' + ($obj | ConvertTo-Json -Compress))
            [Console]::Out.Flush()
            continue
        }
        if ($null -ne $skipRes.Error) {
            $obj = @{ index=$idx; status='skipif'; output_b64=''; error_b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("skipif error: $($skipRes.Error)")) }
            [Console]::Out.WriteLine('__PHPT_RES__:' + ($obj | ConvertTo-Json -Compress))
            [Console]::Out.Flush()
            continue
        }
    }

    $stdinText = if ($c.stdin_b64) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$c.stdin_b64)) } else { '' }
    $fileCode = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$c.code_b64))
    $runRes = Invoke-PhptSnippet $fileCode $sourcePath $iniMap $scriptArgs $stdinText
    $cleanCode = if ($c.clean_b64) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$c.clean_b64)) } else { '' }
    if ($cleanCode.Length -gt 0) {
        [void](Invoke-PhptSnippet $cleanCode $sourcePath $iniMap $scriptArgs '')
    }
    $outB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($runRes.Output))
    if ($null -ne $runRes.Error) {
        $errB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($runRes.Error))
        $obj = @{ index=$idx; status='unsupported'; output_b64=$outB64; error_b64=$errB64 }
    } else {
        $obj = @{ index=$idx; status='executed'; output_b64=$outB64; error_b64='' }
    }
    [Console]::Out.WriteLine('__PHPT_RES__:' + ($obj | ConvertTo-Json -Compress))
    [Console]::Out.Flush()
}
"#;

#[derive(Debug, Clone)]
struct WorkerCaseResult {
    index: usize,
    status: String,
    output: String,
    error: String,
}

fn default_adapter_path() -> PathBuf {
    if let Ok(exe) = env::current_exe() {
        if let Some(dir) = exe.parent() {
            let candidate = dir.join("languages").join("php.ps1");
            if candidate.exists() {
                return candidate;
            }
        }
    }
    let d_candidate = PathBuf::from(r"D:\ALL\languages\php.ps1");
    if d_candidate.exists() {
        return d_candidate;
    }
    PathBuf::from(r"C:\Users\rinpa\ALL\languages\php.ps1")
}

fn run_oracle_php(oracle: &Path, case: &PhptCase, tmp_dir: &Path, id: usize) -> Option<String> {
    let script_path = tmp_dir.join(format!("oracle_{}.php", id));
    if fs::write(&script_path, case.code.as_bytes()).is_err() {
        return None;
    }
    let mut cmd = Command::new(oracle);
    cmd.arg("-n");
    if let Some(ref ini_text) = case.ini {
        for raw in ini_text.lines() {
            let line = raw.trim();
            if line.is_empty() || line.starts_with(';') || line.starts_with('#') {
                continue;
            }
            if line.contains('=') {
                cmd.arg("-d").arg(line);
            }
        }
    }
    cmd.arg("-f").arg(&script_path);
    if let Some(ref args_text) = case.args {
        if !args_text.trim().is_empty() {
            cmd.arg("--");
            for tok in args_text.split_whitespace() {
                cmd.arg(tok);
            }
        }
    }
    if let Some(parent) = case.path.parent() {
        cmd.current_dir(parent);
    }
    let out = cmd.output().ok();
    let _ = fs::remove_file(&script_path);
    out.map(|o| {
        let mut combined = String::from_utf8_lossy(&o.stdout).into_owned();
        let err = String::from_utf8_lossy(&o.stderr);
        if !err.is_empty() {
            combined.push_str(&err);
        }
        combined
    })
}

fn normalize_unsupported_reason(err: &str) -> String {
    let first_line = err.lines().next().unwrap_or(err).trim();
    if let Some(pos) = first_line.find(" at offset ") {
        return format!("{} at offset <N>", &first_line[..pos]);
    }
    if first_line.len() > 140 {
        return format!("{}...", &first_line[..140]);
    }
    first_line.to_string()
}

fn run_worker_batch(
    worker_id: usize,
    batch: &[(usize, PhptCase)],
    adapter_path: &Path,
) -> Vec<WorkerCaseResult> {
    let tmp_dir = env::temp_dir().join(format!("all_phpt_run_{}_{}", std::process::id(), worker_id));
    let _ = fs::create_dir_all(&tmp_dir);
    let manifest_path = tmp_dir.join("manifest.json");
    let worker_ps1_path = tmp_dir.join("worker.ps1");

    let mut manifest = String::from("[\n");
    for (i, (orig_idx, case)) in batch.iter().enumerate() {
        if i > 0 {
            manifest.push_str(",\n");
        }
        let stem = case
            .path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("test");
        let source_path = case
            .path
            .parent()
            .unwrap_or_else(|| Path::new("."))
            .join(format!("{}.php", stem));
        let skipif_b64 = case
            .skipif
            .as_deref()
            .map(|s| base64_encode(s.as_bytes()))
            .unwrap_or_default();
        let ini_b64 = case
            .ini
            .as_deref()
            .map(|s| base64_encode(s.as_bytes()))
            .unwrap_or_default();
        let args_b64 = case
            .args
            .as_deref()
            .map(|s| base64_encode(s.as_bytes()))
            .unwrap_or_default();
        let stdin_b64 = case
            .stdin
            .as_deref()
            .map(|s| base64_encode(s.as_bytes()))
            .unwrap_or_default();
        let clean_b64 = case
            .clean
            .as_deref()
            .map(|s| base64_encode(s.as_bytes()))
            .unwrap_or_default();
        let code_b64 = base64_encode(case.code.as_bytes());
        let unsup_sec = case.unsupported_section.as_deref().unwrap_or("");

        manifest.push_str(&format!(
            "  {{\"index\":{},\"source_path\":{},\"unsupported_section\":{},\"skipif_b64\":{},\"ini_b64\":{},\"args_b64\":{},\"stdin_b64\":{},\"clean_b64\":{},\"code_b64\":{}}}",
            orig_idx,
            json_escape(&source_path.to_string_lossy()),
            json_escape(unsup_sec),
            json_escape(&skipif_b64),
            json_escape(&ini_b64),
            json_escape(&args_b64),
            json_escape(&stdin_b64),
            json_escape(&clean_b64),
            json_escape(&code_b64),
        ));
    }
    manifest.push_str("\n]\n");

    let _ = fs::write(&manifest_path, manifest.as_bytes());
    let _ = fs::write(&worker_ps1_path, WORKER_PS1.as_bytes());

    let mut results = Vec::new();
    let child = Command::new("powershell.exe")
        .arg("-NoProfile")
        .arg("-ExecutionPolicy")
        .arg("Bypass")
        .arg("-File")
        .arg(&worker_ps1_path)
        .arg(&manifest_path)
        .arg(adapter_path)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn();

    match child {
        Ok(mut proc_handle) => {
            if let Some(stdout) = proc_handle.stdout.take() {
                let reader = BufReader::new(stdout);
                for line_res in reader.lines() {
                    if let Ok(line) = line_res {
                        if let Some(json_part) = line.strip_prefix("__PHPT_RES__:") {
                            if let (Some(idx), Some(status)) = (
                                extract_json_usize_field(json_part, "index"),
                                extract_json_str_field(json_part, "status"),
                            ) {
                                let out_b64 = extract_json_str_field(json_part, "output_b64")
                                    .unwrap_or_default();
                                let err_b64 = extract_json_str_field(json_part, "error_b64")
                                    .unwrap_or_default();
                                let output =
                                    String::from_utf8_lossy(&base64_decode(&out_b64)).into_owned();
                                let error =
                                    String::from_utf8_lossy(&base64_decode(&err_b64)).into_owned();
                                results.push(WorkerCaseResult {
                                    index: idx,
                                    status,
                                    output,
                                    error,
                                });
                            }
                        }
                    }
                }
            }
            let _ = proc_handle.wait();
        }
        Err(e) => {
            for (orig_idx, _) in batch {
                results.push(WorkerCaseResult {
                    index: *orig_idx,
                    status: "unsupported".to_string(),
                    output: String::new(),
                    error: format!("Worker launch failed: {}", e),
                });
            }
        }
    }

    let _ = fs::remove_dir_all(&tmp_dir);
    results
}

fn cmd_scan_phpt(dir_arg: &str) {
    let start = Instant::now();
    let root = Path::new(dir_arg);
    let mut files = Vec::new();
    collect_phpt_files(root, &mut files);
    let total_files = files.len();

    let workers = thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(4);
    let queue = Arc::new(Mutex::new(files));
    let parsed_count = Arc::new(Mutex::new(0usize));
    let mut handles = Vec::new();

    for _ in 0..workers {
        let q = Arc::clone(&queue);
        let cnt = Arc::clone(&parsed_count);
        handles.push(thread::spawn(move || {
            let mut local = 0usize;
            loop {
                let next = {
                    let mut guard = q.lock().unwrap();
                    guard.pop()
                };
                match next {
                    Some(p) => {
                        if parse_phpt(&p).is_some() {
                            local += 1;
                        }
                    }
                    None => break,
                }
            }
            *cnt.lock().unwrap() += local;
        }));
    }
    for h in handles {
        let _ = h.join();
    }
    let elapsed = start.elapsed().as_secs_f64();
    let valid = *parsed_count.lock().unwrap();
    println!(
        "{{\"total_phpt\":{},\"valid_parsed\":{},\"workers\":{},\"elapsed_sec\":{:.4}}}",
        total_files, valid, workers, elapsed
    );
}

#[derive(Debug)]
struct FailureSample {
    path: String,
    title: String,
    expected: String,
    actual: String,
    oracle_actual: Option<String>,
}

fn truncate_str(s: &str, max_len: usize) -> String {
    if s.chars().count() <= max_len {
        return s.to_string();
    }
    let cut: String = s.chars().take(max_len).collect();
    format!("{}...(truncated)", cut)
}

fn cmd_run_phpt(args: &[String]) {
    if args.is_empty() {
        eprintln!("Usage: all_runner run-phpt <phpt-dir> [--filter <substr>] [--limit <N>] [--adapter <php.ps1>] [--oracle <php.exe>] [--report <out.json>] [--workers <N>]");
        std::process::exit(2);
    }

    let root = PathBuf::from(&args[0]);
    let mut filter: Option<String> = None;
    let mut limit: Option<usize> = None;
    let mut adapter_path = default_adapter_path();
    let mut oracle_path: Option<PathBuf> = None;
    let mut report_path: Option<PathBuf> = None;
    let mut workers = thread::available_parallelism()
        .map(|n| n.get().min(8))
        .unwrap_or(4);

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--filter" if i + 1 < args.len() => {
                filter = Some(args[i + 1].clone());
                i += 2;
            }
            "--limit" if i + 1 < args.len() => {
                limit = args[i + 1].parse::<usize>().ok();
                i += 2;
            }
            "--adapter" if i + 1 < args.len() => {
                adapter_path = PathBuf::from(&args[i + 1]);
                i += 2;
            }
            "--oracle" if i + 1 < args.len() => {
                oracle_path = Some(PathBuf::from(&args[i + 1]));
                i += 2;
            }
            "--report" if i + 1 < args.len() => {
                report_path = Some(PathBuf::from(&args[i + 1]));
                i += 2;
            }
            "--workers" if i + 1 < args.len() => {
                if let Ok(w) = args[i + 1].parse::<usize>() {
                    workers = w.max(1).min(32);
                }
                i += 2;
            }
            other => {
                eprintln!("Unknown option: {}", other);
                std::process::exit(2);
            }
        }
    }

    if !adapter_path.exists() {
        eprintln!("Adapter not found: {}", adapter_path.display());
        std::process::exit(1);
    }

    let start = Instant::now();
    let mut files = Vec::new();
    collect_phpt_files(&root, &mut files);
    if let Some(ref f) = filter {
        let fl = f.to_lowercase();
        files.retain(|p| p.to_string_lossy().to_lowercase().contains(&fl));
    }
    if let Some(lim) = limit {
        files.truncate(lim);
    }

    let mut cases: Vec<PhptCase> = Vec::with_capacity(files.len());
    let mut invalid_phpt = 0usize;
    for f in &files {
        match parse_phpt(f) {
            Some(c) => cases.push(c),
            None => invalid_phpt += 1,
        }
    }

    let total_cases = cases.len();
    let actual_workers = workers.min(total_cases.max(1));
    let mut buckets: Vec<Vec<(usize, PhptCase)>> = vec![Vec::new(); actual_workers];
    for (idx, c) in cases.iter().enumerate() {
        buckets[idx % actual_workers].push((idx, c.clone()));
    }

    let all_results = Arc::new(Mutex::new(Vec::<WorkerCaseResult>::with_capacity(total_cases)));
    let adapter_arc = Arc::new(adapter_path.clone());
    let mut handles = Vec::new();

    for (wid, bucket) in buckets.into_iter().enumerate() {
        if bucket.is_empty() {
            continue;
        }
        let res_arc = Arc::clone(&all_results);
        let adp = Arc::clone(&adapter_arc);
        handles.push(thread::spawn(move || {
            let batch_res = run_worker_batch(wid, &bucket, &adp);
            res_arc.lock().unwrap().extend(batch_res);
        }));
    }
    for h in handles {
        let _ = h.join();
    }

    let mut res_by_idx: HashMap<usize, WorkerCaseResult> = HashMap::new();
    for r in all_results.lock().unwrap().drain(..) {
        res_by_idx.insert(r.index, r);
    }

    let mut pass_count = 0usize;
    let mut fail_count = 0usize;
    let mut skipif_count = 0usize;
    let mut unsupported_count = 0usize;
    let mut unsupported_reasons: BTreeMap<String, usize> = BTreeMap::new();
    let mut fail_samples: Vec<FailureSample> = Vec::new();

    let oracle_tmp = env::temp_dir().join(format!("all_phpt_oracle_{}", std::process::id()));
    if oracle_path.is_some() {
        let _ = fs::create_dir_all(&oracle_tmp);
    }

    for (idx, case) in cases.iter().enumerate() {
        let rel_path = case
            .path
            .strip_prefix(&root)
            .unwrap_or(&case.path)
            .to_string_lossy()
            .to_string();
        let res = match res_by_idx.get(&idx) {
            Some(r) => r.clone(),
            None => WorkerCaseResult {
                index: idx,
                status: "unsupported".to_string(),
                output: String::new(),
                error: "Worker dropped case without result".to_string(),
            },
        };

        if res.status == "skipif" {
            skipif_count += 1;
            continue;
        }
        if res.status == "unsupported" {
            unsupported_count += 1;
            let key = normalize_unsupported_reason(&res.error);
            *unsupported_reasons.entry(key).or_insert(0) += 1;
            continue;
        }

        if case.expect.is_none() && case.expectf.is_none() && case.expect_regex.is_none() {
            unsupported_count += 1;
            *unsupported_reasons
                .entry("Missing EXPECT/EXPECTF/EXPECTREGEX section".to_string())
                .or_insert(0) += 1;
            continue;
        }

        if match_phpt_output(&res.output, case) {
            pass_count += 1;
        } else {
            fail_count += 1;
            if fail_samples.len() < 40 {
                let oracle_actual = oracle_path
                    .as_ref()
                    .and_then(|op| run_oracle_php(op, case, &oracle_tmp, idx))
                    .map(|s| truncate_str(&s, 300));
                let expected_preview = case
                    .expect
                    .as_deref()
                    .or(case.expectf.as_deref())
                    .or(case.expect_regex.as_deref())
                    .unwrap_or("");
                fail_samples.push(FailureSample {
                    path: rel_path,
                    title: case.title.clone(),
                    expected: truncate_str(expected_preview, 300),
                    actual: truncate_str(&res.output, 300),
                    oracle_actual,
                });
            }
        }
    }

    if oracle_path.is_some() {
        let _ = fs::remove_dir_all(&oracle_tmp);
    }

    let elapsed = start.elapsed().as_secs_f64();
    let mut reason_vec: Vec<(String, usize)> = unsupported_reasons.into_iter().collect();
    reason_vec.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));

    let runnable = pass_count + fail_count + unsupported_count;
    let pass_rate_runnable = if runnable > 0 {
        (pass_count as f64) * 100.0 / (runnable as f64)
    } else {
        0.0
    };

    let mut report = String::new();
    report.push_str("{\n");
    report.push_str(&format!("  \"phpt_dir\": {},\n", json_escape(&root.to_string_lossy())));
    report.push_str(&format!("  \"adapter\": {},\n", json_escape(&adapter_path.to_string_lossy())));
    report.push_str(&format!("  \"workers\": {},\n", actual_workers));
    report.push_str(&format!("  \"total_files\": {},\n", files.len()));
    report.push_str(&format!("  \"valid_cases\": {},\n", total_cases));
    report.push_str(&format!("  \"invalid_skipped\": {},\n", invalid_phpt));
    report.push_str(&format!("  \"pass\": {},\n", pass_count));
    report.push_str(&format!("  \"fail\": {},\n", fail_count));
    report.push_str(&format!("  \"skipif\": {},\n", skipif_count));
    report.push_str(&format!("  \"unsupported\": {},\n", unsupported_count));
    report.push_str(&format!("  \"pass_rate_runnable_pct\": {:.2},\n", pass_rate_runnable));
    report.push_str(&format!("  \"elapsed_sec\": {:.4},\n", elapsed));

    report.push_str("  \"top_unsupported_reasons\": [\n");
    for (idx, (msg, cnt)) in reason_vec.iter().take(30).enumerate() {
        let comma = if idx + 1 < reason_vec.len().min(30) { "," } else { "" };
        report.push_str(&format!(
            "    {{\"count\": {}, \"reason\": {}}}{}\n",
            cnt,
            json_escape(msg),
            comma
        ));
    }
    report.push_str("  ],\n");

    report.push_str("  \"sample_failures\": [\n");
    for (idx, sample) in fail_samples.iter().enumerate() {
        let comma = if idx + 1 < fail_samples.len() { "," } else { "" };
        let oracle_json = match sample.oracle_actual {
            Some(ref s) => json_escape(s),
            None => "null".to_string(),
        };
        report.push_str(&format!(
            "    {{\"path\": {}, \"title\": {}, \"expected\": {}, \"actual\": {}, \"oracle_actual\": {}}}{}\n",
            json_escape(&sample.path),
            json_escape(&sample.title),
            json_escape(&sample.expected),
            json_escape(&sample.actual),
            oracle_json,
            comma
        ));
    }
    report.push_str("  ]\n");
    report.push_str("}\n");

    if let Some(ref rp) = report_path {
        if let Some(parent) = rp.parent() {
            let _ = fs::create_dir_all(parent);
        }
        if let Err(e) = fs::write(rp, report.as_bytes()) {
            eprintln!("Failed to write report {}: {}", rp.display(), e);
        }
    }

    println!(
        "{{\"total\":{},\"pass\":{},\"fail\":{},\"skipif\":{},\"unsupported\":{},\"pass_rate_runnable_pct\":{:.2},\"workers\":{},\"elapsed_sec\":{:.4}}}",
        total_cases, pass_count, fail_count, skipif_count, unsupported_count, pass_rate_runnable, actual_workers, elapsed
    );
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        println!(
            "{{\"engine\":\"all_rust_engine\",\"version\":{},\"status\":\"READY\"}}",
            all_engine::all_engine_version()
        );
        return;
    }
    let cmd = &args[1];
    if cmd == "scan-phpt" && args.len() >= 3 {
        cmd_scan_phpt(&args[2]);
    } else if cmd == "run-phpt" || cmd == "phpt" {
        cmd_run_phpt(&args[2..]);
    } else {
        eprintln!("Unknown command: {}", cmd);
        std::process::exit(2);
    }
}
