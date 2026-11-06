#!/usr/bin/perl
# chk_inst.pl v3 — 例化对齐检查 (规则8修订版, 配套 norm_inst.pl v3):
#   分析前先剥尾部 `// 注释`。点连接行 (`.*` 例外) 检查:
#   A. 同行多连接 (`), .` / `); .`) → 违反"一信号一行";
#   B. 块内 `(` 列 / `)` 列不齐 (列号量自原始行: 首 `(` 与末 `)`);
#   C. 空连接被填充 (规则: 空连接 .port() 不参与右括号列);
#   D. 尾随注释未贴 (可选提示, 不算违例)。
use strict;
use warnings;

my $file = $ARGV[0] or die "usage: chk_inst.pl <file>\n";
open my $fh, '<', $file or die "$file: $!";
my @lines = <$fh>;
close $fh;

my $viol = 0;
my @blk;

sub flush {
   return unless @blk;
   my (%lcol, %rcol);
   for my $l (@blk) {
      my ($ln, $code) = @$l;
      $lcol{ index($code, '(') } = 1;
      # 空连接 .port() 不参与右括号列 (规则8) — 豁免
      $rcol{ rindex($code, ')') } = 1 unless $code =~ /^\s*\.[A-Za-z_][A-Za-z0-9_]*\s*\(\s*\)/;
      if ($code =~ /^\s*\.[A-Za-z_][A-Za-z0-9_]*\s*\(\s+\)/) {
         print "$file:$ln: C 空连接被填充: $code\n";
         $viol++;
      }
   }
   my @ls = sort { $a <=> $b } keys %lcol;
   my @rs = sort { $a <=> $b } keys %rcol;
   if (@ls > 1) {
      print "$file:$blk[0][0]-$blk[-1][0]: B 左括号列不齐 (" . join(',', @ls) . ")\n";
      $viol++;
   }
   if (@rs > 1) {
      print "$file:$blk[0][0]-$blk[-1][0]: B 右括号列不齐 (" . join(',', @rs) . ")\n";
      $viol++;
   }
   @blk = ();
}

my $n = 0;
for my $line (@lines) {
   $n++;
   chomp $line;
   $line =~ s/\r$//;
   if ($line =~ /^\s*$/) {
      flush();    # 空行 = 块边界 (与 norm_inst.pl 一致)
      next;
   }
   if ($line =~ /^\s*\./ and $line !~ /^\s*\.\s*\*/) {
      my $code = $line;
      my $pos = index($line, '//');
      if ($pos >= 0) {
         $code = substr($line, 0, $pos);
         $code =~ s/\s+$//;
      }
      if ($code =~ /,\s*\./ or $code =~ /;\s*\./) {
         flush();
         print "$file:$n: A 同行多连接: $line\n";
         $viol++;
      } elsif ($code =~ /^\s*\.[A-Za-z_][A-Za-z0-9_]*\s*\(/) {
         push @blk, [ $n, $code ];
      } else {
         flush();
         print "$file:$n: A 非连接点行: $line\n";
         $viol++;
      }
   } else {
      flush();
   }
}
flush();
exit 0;
