#!/usr/bin/perl

# +FHDR-------------------------------------------------
# Copyright (c) 2019 Horizon Robotics Inc. All  rights reserved.
# Horizon Robotics Property.
# FILE NAME       : run_reg_gen.pl
# DEPARTMENT      : IC Horizon Robotics Inc. 
# AUTHOR          : Bumblebee
# AUTHOR'S EMAIL  : 
#  -----------------------------------------------------
# RELEASE HISTORY
# VERSION          DATE               AUTHOR          DESCRIPTION
# 0.10 2019-05-02 21:07 Bumblebee          Initial
# 0.20 2020-05-27 21:07 Bumblebee          Initial
# 0.30 2022-05-27 21:07 Bumblebee          Initial

# r3p0 2022-2-19: solve the offset format is **H bug
#                 solve the ecc addr with C parse error
# 
# ------------------------------------------------------
# PURPOSE    : 
# 
# +-FHDR------------------------------------------------
# vim: fdm=marker

use Getopt::Long;
use Spreadsheet::ParseExcel;
use Spreadsheet::ParseXLSX;
use List::Util qw(max);
##########################_by guwen gen Data
use POSIX qw(strftime);

our $date = strftime("Date : %Y-%m-%d %H:%M:%S\n",localtime(time));
chomp $date;
our $username = `whoami`;
chomp $username;
#print $date;
##############

###----------------------------------------------------
our $sync = 0;    ##global
our $version = 'v0p3-2023/4/5';
#my %options;
##----- options parse
@tmp = &parse_option();
my $regdef = $tmp[0];
$sync   = $tmp[1];
$noecc  = $tmp[2];

###----------------------------------------------------
my $infile  = $ARGV[0];

if ($ARGV[1] and $ARGV[1]=~/,|;/) {
  $sep_char=$ARGV[1];
} else{
  $sep_char=';';
}
###----------------------------------------------------
# enc check
if (not defined $ENV{"PRJDIR"}){
    print "[ERROR] please set PRJDIR enviroment.\n\n";
    exit 1;
}
###----------------------------------------------------
###----------------------------------------------------
my $addr_head ='BASE_ADDR:';
my $width_head='ADDR_WIDTH=';
my $regnum_head='REG_NUM=';
my $offset_head='ECC_OFFSET:';
my $mtsys_head='Subsystem:';
###----------------------------------------------------

my $outfileName;
my $moduleName;
my $infileName;
my @tmp;

print "-------------------------------\n\n"; 
#------------------------------
#command line parsing
@tmp = &Parse_opt($infile);
  $moduleName  = $tmp[0];
  $outfileName = $tmp[1];
  $outdefName  = $tmp[2];
  $outhdefName = $tmp[3];

#------------------------------
$ifclk = 0;
if ($moduleName=~/\w*_clk_rf\w*/) {
  $ifclk = 1;
} 

#------------------------------
#xls file convert to csv lines
my $base_addr;
my $addr_width;
my $bus;
my $number;
my @info_array;

my $multisys;
@tmp = &Parse_cfg($infile,$sep_char);
  $base_addr   = $tmp[0];
  $base_offset = $tmp[1];
  $addr_width  = $tmp[2];
  $bus         = $tmp[3];
  $number      = $tmp[4];
  @info_array  = @{$tmp[5]};
  $ecc_offset  = $tmp[6];
  $multisys    = $tmp[7];

$multisys = uc($multisys);
my $mul=  $multisys;
my $search = "_SYS";
my $replace = "";
$mul =~ s/$search/$replace/g;
my @sys_array;
@sys_array = split("/",$mul);
my $sys_num = @sys_array;
#print "sysn is $sys_num\n";

#if($sys_num == 1){
#  print "[ERROR]: Reg is only used by one subsys!\n";
#}
  print "[INFO]: Base addr is $base_addr\n"; 
  print "[INFO]: Addr width is $addr_width\n"; 
  print "[INFO]: BUS is $bus\n"; 
  print "[INFO]: REG NUM is $number\n"; 
  if ($number >1) {
    print "[INFO]: Base addr offset is $base_offset\n\n"; 
  }


#------------------------------

#------------------------------
#csv lines proc
my $reg_num   ; 
my $field_num ; 
my %hash_offset;
my %hash_group; 
my %hash_reg  ; 
my %hash_field; 
my %hash_msb  ; 
my %hash_lsb  ; 
my %hash_width; 
my %hash_attr ; 
my %hash_value; 
my %hash_descr; 
@tmp = &Proc_info($addr_width,$bus,\@info_array,$ecc_offset);
  $reg_num     = $tmp[0];
  $field_num   = $tmp[1];
  @reg_list    = @{$tmp[2]};
  @field_list  = @{$tmp[3]};
  @ecc_addr    = @{$tmp[4]};
  print "[INFO]: ECC REG is @ecc_addr\n"; 
#------------------------------

#------------------------------
&Gen_reg_file($addr_width,$bus,$outfileName,$reg_num,$field_num,
              \@reg_list,\@field_list,$regdef);
#------------------------------

#------------------------------
if ($regdef) {
  &Gen_def_file($moduleName,$base_addr,$outdefName,$outhdefName,
                $number,$base_offset,\@reg_list,\@sys_array,$sys_num);
}
#------------------------------

##------------------------------
if ($regdef) {
  &Gen_bdef_file($moduleName,$base_addr,$outdefName,$outbdefName,
                $number,$base_offset,\@reg_list,\@field_list,\@sys_array,$sys_num);
}
##------------------------------
#
 #=======================================================================
 # add testbench generator and run simulation
 #=======================================================================
#$tb_gen_cmd = "python3 reg_gen_ecc_tb_gen.py $infile";
#system($tb_gen_cmd);

 #=======================================================================
 # parse command opts
 # Father process : main
 # Depth : main -> parse_opt
 #=======================================================================
sub parse_option {
  #my ($ps_options) = @_;
  my $help = 0;
  my $sync = 0;
  my $regdef = 0;
  my $noecc = 0;
  
  if (GetOptions(
       'help!'    => \$help,
       'def!'     => \$regdef,
       'noecc!'    => \$noecc,
       'sync=s'   => \$sync,
     )
  ) {
  } 
  else {
          print "[ERROR] program doesn't get correct option, please re-indicate the options. \n";
          print "Try `reg_gen_ecc.pl --help` for more information. \n";
          exit 1;
  }
  if ($help) {
    &print_help();
  }

  #if ($sync==0 and $sync=1){
  #        print "[ERROR] sync option shold be 0 or 1. \n";
  #        exit 1;
  #}
  
  return ($regdef, $sync, $noecc);
  #$ps_options->{sync} = $sync;
}


#=======================================================================
# command parsing
# Father process : main
# Depth : main ->Parse_opt
#=======================================================================
sub Parse_opt{
  my ($infile) = @_;
  if(($infile =~/([a-zA-Z0-9_]+).xls/) or ($infile =~/([a-zA-Z0-9_]+).csv/)) {
    $moduleName = $1;
  } 
  else {
    die "[ERROR]: You need to specify a .xls OR .csv file for reg generation\n";
  }
  
  $outfileName = $moduleName.'.v';
  $outdefName  = $moduleName.'_define.v';
  $outhdefName = $moduleName.'_define.h';
  $outbdefName = $moduleName.'_bit_define.h';
 
  return ($moduleName, $outfileName, $outdefName, $outhdefName);
}; 

#=======================================================================
# config parsing, convert .xls to csv lines
# Father process : main
# Depth : main ->Parse_cfg
#=======================================================================
sub Parse_cfg {
  my ($infile,$sep_char) = @_;
  my $row,$col,$cell,$value;
  my @row_array;
  my $line;
  my @lines;

  ### .csv file process
  if ($infile =~/(.*).csv/){
    open CFG_CSV, "<$infile" or die ("[ERROR]: Could not open $infile");
    $first_line = 6;

    while($line = <CFG_CSV>){
      if ($line=~/$sep_char/i) {
      } else{
          print "[ERROR]: Wrong seperator character '$sep_char' ,should be --',' or ';'\n";
          #exit 1;
      }
      $line=~s/[\f\t\n\r]//g;
      $line=~s/$sep_char/;/g;
      if ($.==1) {
        $_ = $line;
        @_ = split/;/,$_;
        if (@_[0] =~/^\s*$addr_head\s*(0x[a-zA-Z0-9]+)\/(0x[a-zA-Z0-9]+)$/){
          $base_addr = $1;
          $base_offset=$2;
        }
        elsif (@_[0] =~/^\s*$addr_head\s*(0x[a-zA-Z0-9]+)$/){
          $base_addr = $1;
          $base_offset='';
        }
        #else{
        #  print "[ERROR]: Wrong address format, should be $addr_head 0x80000000\n";
        #  exit 1;
        #}
      }
      elsif ($.==2) {
        $_ = $line;
        @_ = split/;/,$_;
        @_[0] =~/^$width_head(\d*)/;
        $addr_width = $1;
      }
      elsif ($.==3) {
        $_ = $line;
        @_ = split/;/,$_;
        $bus = @_[0];
      }
      elsif ($.==4) {
        $_ = $line;
        @_ = split/;/,$_;
        @_[0] =~/^$regnum_head(\d*)/;
        $number = $1;
        #if (($number == 1) and ($base_offset)){
        #  print "[ERROR]: Reg use only once, so addr should be $addr_head 0x80000000\n";
        #  exit 1;
        #} elsif (($number > 1) and (!$base_offset)){
        #  print "$number |||$base_offset";
        #  print "[ERROR]: Reg use more than once, so addr should be $addr_head 0x80000000/0x10000\n";
        #  exit 1;
        #}
      }
      elsif ($.==5) {
        $_ = $line;
        @_ = split/;/,$_;
        @_[0] =~/^$offset_head\s*(0[xX][0-9a-fA-F]+)\s*$/;
        $ecc_offset = $1;
      }
      elsif ($.>=6) {
        if ( $cell=~/^$mtsys_head(.*)/) {
            $first_line = 7;
            $multisys=$1;
            $multisys=~s/\s*//;
        } else {
            $first_line = 6;
        }
      }
      if ($.>=$first_line){
        push (@lines,$line);
      }
    }
    close CFG_CSV;
  }
  ### .xls file process
  elsif ($infile =~/(.*).xls/){
    $File = Spreadsheet::ParseExcel::Workbook->Parse($infile);
    #print "FILE: ",$File->{File}, "\n";
    #print "Count: ",$File->{SheetCount}, "\n";
    #print "Author: ",$File->{Author}, "\n";
    if(defined $File->{SheetCount}) {
      $Sheet_reg = $File->{Worksheet}[0]; # assign Sheet0
    } # if
    #print "row is $Sheet_reg->{MaxRow}\n";
    #print "col is $Sheet_reg->{MaxCol}\n";

    $_ = $Sheet_reg->{Cells}[0][0]->Value;
    if ($_ =~/^\s*$addr_head\s*(0x[a-zA-Z0-9]+)\/(0x[a-zA-Z0-9]+)\s*$/){
      $base_addr = $1;
      $base_offset=$2;
    }
    elsif ($_ =~/^\s*$addr_head\s*(0x[a-zA-Z0-9]+)\s*$/){
      $base_addr = $1;
      $base_offset='';
    }
    #else{
    #  print "[ERROR]: Wrong address format, should be $addr_head 0x80000000\n";
    #  exit 1;
    #}

    my $_ = $Sheet_reg->{Cells}[1][0]->Value;
    $_=~/^$width_head(\d*)/;
    $addr_width = $1;

    $bus = $Sheet_reg->{Cells}[2][0]->Value;

    my $_ = $Sheet_reg->{Cells}[3][0]->Value;
    $_=~/^$regnum_head(\d*)/;
    $number = $1;
    #if (($number == 1) and ($base_offset)){
    #  print "[ERROR]: Reg use only once, so addr should be $addr_head 0x80000000\n";
    #  exit 1;
    #} elsif (($number > 1) and (!$base_offset)){
    #  print "[ERROR]: Reg use more than once, so addr should be $addr_head 0x80000000/0x10000\n";
    #  exit 1;
    #}

    my $_ = $Sheet_reg->{Cells}[4][0]->Value;
    $_=~/^\s*$offset_head\s*(0[xX][0-9a-fA-F]+)\s*$/;
    $ecc_offset = $1;

    my ($row_min,$row_max) = $Sheet_reg->row_range();
    my ($col_min,$col_max) = $Sheet_reg->col_range();
    $cell=$Sheet_reg->{Cells}[5][0]->Value;
    if ($cell=~/^$mtsys_head(.*)/) {
        $first_line = 6;
        $multisys=$1;
        $multisys=~s/\s*//;
    } else {
        $first_line = 5;
    }
    for $row ($first_line .. $row_max){
      @row_array =undef;
      for $col ($col_min .. $col_max){
        #next if $Sheet_reg->Range("$row:$row")->EntireRow->{Hidden};
        $cell=$Sheet_reg->get_cell($row,$col);
        next unless $cell;
        $value=$cell->Value;
        $row_array[$col] = $value;
      }#each xls line
    $line = join ";", @row_array;
    push (@lines, $line."\n");
    }#all xls lines
  }#xls process

  #$addr_max = $ecc_offset+0x100; #suppose 100 addr max
  #while ($ecc_offset <= $addr_max){
  #  $format_addr = sprintf("%x", $ecc_offset);
  #  $format_addr =~s/0x//g; 
  #  $format_addr=$format_addr.'h'; 
  #  push (@ecc_addr,"$format_addr");
  #
  #  $ecc_offset+=0x4;
  #}
  return ($base_addr,$base_offset,$addr_width,$bus,$number,\@lines,$ecc_offset,$multisys);
}


#=======================================================================
# config parsing, convert .xls to csv lines
# Father process : main
# Depth : main ->Proc_info
#=======================================================================
sub Proc_info{
  my ($addr_width,$bus,$info,$ecc_offset) =@_;
  my @lines = @{$info}; 
  my $line, $line_cnt=0;
  my @list;
  my %col_id_hash, %col_name_hash;
  my $reg_num, $field_num;
    
  my @reg_list  = [];
  my @field_list= [];

  foreach $line (@lines){
    $line =~ s/\s*//g;
    @list = split /;/,$line;
    my $max_col_num = $#list;
    my $col_offset   = "";
    my $col_group    = "";
    my $col_bits     = "";
    my $col_field    = "";
    my $col_shadow   = "";
    my $col_shadaddr = "";
    my $col_attr     = "";
    my $col_value    = "";
    my $col_descr    = "";
    my $col_cdc      = "";
    my $col_setclr   = "";

    if ($line_cnt==0){
       for $col (0 .. $max_col_num){
        $cur_cell = @list[$col];
        $cur_cell = lc($cur_cell);
        $col_id_hash{$cur_cell}=$col;
        $col_name_hash{$col} = $cur_cell;
       }
    }#line_cnt=0
    elsif (not @list) {
      next;
    }
    elsif ($line_cnt==1) {
    } else {
      $col_offset = $col_id_hash{offset};
      $col_group  = $col_id_hash{registername};
      $col_bits   = $col_id_hash{subbits};
      $col_field  = $col_id_hash{fieldname};
      $col_shadow = $col_id_hash{shadow};
      $col_shadaddr = $col_id_hash{shadowaddr};
      $col_attr   = $col_id_hash{attribute};
      $col_value  = $col_id_hash{defaultvalue};
      $col_descr  = $col_id_hash{description};
      $col_cdc    = $col_id_hash{cdc};
      $col_setclr = $col_id_hash{setclear};
      #shadow column
      if (($list[$col_shadow] eq "") or ($list[$col_shadow]=~/^\w+$/)) {
      } else {
          print "[ERROR]: REG $list[$col_offset] shadow colomn format error\n";
          exit 1;
      }

      #shadow addr column
      if (($list[$col_shadaddr]) and (grep /^$list[$col_shadaddr]$/, @group_values)){
          print "[ERROR]: REG $list[$col_shadow] shadow address is duplicated\n";
          exit 1;
      }
      if (($list[$col_shadaddr] eq "") or ($list[$col_shadaddr]=~/^([0-9a-fA-F]+)[hH]$/)) {
      } else {
          print "[ERROR]: REG $list[$col_offset] shadow addr colomn has wrong offset format, it should be 111h or empty\n";
          exit 1;
      }


      #offset, group
      if (($list[$col_group]) and (grep /^$list[$col_group]$/, @group_values)){
          print "[ERROR]: REG $list[$col_group] is duplicated\n";
          exit 1;
      }

      if (($list[$col_offset]) and (grep /^$list[$col_offset]$/, @offset_values)){
          print "[ERROR]: Offset $list[$col_offset] is duplicated\n";
          exit 1;
      }
      elsif ($list[$col_offset]=~/^([0-9a-fA-F]+)[hH]$/) {
        $reg_num++;
        push(@offset_values, $list[$col_offset]);
        $reg_list[$reg_num]{'offset'} = $list[$col_offset];
        if($list[$col_group] ne ""){
          push (@group_values, $list[$col_group]);
          $reg_list[$reg_num]{'gname'} = $list[$col_group];
        } else{
          print "[ERROR]: REG $list[$col_offset] should have a register name\n";
          exit 1;
        }
      } elsif($list[$col_offset] eq ""){
      } else{
        print "[ERROR]: REG offset $list[$col_offset] has wrong offset format, it should be 111h\n";
        exit 1;
      }

      #set/clear
      if (($col_setclr) and ($list[$col_setclr])) {
        if (($list[$col_attr] ne 'RW') and ($list[$col_attr] ne 'HW')) {
          print "[ERROR]: REG $list[$col_offset] Field $list[$col_field] is not RW/HW attribute, so it shouldn't add set/clear feature\n";
          exit 1;
        }
##        if ($list[$col_group]=~/^FUSA_CTRL|Mask\d*$|Status\d*$|Set\d*$|PASSWORD/) {
##         print "[ERROR]: REG $list[$col_offset] Field $list[$col_field] is fusa register, so it shouldn't add set/clear feature\n";
##          exit 1;
##        }

        #push(@setclr_values, ($list[$col_setclr]+$list[$col_setclr]));
        $cur_offset = hex($reg_list[$reg_num]{'offset'});
        if ($list[$col_setclr]=~/^([0-9a-fA-F]+)[hH]$/) {
            $setaddr = $1;
            $setaddrh = $setaddr.'h';
            #$reg_list[$reg_num]->{'set'} = $list[$col_setclr];
            push(@setaddr_values, ($cur_offset+$setaddr));
        }
        elsif ($list[$col_setclr]=~/^\/([0-9a-fA-F]+)[hH]/) {
            $clraddr = $2;
            $clraddrh = $clraddr.'h';
            #$reg_list[$reg_num]->{'clr'} = $list[$col_setclr];
            push(@clraddr_values, ($cur_off+$clraddr));
        }
        elsif ($list[$col_setclr]=~/^([0-9a-fA-F]+)[hH]\/([0-9a-fA-F]+)[hH]/) {
            $setaddr = $1;
            $clraddr = $2;
            #$reg_list[$reg_num]->{'set'} = $setaddr;
            #$reg_list[$reg_num]->{'clr'} = $clraddr;
            $setaddrh = $setaddr.'h';
            $clraddrh = $clraddr.'h';
            push(@setaddr_values, ($cur_offset+hex($setaddrh)));
            push(@clraddr_values, ($cur_offset+hex($clraddrh)));
        } else {
          print "[ERROR]: Field $list[$col_field] setclear $list[$col_setclr] format error, should be 000h/000h or 000H/000H\n";
          exit 1;
        }
      } else {
        $setaddr = "";
        $clraddr = "";
      }

      #field
      my $msb,$lsb;
      if (($list[$col_field]) and ($list[$col_field] ne "reserved") and (grep /^$list[$col_field]$/, @field_values)){
          print "[ERROR]: REG $reg_list[$reg_num]{'offset'} bit $list[$col_field] is duplicated\n";
          exit 1;
      }
      if($list[$col_field]) {
        #msb,lsb format check
        if ($list[$col_bits]=~"\\[([0-9]*):([0-9]*)\\]") {
          $msb=$1;
          $lsb=$2;
        } elsif($list[$col_bits]=~"\\[([0-9]*)\\]") {
          $msb=$1;
          $lsb=$1;
        } else{
          print"[ERROR]: REG offset $reg_list[$reg_num]{'offset'} -field $list[$col_field] should have bit range\n";
          exit 1;
        }
        #non-reserved format check 
        if($list[$col_field] ne "reserved"){
          if(($list[$col_attr] eq "")|($list[$col_value]) eq ""){
            print"[ERROR]: REG offset $reg_list[$reg_num]{'offset'} -field $list[$col_field] should have attribution and default value\n";
            exit 1;
          }
        }


        #reserved attribute check
        if($list[$col_field] eq "reserved"){
          if($list[$col_attr] ne "RO"){
            print"[ERROR]: REG offset $reg_list[$reg_num]{'offset'} -field reserved field must has RO attribution\n";
            exit 1;
          }
          if($list[$col_value] eq ""){
            print"[ERROR]: REG offset $reg_list[$reg_num]{'offset'} -field reserved field must has a value, format: 'h0, or 0\n";
            exit 1;
          }
        } 


        if($list[$col_field]=~/^\w+$/){
        } else {
            print"[ERROR]: REG offset $reg_list[$reg_num]{'offset'} -field $list[$col_field] format error\n";
            exit 1;
        }

        $field_num++;
        push(@field_values, $list[$col_field]);
        $field_list[$field_num]->{'field'} = $list[$col_field];
        $field_list[$field_num]->{'msb'}   = $msb;
        $field_list[$field_num]->{'lsb'}   = $lsb;
        $field_list[$field_num]->{'width'} = $msb-$lsb+1;
        $field_list[$field_num]->{'attr'}  = $list[$col_attr];
        $field_list[$field_num]->{'value'} = $list[$col_value];
        $field_list[$field_num]->{'descr'} = $list[$col_descr];
        $field_list[$field_num]->{'cdc'}   = $list[$col_cdc];
        $field_list[$field_num]->{'set'}   = $setaddr; #$reg_list[$reg_num]->{'set'};
        $field_list[$field_num]->{'clr'}   = $clraddr; #$reg_list[$reg_num]->{'clr'};
        if (defined $col_shadow) {
            $field_list[$field_num]->{'shad'}  = $list[$col_shadow];
        } else {
            $field_list[$field_num]->{'shad'}  = '';
        }
        if (defined $col_shadaddr) {
            $field_list[$field_num]->{'shadaddr'} = $list[$col_shadaddr];
        } else {
            $field_list[$field_num]->{'shadaddr'} = '';
        }
        $field_list[$field_num]->{'fname'} = $reg_list[$reg_num]->{'gname'};
        $field_list[$field_num]->{'offset'}= $reg_list[$reg_num]->{'offset'};
      } #defined field
      #value

      if ($list[$col_value]){
        if (not $list[$col_value] =~ /\d*'[bodh]\w+/){
          print "[ERROR]: Value of REG $reg_list[$reg_num]{'offset'} field $list[$col_field] has wrong format\n";
          exit 1;
        }
      }
    } #reg lines
    $line_cnt++;
  } #all lines

  #offset value compare
  for $i (1 .. $#offset_values-1){
    $offset_pre = hex($offset_values[$i-1]);
    $offset_cur = hex($offset_values[$i]);
    $offset_nxt = hex($offset_values[$i+1]);
    #print "$i, $offset_pre,$offset_cur,$offset_nxt\n";
    if (($offset_pre < $offset_cur) and ($offset_nxt > $offset_cur)){
    }else{
      $offset_cur = sprintf("%x",$offset_cur);
      print "[ERROR]: Offset ${offset_cur}h should be increaced\n";
      exit 1;
    }
  }

  #setclr addr & offset addr check duplicated
  #my %count = ();
  #$count{$_} += 1 foreach (@offset_values);
  #$count{$_} -= 1 foreach (@setaddr_values);
  my %ha, %hb;
  @setaddr_uniq = grep {++$ha{$_}<2} @setaddr_values;
  @clraddr_uniq = grep {++$ha{$_}<2} @clraddr_values;
  for $i (1 .. $#offset_values-1){
    $offset = $offset_values[$i];
    #$offset =~s/h//g;
    $offset_cur = hex($offset_values[$i]);
    $offset_cur = sprintf("%x",$offset_cur);
    for $j (0 .. $#setaddr_uniq-1) {
        $setaddr = $setaddr_uniq[$j];
        if ($offset eq $setaddr) {
            print "[ERROR]: No.$i REG with Offset ${offset_cur}h is duplicated with setaddr $setaddr\n";
            exit 1;
        }
    }
    for $j (0 .. $#clraddr_uniq-1) {
        $clraddr = $clraddr_uniq[$j];
        if ($offset eq $clraddr) {
            print "[ERROR]: No.$i REG with Offclr ${offset_cur} is duplicated with clraddr\n";
            exit 1;
        }
    }
  }


  #get ecc_offset
  $ecc_offset = hex($ecc_offset);
  for $i (0 .. $#offset_values){
    $offset =hex($offset_values[$i]); 
    if ($offset >= $ecc_offset){
      push (@ecc_addr,lc($offset_values[$i]));
    }
  } 
   

  #fusa reg attr check  
#  for $i (1 .. $field_num){
#    $offset = lc($field_list[$i]->{'offset'});
#    if (grep /^$offset$/, @ecc_addr){
#      if ($field_list[$i]{'field'} ne "reserved" and $field_list[$i]{'attr'} !~/^HW$|^RW$|^W1C$/){
#        print "[ERROR]: ECC regs $field_list[$i]{'gname'} should only have RW or HW or W1C attribution\n";
#        exit 1;
#      }
#    }
#  }

  #bits check
  local $i,$j;
  local $width_sum;
  for $i(1 .. $reg_num){
    $width_sum=0;
    for $j(1 .. $field_num){
      if ($reg_list[$i]{'gname'} eq $field_list[$j]{'fname'}){
        $width_sum=$width_sum+$field_list[$j]{'width'};
      }
    }
    if ($width_sum != 32){
      print"[ERROR]: REG $reg_list[$i]{'gname'} should have total 32b field\n";
      exit 1;
    }
  }

  #reg set/clr addr
  for $i(1 .. $reg_num){
    $set_flag=0;
    $clr_flag=0;
    for $j(1 .. $field_num){
      if ($reg_list[$i]{'gname'} eq $field_list[$j]{'fname'}){
        if ($field_list[$j]->{'set'}) {
          $set_flag = 1;
          $set_addr = $field_list[$j]->{'set'};
        }
        if ($field_list[$j]->{'clr'}) {
          $clr_flag = 1;
          $clr_addr = $field_list[$j]->{'clr'};
        }
      }
    }
    if ($set_flag == 1) {
      $reg_list[$i]->{'set'} = $set_addr;
    } else {
      $reg_list[$i]{'set'} = "";
    } 

    if ($clr_flag == 1) {
      $reg_list[$i]->{'clr'} = $clr_addr;
    } else {
      $reg_list[$i]{'clr'} = "";
    }
  }
  

  return($reg_num,$field_num,\@reg_list,\@field_list,\@ecc_addr);
}

#=======================================================================
# reg file generation
# Father process : main
# Depth : main ->Gen_reg_file
#=======================================================================
sub Gen_reg_file{
  my ($addr_width,$bus,$outfileName,$reg_num,$field_num,$reg,$field,$regdef) = @_;

  my @reg_list    = @{$reg};
  my @field_list  = @{$field};


  my @return;

  print "\n";
  
  print "[INFO]: output file name is    $outfileName\n"; 
  if($regdef == 1){
    print "[INFO]: output define name is  $outdefName\n"; 
    print "[INFO]: output hdefine name is $outhdefName\n"; 
    print "[INFO]: output bit define name is $outbdefName\n\n"; 
  }
  else {
    print "\n";
}

  open(REG_FILE,">$outfileName") or die "[ERROR]:Can't create register file\n";

####copyright -by guwen
  printf REG_FILE "/*\n * Horizon Robotics\n *\n * Copyright (C) 2022 Horizon Robotics Inc.\n * All rights reserved.\n *\n * This file is auto generated by Horizon Robotics for Sigiriya Chip.\n * Version : J6B-fusa update\n * $date $username*/";

 ###1.module
  printf REG_FILE "\n//Auto generated file - Parity script $version\n";
  printf REG_FILE "\nmodule $moduleName (/*autoarg*/);\n\n";
 
  printf REG_FILE "parameter ADDR_BASE   = ${addr_width}'h0; //lower bits of the bus addr\n";
  printf REG_FILE "localparam PARITY_MODE = 0;    //0-EVEN/1-ODD\n";
  printf REG_FILE "localparam ENC_BIT     = 8;    //Number of bits to calculate parity on\n";
  printf REG_FILE "localparam DATA_WD     =32;    //Data bus width which to be protected\n";
  printf REG_FILE "localparam PARITY_WD   = 4;    //Parity bit of data bus\n";

  #preparation
  my @field_array;
  for $i(1 .. $field_num){
    push(@field_array, $field_list[$i]{'field'});
  }
    

###2.port list
  my @tmp =&Gen_rtl_iop($addr_width,$bus,$field_num,\@field_list);
  my @rtl_iop = @{$tmp[0]};
  my @ext_int= @{$tmp[1]};
  foreach $int (@ext_int){
    $int_mask = $int."_mask";
    $int_set  = $int."_set";
    if (not grep /^$int_mask$/, @field_array ){
      print "[ERROR] A $int_mask must be added for the ${int}_status enable.\n\n";
      exit 1;
    }
    if (not grep /^$int_set$/, @field_array ){
      print "[ERROR] A $int_set must be added for the ${int}_status value set.\n\n";
      exit 1;
    }
  }
  #print "port list is\n@rtl_iop";
  printf REG_FILE "\n";
  printf REG_FILE "//-----------------------------------\n";
  printf REG_FILE "//Port signals definition \n";
  printf REG_FILE "//-----------------------------------\n";
  foreach (@rtl_iop) {
    printf REG_FILE "$_";
  }
  printf REG_FILE "\n\n";

###3.auto define
  printf REG_FILE "//-----------------------------------\n";
  printf REG_FILE "//Define list\n";
  printf REG_FILE "//-----------------------------------\n";
  printf REG_FILE "/*autodefine*/

//auto wires{{{

//}}}
//auto regs{{{

//}}}
//End of automatic define
\n";

  @reg_list =&Attr_check($reg_num,$field_num,\@reg_list,\@field_list);

  my @return=&Gen_wr_logic($addr_width,$reg_num,\@reg_list,\@field_list);
  my @wr_logic  = @{$return[0]};
  my $reg_num_w = $return[1];
  my @reg_w_list = @{$return[2]};

  my ($func_num_w,$fusa_ctrl_mask, @man_def)=&Gen_man_def($reg_num_w,\@reg_list);
  foreach (@man_def) {
    printf REG_FILE "$_";
  }

###4.write logic
  printf REG_FILE "\n";
  printf REG_FILE "//-----------------------------------\n";
  printf REG_FILE "//Glue logic\n";
  printf REG_FILE "//-----------------------------------\n";
  foreach (@wr_logic) {
    printf REG_FILE "$_";
  }

###5.reg attribution decode logic
  my (@lines_attr_dec,@lines_attr_ecc)=&Gen_attr_dec($reg_num,$field_num,\@reg_list,\@field_list);
  #print "dec lines\n@lines_attr_dec";
  printf REG_FILE "\n//reg attribution logic";
  foreach (@lines_attr_dec) {
    printf REG_FILE "$_";
  }
  foreach (@lines_attr_ecc) {
    printf REG_FILE "$_";
  }
  printf REG_FILE "\n\n";

###6.ECC logic
  my @tmp =&Reg_value($reg_num,$field_num,$reg_num_w,\@reg_list, \@field_list, \@reg_w_list);
  my @reg_list   = @{$tmp[0]};
  my @reg_w_list = @{$tmp[1]};

  my @ecc_reg  =&Gen_ecc_reg($field_num,\@reg_list,\@field_list,\@ext_int);
  foreach (@ecc_reg) {
    printf REG_FILE "$_";
  }


  if (not $noecc) { #XIN20221028
    printf REG_FILE "\nassign parity_decoder_bypass = ~parity_decoder_enable;\n";
  }
  my @ecc_logic=&Gen_ecc_logic($reg_num_w,\@reg_w_list,$func_num_w,$ecc_addr,\@ext_int,$fusa_ctrl_mask);
  foreach (@ecc_logic) {
    printf REG_FILE "$_";
  }
  printf REG_FILE "\n\n";

###7.reg wr logic
  my @reg_wr = &Gen_reg_wr($reg_num,$func_num_w,$field_num,\@reg_list,\@field_list,\@ext_int);
  foreach (@reg_wr) {
    printf REG_FILE "$_";
  }
  printf REG_FILE "\n";



###8.reg rd logic
  my @reg_rd=&Gen_reg_rd($addr_width,\@reg_list,\@field_list);
  foreach (@reg_rd) {
    printf REG_FILE "$_";
  }
  printf REG_FILE "\n\n";
  
###8.reg macro define
  my @macro_def=&Gen_macro_def($moduleName,$base_addr,\@reg_list,\@field_list);
  foreach (@macro_def) {
    printf REG_FILE "$_";
  }

  
  printf REG_FILE "\n\n";
  printf REG_FILE "endmodule";
  close (REG_FILE);

  #Vim auto
  &Vim_auto ($outfileName,".");

  &Auto_def_post($outfileName,".");

  print "[INFO]: Generation DONE\n\n"; 
  print "-------------------------------\n"; 
}#sub task

#=======================================================================
# reg file - io ports generation
# Father process : Gen_reg_file
# Depth : Gen_reg_file ->Gen_rtl_iop
#=======================================================================
sub Gen_rtl_iop{
  my($addr_width,$bus,$field_num,$field) = @_;
  my @field_list = @{$field};
  my @rtl_iop=(); 
  my @ext_int=(); 
  my $width;
  
  $width=sprintf("%2d",$addr_width-1);
  push(@rtl_iop,"//APB bus interface\n");
  push(@rtl_iop,"    input             pclk;\n");
  push(@rtl_iop,"    input             presetn;\n");
  push(@rtl_iop,"    input             psel;\n");
  push(@rtl_iop,"    input             penable;\n");
  push(@rtl_iop,"    input [$width:0]      paddr;\n");
  push(@rtl_iop,"    input             pwrite;\n");
  push(@rtl_iop,"    input [31:0]      pwdata;\n");
  push(@rtl_iop,"    output[31:0]      prdata;\n");    
  if($bus =~/^APB3$/){
    push(@rtl_iop, "    output            pready;\n");
    push(@rtl_iop, "    output            pslverr;\n");
  }  

###out register signals
  push (@rtl_iop, "//output signals\n");
  for $i(1 .. $field_num){
    $field  = $field_list[$i]{'field'};
    $width  = $field_list[$i]{'width'};
    $attr   = $field_list[$i]{'attr'};
    $offset = lc($field_list[$i]{'offset'});
    $shad = $field_list[$i]{'shad'};
    if ($field_list[$i]{'width'} == 1) {
      $width=' 'x6;
    } else{
      $width=sprintf("[%-2d:0]",$width-1);
    }

    if (grep /^$offset$/, @ecc_addr){
    }
    else{
      if($field ne "reserved"){
        if(($attr ne "RO") and ($attr ne "RC")) {
          if ($shad eq '') {
            push(@rtl_iop, "    output $width     $field;\n");
          }
          if ($attr =~ /^HW$|^W1S$|^W1C$|^W0S$|^W0C$/) {
            if (($sync ==1)and $attr =~ /^HW$|^W1C$/){
              push(@rtl_iop, "    input             $field\_clk;\n");
              push(@rtl_iop, "    input             $field\_rstn;\n");
            }
            push(@rtl_iop, "    input             $field\_wr;\n");
            push(@rtl_iop, "    input  $width     $field\_in;\n");
          } 
          if ($attr =~ /^MRW$|^MWO$/) {
            push(@rtl_iop, "    input  $width     $field\_mask;\n");
          } 
        }#non-RO/RC
      }#non-reserved     
    }#non-ecc
  }#scan all field

###input register signals
  push (@rtl_iop, "//input signals\n");
  for $i(1 .. $field_num){
    $field  = $field_list[$i]{'field'};
    $width  = $field_list[$i]{'width'};
    $attr   = $field_list[$i]{'attr'};
    $offset = lc($field_list[$i]{'offset'});
    if ($width == 1) {
      $width=' 'x6;
    } else{
      $width=sprintf("[%-2d:0]",$width-1);
    }

    if (grep /^$offset$/, @ecc_addr){
    }
    else{
      if($field ne "reserved"){
        if($attr eq "RC"){
          push(@rtl_iop, "    input  $width     $field;\n");
          push(@rtl_iop, "    output $width     ${field}_cap;\n");
        }#RC
        if($attr eq "RO"){
          push(@rtl_iop, "    input  $width     $field;\n");
        }#RO
      }#non-reserved        
    }#non-ecc
  }#scan all field

#shadow register control signals
  push (@rtl_iop, "\n//shadow register signals\n");
  my @shad_group = [];
  my $num = 1;
  for $i(1 .. $field_num){
    $field= $field_list[$i]{'field'};
    $width= $field_list[$i]{'width'};
    $shad = $field_list[$i]{'shad'};
    if ($shad) {
      #$shad_hash{$field}->{'shad'} = $field;
      #$shad_hash{$field}->{'width'}= $width;
      if ($width == 1){
          $index = ' 'x 6;
      }
      else{
          $index = sprintf('[%-5s',($width-1).':0]');
      }
      push(@rtl_iop, "   output $index      ${field}_shd;\n");
      if (not grep /^$shad$/, @shad_group){
        push (@shad_group, $shad);
      } 
      $num++;
    }
  }
  push (@rtl_iop, "\n//shadow register control signals\n");
  for $num (1 .. $#shad_group){
    $shad   = $shad_group[$num];
    push(@rtl_iop, "    input             clk_${shad};\n");
    push(@rtl_iop, "    input             rst_${shad}_n;\n");
    push(@rtl_iop, "    input             shd_load_${shad};\n");
  }



###ecc signals
  push (@rtl_iop, "//ECC signals\n");
  if (not $noecc) { #XIN20221028
    push (@rtl_iop, "    output            mission_int;\n");
  }
  for $i(1 .. $field_num){
    $fname  = $field_list[$i]{'fname'};
    $field  = $field_list[$i]{'field'};
    $width  = $field_list[$i]{'width'};
    $attr   = $field_list[$i]{'attr'};
    $offset = lc($field_list[$i]{'offset'});
    $cdc    = $field_list[$i]{'cdc'};
    if (($fname !~ /Status\d*$/) and ($cdc =~'p2l')){
        print "[ERROR]: REG $fname is not FUSA status register, so it shouldn't add p2l\n";
        exit 1;
    }
    if ($width == 1){
        $index = ' 'x 6;
    }
    else{
        $index = sprintf('[%-5s',($width-1).':0]');
    }
    if ((grep /^$offset$/, @ecc_addr) and 
        #($field =~ /_status$/) and
        ($field !~ /^parity_err_status$|^reserved$/)){
        if ($attr  =~ /^HW$|^W1C$/){
          if ($cdc eq 'p2l') {
            push(@rtl_iop, "    input  $index     ${field}_pulse;\n");
          } else {
            if ($fname =~ /^FUSA_CTRL/) {
##            print "yesyesyes";
            push(@rtl_iop, "    input             $field\_wr;\n");
            } else {
            push(@rtl_iop, "    input  $index     $field\_wr;\n");}
            push(@rtl_iop, "    input  $index     $field\_in;\n");
          }
        }

        if ($field =~ /_status$/) {
            $_ = $field;
            $_=~s/_status//g;
            push (@ext_int, $_);
            push (@ext_int_width, $width);
        }
    }
    if ((grep /^$offset$/, @ecc_addr) and 
        ($fname =~ /^FUSA_CTRL/) and
        ($field !~ /^parity_decoder_enable$|^fault_injection_en$|^parity_fault_injection$|^reserved$|^parity_invert$/)){
        if ($attr ne "RO|RC"){
            push(@rtl_iop, "    output $index     $field;\n");
        }
    }
    if ((grep /^$offset$/, @ecc_addr) and 
        ($attr eq "RO")and
        ($field !~ /^reserved$/)){
        push(@rtl_iop, "    input $index      $field;\n");
    }


  }
  if (@ext_int){
      push (@rtl_iop, "//Extended error sets\n");
      for $num (0 .. $#ext_int) {
        $width = $ext_int_width[$num];
        $int = $ext_int[$num];
        if ($width == 1){
            $index = ' 'x 6;
        }
        else{
            $index = sprintf('[%-5s',($width-1).':0]');
        }
    
        $int_out = "${int}_err";
        $int_out =~s/_err_err/_err/;
        push(@rtl_iop, "    output $index     $int_out;\n");
      }
  }
  return(\@rtl_iop,\@ext_int);
}

#=======================================================================
# reg file - attrbution check
# Father process : Gen_reg_file
# Depth : Gen_reg_file ->Attr_check
#=======================================================================
sub Attr_check{
  my ($reg_num,$field_num,$reg,$field) = @_;
  my @reg_list = @{$reg};
  my @field_list = @{$field};
  my $res_field=0;
  my $w1s_field=0;
  my $w0c_field=0;
  my $w0s_field=0;
  my $w1c_field=0;
  my $wt_field=0;
  my $rc_field=0;
  my $rw_field=0;
  my $hw_field=0;
  my $ro_field=0;
  my %reg_attr;
  my $i, $j;
  my $attr_com;
  for $i (1 .. $reg_num) {
    $shad_flag=0;
    for $j (1 .. $field_num) {
      $gname = $reg_list[$i]{'gname'};
      $fname = $field_list[$j]{'fname'};
      $field = $field_list[$j]{'field'};
      $attr  = $field_list[$j]{'attr'};

      if($fname eq $gname) {
        $shad  = $field_list[$j]{'shad'};
        if ($shad) {
          $shad_flag=1;
          $shadaddr  = $field_list[$j]{'shadaddr'};
        }
        if($field=~/^reserved$/){
          $res_field=1;
        }else{
          if($attr =~ /^W1F$|^W1S$/){
            $w1s_field=1;}
          if($attr =~ /^W1C$/){
            $w1c_field=1;}
          if($attr =~ /^W0S$/){
            $w0s_field=1;}
          if($attr =~ /^W0F$|^W0C$/){
            $w0c_field=1;}
          if($attr eq "WT"){
            $wt_field=1;}
          if($attr eq "RC"){
            $rc_field=1;}
          if($attr =~ /^RW$|^MRW$|^WO$|^MWO$/){
            $rw_field=1;}
          if($attr =~ /^HW$/){
            $hw_field=1;}
          if($attr eq "RO"){
            $ro_field=1;}
        }#non-reserved bits
      }#field in current reg
    }#scan all field
    $reg_list[$i]->{'shad'} = $shad_flag;
    if ($shad_flag ==1) {
      $reg_list[$i]->{'shadaddr'} = $shadaddr;
    }
    $attr_com="$res_field,$w1s_field,$w1c_field,$w0s_field,$w0c_field,$wt_field,$rc_field,$rw_field,$hw_field,$ro_field";
    $wr_attr_com="$w1s_field,$w1c_field,$w0s_field,$w0c_field,$wt_field,$rc_field,$rw_field,$hw_field,$ro_field";
    $reg_list[$i]->{'attr_com'} = $attr_com;
    $attr_com=~s/,//g;
    $wr_attr_com=~s/,//g;
    if($attr_com    eq "1000000000"){
      $reg_list[$i]->{'reg_attr'}="RES";}
    elsif($wr_attr_com eq "100000000"){
      $reg_list[$i]->{'reg_attr'}="W1S";}
    elsif($wr_attr_com eq "010000000"){
      $reg_list[$i]->{'reg_attr'}="W1C";}
    elsif($wr_attr_com eq "001000000"){
      $reg_list[$i]->{'reg_attr'}="W0S";}
    elsif($wr_attr_com eq "000100000"){
      $reg_list[$i]->{'reg_attr'}="W0C";}
    elsif($wr_attr_com eq "000010000"){
      $reg_list[$i]->{'reg_attr'}="WT";}
    elsif($wr_attr_com eq "000001000"){
      $reg_list[$i]->{'reg_attr'}="RC";}
    elsif($wr_attr_com eq "000000100"){
      $reg_list[$i]->{'reg_attr'}="RW";}
    elsif($wr_attr_com eq "000000010"){
      $reg_list[$i]->{'reg_attr'}="HW";}
    elsif($wr_attr_com eq "000000001"){
      $reg_list[$i]->{'reg_attr'}="RO";}
    else{
       $reg_list[$i]->{'reg_attr'}="MIX";}
    $res_field=0;
    $w1s_field=0;
    $w1c_field=0;
    $w0s_field=0;
    $w0c_field=0;
    $wt_field=0;
    $rc_field=0;
    $rw_field=0;
    $hw_field=0;
    $ro_field=0;
  }
  return(@reg_list);
}
#=======================================================================
# reg file - REG default value handle
# Father process : Gen_ecc_logic
# Depth : Gen_ecc_logic -> Reg_value
#=======================================================================
sub Reg_value{
  my ($reg_num,$field_num,$reg_w_num,$reg,$field,$reg_w)=@_;
  my @reg_list   = @{$reg};
  my @field_list = @{$field};
  my @reg_w_list = @{$reg_w};
  my $reg_num_w,$reg_value;
  my $str;

  for $i(1 .. $reg_num){
    $reg_value="{};"; 
    $gname    = $reg_list[$i]{'gname'};
    $reg_attr = $reg_list[$i]{'reg_attr'};
    if ($reg_attr ne "RO" and $reg_attr ne "RES"){
      $reg_num_w++;

      for $j (1 .. $field_num){
        $fname   = $field_list[$j]{'fname'};

        $field   = $field_list[$j]{'field'};
        $width   = $field_list[$j]{'width'};
        $value   = $field_list[$j]{'value'};
        if($gname eq $fname){
          $str=$value;
          $str=~s/\s*//g;
          $str=~/(\d*)'(\w)(.*)/;
          $radix=$2;
          $str=$3;

          if($field eq "reserved") {
            $reg_value=~s/\};/,${width}'h0\};/g;
          }
          else{
            $reg_value=~s/\};/,${width}'$radix$str\};/g;
          }
        }
#    print "reg_num is $reg_num_w, gname=$gname, num=$j, fname = $fname, reg_value = $reg_value\n";
      }
      $reg_value=~s/\{,/\{/g;
      $reg_w_list[$reg_num_w]{'gname'}    =$gname;
#      print "reg_num_w = $reg_num_w, gname = $reg_w_list[$reg_num_w]{'gname'}\n";
      $reg_w_list[$reg_num_w]{'reg_value'}=$reg_value;
#      print "reg_value = $reg_value\n";
    }#scan all non-RO reg
  }#scan all reg

  for $i(1 .. $reg_num){
    $reg_value="{};"; 
    $reg_mask ="{};"; 
    $gname    = $reg_list[$i]{'gname'};
    $reg_attr = $reg_list[$i]{'reg_attr'};

    for $j (1 .. $field_num){
        $fname   = $field_list[$j]{'fname'};
        $field   = $field_list[$j]{'field'};
        $attr    = $field_list[$j]{'attr'};
        $msb     = $field_list[$j]{'msb'};
        $lsb     = $field_list[$j]{'lsb'};
        $value   = $field_list[$j]{'value'};
        
        $width   = $msb-$lsb+1;

      if($gname eq $fname){
        $deft=$value;
        $deft=~s/\s*//g;
        $deft=~/(\d*)'(\w)(.*)/;
        $deft=$3;
        
        $radix = $2;

        ##reg mask
        if($field =~ /^reserved$/ or $attr =~ /^RO$|^RC$/){
          $mask='0' x $width;
        }else {
          $mask='1' x $width;
        }

        $reg_mask=~s/\};/$mask\};/g;

        ##reg default value---hex format
        #if($field eq "reserved") {
        #  $reg_value=~s/\};/,${width}'h0\};/g;
        #}
        #else{
        #  $reg_value=~s/\};/,${width}'h$deft\};/g;
        #}
        if ($radix eq 'b'){
          $deft=sprintf('%0*b', $width,$deft);
          #$deft=$deft;
        }elsif($radix eq 'o'){
          $deft=sprintf('%0*b', $width,oct($deft));
        }elsif($radix eq 'd'){
          $deft=sprintf('%0*b', $width,int($deft));
        }elsif($radix eq 'h'){
          $deft=sprintf('%0*b', $width,hex($deft));
        }else{
          $deft=sprintf('%0*b', $width,0);
        }

          $reg_value=~s/\};/$deft\};/g;



      }
    }
    $reg_value=~s/\{//;
    $reg_value=~s/};//;
    $reg_value=sprintf('%0*x', 8, oct("0b$reg_value"));
    $reg_list[$i]{'reg_value'}=uc($reg_value);

    $reg_mask=~s/\{//;
    $reg_mask=~s/};//;
    $reg_mask=sprintf('%0*x', 8, oct("0b$reg_mask"));
    $reg_list[$i]{'reg_mask'}=uc($reg_mask);

  }#scan all reg
  return(\@reg_list, \@reg_w_list);
}

#=======================================================================
# reg file - wr logic generation
# Father process : Gen_reg_file
# Depth : Gen_reg_file ->Gen_wr_logic
#=======================================================================
sub Gen_wr_logic{
  my ($addr_width,$reg_num,$reg,$field)= @_;
  my @reg_list = @{$reg};
  my @field_list=@{$field};
  

  $addr_msb   = $addr_width-1;
  $addr_cut   = $addr_width-2;
  $addr_cut_msb = $addr_cut-1;

  local $i,$j;
  local @list;
  local $reg_num_w;
  my @reg_w_list;
  my @tmp_wr=();
  my @addr_param=();
  push (@addr_param, "//local parameters\n");



  push (@wr_logic, "//register write logic\n");
  push (@wr_logic, "assign  apb_wr = psel & penable & pwrite;\n");
  push (@wr_logic, "assign  apb_rd = psel & ~penable & ~pwrite;\n");
  push (@wr_logic, "\n");

  push (@wr_logic, "//BUS addr parameter");
  for $i(1 .. $reg_num){
  ##reg field attr proc
    $gname    = $reg_list[$i]{'gname'};
    $gname_uc = uc($gname);
    $offset   = lc($reg_list[$i]{'offset'});
    $reg_attr = $reg_list[$i]{'reg_attr'};
    $attr_com = $reg_list[$i]{'attr_com'};
    $shadaddr = $reg_list[$i]{'shadaddr'};
    $setaddr  = $reg_list[$i]{'set'};
    $clraddr  = $reg_list[$i]{'clr'};
    $attr_com=~s/,//g;

    @list = split//,$attr_com;
    @list = reverse(@list);
    my $hwr_group=sprintf("%-34s",("hwr_".$gname));
    my $hrd_group=sprintf("%-34s",("hrd_".$gname));
    my $hrm_group=sprintf("%-34s",("hrm_".$gname));
    my $hwr_set=sprintf("%-34s",("hwr_"."${gname}_set"));
    my $hwr_clr=sprintf("%-34s",("hwr_"."${gname}_clr"));

    my $addr = hex($offset);
    $addr = sprintf("%x",$addr);
    my $addr_vcut = hex($offset)/4;
    $addr_vcut = sprintf("%x",$addr_vcut);

    my $addr_shd_cut = hex($shadaddr)/4;
    $addr_shd_cut = sprintf("%x",$addr_shd_cut);

    #parameter generation
    push (@addr_param, "//'h$addr\n");
    push (@addr_param, sprintf ("localparam [${addr_cut_msb}:0] %-35s = ADDR_BASE[%-2s:2] + $addr_cut\'h$addr_vcut ;\n", "${gname_uc}","$addr_msb"));
    if ($setaddr) {
      push (@addr_param, sprintf ("localparam [${addr_cut_msb}:0] %-35s = ADDR_BASE[%-2s:2] + $addr_cut\'h$addr_vcut + ($addr_width\'h$setaddr>>2) ;\n","${gname_uc}_set","$addr_msb"));
    }
    if ($clraddr) {
      push (@addr_param, sprintf ("localparam [${addr_cut_msb}:0] %-35s = ADDR_BASE[%-2s:2] + $addr_cut\'h$addr_vcut + ($addr_width\'h$clraddr>>2) ;\n","${gname_uc}_clr","$addr_msb"));
    }
    if ($shadaddr) {
      push (@addr_param, sprintf ("localparam [${addr_cut_msb}:0] %-35s = ADDR_BASE[%-2s:2] + $addr_cut\'h$addr_shd_cut ;\n","${gname_uc}_SHD","$addr_msb"));
    }
    
    my $blank = ' ' x 51;
    if ($reg_attr ne "RO" and $reg_attr ne "RES"){
      $reg_num_w=$reg_num_w+1;
      $reg_w_list[$reg_num]->{'gname'} = $gname;
      $reg_w_list[$reg_num]->{'offset'} = $addr;

      $addrh = lc($addr."h");
      #if($addrh eq $ecc_addr[0]){
      if (grep /^$offset$/, @ecc_addr) {
        if (($offset eq $ecc_addr[0])) {
          #push (@tmp_wr, "assign $hwr_group = apb_wr && (paddr[$addr_msb:2] == $addr_cut\'h$addr_cut);\n");
          push (@tmp_wr, "assign $hwr_group = apb_wr && (paddr[$addr_msb:2] == $gname_uc);\n");
        } 
        #elsif((grep /^$addrh$/, @ecc_addr) and ($addrh ne $ecc_addr[0])){
        elsif(($offset ne $ecc_addr[0])){
          push (@tmp_wr, "assign $hwr_group = apb_wr && (paddr[$addr_msb:2] == $gname_uc)\n");
          push (@tmp_wr, "$blank&& (passwd==32'h95f2d303);\n");
      
         if ( $setaddr | $clraddr) {
         print "[ERROR]: REG $gname Field $offset is fusa register, so it shouldn't add set/clear feature\n";
          exit 1;
        }  
         

        }
      }else{
          push (@tmp_wr, "assign $hwr_group = apb_wr && (paddr[$addr_msb:2] == $gname_uc);\n");
          if ($setaddr) {
            push (@tmp_wr, "assign ${hwr_set} = apb_wr && (paddr[$addr_msb:2] == ${gname_uc}_set);\n");
          }
          if ($clraddr) {
            push (@tmp_wr, "assign ${hwr_clr} = apb_wr && (paddr[$addr_msb:2] == ${gname_uc}_clr);\n");
          }
    
          if($list[3] ==1){
            push (@tmp_wr, "assign $hrd_group = apb_rd && (paddr[$addr_msb:2] == $gname_uc);\n");
          }
      }
    }
  }
  push (@tmp_wr, "\n");

  

  push (@wr_logic, @addr_param);
  push (@wr_logic, "\n\n//BUS wr access signal for each register\n");
  push (@wr_logic, @tmp_wr);
  return (\@wr_logic,$reg_num_w,\@reg_w_list);
} 

#=======================================================================
# reg file - attrbution decode
# Father process : Gen_reg_file
# Depth : Gen_reg_file ->Gen_attr_dec
#=======================================================================
sub Gen_attr_dec{
  my($reg_num,$field_num,$reg,$field) = @_;
  my @reg_list  = @{$reg};
  my @field_list= @{$field};
  ###
  my $res, $w1c, $w1s, $wt;
  my $rc, $wr, $hw, $hwdata;
  my $i,$j,$num=0;
  my @list;
  my @lines_attr_dec;
  my @lines_attr_ecc;
  my $sc;
  for $i (1 .. $reg_num){
    my $str_sync='';
    my $gname    = $reg_list[$i]{'gname'};
    my $offset   = lc($reg_list[$i]{'offset'});
    my $attr_com = $reg_list[$i]{'attr_com'};
    my $reg_attr = $reg_list[$i]{'reg_attr'};
    $setaddr = $reg_list[$i]{'set'};
    $clraddr = $reg_list[$i]{'clr'};
    if ($reg_attr ne "RO" and $reg_attr ne "RES"){
      $num++;
      $attr_com=~s/,//g;
      @list = split//,$attr_com;
      @list = reverse(@list);
      $sc = join '', @list[8,7,6,5];
      $sc = sprintf("%s",$sc);
      $res="{};"; 
      $w1s="{};";
      $w1c="{};";
      $w0s="{};";
      $w0c="{};";
      $wt="{};";
      $rc="{};";
      $wr="{};";
      $hw="{};";
      $hwdata="{};";
      if ($list[9] ==0) {$res="32'h0;"};
      if (($list[8] ==0) and (not $setaddr)) {$w1s="32'h0;"};
      if (($list[7] ==0) and (not $clraddr)) {$w1c="32'h0;"};
      if ($list[6] ==0) {$w0s="32'h0;"};
      if ($list[5] ==0) {$w0c="32'h0;"};
      if ($list[4] ==0) {$wt="32'h0;"};
      if ($list[3] ==0) {$rc ="32'h0;"};
      if (($list[2] ==0)&($list[1]==0)) {$wr ="32'h0;"};
      if (($list[1] ==0)&($list[3]==0)&($sc eq '0000')){$hw ="32'h0;"}; 
      if (($list[1] ==0)&($list[3]==0)&($sc eq '0000')){$hwdata ="32'h0;"};
        
      my $k;
      my $blank =' ' x 36;
      for $j (1 .. $field_num){
        $fname = $field_list[$j]{'fname'};
        $field = $field_list[$j]{'field'};
        $attr  = $field_list[$j]{'attr'};
        $width = $field_list[$j]{'width'};
        $setaddr = $field_list[$j]{'set'};
        $clraddr = $field_list[$j]{'clr'};
        if ($fname eq $gname){
          $hwr_reg = "hwr_".$fname;
          $hrd_reg = "hrd_".$fname;
          $hrm_group="hrm_".$gname;
          $hw_field=$field."_wr";
          $hw_data =$field."_in";
          if ($attr =~ /^W1C$|^HW$/){
          $str_sync.="
wire     ${hw_field}_sync;
cdc_pulse_level_sync u_pulse_level_${hw_field} (.clk_s(${field}_clk),.rstn_s(${field}_rstn),.pulse_s(${hw_field}),
                                             .clk_d(pclk),.rstn_d(presetn),.pulse_d(${hw_field}_sync));
";
          }
            if($width==1){
              $wr_tmp=$hwr_reg;
              $mwr_tmp=$hwr_reg." & ~".$field."_mask";
              $wr_setaddr="${hwr_reg}_set";
              $wr_clraddr="${hwr_reg}_clr";}
            elsif($width==32){
              $wr_tmp="32{".$hwr_reg."}";
              $mwr_tmp="{32{".$hwr_reg."}}"." & ~".$field."_mask";
              $wr_setaddr="32{${hwr_reg}_set\}";
              $wr_clraddr="32{${hwr_reg}_clr\}";}
            else{
              $wr_tmp="{".$width."{".$hwr_reg."}}";
              $mwr_tmp="{".$width."{".$hwr_reg."}}"." & ~".$field."_mask";
              $wr_setaddr="{".$width."{${hwr_reg}_set\}\}";
              $wr_clraddr="{".$width."{${hwr_reg}_clr\}\}";}
            $wr_tmp=$blank.$wr_tmp;
            $wr_tmp=(",\n".$wr_tmp) and ($width!=32);
            $mwr_tmp=$blank.$mwr_tmp;
            $mwr_tmp=(",\n".$mwr_tmp) and ($width!=32);
            $wr_setaddr=$blank.$wr_setaddr;
            $wr_setaddr=(",\n".$wr_setaddr) and ($width!=32);
            $wr_clraddr=$blank.$wr_clraddr;
            $wr_clraddr=(",\n".$wr_clraddr) and ($width!=32);

            if($width==1){
              $hw_tmp=$hw_field;
              $hwd_tmp=$hw_data;
              $hw_tmp_sync=$hw_field."_sync";
            }
            elsif($width==32){
              $hw_tmp="32{".$hw_field."}";
              $hwd_tmp=$hw_data."[31:0]";
              $hw_tmp_sync="32{".$hw_field."_sync}";
            }
            else{
              $hw_tmp="{".$width."{".$hw_field."}}";
              $hwd_tmp=$hw_data."[".($width-1).":0]";
              $hw_tmp_sync="{".$width."{".$hw_field."_sync}}";
            }
            $hw_tmp =$blank.$hw_tmp;
            $hw_tmp =",\n".$hw_tmp;
            $hwd_tmp=$blank.$hwd_tmp;
            $hwd_tmp=",\n".$hwd_tmp;

            $hw_tmp_sync =$blank.$hw_tmp_sync;
            $hw_tmp_sync =",\n".$hw_tmp_sync;
##

          if($field =~/^reserved$/){
            if($width==1){
              $res =~s/\};/,1'b1\};/g;}
            elsif ($width==32){
              $res="{32{".$hwr_reg."}};";}
            else{
              $res =~s/\};/,{$width\{1'b1\}}\};/g;}
            $w1s=~s/\};/,$width\'h0\};/g;
            $w1c=~s/\};/,$width\'h0\};/g;
            $w0s=~s/\};/,$width\'h0\};/g;
            $w0c=~s/\};/,$width\'h0\};/g;
            $wt=~s/\};/,$width\'h0\};/g;
            $rc =~s/\};/,$width\'h0\};/g;
            $wr =~s/\};/,$width\'h0\};/g;
            $hw =~s/\};/,$width\'h0\};/g;
            $hwdata =~s/\};/,$width\'h0\};/g;
          }
          elsif(($attr =~ /^W1F$|^W1S$/)){
            $res=~s/\};/,$width\'h0\};/g;
            if($width==1){
              $w1s=~s/\};/,$hwr_reg\};/g;}
            elsif($width==32){
              $w1s="{32{".$hwr_reg."}};";}
            else{
              $w1s=~s/\};/,{$width\{$hwr_reg\}}\};/g;}
            $w1c=~s/\};/,$width\'h0\};/g;
            $w0s=~s/\};/,$width\'h0\};/g;
            $w0c=~s/\};/,$width\'h0\};/g;
            $wt=~s/\};/,$width\'h0\};/g;
            $rc =~s/\};/,$width\'h0\};/g;
            $wr =~s/\};/,$width\'h0\};/g;
            if ($attr =~ /^W1S$/){
              $hw =~s/\};/$hw_tmp\};/g;
              $hwdata =~s/\};/$hwd_tmp\};/g;
            } elsif ($attr =~ /^W1F$/){
              $hw =~s/\};/,$width\'h0\};/g;
              $hwdata =~s/\};/,$width\'h0\};/g;
            }
          }
          elsif(($attr eq "W1C")){
            $res=~s/\};/,$width\'h0\};/g;
            $w1s=~s/\};/,$width\'h0\};/g;
            if($width==1){
              $w1c=~s/\};/,$hwr_reg\};/g;}
            elsif($width==32){
              $w1c="{32{".$hwr_reg."}};";}
            else{
              $w1c=~s/\};/,{$width\{$hwr_reg\}}\};/g;}
            $w0s=~s/\};/,$width\'h0\};/g;
            $w0c=~s/\};/,$width\'h0\};/g;
            $wt=~s/\};/,$width\'h0\};/g;
            $rc =~s/\};/,$width\'h0\};/g;
            $wr =~s/\};/,$width\'h0\};/g;
            if ($sync==0){
              $hw =~s/\};/$hw_tmp\};/g;
              $hwdata =~s/\};/$hwd_tmp\};/g;
            } elsif($sync==1){
              $hw =~s/\};/$hw_tmp_sync\};/g;
              $hwdata =~s/\};/$hwd_tmp\};/g;
            }
          }
          elsif($attr eq "W0S"){
            $res=~s/\};/,$width\'h0\};/g;
            $w1s=~s/\};/,$width\'h0\};/g;
            $w1c=~s/\};/,$width\'h0\};/g;
            if($width==1){
              $w0s=~s/\};/,$hwr_reg\};/g;}
            elsif($width==32){
              $w0s="{32{".$hwr_reg."}};";}
            else{
              $w0s=~s/\};/,{$width\{$hwr_reg\}}\};/g;}
            $w0c=~s/\};/,$width\'h0\};/g;
            $wt=~s/\};/,$width\'h0\};/g;
            $rc =~s/\};/,$width\'h0\};/g;
            $wr =~s/\};/,$width\'h0\};/g;
            $hw =~s/\};/$hw_tmp\};/g;
            $hwdata =~s/\};/$hwd_tmp\};/g;
          }
          elsif($attr =~ /^W0F$|^W0C$/ ){
            $res=~s/\};/,$width\'h0\};/g;
            $w1s=~s/\};/,$width\'h0\};/g;
            $w1c=~s/\};/,$width\'h0\};/g;
            $w0s=~s/\};/,$width\'h0\};/g;
            if($width==1){
              $w0c=~s/\};/,$hwr_reg\};/g;}
            elsif($width==32){
              $w0c="{32{".$hwr_reg."}};";}
            else{
              $w0c=~s/\};/,{$width\{$hwr_reg\}}\};/g;}
            $wt=~s/\};/,$width\'h0\};/g;
            $rc =~s/\};/,$width\'h0\};/g;
            $wr =~s/\};/,$width\'h0\};/g;
            if ($attr =~ /^W0C$/){
              $hw =~s/\};/$hw_tmp\};/g;
              $hwdata =~s/\};/$hwd_tmp\};/g;
            } elsif ($attr =~ /^W0F$/){
              $hw =~s/\};/,$width\'h0\};/g;
              $hwdata =~s/\};/,$width\'h0\};/g;
            }
          }
          elsif($attr eq "WT"){
            $res=~s/\};/,$width\'h0\};/g;
            $w1s=~s/\};/,$width\'h0\};/g;
            $w1c=~s/\};/,$width\'h0\};/g;
            $w0s=~s/\};/,$width\'h0\};/g;
            $w0c=~s/\};/,$width\'h0\};/g;
            if($width==1){
              $wt=~s/\};/,$hwr_reg\};/g;}
            elsif($width==32){
              $wt="{32{".$hwr_reg."}};";}
            else{
              $wt=~s/\};/,{$width\{$hwr_reg\}}\};/g;}
            $rc =~s/\};/,$width\'h0\};/g;
            $wr =~s/\};/,$width\'h0\};/g;
            $hw =~s/\};/,$width\'h0\};/g;
            $hwdata =~s/\};/,$width\'h0\};/g;
          }

          elsif($attr eq "RC"){
            $data=$field;
            $res=~s/\};/,$width\'h0\};/g;
            $w1s=~s/\};/,$width\'h0\};/g;
            $w1c=~s/\};/,$width\'h0\};/g;
            $w0s=~s/\};/,$width\'h0\};/g;
            $w0c=~s/\};/,$width\'h0\};/g;
            $wt=~s/\};/,$width\'h0\};/g;
            if($width==1){
              $rc=~s/\};/,$hrd_reg\};/g;
              $hw=~s/\};/,$data\};/g;
              $hwdata=~s/\};/,$data\};/g;
            }
            elsif($width==32){
              $rc="{32{".$hrd_reg."}};";
              $hw=$data.'[31:0];';
              $hwdata=$data.'[31:0];';
            }
            else{
              $rc=~s/\};/,\{$width\{$hrd_reg\}\}\};/g;
              $hw=~s/\};/,$data\};/g;
              $hwdata=~s/\};/,$data\};/g;
            }
            $wr =~s/\};/,$width\'h0\};/g;
          }
          elsif($attr =~ /^RW$|^WO$/){
            $res=~s/\};/,$width\'h0\};/g;
            if (not $setaddr) {
              $w1s=~s/\};/,$width\'h0\};/g;
            }
            if (not $clraddr) {
              $w1c=~s/\};/,$width\'h0\};/g;
            }
            $w0s=~s/\};/,$width\'h0\};/g;
            $w0c=~s/\};/,$width\'h0\};/g;
            $wt=~s/\};/,$width\'h0\};/g;
            $rc =~s/\};/,$width\'h0\};/g;
            $wr =~s/\};/$wr_tmp\};/g;
            $hw =~s/\};/,$width\'h0\};/g;
            $hwdata =~s/\};/,$width\'h0\};/g;
          }
          elsif($attr =~ /^MRW$|^MWO$/){
            $res=~s/\};/,$width\'h0\};/g;
            if (not $setaddr) {
              $w1s=~s/\};/,$width\'h0\};/g;
            }
            if (not $clraddr) {
              $w1c=~s/\};/,$width\'h0\};/g;
            }
            $w0s=~s/\};/,$width\'h0\};/g;
            $w0c=~s/\};/,$width\'h0\};/g;
            $wt=~s/\};/,$width\'h0\};/g;
            $rc =~s/\};/,$width\'h0\};/g;
            $wr =~s/\};/$mwr_tmp\};/g;
            $hw =~s/\};/,$width\'h0\};/g;
            $hwdata =~s/\};/,$width\'h0\};/g;
          }
          elsif($attr eq "HW"){
            $res=~s/\};/,$width\'h0\};/g;
            if (not $setaddr) {
              $w1s=~s/\};/,$width\'h0\};/g;
            }
            if (not $clraddr) {
              $w1c=~s/\};/,$width\'h0\};/g;
            }
            $w0s=~s/\};/,$width\'h0\};/g;
            $w0c=~s/\};/,$width\'h0\};/g;
            $wt=~s/\};/,$width\'h0\};/g;
            $rc =~s/\};/,$width\'h0\};/g;
            $wr =~s/\};/$wr_tmp\};/g;
            if ($sync==0){
              $hw =~s/\};/$hw_tmp\};/g;
              $hwdata =~s/\};/$hwd_tmp\};/g;
            } elsif($sync==1){
              $hw =~s/\};/$hw_tmp_sync\};/g;
              $hwdata =~s/\};/$hwd_tmp\};/g;
            }
          }
          elsif($attr eq "RO"){
            $res=~s/\};/,$width\'h0\};/g;
            $w1s=~s/\};/,$width\'h0\};/g;
            $w1c=~s/\};/,$width\'h0\};/g;
            $w0s=~s/\};/,$width\'h0\};/g;
            $w0c=~s/\};/,$width\'h0\};/g;
            $wt=~s/\};/,$width\'h0\};/g;
            $rc =~s/\};/,$width\'h0\};/g;
            $wr =~s/\};/,$width\'h0\};/g;
            $hw =~s/\};/,$width\'h0\};/g;
            $hwdata =~s/\};/,$width\'h0\};/g;
          }
          if ($setaddr) {
            $w1s =~s/\};/$wr_setaddr\};/g;
          }
          if ($clraddr) {
            $w1c =~s/\};/$wr_clraddr\};/g;
          }

            
        }#current reg's field
      }#scan all field
      $res =~s/\{,/\{/g; 
      $w1s =~s/\{,/\{/g; 
      $w1c =~s/\{,/\{/g;  
      $w0s =~s/\{,/\{/g; 
      $w0c =~s/\{,/\{/g;  
      $wt  =~s/\{,/\{/g; 
      $rc  =~s/\{,/\{/g; 
      $wr  =~s/\{,/\{/g; 
      $hw  =~s/\{,/\{/g; 
      $hwdata=~s/\{,/\{/g;
      my $addr = hex ($offset);
      $addr = sprintf("%x",$addr);

      $addr_format = lc($addr).'h';
      if ($gname =~ /^PASSWORD$|Set\d*$|Status\d*$/){
        $num = $num-1;
      }
      $index = $num-1;
      #if (not grep /^$addr_format$/, @ecc_addr){
##      if (not grep /^$offset$/, @ecc_addr){
      if (not $gname =~ /^PASSWORD$|Set\d*$|Status\d*$/){
        push (@lines_attr_dec, "\n// address $addr\n");
        if ($sync==1){
          push (@lines_attr_dec,$str_sync);
        }
        #if($reg_i_rem == 0){
        push (@lines_attr_dec,"assign reg_data_res[$index][31:0] = $res\n");
        push (@lines_attr_dec,"assign reg_data_w1s[$index][31:0] = $w1s\n");
        push (@lines_attr_dec,"assign reg_data_w1c[$index][31:0] = $w1c\n");
        push (@lines_attr_dec,"assign reg_data_w0s[$index][31:0] = $w0s\n");
        push (@lines_attr_dec,"assign reg_data_w0c[$index][31:0] = $w0c\n");
        push (@lines_attr_dec,"assign reg_data_wt[$index][31:0]  = $wt\n");
        push (@lines_attr_dec,"assign reg_data_rc[$index][31:0]  = $rc\n");
        push (@lines_attr_dec,"assign reg_data_wr[$index][31:0]  = $wr\n");
        push (@lines_attr_dec,"assign reg_data_hw[$index][31:0]  = $hw\n");
        push (@lines_attr_dec,"assign hw_wdata[$index][31:0]         = $hwdata\n");
##        print "the name is $gname, the index is $index\n";
        #}
        #else{
        #  push (@lines_attr_dec,"assign reg_data_res[$reg_num_quot][63:32]= $res\n");
        #  push (@lines_attr_dec,"assign reg_data_w1s[$reg_num_quot][63:32] = $w1s\n");
        #  push (@lines_attr_dec,"assign reg_data_w1c[$reg_num_quot][63:32] = $w1c\n");
        #  push (@lines_attr_dec,"assign reg_data_w0s[$reg_num_quot][63:32] = $w0s\n");
        #  push (@lines_attr_dec,"assign reg_data_w0c[$reg_num_quot][63:32] = $w0c\n");
        #  push (@lines_attr_dec,"assign reg_data_wt[$reg_num_quot][63:32] = $wt\n");
        #  push (@lines_attr_dec,"assign reg_data_rc[$reg_num_quot][63:32] = $rc\n");
        #  push (@lines_attr_dec,"assign reg_data_wr[$reg_num_quot][63:32] = $wr\n");
        #  push (@lines_attr_dec,"assign reg_data_hw[$reg_num_quot][63:32] = $hw\n");
        #  push (@lines_attr_dec,"assign hw_wdata[$reg_num_quot][63:32]        = $hwdata\n");
        #}
        } ### non-ecc reg
     }
  }#scan all reg
  #$total_rem  = ($num-6-1)%2;
  #$total_quot = ($num-6-1)/2;
  #push (@lines_attr_dec,"\n//Zero fill\n");
  #if ($total_rem == 0) {
  #      push (@lines_attr_dec,"assign reg_data_res[$total_quot][63:32] = 32'h0;\n");
  #      push (@lines_attr_dec,"assign reg_data_w1s[$total_quot][63:32] = 32'h0;\n");
  #      push (@lines_attr_dec,"assign reg_data_w1c[$total_quot][63:32] = 32'h0;\n");
  #      push (@lines_attr_dec,"assign reg_data_w0s[$total_quot][63:32] = 32'h0;\n");
  #      push (@lines_attr_dec,"assign reg_data_w0c[$total_quot][63:32] = 32'h0;\n");
  #      push (@lines_attr_dec,"assign reg_data_wt[$total_quot][63:32]  = 32'h0;\n");
  #      push (@lines_attr_dec,"assign reg_data_rc[$total_quot][63:32]  = 32'h0;\n");
  #      push (@lines_attr_dec,"assign reg_data_wr[$total_quot][63:32]  = 32'h0;\n");
  #      push (@lines_attr_dec,"assign reg_data_hw[$total_quot][63:32]  = 32'h0;\n");
  #      push (@lines_attr_dec,"assign hw_wdata[$total_quot][63:32]         = 32'h0;\n");
  #}
  return(@lines_attr_dec, @lines_attr_ecc);
}


#=======================================================================
# reg file - ecc logic generation
# Father process : Gen_reg_file
# Depth : Gen_reg_file ->Gen_ecc_reg
#=======================================================================
sub Gen_ecc_reg{
  my ($field_num, $reg, $field, $int) =@_;
  my @reg_list = @{$reg};
  my @field_list=@{$field};
  my @ext_int   =@{$int};

  unshift (@ext_int, "parity_err");
  my $index;
  my @ecc_reg=();
  push (@ecc_reg, "//---ECC register wr logic\n");
  for $i (1 ..$reg_num){
    $offset= lc($reg_list[$i]{'offset'});
    $gname = $reg_list[$i]{'gname'};
    $reg_attr = $reg_list[$i]{'reg_attr'};

    $w1c_flag = 0;
    if ((grep /^$offset$/, @ecc_addr) and ($reg_attr ne "RO")){
      if ($gname =~ /^PASSWORD$|^FUSA_CTRL|Mask\d*$/){
        if ($gname =~ /^PASSWORD$/){
        for $j (1 .. $field_num){
          $fname = $field_list[$j]{'fname'};
          $field = $field_list[$j]{'field'};
          $value = $field_list[$j]{'value'};
          $attr  = $field_list[$j]{'attr'};
          $msb   = $field_list[$j]{'msb'};
          $lsb   = $field_list[$j]{'lsb'};
          $cdc   = $field_list[$j]{'cdc'};
          $width = $msb-$lsb+1;
          if (($gname eq $fname)){
            if ($attr eq 'W1C') {
              $w1c_flag = 1;
            }
          if ($cdc eq 'p2l') {
            if ($width == 1 ){
              $hw_in = "${field}_level";
              push (@ecc_reg,"
  cdc_pulse_expend_level_sync_d u_cdc_pulse_2_level_$field (
    .pulse_d  (${field}_level),
    .clk_d    (pclk ),
    .rstn_d   (presetn),
    .sync_s   (${field}_pulse)
  );
");
          } else {
            $msb = $width-1;
            $hw_in = "${field}_level[$msb:0]";
            for $num (0 .. $width-1) {
              push (@ecc_reg,"
  cdc_pulse_expend_level_sync_d u_cdc_pulse_2_level_${field}_${num} (
    .pulse_d  (${field}_level[$num]),
    .clk_d    (pclk ),
    .rstn_d   (presetn),
    .sync_s   (${field}_pulse[$num])
  );
");
              }
            }
          } # p2l
          } #current reg
        }

        if ($w1c_flag eq 1) {
          for $j (1 .. $field_num){
            $fname = $field_list[$j]{'fname'};
            $field = $field_list[$j]{'field'};
            $value = $field_list[$j]{'value'};
            $attr  = $field_list[$j]{'attr'};
            $msb   = $field_list[$j]{'msb'};
            $lsb   = $field_list[$j]{'lsb'};
            $cdc   = $field_list[$j]{'cdc'};
            $width = $msb-$lsb+1;

            if (($gname eq $fname) and ($field ne 'reserved')){
              if ($attr eq 'W1C') {
                if ($cdc eq 'p2l') {
                    $maxb = $width-1;
                    if ($width == 1 ){
                      $hw_in = "${field}_level";
                    } else {
                      $hw_in = "${field}_level[$maxb:0]"
                    }
                    $hw_ctrl ="|$hw_in";
                    $hw_data ="1\'h1";
                } else {
                    $hw_ctrl ="|${field}_wr";
                    $hw_data ="${field}_in";
                }
              }

              #width
              if($width==1){
                $index = "[$msb]";
              }else{
                $index = "[$msb:$lsb]";
              }

              #value
              if($value=~/^\d+\'\w+$/){
                $value=$value;
              }
              elsif($value=~/^\'\w+$/) {
                $value=$width.$value;
              }

              push (@ecc_reg,"
  always @(posedge pclk or negedge presetn)
  begin
      if (!presetn) begin
          $field  <= $value;
      end");
              if ($attr eq 'W1C') {
                push (@ecc_reg, "
      else if ($hw_ctrl) begin");
                for $num (0 .. $width-1) {
                  $cur_bit = $lsb+$num;
                  if ($cdc eq 'p2l') {
                    push (@ecc_reg, "
          if (${field}_level\[${num}]) 
              $field\[${num}] <= ${hw_data};");
                  } else {
                    push (@ecc_reg, "
          if (${field}_wr\[${num}]) 
              $field\[${num}] <= ${hw_data}\[${num}];");
                  }
                } #scan all the sub-field            
                push (@ecc_reg, "
      end");
              } #W1C branch

              push (@ecc_reg,"
      else if (hwr_$gname) begin");
              if ($attr eq 'W1C') {
                if ($width == 1) {
                    push (@ecc_reg,"
          if (pwdata$index == 1'b1) begin
              $field  <= ~pwdata$index;
          end");
              } else {
                  for $num (0 .. $width-1) {
                    $cur_bit = $lsb+$num;
                    push (@ecc_reg,"
          if (pwdata[$cur_bit] == 1'b1)
              ${field}\[$num]  <= ~pwdata[$cur_bit];");
                    }
                }                
              } else {
                  push (@ecc_reg,"
          $field  <= pwdata$index;");
              }
              push (@ecc_reg,"
      end");

              push (@ecc_reg,"
  end
              ");
        
            }#current reg
          } #scan all field
        }#with W1C registers
        

        else {
        push (@ecc_reg,"
  always @(posedge pclk or negedge presetn)
  begin
      if (!presetn) begin");

        for $j (1 .. $field_num){
          $fname = $field_list[$j]{'fname'};
          $field = $field_list[$j]{'field'};
          $value = $field_list[$j]{'value'};
          $attr  = $field_list[$j]{'attr'};
          $msb   = $field_list[$j]{'msb'};
          $lsb   = $field_list[$j]{'lsb'};
          $cdc   = $field_list[$j]{'cdc'};
          $width = $msb-$lsb+1;
          #width
          if($width==1){
            $index = "[$msb]";
          }else{
            $index = "[$msb:$lsb]";
          }

          #value
          if($value=~/^\d+\'\w+$/){
            $value=$value;
          }
          elsif($value=~/^\'\w+$/) {
            $value=$width.$value;
          }
          if (($gname eq $fname) and ($field ne "reserved") and ($attr ne "RO")){
            push (@ecc_reg,"
          $field  <= $value;");
          }
        }#scan field to get current reg default value
        for $j (1 .. $field_num){
          $fname = $field_list[$j]{'fname'};
          $field = $field_list[$j]{'field'};
          $value = $field_list[$j]{'value'};
          $attr  = $field_list[$j]{'attr'};
          $msb   = $field_list[$j]{'msb'};
          $lsb   = $field_list[$j]{'lsb'};
          $cdc   = $field_list[$j]{'cdc'};
          $width = $msb-$lsb+1;
          #width
          if($width==1){
            $index = "[$msb]";
          }else{
            $index = "[$msb:$lsb]";
          }
          if ($attr eq 'W1C') {
            if ($cdc eq 'p2l') {
                $hw_ctrl ="|$hw_in";
                $hw_data ="1\'h1";
            } else {
                $hw_ctrl ="|${field}_wr";
                $hw_data ="${field}_in";
            }
            if (($gname eq $fname)){
                push (@ecc_reg, "
      end 
      else if ($hw_ctrl) begin");
                for $num (0 .. $width-1) {
                  $cur_bit = $lsb+$num;
                  if ($cdc eq 'p2l') {
                    push (@ecc_reg, "
          if (${field}_level\[${num}]) 
              $field\[${num}] <= ${hw_data};");
                  } else {
                    push (@ecc_reg, "
          if (${field}_wr\[${num}]) 
              $field\[${num}] <= ${hw_data}\[${num}];");
                  }
                } #scan all the sub-field
            }
          }
        }

        push (@ecc_reg,"
      end 
      else if (hwr_$gname) begin");

        for $j (1 .. $field_num){
          $fname = $field_list[$j]{'fname'};
          $field = $field_list[$j]{'field'};
          $value = $field_list[$j]{'value'};
          $attr  = $field_list[$j]{'attr'};
          $width = $field_list[$j]{'width'};
          $msb   = $field_list[$j]{'msb'};
          $lsb   = $field_list[$j]{'lsb'};
          $cdc   = $field_list[$j]{'cdc'};
          #width
          if($width==1){
            $index = "[$msb]";
          }else{
            $index = "[$msb:$lsb]";
          }
          if ($gname eq $fname and $field ne "reserved"){
            if ($attr eq 'W1C') {
                if ($width == 1) {
                    push (@ecc_reg,"
          if (pwdata$index == 1'b1) begin
              $field  <= ~pwdata$index;
          end");
                } else {
                    for $num (0 .. $width-1) {
                      $cur_bit = $lsb+$num;
                      push (@ecc_reg,"
          if (pwdata[$cur_bit] == 1'b1)
              ${field}\[$num]  <= ~pwdata[$cur_bit];");
                    }
                }
            } else {
            push (@ecc_reg,"
          $field  <= pwdata$index;");
            }
          }
        }#scan field to get current reg field 
        push (@ecc_reg,"
      end");
        for $j (1 .. $field_num){
            $fname = $field_list[$j]{'fname'};
            $field = $field_list[$j]{'field'};
            #print "$field_num, $field\n";
            if ($gname eq $fname and$field eq "parity_invert") {
                push (@ecc_reg,"
      else if(parity_invert_d) begin
          parity_invert <= 1'b0;
      end
            ");
            }
        }
        push (@ecc_reg,"
  end
        ");
        } #register with no W1C bits
       }
      } #password, fusa_ctrl, en, set reg
      else{
        for $j (1 .. $field_num) {
          $offset= lc($field_list[$j]{'offset'});
          $fname = $field_list[$j]{'fname'};
          $field = $field_list[$j]{'field'};
          $value = $field_list[$j]{'value'};
          $width = $field_list[$j]{'width'};
          $attr  = $field_list[$j]{'attr'};
          $msb   = $field_list[$j]{'msb'};
          $lsb   = $field_list[$j]{'lsb'};
          $cdc   = $field_list[$j]{'cdc'};
          #width
          if($width==1){
            $hvalue= "1'b1";
            $index = "[$msb]";
            $field_index = "";
          }else{
            $hvalue= "$width\{1'b1\}";
            $index = "[$msb:$lsb]";
            $field_msb = $width-1;
            $field_index = "[$field_msb:0]";
          }
          #value
          if($value=~/^\d+\'\w+$/){
            $value=$value;
          }
          elsif($value=~/^\'\w+$/) {
            $value=$width.$value;
          }
      
          $offset = lc($offset);
          if (($gname eq $fname) and 
              (grep /^$offset$/, @ecc_addr) and 
              ($fname !~ /^PASSWORD$|^FUSA_CTRL$|Mask\d$/) and 
              ($field ne "reserved") and
              ($attr ne "RO")){



            if ($fname =~ /Set\d*$/){
                if ($attr eq 'RW'){
                    print "[Error]: set should be WO attribute\n";
                    exit;
                    push (@ecc_reg,"
  always @(posedge pclk or negedge presetn)
  begin
      if (!presetn) begin
          $field  <= $value;
      end
      else if (hwr_$fname) begin
          $field  <= pwdata$index;
      end
  end
        ");
                }
            }
            elsif ((not $field=~/_status$/)){
              push (@ecc_reg,"
  always @(posedge pclk or negedge presetn)
  begin
      if (!presetn) begin
          $field  <= $value;
      end
      else if (hwr_$fname) begin
          $field  <= pwdata$index;
      end
  end
        ");
            }
#            elsif (($field=~/^parity_err_status$/)){
#              push (@ecc_reg,"
#  always @(posedge pclk or negedge presetn)
#  begin
#      if (!presetn) begin
#          $field  <= $value;
#      end
#      else if (reg_parity_error) begin
#          $field  <= $hvalue;
#      end
#      else if (hwr_MIssionIntStatusSet0 & pwdata$index) begin
#          $field  <= 1'b1;
#      end
#      else if (hwr_$fname) begin
#          if ( pwdata$index == 'b1) begin
#              $field  <= ~pwdata$index;
#          end
#      end
#  end
#        ");
#            }

            $field_pre = $field;
            $field_pre =~s/_status//g;
            if (grep /^$field_pre$/, @ext_int ){
              $set = $fname;
              $set =~s/Status/StatusSet/g;
              if ($cdc eq 'p2l') {
                if ($width == 1 ){
                  push (@ecc_reg,"
  cdc_pulse_expend_level_sync_d u_cdc_pulse_2_level_$field (
    .pulse_d  (${field}_level),
    .clk_d    (pclk ),
    .rstn_d   (presetn),
    .sync_s   (${field}_pulse)
  );
");
                } else {
                  for $num (0 .. $width-1) {
                    push (@ecc_reg,"
  cdc_pulse_expend_level_sync_d u_cdc_pulse_2_level_${field}_${num} (
    .pulse_d  (${field}_level[$num]),
    .clk_d    (pclk ),
    .rstn_d   (presetn),
    .sync_s   (${field}_pulse[$num])
  );
");
                  }
                }
              }
if ($width > 1 ) {
              push (@ecc_reg,"
  reg  [$width-1:0] $field;                          
genvar i_$field;
generate
for(i_$field=0;i_$field<$width;i_$field=i_$field+1)begin: gen_$field
");
}
      if ($width == 1) {
               push (@ecc_reg,"
reg                  $field;                          
  always @(posedge pclk or negedge presetn)
  begin
      if (!presetn) begin
          $field  <= $value;
      end");
     }
          else {       push (@ecc_reg,"
  always @(posedge pclk or negedge presetn)
  begin
      if (!presetn) begin
          $field\[i_$field\]  <= 1'b0;
      end");
            }
#######
            if ($field=~/^parity_err_status$/){
              if (not $noecc) {
                push (@ecc_reg,"
      else if (reg_parity_error) begin
          $field  <= $hvalue;
      end");
              }
            }
            elsif ($attr =~ /^HW$|^W1C$/){
              if ($cdc eq 'p2l') {
                if ($width == 1) {
                  push (@ecc_reg,"
      else if (${field}_level) begin
          $field  <= 1'b1;
      end");
                } #p2l width=1 
#######
                else {
                  push (@ecc_reg,"
      else if (${field}_level\[i_$field\]) begin");
                  #for $num (0 .. $width-1) {
                  #  $cur_bit = $lsb+$num;
          #if (${field}_level\[i_$offset\]) 
                    push(@ecc_reg," 
          ${field}\[i_$field\]  <= 1'b1;");
                  #} #scan all field bit
                  push (@ecc_reg,"
      end");
                } #p2l width>1
              } #p2l
              else {
                if ($width == 1) {
                  push (@ecc_reg,"
      else if (${field}_wr) begin
          $field  <= ${field}_in;
      end");
                } #no p2l width=1 
                else {
                  push (@ecc_reg,"
      else if (${field}_wr\[i_$field\]) begin");
                  #for $num (0 .. $width-1) {
                  #  $cur_bit = $lsb+$num;
          #if (${field}_wr\[i_$offset\]) 
                    push(@ecc_reg," 
          ${field}\[i_$field]  <= ${field}_in\[i_$field\];");
                  #} #scan all field bit
                  push (@ecc_reg,"
      end");
                } #p2l width>1
              } #no p2l
            }

        if ($width == 1) {
          push (@ecc_reg,"
      else if (hwr_$set & pwdata$index) begin
          $field  <= 1'b1;
      end");

        } else {
          push (@ecc_reg,"
      else if (hwr_$set) begin");
          #for $num (0 .. $width-1) {
          #  #$cur_bit = $lsb+$num;
            push (@ecc_reg,"
          if (pwdata[i_$field+$lsb])
              ${field}\[i_$field\]  <= 1'b1;");
          #} #scan all bit of current field
          push (@ecc_reg, "
      end");
        }
    
            push (@ecc_reg,"
      else if (hwr_$fname) begin");

            if ($attr =~ /^RW$|^HW$/) {
              push (@ecc_reg,"
          $field  <= pwdata$index;");
        } 
            if ($attr eq 'W1C') {

              if ($width == 1) {
                push (@ecc_reg,"
          if (pwdata$index == 1'b1) begin
              $field  <= ~pwdata$index;
          end");

              } else {
              #  for $num (0 .. $width-1) {
              #    #$cur_bit = $lsb+$num;
                  push (@ecc_reg,"
          if (pwdata[i_$field+$lsb\] == 1'b1)
              ${field}\[i_$field\]  <= ~pwdata[i_$field+$lsb];");

              #  }
              }
        } 
              push (@ecc_reg,"
      end
  end
        ");
         if ($width > 1 ) {
push (@ecc_reg,"
end
endgenerate
        ");
}
            }
          } #non-reserved
        }#scan all field
      }#status processing
    } #all ecc reg
  }

push (@ecc_reg,"
  always @(posedge pclk or negedge presetn)
  begin
      if (!presetn) begin
          parity_invert_d <= 1'b0;
      end

      else
          parity_invert_d <= parity_invert;
      end

  always @(posedge pclk or negedge presetn)
  begin
      if (!presetn) begin
          parity_invert_d2 <= 1'b0;
      end

      else
          parity_invert_d2 <= parity_invert_d;
      end

   assign parity_invert_posedge = parity_invert & (~parity_invert_d);
   assign parity_invert_d_posedge = parity_invert_d & (~parity_invert_d2);
   assign parity_invert_2cycle = parity_invert_posedge | parity_invert_d_posedge;
            ");

  return @ecc_reg; 
}


#=======================================================================
# reg file - ecc logic generation
# Father process : Gen_reg_file
# Depth : Gen_reg_file ->Gen_ecc_logic
#=======================================================================
sub Gen_ecc_logic{
  my ($reg_num_w,$reg_w,$func_num_w,$ecc_addr,$int,$fusa_ctrl_mask)=@_;
  my %hash_reg_value_w  =%{$value_w};
  my %hash_default_value;

  my @reg_w_list = @{$reg_w};
  my @ext_int   = @{$int};

  my $k,$str;
  my $reg_value;
  my @ecc_logic=();
  my $i,$num_r4p0=0; 
  push (@ecc_logic, "\n//--- ECC process logic\n");
  for $i(0 .. $reg_num_w-1) {
      $gname = $reg_w_list[$i+1]{'gname'};
      $value = $reg_w_list[$i+1]{'reg_value'};
#      print "reg_num=$i, and yesyes gname=$gname, value=$value\n";
      $reg_attr = $reg_w_list[$i+1]{'reg_attr'};
      $reg_value="{};";
      $offset_format=$value.'h';
      $num_r4p0=$num_r4p0+1;
##      print "num_r4p0 is $num_r4p0\n";

      if(defined $gname){
        $str=$value;
        $str=~s/\{//g;
        $str=~s/\};//g;
        $reg_value=~s/\};/,$str\};/g;
      }

      $reg_value=~s/\{,/\{/g;
      $hash_default_value{$i}=$reg_value;

#  $index_r4p0 = $num_r4p0-1;
      if ($gname =~ /^PASSWORD$|Set\d*$|Status\d*$/){
        $num_r4p0 = $num_r4p0-1;
      }
      $index_r4p0 = $num_r4p0-1;
      #if (not grep /^$addr_format$/, @ecc_addr){
##      if (not grep /^$offset$/, @ecc_addr){
      if (not $gname =~ /^PASSWORD$|Set\d*$|Status\d*$/){
       push (@ecc_logic,"assign reg_default_value[$index_r4p0][31:0] = $hash_default_value{$i}\n");

  }
}
  
  push (@ecc_logic,"
genvar i;
genvar j;
generate
  for (i=0; i<$func_num_w; i=i+1) begin: reg_data_bank
    for (j=0; j<32; j=j+1) begin: in_bank_data_l
      assign reg_enc_data_in[i][j] = 
             reg_data_res[i][j] ? 1'b0                :
             reg_data_hw[i][j]  ? hw_wdata[i][j]      :
             reg_data_w1s[i][j] ? pwdata[j]  | reg_enc_data[i][j]:
             reg_data_w1c[i][j] ? ~pwdata[j] & reg_enc_data[i][j]:
             reg_data_w0s[i][j] ? ~pwdata[j] | reg_enc_data[i][j]:
             reg_data_w0c[i][j] ? pwdata[j]  & reg_enc_data[i][j]:
             reg_data_wt[i][j]  ? ~reg_enc_data[i][j] :
             reg_data_wr[i][j]  ? pwdata[j]           :
             reg_data_rc[i][j]  ? 1'b0                :
		                          reg_enc_data[i][j]  ; 
    end
");

  if (not $noecc) {
    push (@ecc_logic,"
    assign reg_parity_update[i] = ~fault_injection_en &((|reg_data_w1s[i])| 
                                                       (|reg_data_w1c[i]) |
                                                       (|reg_data_w0s[i]) |
                                                       (|reg_data_w0c[i]) |
                                                       (|reg_data_wt[i] ) |
                                                       (|reg_data_rc[i] ) |
                                                       (|reg_data_wr[i] ) |
                                                       (|reg_data_hw[i] ))
                                | fault_injection_en & (|reg_data_wr[i] )
                                | parity_invert_2cycle; 


  end
");
  } else {
    push (@ecc_logic,"
    assign reg_parity_update[i] = ((|reg_data_w1s[i])| 
                                   (|reg_data_w1c[i]) |
                                   (|reg_data_w0s[i]) |
                                   (|reg_data_w0c[i]) |
                                   (|reg_data_wt[i] ) |
                                   (|reg_data_rc[i] ) |
                                   (|reg_data_wr[i] ) |
                                   (|reg_data_hw[i] ));
    

  end
");
  }

  push (@ecc_logic,
"endgenerate


");
#    assign reg_parity_update[i] =     (|reg_data_w1s[i]) | 
#                                      (|reg_data_w1c[i]) |
#                                      (|reg_data_w0s[i]) |
#                                      (|reg_data_w0c[i]) |
#                                      (|reg_data_wt[i] ) |
#                                      (|reg_data_rc[i] ) |
#                                      (|reg_data_wr[i] ) |
#                                      (|reg_data_hw[i] ); 
#
push (@ecc_logic,"//Default value logic\n");
###default value gen
#for $i (0 .. $reg_num_w-1){
#  push (@ecc_logic,"assign reg_default_value[$default_value_index][31:0] = $hash_default_value{$default_value_index}\n");
#}    
#
    if (not $noecc) {
        push (@ecc_logic,"
//get the parity bits of default value
generate 
  for (i=0; i<$func_num_w; i=i+1) begin: parity_default
    parity_enc #(PARITY_MODE, ENC_BIT, DATA_WD, PARITY_WD)
      u_parity_deft_enc(
        .parity_enc_bypass         (1'b0                           ), //I
        .parity_enc_data_in        (reg_default_value[i][31:0]     ), //I
        .parity_enc_parity_in      (4'h0                           ), //I
        .parity_enc_data_out       (                               ), //O
        .parity_enc_parity_out     (reg_default_value[i][35:32]    )  //O
    );
  end
endgenerate
");
        }

    if (not $noecc) {
        push (@ecc_logic,"
generate 
  for (i=0; i<$func_num_w; i=i+1) begin: reg_parity
    assign reg_enc_parity_mux[i] = parity_invert_2cycle ? (~reg_enc_parity[i]) : reg_enc_parity_out[i];

    always @(posedge pclk or negedge presetn)
      if (!presetn) begin
        reg_enc_parity[i] <= reg_default_value[i][35:32];
      end else if(reg_parity_update[i]) begin
        reg_enc_parity[i] <= reg_enc_parity_mux[i][3:0];
      end

    always @(posedge pclk or negedge presetn)
      if (!presetn) begin
        reg_enc_data[i] <= reg_default_value[i][31:0];
      end else if(reg_parity_update[i]) begin
        reg_enc_data[i] <= reg_enc_data_out[i][31:0];
      end

    parity_enc #(PARITY_MODE, ENC_BIT, DATA_WD, PARITY_WD)
      u_parity_enc(
        .parity_enc_bypass         (fault_injection_en&(|reg_data_wr[i])), //I
        .parity_enc_data_in        (reg_enc_data_in[i][31:0]   ), //I
        .parity_enc_parity_in      (parity_fault_injection     ), //I
        .parity_enc_data_out       (reg_enc_data_out[i][31:0]  ), //O
        .parity_enc_parity_out     (reg_enc_parity_out[i][3:0] )  //O
    );

    parity_dec #(PARITY_MODE, ENC_BIT, DATA_WD, PARITY_WD)
      u_parity_dec(
        .parity_dec_bypass         (parity_decoder_bypass      ), //I
        .parity_dec_data_in        (reg_enc_data[i][31:0]      ), //I
        .parity_dec_parity_in      (reg_enc_parity[i][3:0]     ), //I
        .parity_dec_data_out       (reg_dec_data_out[i][31:0]  ), //O
        .parity_dec_parity_out     (reg_dec_parity_out[i][3:0] ), //O
        .parity_dec_error          (parity_dec_error[i]        )  //O
    );
  end
endgenerate

");
        } else {
        push (@ecc_logic,"
generate 
  for (i=0; i<$func_num_w; i=i+1) begin: reg_parity
    always @(posedge pclk or negedge presetn)
      if (!presetn) begin
        reg_enc_data[i] <= reg_default_value[i][31:0];
      end else if(reg_parity_update[i]) begin
        reg_enc_data[i] <= reg_enc_data_in[i][31:0];
      end
  end
endgenerate

");
        }
  

  if (not $noecc) {
  push (@ecc_logic,"//get register parity error information\n");
  push (@ecc_logic,"\n//REG_field: reg_ecc_error_type\n");
  my $blank1=' ' x 32;
  my $blank2=' ' x 2;
#  push (@ecc_logic,"assign reg_ecc_check_status_in_raw =\n");
#  my @dec_com;
#  my $i,$ii;
#  #my $format0=sprintf("%45s",("reg_ecc_enc_error"));
#  #my $format1=sprintf("%10s",("reg_ecc_enc_error"));
#  my $format0=$blank1."reg_ecc_enc_error";
#  my $format1=$blank2."reg_ecc_enc_error";
#  for $i(0 .. $quot_func){
#    $ii=$i%2;
#    if($ii == 0){
#      $str=${format0}."[".${i}."] |";
#      push(@ecc_logic,$str);
#      if($i == $quot_func){
#        push(@ecc_logic,"\n");
#      }
#    }
#    else{
#      $str=${format1}."[".${i}."] |";
#      push(@ecc_logic,$str);
#      push(@ecc_logic,"\n");
#    }
#    if($i==$quot_func){
#      push(@ecc_logic,"\n");
#    }
#  }
#  $format0=$blank1."reg_ecc_dec_error";
#  $format1=$blank2."reg_ecc_dec_error";
#  for $i(0 .. $quot_func){
#    $ii=$i%2;
#    if($ii == 0){
#      $str=${format0}."[".${i}."] |";
#      if($i == $quot_func){
#        $str=~s/\|/;/g;
#      }
#      push(@ecc_logic,$str);
#    }
#    else{
#      $str=${format1}."[".${i}."] |";
#      if($i == $quot_func){
#        $str=~s/\|/;/g;
#      }
#      push(@ecc_logic,$str);
#      push(@ecc_logic,"\n");
#    }
#  }
#  push(@ecc_logic,"\n");

#  push(@ecc_logic,"
#fusa_tvr #(.RESET_VALUE(1'b0),
#            .DATA_WIDTH (2)) u_fusa_ecc_check_status_in(
#    .q      (reg_ecc_check_status_in[1:0]),
#    .d      (reg_ecc_check_status_in_raw[1:0]),
#    .en     (1'b1),
#    .clk    (pclk),
#    .reset_n(presetn)
#);
#
#fusa_tvr #(.RESET_VALUE(1'b0),
#            .DATA_WIDTH (2)) u_fusa_ecc_check_status_out(
#    .q      (reg_ecc_check_status_d[1:0]),
#    .d      (reg_ecc_check_status[1:0]),
#    .en     (1'b1),
#    .clk    (pclk),
#    .reset_n(presetn)
#);
#
#assign reg_ecc_check_status_wr = 
#                               {(reg_ecc_check_status_d[1] != reg_ecc_check_status_in[1]),
#                                (reg_ecc_check_status_d[0] != reg_ecc_check_status_in[0])};
#
#");
#all register parity_decode_error OR
  push (@ecc_logic,"assign reg_parity_error_or    =\n");
  $format0=$blank1."parity_dec_error";
  $format1=$blank2."parity_dec_error";
  for $i(0 .. $func_num_w-1){
    $ii=$i%2;
    if($ii == 0){
      $str=${format0}."[".${i}."] |";
    } else {
      $str=${format1}."[".${i}."] |";
    }
    if($i == $func_num_w-1){
        $str=~s/\|/;/g;
    }
    push(@ecc_logic,$str);
    if ($ii != 0) {
      push(@ecc_logic,"\n");
    } 
  }

  #if (@ext_int) {
  #  push (@ecc_logic, "\n");
  #  foreach $int (@ext_int){
  #    push (@ecc_logic,$blank1."| (~${int}_mask & ${int}_status)\n" );
  #  }
  #  push (@ecc_logic, $blank1.";\n");
  #}
  #else{
    push (@ecc_logic, "\n");
  #}

#all register parity_decode_error AND
  push (@ecc_logic,"\n\nassign reg_parity_error_and   =\n");

  $format0=$blank1."parity_dec_error";
  $format1=$blank2."parity_dec_error";
  push (@ecc_logic,"${blank1}reg_parity_error_or & \n");
  for $i(0 .. $func_num_w-1){
    $ii=$i%2;
    if($ii == 0){
      $str=${format0}."[".${i}."] &";
    } else {
      $str=${format1}."[".${i}."] &";
    }
    if($i == $func_num_w-1){
        $str=~s/&/;/g;
    }
    push(@ecc_logic,$str);
    if ($ii != 0) {
      push(@ecc_logic,"\n");
    } 
  }

    push (@ecc_logic, "\n");


#  push(@ecc_logic,"\n//REG_field:reg_uce_status");
#  push(@ecc_logic,"
#assign ecc_uce_status      = reg_ecc_error_type[1]; 
#");
#  push(@ecc_logic,"\n//REG_field:reg_ce_status");
#  push(@ecc_logic,"
#assign ecc_ce_status       = reg_ecc_error_type[0]; 
#");
  } #with ecc parity error process logic
  
  return (@ecc_logic);
}

#=======================================================================
# reg file - reg-wr generation
# Father process : Gen_reg_file
# Depth : Gen_reg_file ->Gen_reg_wr
#=======================================================================
sub Gen_reg_wr{
  my ($reg_num,$func_num_w,$field_num,$reg,$field,$int) =@_;
  my @reg_list = @{$reg};
  my @field_list=@{$field};
  my @ext_int   = @{$int};
  
  my $i, $ii, $j, $k;
  my $sig,$str,$format,$buf;
  my $msb,$lsb,$width;
  my @reg_wr;
  my $num=0;

  push(@reg_wr,"//get configuration and status data from ecc correct data\n");
  if (not $noecc){
    $data_src = "reg_dec_data_out";
  } else {
    $data_src = "reg_enc_data";
  }
  
  for $i(1 .. $reg_num){
    $gname    = $reg_list[$i]{'gname'};
    $offset   = lc($reg_list[$i]{'offset'});
    $reg_attr = $reg_list[$i]{'reg_attr'};

    push (@reg_wr,"//$offset\n");
    if($reg_attr ne 'RO' and $reg_attr ne 'RES'){    
#    elsif(not grep /^$offset$/, @ecc_addr){
      $num=$num+1;
    if($gname =~/^PASSWORD$|Set\d*$|Status\d*$/){
        $num=$num-1;
    }
    elsif(not $gname =~/^PASSWORD$|Set\d*$|Status\d*$/){
      for $j(1 .. $field_num){
        $fname = $field_list[$j]{'fname'};
        $field = $field_list[$j]{'field'};
        $attr  = $field_list[$j]{'attr'};
        $value = $field_list[$j]{'value'};
        $msb   = $field_list[$j]{'msb'};
        $lsb   = $field_list[$j]{'lsb'};
        if (($field ne "reserved") && ($attr ne "RO")){
          $width = $msb-$lsb+1;
          $width = $width-1;
          if ($width ==0) {
            $index = "";}
          else{
            $index = "[$width:0]";}
          
          if($gname eq $fname) {
            if ($attr eq "RC"){
              $sig="assign ${field}_cap$index"
            }
            elsif ($field=~/mem_cfg\d*$/) {
              $sig="assign ${field}_pre$index";
            }
            else{
              $sig="assign ${field}$index";
            }
            $format=sprintf("%-30s",$sig);
            $numi = $num-1;
            if($width ==0){
              $str="$format = ${data_src}\[$numi][$msb];";
            }else{
              $str="$format = ${data_src}\[$numi][$msb:$lsb];";
            }
            if($width ==0){
              $str="$format = $data_src\[$numi][$msb];";
            }else{
              $str="$format = $data_src\[$numi][$msb:$lsb];";
            }
            $str = $str." //deft: $value\n";
            push(@reg_wr,$str);
            if ($field=~/mem_cfg\d*$/) {
              for $k(0..$width){
                $buf = "cell_buf u_${field}_$k (.I(${field}_pre[$k]), .Z(${field}\[$k\]));\n",;
                push(@reg_wr,$buf);
              }
            }
          }
        }#non-reserved field
      }#scan all field
     }
    }#all non-RO reg
    push (@reg_wr,"\n");

  }#scan all reg

  #shadow register instance
  push(@reg_wr,"//Shadow registers\n");
  for $i(1 .. $field_num){
    $shad  = $field_list[$i]{'shad'};
    if ($shad) {
      $field = $field_list[$i]{'field'};
      $width = $field_list[$i]{'width'};
      $offset = $field_list[$i]{'offset'};
      if($width==1){
        $width_index="";
      } else{
        $width_index=$width-1;
        $width_index="[$width_index:0]";
      }


  push(@reg_wr,"
//$offset
shd_reg #($width) u_shd_reg_$field(
");
  push (@reg_wr, sprintf("    %-13s (%-20s), //I\n", ".clkin","clk_$shad"));
  push (@reg_wr, sprintf("    %-13s (%-20s), //I\n", ".rst_in_n","rst_${shad}_n"));
  push (@reg_wr, sprintf("    %-13s (%-20s), //I\n", ".reg_pre","${field}${width_index}"));
  push (@reg_wr, sprintf("    %-13s (%-20s), //I\n", ".shd_load","shd_load_$shad"));
  push (@reg_wr, sprintf("    %-13s (%-20s)  //O\n", ".reg_shadow","${field}_shd${width_index}"));
  push(@reg_wr,"
);\n")
    }#shadow reg is true
  } #scan all reg
   

  my @str_int;
  my $int;

  if (not $noecc) {
  




#push (@str_int, "  assign parity_reg_error = ~parity_err_mask & parity_err_status;");
 push (@str_int, sprintf (" assign %-16s = (%s)? %s : %s;\n","reg_parity_error","parity_invert_2cycle","reg_parity_error_and","reg_parity_error_or"));
## wangyu for bugfix
##    push (@str_int, "  
##  always @(posedge pclk or negedge presetn)
##  begin
##      if(!presetn) begin
##        parity_reg_error <= 1'b0; 
##   end 
##   else begin
##        parity_reg_error <= ~parity_err_mask & parity_err_status; 
##   end
##end
##    ");

#assign %-16s = ~%-10s & %s;\n","parity_reg_error","parity_err_mask","parity_err_status"));


  }
  if (@ext_int){
    #foreach $int (@ext_int){
    for $num (0 .. $#ext_int) {
      #push (@str_int,' 'x 25 ."| ~${int}_mask & ${int}_status\n" );
      $width = $ext_int_width[$num];
      $int = $ext_int[$num];
      if ($width == 1){
          $index = ' 'x 6;
      }
      else{
          $index = sprintf('[%-5s',($width-1).':0]');
      }
      $int_out = $int."_err";
      $int_out =~s/_err_err/_err/;
      if ($width == 1) {
        push (@str_int," 
  always @(posedge pclk or negedge presetn)
  begin
      if(!presetn) begin
        $int_out <= 1'b0; 
   end 
   else begin
        $int_out <= ~${int}_mask & ${int}_status; 
   end
end

");
      } else {
        for $bit (0 .. $width-1) {
          push (@str_int," 
  always @(posedge pclk or negedge presetn)
  begin
      if(!presetn) begin
        $int_out\[$bit] <= 1'b0; 
   end 
   else begin
        $int_out\[$bit] <= ~${int}_mask[$bit] & ${int}_status[$bit]; 
   end
end

");
        }
      }
    }
    #push (@str_int, ' 'x 23 .";\n");
  }


  push (@reg_wr,"
// register_error
@str_int");

  
  if (not $noecc) {
    push (@reg_wr,"
// mission_int, include SW parity_invert injection

  always @(posedge pclk or negedge presetn)
  begin
      if(!presetn) begin
        mission_int <= 1'b0; 
   end 
   else begin
        mission_int <= ~parity_err_mask & parity_err_status; 
   end
end


");
  }
  return(@reg_wr);
}

#=======================================================================
# reg file - reg-rd generation
# Father process : Gen_reg_file
# Depth : Gen_reg_file ->Gen_reg_rd
#=======================================================================
sub Gen_reg_rd{
  my ($addr_width,$reg,$field)=@_;
  my @reg_list  = @{$reg};
  my @field_list= @{$field};
  my $reg_num   = $#reg_list;
  my $field_num = $#field_list;

  my @reg_rd;
  my $offset,$offset_cut;
  my $i,$j;
  my $sig,$str,$blank;

  $addr_reg  =$addr_width-2;
  $addr_width=$addr_width-1;

  push (@reg_rd, "//Bus read reg logic\n");
  push (@reg_rd, "always @(*) begin\n");
  push (@reg_rd, "  case(paddr[$addr_width:2])\n");
  for $i(1 .. $reg_num) {
    
    $gname = $reg_list[$i]{'gname'};
    $gname_uc = uc($gname);
    $offset = lc($reg_list[$i]{'offset'});
    $setaddr  = lc($reg_list[$i]{'set'});
    $clraddr  = lc($reg_list[$i]{'clr'});
    $str="{};";

    #$offset = hex($offset);
    #$offset =~s/h|H//g;
    $offset_d = sprintf("%x",hex($offset));
    $offset_cmt = "//0x$offset_d";

    $offset_set = sprintf("%x",hex($offset+$setaddr));
    $offset_scmt = "//0x$offset_set";

    $offset_clr = sprintf("%x",hex($offset+$clraddr));
    $offset_ccmt = "//0x$offset_clr";

    $offseth= lc($offset_d).'h';

    #$offset_c = hex($offset_d)/4; 
    #$offset_c = sprintf("%x",$offset_c);
    #$offset_c = "      ".$addr_reg."'h".$offset_c.":";

    #$format =sprintf("%-14s",($offset_c));
    $format =sprintf("%-35s",("      ${gname_uc}:"));
    $sformat =sprintf("%-35s",("      ${gname_uc}_set:"));
    $cformat =sprintf("%-35s",("      ${gname_uc}_clr:"));

    #if (grep /^$offset$/, @ecc_addr and $gname =~/StatusSet/){
    #  $str = "32'b0;";
    #}

      for $j(1 .. $field_num){
        $fname = $field_list[$j]{'fname'};
        $field = $field_list[$j]{'field'};
        $width = $field_list[$j]{'width'};
        $attr  = $field_list[$j]{'attr'};

        if($gname eq $fname) {
          if($field_list[$j]{'width'}==1){
            $width="";
          } else{
            $width=$field_list[$j]{'width'}-1;
            $width="[$width:0]";
          }
          if($field eq "reserved"){
            $sig=$field_list[$j]{'width'}."'h0";
          } elsif($attr eq 'RC'){
            $sig=$field.'_cap'.$width;
          }elsif($attr =~ /^WO$|^MWO$/){
            $sig=$field_list[$j]{'width'}."'h0";
          }elsif(($offset eq $ecc_addr[0]) and ($gname eq "PASSWORD")){
            $sig="32'h0badbeef";
          }else{
            $sig=$field.$width;
          }
          $blank = ' ' x 45;
          $sig=$blank.$sig;
          $sig=",\n".$sig;
          $str=~s/\};/$sig\};/g;
        }#current reg's field
      }#scan all field
    $str=~s/\{,/\{/g;
    push(@reg_rd,"$offset_cmt\n");
    push(@reg_rd,"$format prdata_in = $str\n");
    if ($setaddr) {
        push(@reg_rd,"$offset_scmt\n");
        push(@reg_rd,"$sformat prdata_in = $str\n");
    }
    if ($clraddr) {
        push(@reg_rd,"$offset_ccmt\n");
        push(@reg_rd,"$cformat prdata_in = $str\n");
    }
    
  }#scan all reg
  push (@reg_rd, "//shadow register read\n");
  for $i(1 .. $reg_num) {
    
    $regshad = $reg_list[$i]{'shad'};
    if ($regshad==1) {
      $gname = $reg_list[$i]{'gname'};
      $gname_uc = uc($gname);
      $shadaddr= $reg_list[$i]{'shadaddr'};
      $str="{};";

      $shadaddr_d = sprintf("%x",hex($shadaddr));
      $addr_cmt = "//0x$shadaddr_d";

      $format =sprintf("%-35s",("      ${gname_uc}_SHD:"));

      for $j (1 .. $field_num) {
        $fname = $field_list[$j]{'fname'};
        $shad  = $field_list[$j]{'shad'};
        if($gname eq $fname) {
          if ($shad) {
            $field = $field_list[$j]{'field'};
            $width = $field_list[$j]{'width'};
            $offset = $field_list[$j]{'offset'};
            $shadaddr = $field_list[$j]{'shadaddr'};
            if($width==1){
              $width="";
            } else{
              $width=$width-1;
              $width="[$width:0]";
            }
            $sig = "${field}_shd$width";

          }#shadow reg is true
          else {
            $sig = $field_list[$j]{'width'}."'h0";
          }
          $sig=$blank.$sig;
          $sig=",\n".$sig;
          $str=~s/\};/$sig\};/g;
        }#current reg's field
      }#scan all field
      $str=~s/\{,/\{/g;
      push(@reg_rd,"$addr_cmt\n");
      push(@reg_rd,"$format prdata_in = $str\n");
    }#only if when current reg has shad attr
  }#scan all reg


  push(@reg_rd,"      default: prdata_in = 32'h0;\n");
  push(@reg_rd,"  endcase\n");
  push(@reg_rd,"end\n");

  push(@reg_rd,"
always @(posedge pclk or negedge presetn) begin
  if (!presetn) begin
    prdata               <= 32'h0;
  end else if(apb_rd) begin
    prdata               <= prdata_in;
  end
end

assign pready  = 1'b1;
assign pslverr = 1'b0;

");
  return(@reg_rd);
}#function end

#=======================================================================
# reg file - define file generation
# Father process : main
# Depth : main ->Gen_def_file
#=======================================================================
sub Gen_def_file{
  my($moduleName,$base_addr,$outdefName,$outhdefName,$number,$base_offset,$reg,$sysarray,$sys_num)=@_;
  my @reg_list = @{$reg};
  my $base_addr_upper = uc($base_addr);
  my $base_addr_hex= uc($base_addr);
  my $base_offset_upper, $base_offset_hex;
  my @sys_array = @{$sysarray};

  my $moduleName_upper = uc($moduleName);
  if ($moduleName =~/([a-zA-Z0-9]_pre_div_clk_rf)/){
    $moduleName_upper =~ s/_CLK_RF/_CLK/g;
  }
  elsif ($moduleName =~/([a-zA-Z0-9]_clk_rf)/){
    $moduleName_upper =~ s/_CLK_RF/_CLKTOP/g;
  }


  open(REG_DEF,">$outdefName") or die "[ERROR]:Can't create register define file\n";
  open(REG_HDEF,">$outhdefName") or die "[ERROR]:Can't create register hex define file\n";
####copyright
  printf REG_DEF "/*\n * Horizon Robotics\n *\n * Copyright (C) 2022 Horizon Robotics Inc.\n * All rights reserved.\n *\n * This file is auto generated by Horizon Robotics for Sigiriya Chip.\n * Version :J6B-fusa update \n * $date $username*/";
  printf REG_HDEF "/*\n * Horizon Robotics\n *\n * Copyright (C) 2022 Horizon Robotics Inc.\n * All rights reserved.\n *\n * This file is auto generated by Horizon Robotics for Sigiriya Chip.\n * Version :J6B-fusa update \n * $date $username*/";



###define  file generate
if ($sys_num == 0) {
  my $def_base_addr = "BASE_ADDR_".$moduleName_upper;

  $base_addr_upper =~ s/0X/32'h/g;
  $base_addr_hex =~ s/0X/0x/g;
  if ($number >1){
    $base_offset_upper = uc($base_offset);
    $base_offset_hex= uc($base_offset);
    $base_offset_upper =~ s/0X/32'h/g;
    $base_offset_hex =~ s/0X/0x/g;
    $base_addr_upper = "(".$base_addr_upper." + i*".$base_offset_upper.")";
    $base_addr_hex   = "(".$base_addr_hex." + i*".$base_offset_hex.")";
    $def_base_addr   = $def_base_addr."(i)";
  }

 ############
  printf REG_DEF "\n`ifndef ${moduleName_upper}_DEF_V_";
  printf REG_DEF "\n`define ${moduleName_upper}_DEF_V_\n";
  printf REG_DEF "//\n";
  printf REG_DEF "//Register offset macro defines\n";
  printf REG_DEF "//\n";
  #printf REG_DEF "\`define %-40s $base_addr_upper\n",$def_base_addr; # Base Address
  #printf REG_DEF "\`define %-40s  (%-10s + 32\'h%04x)\n"
             #,("REG_".${moduleName_upper}."_".uc$gname)."(i)", "\`".$def_base_addr,hex($offset);
      

  if ($number > 1){
    for $i(1 .. $reg_num) {
      $gname = $reg_list[$i]{'gname'};
      $offset= $reg_list[$i]{'offset'};
      printf REG_DEF "\`define %-40s  (32\'h%04x)\n"
             ,("OFST_".${moduleName_upper}."_".uc$gname), hex($offset);
    }
  }
  else{
    for $i(1 .. $reg_num) {
      $gname = $reg_list[$i]{'gname'};
      $offset= $reg_list[$i]{'offset'};
      printf REG_DEF "\`define %-40s  (32\'h%04x)\n"
             ,("OFST_".${moduleName_upper}."_".uc$gname), hex($offset);
    }
  }
  printf REG_DEF "\n`endif //${moduleName_upper}_DEF_V_\n";

###define hex file generate

####

  printf REG_HDEF "\n#ifndef ${moduleName_upper}_DEF_H_";
  printf REG_HDEF "\n#define ${moduleName_upper}_DEF_H_\n";
  printf REG_HDEF "//\n";
  printf REG_HDEF "//Register offset macro defines\n";
  printf REG_HDEF "//\n";
  #printf REG_HDEF "\#define %-40s $base_addr_hex\n",$def_base_addr; # Base Address
  if ($number > 1){
    for $i(1 .. $reg_num) {
      $gname = $reg_list[$i]{'gname'};
      $offset= $reg_list[$i]{'offset'};
      #printf REG_HDEF "\#define %-40s  (%-10s + 0x%04x)\n"
            # ,("REG_".${moduleName_upper}."_".uc$gname)."(i)", $def_base_addr,hex($offset);

      printf REG_HDEF "\#define %-40s  (0x%04x)\n"
             ,("OFST_".${moduleName_upper}."_".uc$gname),hex($offset);
    }
  }
  else{
    for $i(1 .. $reg_num) {
      $gname = $reg_list[$i]{'gname'};
      $offset= $reg_list[$i]{'offset'};
      printf REG_HDEF "\#define %-40s  (0x%04x)\n"
             ,("OFST_".${moduleName_upper}."_".uc$gname),hex($offset);
    }
  }
  printf REG_HDEF "\n#endif //${moduleName_upper}_DEF_H_\n";
}
elsif($sys_num>=1) {
  foreach $sys_array (@sys_array) {
    my $def_base_addr = "BASE_ADDR_".${sys_array}."_".${moduleName_upper};

  $base_addr_upper =~ s/0X/32'h/g;
  $base_addr_hex =~ s/0X/0x/g;
  if ($number >1){
    $base_offset_upper = uc($base_offset);
    $base_offset_hex= uc($base_offset);
    $base_offset_upper =~ s/0X/32'h/g;
    $base_offset_hex =~ s/0X/0x/g;
    $base_addr_upper = "(".$base_addr_upper." + i*".$base_offset_upper.")";
    $base_addr_hex   = "(".$base_addr_hex." + i*".$base_offset_hex.")";
    $def_base_addr   = $def_base_addr."(i)";
  }

 ############
  printf REG_DEF "\n`ifndef ${sys_array}_${moduleName_upper}_DEF_V_";
  printf REG_DEF "\n`define ${sys_array}_${moduleName_upper}_DEF_V_\n";
  printf REG_DEF "//\n";
  printf REG_DEF "//Register offset macro defines\n";
  printf REG_DEF "//\n";
  #printf REG_DEF "\`define %-40s $base_addr_upper\n",$def_base_addr; # Base Address
  if ($number > 1){
    for $i(1 .. $reg_num) {
      $gname = $reg_list[$i]{'gname'};
      $offset= $reg_list[$i]{'offset'};
      #printf REG_DEF "\#define %-40s  (%-10s + 0x%04x)\n"
            # ,("REG_".${moduleName_upper}."_".uc$gname)."(i)", $def_base_addr,hex($offset);

      printf REG_DEF "\`define %-40s  (32\'h%04x)\n"
             ,("OFST_".${sys_array}."_".${moduleName_upper}."_".uc$gname),hex($offset);
    }
  }
  else{
    for $i(1 .. $reg_num) {
      $gname = $reg_list[$i]{'gname'};
      $offset= $reg_list[$i]{'offset'};
      printf REG_DEF "\`define %-40s  (32\'h%04x)\n"
             ,("OFST_".${sys_array}."_".${moduleName_upper}."_".uc$gname),hex($offset);
    }
  }
  printf REG_DEF "\n`endif //${sys_array}_${moduleName_upper}_DEF_V_\n";
  printf REG_DEF "\n\n\n\n\n\n\n\n\n\n\n";


###define hex file generate

####

  printf REG_HDEF "\n#ifndef ${sys_array}_${moduleName_upper}_DEF_H_";
  printf REG_HDEF "\n#define ${sys_array}_${moduleName_upper}_DEF_H_\n";
  printf REG_HDEF "//\n";
  printf REG_HDEF "//Register offset macro defines\n";
  printf REG_HDEF "//\n";
  #printf REG_HDEF "\#define %-40s $base_addr_hex\n",$def_base_addr; # Base Address
  if ($number > 1){
    for $i(1 .. $reg_num) {
      $gname = $reg_list[$i]{'gname'};
      $offset= $reg_list[$i]{'offset'};
      printf REG_HDEF "\#define %-40s  (0x%04x)\n"
             ,("OFST_".${sys_array}."_".${moduleName_upper}."_".uc$gname),hex($offset);
    }
  }
  else{
    for $i(1 .. $reg_num) {
      $gname = $reg_list[$i]{'gname'};
      $offset= $reg_list[$i]{'offset'};
      printf REG_HDEF "\#define %-40s  (0x%04x)\n"
             ,("OFST_".${sys_array}."_".${moduleName_upper}."_".uc$gname),hex($offset);
    }
  }
  printf REG_HDEF "\n#endif //${sys_array}_${moduleName_upper}_DEF_H_\n";
  printf REG_HDEF "\n\n\n\n\n\n\n\n\n\n\n";

  }


}
 
  close (REG_DEF);
  close (REG_HDEF);
}


#=======================================================================
# reg file - define file generation
# Father process : main
# Depth : main ->Gen_bdef_file
#=======================================================================
sub Gen_bdef_file{
  my($moduleName,$base_addr,$outdefName,$outhdefName,$number,$base_offset,$reg,$field,$sysarray,$sys_num)=@_;
  my @reg_list = @{$reg};
  my @field_list = @{$field};
  my $base_addr_upper = uc($base_addr);
  my $base_addr_hex= uc($base_addr);
  my $base_offset_upper, $base_offset_hex;
  my @sys_array = @{$sysarray};


  my $moduleName_upper = uc($moduleName);
  if ($moduleName =~/([a-zA-Z0-9]_pre_div_clk_rf)/){
    $moduleName_upper =~ s/_CLK_RF/_CLK/g;
  }
  elsif ($moduleName =~/([a-zA-Z0-9]_clk_rf)/){
    $moduleName_upper =~ s/_CLK_RF/_CLKTOP/g;
  }

  open(REG_BDEF,">$outhdefName") or die "[ERROR]:Can't create register hex define file\n";

####copyright
  printf REG_BDEF "/*\n * Horizon Robotics\n *\n * Copyright (C) 2022 Horizon Robotics Inc.\n * All rights reserved.\n *\n * This file is auto generated by Horizon Robotics for Sigiriya Chip.\n * Version: J6B-fusa update\n * $date $username*/";
####

if ($sys_num == 0) {
  my $def_base_addr = "BASE_ADDR_".$moduleName_upper;

  $base_addr_upper =~ s/0X/32'h/g;
  $base_addr_hex =~ s/0X/0x/g;
  if ($number >1){
    $base_offset_upper = uc($base_offset);
    $base_offset_hex= uc($base_offset);
    $base_offset_upper =~ s/0X/32'h/g;
    $base_offset_hex =~ s/0X/0x/g;
    $base_addr_upper = "(".$base_addr_upper." + i*".$base_offset_upper.")";
    $base_addr_hex   = "(".$base_addr_hex." + i*".$base_offset_hex.")";
    $def_base_addr   = $def_base_addr."(i)";
  }


###define  file generate


  printf REG_BDEF "\n#ifndef ${moduleName_upper}_DEF_H_";
  printf REG_BDEF "\n#define ${moduleName_upper}_DEF_H_\n";
  printf REG_BDEF "//\n";
  printf REG_BDEF "//\n";
  printf REG_BDEF "//Register macro defines\n";
  printf REG_BDEF "//\n";
  #printf REG_BDEF "\#define %-40s $base_addr_hex\n",$def_base_addr; # Base Address

#reg addr macro
  printf REG_BDEF "\n\n";
  printf REG_BDEF "//-------------------------------------------------\n";
  printf REG_BDEF "//Register offset macro defines\n";
  printf REG_BDEF "//-------------------------------------------------\n";
  if ($number > 1){
    for $i(1 .. $#reg_list) {
      $gname = $reg_list[$i]{'gname'};
      $offset= $reg_list[$i]{'offset'};
      printf REG_BDEF "\#define %-40s  (0x%04x)\n"
             ,("OFST_".${moduleName_upper}."_".uc$gname),hex($offset);
    }
  }
  else{
    for $i(1 .. $#reg_list) {
      $gname = $reg_list[$i]{'gname'};
      $offset= $reg_list[$i]{'offset'};
      printf REG_BDEF "\#define %-40s  (0x%04x)\n"
             ,("OFST_".${moduleName_upper}."_".uc$gname),hex($offset);
    }
  }

#reg mask
  printf REG_BDEF "\n\n";
  printf REG_BDEF "//-------------------------------------------------\n";
  printf REG_BDEF "//Register mask macro defines\n";
  printf REG_BDEF "//-------------------------------------------------\n";
  for $i(1 .. $reg_num) {
    $gname = $reg_list[$i]{'gname'};
    $offset= $reg_list[$i]{'offset'};
    $mask  = $reg_list[$i]{'reg_mask'};
    printf REG_BDEF "\#define %-40s  (%-10s)\n"
           ,("MASK_".${moduleName_upper}."_".uc$gname), '0x'.$mask;
  }

#reg default
  printf REG_BDEF "\n\n";
  printf REG_BDEF "//-------------------------------------------------\n";
  printf REG_BDEF "//Register default value macro defines\n";
  printf REG_BDEF "//-------------------------------------------------\n";
  for $i(1 .. $reg_num) {
    $gname = $reg_list[$i]{'gname'};
    $offset= $reg_list[$i]{'offset'};
    $deft  = $reg_list[$i]{'reg_value'};
    printf REG_BDEF "\#define %-40s  (%-10s)\n"
           ,("DFLT_".${moduleName_upper}."_".uc$gname), '0x'.$deft;
  }

#reg bit
  printf REG_BDEF "\n\n";
  printf REG_BDEF "//-------------------------------------------------\n";
  printf REG_BDEF "//-------------------------------------------------\n";
  printf REG_BDEF "//Register bit information\n";
  printf REG_BDEF "//-------------------------------------------------\n";
  printf REG_BDEF "//-------------------------------------------------\n";

  for $i (1 .. $#reg_list){
    $gname    = $reg_list[$i]{'gname'};
    $offset   = $reg_list[$i]{'offset'};
    $reg_name = "OFST_".${moduleName_upper}."_".uc$gname;

    printf REG_BDEF "\n//...............................\n";
    printf REG_BDEF "//Register Name: $reg_name\n";
    printf REG_BDEF "//Register offset: 0x%x\n", hex($offset);
    printf REG_BDEF "//...............................\n";

    for $j (1 .. $#field_list){
      $fname  = $field_list[$j]{'fname'};
      $field  = $field_list[$j]{'field'};
      $width  = $field_list[$j]{'width'};
      $msb    = $field_list[$j]{'msb'};
      $lsb    = $field_list[$j]{'lsb'};
      $attr   = uc($field_list[$j]{'attr'});
      $bit_or = '()';
      if ($fname eq $gname){
        if ($msb == 31 and $lsb == 0){
          printf REG_BDEF "\n";
        }elsif($field ne 'reserved') {
          if ($width == 1){
            $bit_name = "BIT_".${moduleName_upper}."_".uc$gname."_".uc$field;
            printf REG_BDEF "\#define %-50s  (BIT_%d)\n", ($bit_name, $msb);
            #$bit_name = "ATTR".${moduleName_upper}."_".uc$gname."_".uc$field;
            #printf REG_BDEF "\#define %-50s  (ATTR_%s)\n", ($bit_name, $attr);
          }
          else{
            $bit_name = "BIT_".${moduleName_upper}."_".uc$gname."_".uc$field."(_X_)";
            for $k ($lsb .. $msb){
              $bit_tmp=sprintf('BIT_%-2d',$k);
              $bit_or=~s/\)/\|$bit_tmp\)/g;
            }
            $bit_or=~s/\(\|/\(/g;
            printf REG_BDEF "\#define %-50s  ((_X_) << %-2d & %s)\n", ($bit_name, $lsb, $bit_or);
          }
          $bit_name = "ATTR_".${moduleName_upper}."_".uc$gname."_".uc$field;
          printf REG_BDEF "\#define %-50s  (ATTR_%s)\n", ($bit_name, $attr);
        }
      }
    }
  }


  printf REG_BDEF "\n#endif //${moduleName_upper}_DEF_H_\n";
}

elsif($sys_num >= 1) {
  foreach $sys_array (@sys_array) {
  my $def_base_addr = "BASE_ADDR_".${sys_array}."_".$moduleName_upper;

  $base_addr_upper =~ s/0X/32'h/g;
  $base_addr_hex =~ s/0X/0x/g;
  if ($number >1){
    $base_offset_upper = uc($base_offset);
    $base_offset_hex= uc($base_offset);
    $base_offset_upper =~ s/0X/32'h/g;
    $base_offset_hex =~ s/0X/0x/g;
    $base_addr_upper = "(".$base_addr_upper." + i*".$base_offset_upper.")";
    $base_addr_hex   = "(".$base_addr_hex." + i*".$base_offset_hex.")";
    $def_base_addr   = $def_base_addr."(i)";
  }


###define  file generate


  printf REG_BDEF "\n#ifndef ${sys_array}_${moduleName_upper}_DEF_H_";
  printf REG_BDEF "\n#define ${sys_array}_${moduleName_upper}_DEF_H_\n";
  printf REG_BDEF "//\n";
  printf REG_BDEF "//\n";
  printf REG_BDEF "//Register macro defines\n";
  printf REG_BDEF "//\n";
  #printf REG_BDEF "\#define %-40s $base_addr_hex\n",$def_base_addr; # Base Address

#reg addr macro
  printf REG_BDEF "\n\n";
  printf REG_BDEF "//-------------------------------------------------\n";
  printf REG_BDEF "//Register offset macro defines\n";
  printf REG_BDEF "//-------------------------------------------------\n";
  if ($number > 1){
    for $i(1 .. $#reg_list) {
      $gname = $reg_list[$i]{'gname'};
      $offset= $reg_list[$i]{'offset'};
      printf REG_BDEF "\#define %-50s  (0x%04x)\n"
             ,("OFST_".${sys_array}."_".${moduleName_upper}."_".uc$gname),hex($offset);
    }
  }
  else{
    for $i(1 .. $#reg_list) {
      $gname = $reg_list[$i]{'gname'};
      $offset= $reg_list[$i]{'offset'};
      printf REG_BDEF "\#define %-50s  (0x%04x)\n"
             ,("OFST_".${sys_array}."_".${moduleName_upper}."_".uc$gname),hex($offset);
    }
  }

#reg mask
  printf REG_BDEF "\n\n";
  printf REG_BDEF "//-------------------------------------------------\n";
  printf REG_BDEF "//Register mask macro defines\n";
  printf REG_BDEF "//-------------------------------------------------\n";
  for $i(1 .. $reg_num) {
    $gname = $reg_list[$i]{'gname'};
    $offset= $reg_list[$i]{'offset'};
    $mask  = $reg_list[$i]{'reg_mask'};
    printf REG_BDEF "\#define %-50s  (%-10s)\n"
           ,("MASK_".${sys_array}."_".${moduleName_upper}."_".uc$gname), '0x'.$mask;
  }

#reg default
  printf REG_BDEF "\n\n";
  printf REG_BDEF "//-------------------------------------------------\n";
  printf REG_BDEF "//Register default value macro defines\n";
  printf REG_BDEF "//-------------------------------------------------\n";
  for $i(1 .. $reg_num) {
    $gname = $reg_list[$i]{'gname'};
    $offset= $reg_list[$i]{'offset'};
    $deft  = $reg_list[$i]{'reg_value'};
    printf REG_BDEF "\#define %-50s  (%-10s)\n"
           ,("DFLT_".${sys_array}."_".${moduleName_upper}."_".uc$gname), '0x'.$deft;
  }

#reg bit
  printf REG_BDEF "\n\n";
  printf REG_BDEF "//-------------------------------------------------\n";
  printf REG_BDEF "//-------------------------------------------------\n";
  printf REG_BDEF "//Register bit information\n";
  printf REG_BDEF "//-------------------------------------------------\n";
  printf REG_BDEF "//-------------------------------------------------\n";

  for $i (1 .. $#reg_list){
    $gname    = $reg_list[$i]{'gname'};
    $offset   = $reg_list[$i]{'offset'};
    $reg_name = "OFST_".${sys_array}."_".${moduleName_upper}."_".uc$gname;

    printf REG_BDEF "\n//...............................\n";
    printf REG_BDEF "//Register Name: $reg_name\n";
    printf REG_BDEF "//Register offset: 0x%x\n", hex($offset);
    printf REG_BDEF "//...............................\n";

    for $j (1 .. $#field_list){
      $fname  = $field_list[$j]{'fname'};
      $field  = $field_list[$j]{'field'};
      $width  = $field_list[$j]{'width'};
      $msb    = $field_list[$j]{'msb'};
      $lsb    = $field_list[$j]{'lsb'};
      $bit_or = '()';
      if ($fname eq $gname){
        if ($msb == 31 and $lsb == 0){
          printf REG_BDEF "\n";
        }elsif($field ne 'reserved') {
          if ($width == 1){
            $bit_name = "BIT_".${sys_array}."_".${moduleName_upper}."_".uc$gname."_".uc$field;
            printf REG_BDEF "\#define %-55s  (BIT_%d)\n", ($bit_name, $msb);
          }
          else{
            $bit_name = "BIT_".${sys_array}."_".${moduleName_upper}."_".uc$gname."_".uc$field."(_X_)";
            for $k ($lsb .. $msb){
              $bit_tmp=sprintf('BIT_%-2d',$k);
              $bit_or=~s/\)/\|$bit_tmp\)/g;
            }
            $bit_or=~s/\(\|/\(/g;
            printf REG_BDEF "\#define %-55s  ((_X_) << %-2d & %s)\n", ($bit_name, $lsb, $bit_or);
          }
        }
      }
    }
  }


  printf REG_BDEF "\n#endif //${sys_array}_${moduleName_upper}_DEF_H_\n";
  printf REG_BDEF "\n\n\n\n\n\n\n\n\n\n";


   }
   
}

  close (REG_BDEF);
}



#=======================================================================
# reg file - mannualy define for generate block
# Father process : main
# Depth : main ->Gen_macro_def
#=======================================================================
sub Gen_macro_def{
  my($moduleName,$base_addr,$reg,$field)=@_;
  my @reg_list = @{$reg};
  my @field_list=@{$field};

  local $moduleName_upper, $def_base_addr,$base_addr_upper;
  local $blank,$str,$format;
  local $i,$j;
  local @macro_def;
  $moduleName_upper=uc($moduleName);
  if ($moduleName =~/([a-zA-Z0-9]_pre_div_clk_rf)/){
    $moduleName_upper =~ s/_CLK_RF/_CLK/g;
  }
  elsif ($moduleName =~/([a-zA-Z0-9]_clk_rf)/){
    $moduleName_upper =~ s/_CLK_RF/_CLKTOP/g;
  }

  $def_base_addr = "BASE_ADDR_".$moduleName_upper;
  $base_addr_upper = uc($base_addr);
  $base_addr_upper =~ s/0X/32'h/g;

  push (@macro_def,"\n\n//---- *reg addr define*----");
  push (@macro_def,"\n//`ifndef ${moduleName_upper}_DEF_V_");
  push (@macro_def,"\n//`define ${moduleName_upper}_DEF_V_\n");
  push (@macro_def,"//\n");
  push (@macro_def,"//Register macro defines\n");
  push (@macro_def,"//\n");
  $format=sprintf("%-40s",$def_base_addr);

  push (@macro_def,"//\`define $format  $base_addr_upper\n");
  for $i(1 .. $reg_num) {
    $gname = $reg_list[$i]{'gname'};
    $offset= $reg_list[$i]{'offset'};
    local $format1=sprintf("%-40s",("OFST_".${moduleName_upper}."_".uc($gname)));
    local $format2=sprintf("%-10s",$def_base_addr);
    local $format3=sprintf("%04x",hex($offset));

    push(@macro_def,"//\`define $format1  ($format2 + \'h$format3)\n");
  }
  push (@macro_def,"//`endif //${moduleName_upper}_DEF_V_\n\n\n");
  push (@macro_def,"//---- *reg sig bit info*----\n");
  for $j(1 .. $field_num){
    $fname  = $field_list[$j]{'fname'};
    $field  = $field_list[$j]{'field'};
    $width  = $field_list[$j]{'width'};
    $msb    = $field_list[$j]{'msb'};
    $lsb    = $field_list[$j]{'lsb'};
    if($field ne "reserved"){
      $format1=sprintf("%-30s",$field);
      $format2=sprintf("%-40s",("OFST_".${moduleName_upper}."_".uc($fname)));
      if($width == 1){
        push(@macro_def,"//$format1,`$format2,bit[$msb]\n");
      }
      else{
        push(@macro_def,"//$format1,`$format2,bit[$msb:$lsb]\n");
      }
    }
  }
  return(@macro_def);
}

#=======================================================================
# vim plug-in process
# Father process : Gen_reg_file
# Depth : Gen_reg_file ->Vim_auto
#=======================================================================
sub Gen_man_def{
  my ($reg_num_w,$reg)=@_;
  my @reg_list = @{$reg};
  my @man_def;
  my $ecc_num_w=0;
  my $func_num_w;
  my $fusa_ctrl_mask=0;
  for $i (1 .. $#reg_list){
    $gname    = $reg_list[$i]{'gname'};
    $offset   = lc($reg_list[$i]{'offset'});
    $reg_attr = $reg_list[$i]{'reg_attr'};
    if ((grep /^$offset$/, @ecc_addr) and ($reg_attr ne 'RO') and ($reg_attr ne 'RES')){
      $ecc_num_w=$ecc_num_w+1;
    }

    if ((grep /^$offset$/, @ecc_addr) and ($gname =~ /^FUSA_CTRL|Mask\d*$/)){
##    print "yesyes and gname is $gname\n";
    $fusa_ctrl_mask = $fusa_ctrl_mask+1;
  }
}
  $func_num_w = $reg_num_w-$ecc_num_w+$fusa_ctrl_mask;
##    if ((grep /^$offset$/, @ecc_addr)) {
##    print "yes yes";
##    $func_num_w = $func_num_w+1;
##    }
#    print "func_num_w = $func_num_w\n";
  $reg_msb = $func_num_w-1;

  push (@man_def,"
wire          reg_parity_error;
wire          reg_parity_error_and;
wire          reg_parity_error_or;
wire   [31:0] reg_data_res               [$reg_msb:0];
wire   [31:0] reg_data_w1s               [$reg_msb:0];
wire   [31:0] reg_data_w1c               [$reg_msb:0];
wire   [31:0] reg_data_w0s               [$reg_msb:0];
wire   [31:0] reg_data_w0c               [$reg_msb:0];
wire   [31:0] reg_data_wt                [$reg_msb:0];
wire   [31:0] reg_data_rc                [$reg_msb:0];
wire   [31:0] reg_data_wr                [$reg_msb:0];
wire   [31:0] reg_data_hw                [$reg_msb:0];
wire   [31:0] hw_wdata                   [$reg_msb:0];
wire   [35:0] reg_default_value          [$reg_msb:0];
wire   [$reg_msb:0] reg_parity_update;
wire   [31:0] reg_enc_data_in            [$reg_msb:0];
wire   [31:0] reg_enc_data_out           [$reg_msb:0];
wire   [3 :0] reg_enc_parity_out         [$reg_msb:0];
reg    [31:0] reg_enc_data               [$reg_msb:0];
reg    [3 :0] reg_enc_parity             [$reg_msb:0];
wire   [3 :0] reg_enc_parity_mux         [$reg_msb:0];
wire   [31:0] reg_dec_data_out           [$reg_msb:0];
wire   [3 :0] reg_dec_parity_out         [$reg_msb:0];
wire   [$reg_msb:0] parity_dec_error;
");
  return ($func_num_w,$fusa_ctrl_mask, @man_def);
}

#=======================================================================
# vim plug-in process
# Father process : Gen_reg_file
# Depth : Gen_reg_file ->Vim_auto
#=======================================================================
sub Vim_auto {
    my($outfile,$out_dir) = @_;
    #Call VIM script to do the "auto define" and "auto argument"
    open SCRHD, ">scr.vim" or die ("can't open scr.vim\n");
    # print SCRHD ":APF\n";
    print SCRHD ":AR\n";
    print SCRHD ":AF\n";
    print SCRHD ":AD\n";
    print SCRHD ":wq\n";
    close SCRHD;

    $outfile = "${out_dir}/${outfile}";
    print "[INFO]: $outfile call vim processing ...!\n\n";
    #'gvim -e $file -S scr.vim ;
    `gvim -e -s $outfile < scr.vim`;
    
    `/bin/rm scr.vim`
}

sub Auto_def_post{
  my ($outfile,$out_dir)=@_;
  open(REG_FILE,"<${out_dir}/${outfile}") or die "[ERROR]:Can't create register define file\n";
  local @lines = <REG_FILE>;
  close (REG_FILE);

  local @lines_post;
  foreach (@lines){
    if(($_=~/reg\s*\[i\]/)or($_=~/wire\s*\[i\]/)){
      next;}
    push(@lines_post,$_);
  }

  open(REG_FILE,">${out_dir}/${outfile}") or die "[ERROR]:Can't create register define file\n";
  foreach (@lines_post){
    printf REG_FILE "$_";
  } 
  close (REG_FILE);

### dv add excel check function
##  if($infile =~/([a-zA-Z0-9_]+).xls/){
##    my $xlsfile = $ARGV[0];
##    my $rtlfile = $outfileName;
##    my $script_path = Cwd::realpath($outfileName);
##    #my $rtlfile = $ARGV[0]
##    my $DV_PRJDIR = $ENV{"PRJDIR"};
##    my $python_script = "$DV_PRJDIR/script/dv_script/fusa_reg_test/reg_test_gen.py";
##    system("python3", $python_script,"-xls_file", $xlsfile, "-v_file", $script_path)
##  } 
### add end   
}


#==========================================
# print help information
#==============================================
sub print_help {
print "
Usage: reg_gen_ecc.pl [OPTION]
Example: 

reg_gen_ecc.pl ***.xls 
Descrition: parse xls, HW-wr signal without sync.

reg_gen_ecc.pl ***.xls -s 1
Descrition: parse xls, HW-wr signal with sync.

reg_gen_ecc.pl ***.csv 
Descrition: parse xls, HW-wr signal without sync, csv seperator is ';'.

reg_gen_ecc.pl ***.csv , 
Descrition: parse xls, HW-wr signal without sync, csv seperator is ','.

reg_gen_ecc.pl -def
Descrition: print register macro defination.

reg_gen_ecc.pl -noecc
Descrition: no ecc releted logic in generated .v file.

reg_gen_ecc.pl -h
Descrition: print help infomation.

Option description:
    -h	        --help	        Print help information
    -s xxx      --sync=xxx      if have sync cell for HW-wr signal
"
}
