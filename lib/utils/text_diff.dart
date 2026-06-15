/*
 * Copyright 2026 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// 行级文本对比：Patience Diff（错位时用 lookahead 兜底）。
//
// LCS 会跨远距离匹配（左第 1 行的 `abc` 跟右第 80 行的 `abc` 算公共行），
// 让用户看到"行号错开几十行"的错位结果，对人工对比反直觉。
// 改用 Bram Cohen 的 Patience Diff：
//
//   1. 切公共前缀 / 后缀，直接 emit equal；
//   2. 在剩下的中间段里，找"在两边各自唯一、且都出现"的行作锚点；
//   3. 锚点按 a-index 排序后对 b-index 求 LIS——LIS 上的锚点保证两边顺序一致；
//   4. 用这些锚点把段切短，递归对比每个子段；
//   5. 找不到锚点的小段退化成"双指针 + 短窗前瞻"。
//
// 直觉解释：锚点是两边都"独一无二"的行（比如某条独特的日志、某个唯一的标识符），
// 拿它们当对齐点，公共的样板行（空行、`}`、`)`）因为出现多次不会成为锚点，
// 自然不会让无关行被错配。

/// 前瞻窗口：基线段（无锚点）里发现错位时往前找几行。
/// Patience 切完之后段通常不长，4 已经够用；调大对工程不敏感。
const int _lookahead = 4;

enum LineDiffType { equal, insert, delete }

class LineDiff {
  final LineDiffType type;
  final String text;

  /// 该行在左侧文本里的 1-based 行号；insert 类型为 null
  final int? leftLine;

  /// 该行在右侧文本里的 1-based 行号；delete 类型为 null
  final int? rightLine;

  const LineDiff(this.type, this.text, {this.leftLine, this.rightLine});
}

/// 计算两段文本的行级差异，按出现顺序返回。
List<LineDiff> diffLines(String left, String right) {
  // 用 split('\n') 而不是 LineSplitter：保留尾部空行的差异（"a\n" vs "a"）
  final a = left.split('\n');
  final b = right.split('\n');
  final out = <LineDiff>[];
  _diffRange(a, b, 0, a.length, 0, b.length, out);
  return out;
}

void _diffRange(List<String> a, List<String> b, int aLo, int aHi, int bLo, int bHi, List<LineDiff> out) {
  // 1. 公共前缀
  while (aLo < aHi && bLo < bHi && a[aLo] == b[bLo]) {
    out.add(LineDiff(LineDiffType.equal, a[aLo], leftLine: aLo + 1, rightLine: bLo + 1));
    aLo++;
    bLo++;
  }
  // 2. 公共后缀（先记长度，最后 emit）
  var suffix = 0;
  while (aLo < aHi - suffix && bLo < bHi - suffix && a[aHi - 1 - suffix] == b[bHi - 1 - suffix]) {
    suffix++;
  }
  final aEnd = aHi - suffix;
  final bEnd = bHi - suffix;

  // 3. 中间段：找锚点切分
  if (aLo < aEnd || bLo < bEnd) {
    final anchors = _findAnchors(a, aLo, aEnd, b, bLo, bEnd);
    if (anchors.isEmpty) {
      _lookaheadDiff(a, b, aLo, aEnd, bLo, bEnd, out);
    } else {
      var prevA = aLo, prevB = bLo;
      for (final anchor in anchors) {
        _diffRange(a, b, prevA, anchor.aIdx, prevB, anchor.bIdx, out);
        out.add(LineDiff(
          LineDiffType.equal,
          a[anchor.aIdx],
          leftLine: anchor.aIdx + 1,
          rightLine: anchor.bIdx + 1,
        ));
        prevA = anchor.aIdx + 1;
        prevB = anchor.bIdx + 1;
      }
      _diffRange(a, b, prevA, aEnd, prevB, bEnd, out);
    }
  }

  // 4. 公共后缀
  for (var k = 0; k < suffix; k++) {
    out.add(LineDiff(
      LineDiffType.equal,
      a[aEnd + k],
      leftLine: aEnd + k + 1,
      rightLine: bEnd + k + 1,
    ));
  }
}

class _Anchor {
  final int aIdx;
  final int bIdx;
  const _Anchor(this.aIdx, this.bIdx);
}

/// 在 [aLo,aHi) × [bLo,bHi) 内找"两边各自唯一且都出现"的行，作为对齐锚点。
/// 返回的锚点已按 a-index 升序排列，且对应的 b-index 也单调递增（LIS 保证）。
List<_Anchor> _findAnchors(List<String> a, int aLo, int aHi, List<String> b, int bLo, int bHi) {
  // 统计每行出现次数 + 第一次出现的下标
  final aCount = <String, int>{};
  final aIdx = <String, int>{};
  for (var i = aLo; i < aHi; i++) {
    final s = a[i];
    final c = aCount[s];
    if (c == null) {
      aCount[s] = 1;
      aIdx[s] = i;
    } else {
      aCount[s] = c + 1;
    }
  }
  final bCount = <String, int>{};
  final bIdx = <String, int>{};
  for (var i = bLo; i < bHi; i++) {
    final s = b[i];
    final c = bCount[s];
    if (c == null) {
      bCount[s] = 1;
      bIdx[s] = i;
    } else {
      bCount[s] = c + 1;
    }
  }

  final candidates = <_Anchor>[];
  aCount.forEach((s, ca) {
    if (ca == 1 && bCount[s] == 1) {
      candidates.add(_Anchor(aIdx[s]!, bIdx[s]!));
    }
  });
  if (candidates.isEmpty) return const [];

  candidates.sort((x, y) => x.aIdx.compareTo(y.aIdx));
  return _longestIncreasingSubsequence(candidates);
}

/// 在按 a-index 排序的候选里，找 b-index 严格递增的最长子序列。
/// 这是 Patience Sort 的标准用法：O(n log n)，并通过 prev 指针重建子序列。
List<_Anchor> _longestIncreasingSubsequence(List<_Anchor> sortedByA) {
  final n = sortedByA.length;
  if (n == 0) return const [];

  // tailIdx[k] = 长度 (k+1) 的递增子序列里 b-index 最小的那条所在的 sortedByA 下标
  final tailIdx = <int>[];
  final prev = List<int>.filled(n, -1);

  for (var i = 0; i < n; i++) {
    final bv = sortedByA[i].bIdx;
    var lo = 0, hi = tailIdx.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (sortedByA[tailIdx[mid]].bIdx < bv) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo > 0) prev[i] = tailIdx[lo - 1];
    if (lo == tailIdx.length) {
      tailIdx.add(i);
    } else {
      tailIdx[lo] = i;
    }
  }

  // 从最后一条 tail 顺着 prev 重建
  final result = <_Anchor>[];
  var k = tailIdx.last;
  while (k >= 0) {
    result.add(sortedByA[k]);
    k = prev[k];
  }
  return result.reversed.toList();
}

/// 段内没有锚点时的兜底：双指针 + 短窗前瞻。
/// 不等时在 [_lookahead]² 个候选 (di, dj) 里找最近匹配点；找不到就当作"同行修改"。
void _lookaheadDiff(
    List<String> a, List<String> b, int aLo, int aHi, int bLo, int bHi, List<LineDiff> out) {
  var i = aLo, j = bLo;
  while (i < aHi && j < bHi) {
    if (a[i] == b[j]) {
      out.add(LineDiff(LineDiffType.equal, a[i], leftLine: i + 1, rightLine: j + 1));
      i++;
      j++;
      continue;
    }
    int bestDi = -1, bestDj = -1, bestSum = 1 << 30;
    for (var sum = 1; sum <= _lookahead * 2 && sum < bestSum; sum++) {
      for (var di = 0; di <= sum; di++) {
        final dj = sum - di;
        if (di > _lookahead || dj > _lookahead) continue;
        final ii = i + di;
        final jj = j + dj;
        if (ii >= aHi || jj >= bHi) continue;
        if (a[ii] == b[jj]) {
          bestDi = di;
          bestDj = dj;
          bestSum = sum;
          break;
        }
      }
    }
    if (bestDi >= 0) {
      for (var x = 0; x < bestDi; x++) {
        out.add(LineDiff(LineDiffType.delete, a[i], leftLine: i + 1));
        i++;
      }
      for (var x = 0; x < bestDj; x++) {
        out.add(LineDiff(LineDiffType.insert, b[j], rightLine: j + 1));
        j++;
      }
    } else {
      out.add(LineDiff(LineDiffType.delete, a[i], leftLine: i + 1));
      out.add(LineDiff(LineDiffType.insert, b[j], rightLine: j + 1));
      i++;
      j++;
    }
  }
  while (i < aHi) {
    out.add(LineDiff(LineDiffType.delete, a[i], leftLine: i + 1));
    i++;
  }
  while (j < bHi) {
    out.add(LineDiff(LineDiffType.insert, b[j], rightLine: j + 1));
    j++;
  }
}

/// 字符级差异：标记"两条配对的差异行"中各自被改动的字符范围。
///
/// 给 [diffLines] 出来的"连续 delete + 连续 insert"块在 UI 层做行配对后，
/// 把每对 (left, right) 喂进来：返回左字符串中"被删除/改动"的字符段，
/// 和右字符串中"被新增/改动"的字符段。range 用 [start, end) 半开区间。
class CharDiff {
  /// 在 left 字符串里被改动 / 删除的字符范围（[start, end) 半开）。
  final List<({int start, int end})> leftRanges;

  /// 在 right 字符串里被改动 / 新增的字符范围（[start, end) 半开）。
  final List<({int start, int end})> rightRanges;

  const CharDiff({required this.leftRanges, required this.rightRanges});
}

/// 字符级 LCS 回溯。作用在 utf16 code units 上：
/// 直接用 String.codeUnits 比较避免 emoji / 中文之类多字节字符被中间切开（Dart String
/// 索引本就是 utf16，所以 codeUnits 跟 substring 索引天然一致）。
CharDiff diffChars(String left, String right) {
  final a = left.codeUnits;
  final b = right.codeUnits;
  final m = a.length;
  final n = b.length;

  final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
  for (var i = 0; i < m; i++) {
    for (var j = 0; j < n; j++) {
      if (a[i] == b[j]) {
        dp[i + 1][j + 1] = dp[i][j] + 1;
      } else {
        dp[i + 1][j + 1] = dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1];
      }
    }
  }

  // 回溯收集 delete/insert 单字符位置；相邻位置合并成区间。
  final leftPos = <int>[];
  final rightPos = <int>[];
  var i = m, j = n;
  while (i > 0 && j > 0) {
    if (a[i - 1] == b[j - 1]) {
      i--;
      j--;
    } else if (dp[i - 1][j] >= dp[i][j - 1]) {
      leftPos.add(i - 1);
      i--;
    } else {
      rightPos.add(j - 1);
      j--;
    }
  }
  while (i > 0) {
    leftPos.add(i - 1);
    i--;
  }
  while (j > 0) {
    rightPos.add(j - 1);
    j--;
  }

  return CharDiff(leftRanges: _mergeAdjacent(leftPos), rightRanges: _mergeAdjacent(rightPos));
}

/// 把递减的位置列表合并成连续区间。`positions` 由回溯产生，是降序排列的索引。
List<({int start, int end})> _mergeAdjacent(List<int> positions) {
  if (positions.isEmpty) return const [];
  positions.sort();
  final ranges = <({int start, int end})>[];
  var start = positions.first;
  var prev = start;
  for (var k = 1; k < positions.length; k++) {
    final p = positions[k];
    if (p == prev + 1) {
      prev = p;
    } else {
      ranges.add((start: start, end: prev + 1));
      start = p;
      prev = p;
    }
  }
  ranges.add((start: start, end: prev + 1));
  return ranges;
}
