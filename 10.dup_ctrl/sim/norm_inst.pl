#!/usr/bin/perl
# norm_inst.pl v3 — 例化连接归一化 (规则8修订版: 一信号一行 + 括号内信号左对齐):
#   1. `.端口名` 补空格到本组最长 → `(` 一列;
#   2. 连接表达式紧随 `(` 左对齐, 尾部补空格到本组最长 → `)` 一列 (末行无逗号);
#   3. 空连接 .port() 不参与右括号列 (保持紧贴不填充);
#   4. 多连接同行 (深度感知在深度0的 `)`+`,` 处切分) → 拆成一连接一行;
#   5. 行内 `);` 实例闭合 → 拆出后 `);` 独立成行 (缩进取最近的实例头行);
#   6. 尾随 `// 注释` → 保留, 贴在 (该行最后一条连接 | `);` 行) 尾部;
#   7. 无法安全解析的行 (括号不平衡/段解析失败) 原样跳过。
#   参数 `#()` 段与端口 `()` 段被实例头行天然隔开, 各自独立对齐。
#   变换仅增删/移动空白与换行: tr -d ' \t\r\n' 后与原文件逐字节相同。
use strict;
use warnings;

my $file = $ARGV[0] or die "usage: norm_inst.pl <file>\n";
open my $fh, '<', $file or die "$file: $!";
my @lines = <$fh>;
close $fh;

my $out        = '';
my @blk;
my $hdr_indent;    # 最近一条以 `(` 结尾的行 (实例头) 的缩进, 供 ");" 行使用

my $flush = sub {
   return unless @blk;
   my ($max, $maxn) = (0, 0);
   for my $l (@blk) {
      my $n = length($l->{sig});
      $max = $n if $n > $max;
      if ($l->{pre} =~ /^(\s*)\.([A-Za-z_][A-Za-z0-9_]*)$/) {
         my $nl = length($2);
         $maxn = $nl if $nl > $maxn;
      }
   }
   for my $l (@blk) {
      my $pre = $l->{pre};
      if ($pre =~ /^(\s*)\.([A-Za-z_][A-Za-z0-9_]*)$/) {
         $pre = $1 . '.' . $2 . (' ' x ($maxn - length($2))) . '(';
      }
      my $pad = ($l->{sig} eq '') ? 0 : ($max - length($l->{sig}));
      $out .= $pre . $l->{sig} . (' ' x $pad) . ')' . $l->{comma}
            . ($l->{cmt} ne '' ? '  ' . $l->{cmt} : '')
            . ($l->{crlf} // '') . "\n";
   }
   @blk = ();
};

# 深度感知拆分: 把一行连接区拆成连接列表。
# 返回 (\@conns, $trailing_comma, $inst_close) — conns 元素为 {name, sig};
# 失败返回 () (调用方原样跳过该行)。
sub split_conns {
   my ($code) = @_;
   my @segs;
   my ($depth, $just, $inst_close, $start) = (0, 0, 0, 0);
   my $end = length($code);
   for (my $i = 0; $i < length($code); $i++) {
      my $c = substr($code, $i, 1);
      if ($c eq '(') {
         $depth++;
         $just = 0;
      } elsif ($c eq ')') {
         if ($depth == 0) {
            if ($just and not $inst_close) {
               # 实例级闭括号: 其后只允许空白或 ';'
               my $rest = substr($code, $i + 1);
               return () unless $rest =~ /^\s*;?\s*$/;
               $end        = $i;
               $inst_close = 1;
               last;
            }
            return ();    # 深度0多余的 ')' — 括号不平衡
         }
         $depth--;
         $just = ($depth == 0) ? 1 : 0;
      } elsif ($c eq ',' or $c eq ';') {
         if ($just and $depth == 0 and not $inst_close) {
            if ($c eq ';') {
               # 语句结束: 末段留待 final 截取 (start 未推进)
               return () if substr($code, $i + 1) =~ /\S/;
               $end        = $i;
               $inst_close = 1;
               last;
            }
            push @segs, [ substr($code, $start, $i - $start) ];
            $start = $i + 1;
            $just  = 0;
         } elsif ($depth == 0) {
            return ();    # 深度0界符前不是 ')' — 异常
         }
      } elsif ($c =~ /\S/) {
         $just = 0;
      }
   }
   return () if $depth != 0;
   my $final = $inst_close ? substr($code, $start, $end - $start)
                           : substr($code, $start);
   my $trailing_comma = 0;
   if ($final =~ /^\s*$/) {
      return () if $inst_close;    # `);` 前必须有最后一条连接
      $trailing_comma = 1;         # 行尾 ',' → 本行所有连接保留逗号
   } else {
      push @segs, [$final];
   }
   my @conns;
   for my $s (@segs) {
      my $t = $s->[0];
      return () if $t !~ /\S/;
      $t =~ s/^\s+//;
      $t =~ s/\s+$//;
      return () unless $t =~ /^\.([A-Za-z_][A-Za-z0-9_]*)\s*\((.*)\)$/s;
      my ($name, $sig) = ($1, $2);
      $sig =~ s/^\s+//;
      $sig =~ s/\s+$//;
      push @conns, { name => $name, sig => $sig };
   }
   return (\@conns, $trailing_comma, $inst_close);
}

for my $line (@lines) {
   chomp $line;
   my $crlf = ($line =~ s/\r$//) ? "\r" : "";

   if ($line =~ /^\s*\./ and $line !~ /^\s*\.\s*\*/) {
      my ($indent) = ($line =~ /^(\s*)/);
      my ($code, $cmt) = ($line, '');
      my $pos = index($line, '//');
      if ($pos >= 0) {
         $cmt = substr($line, $pos);
         $cmt =~ s/^\s*//;
         $code = substr($line, 0, $pos);
         $code =~ s/\s+$//;
      }
      my @r = split_conns($code);
      if (!@r) {
         $flush->();
         $out .= $line . $crlf . "\n";    # 无法安全解析 → 原样
      } else {
         my ($conns, $tcomma, $iclose) = @r;
         my $n = scalar @$conns;
         for my $k (0 .. $n - 1) {
            my $comma = ($k < $n - 1) ? ',' : (($tcomma and !$iclose) ? ',' : '');
            my $c = ($k == $n - 1 and !$iclose) ? $cmt : '';
            push @blk,
              { pre => $indent . '.' . $conns->[$k]{name}, sig => $conns->[$k]{sig},
                comma => $comma, cmt => $c, crlf => $crlf };
         }
         if ($iclose) {
            $flush->();
            my $ci = $hdr_indent // $indent;
            $out .= $ci . ');' . ($cmt ne '' ? '  ' . $cmt : '') . $crlf . "\n";
         }
      }
   } else {
      $flush->();
      $out .= $line . $crlf . "\n";
      # 实例头行 (以 `(` 结尾) → 记录缩进供 ");" 行使用
      # (捕获必须立即存词法变量: 后一个成功匹配会清空 $1 — 同 s/// 坑)
      if ($line =~ /^(\s*)\S/) {
         my $ind = $1;
         if ($line =~ /\(\s*$/) {
            $hdr_indent = $ind;
         }
      }
   }
}
$flush->();

open my $w, '>', $file or die "$file: $!";
print {$w} $out;
close $w;
