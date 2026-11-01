#!/usr/bin/env python


#############################################
# Description:
# AUto-Gen for Functional Safety Dual-Core Lock-Step
# Author : honghe.tan
# Data   : 06/12/2019
# Version history:
# 06/17/2019 0.1  honghe.tan  initial version
# 07/15/2019 0.2  honghe.tan  change to class version
# 07/16/2019 0.3  honghe.tan  changed for delay in the future
# 07/22/2019 0.4  honghe.tan  surport dual core delay
# 07/31/2019 0.41 honghe.tan  fix bug for AnalyzeConnection
# 10/04/2019 0.42 honghe.tan  fix bug for getRefWidth
# 10/05/2019 0.43 honghe.tan  support input connect with const value
#          0.44 honghe.tan  support signed kerword declaration
# 10/09/2019 0.44 honghe.tan  fix redeclaration of signals
# 10/19/2019 0.45 honghe.tan  delay dcls_fault_injection when delay mode
# 10/21/2019 0.46 honghe.tan  add reset value for delay signals
#                             change delay signal name
#                             deal port without connection commit as input port
#                             optimise subtop mode
# 10/22/2019 0.47 honghe.tan  support CLK/RST commit to label clock/reset port
# 11/04/2019 0.48 honghe.tan  add gating clock logic and gating cell
# 11/11/2019 0.50 honghe.tan  fix a special statement with only ","
# 11/19/2019 0.51 honghe.tan  add NewProcSigDlyLines and NewProcCmpLines
# 11/20/2019 0.60 honghe.tan  usd adaptive comparator design for compare
# 11/21/2019 0.70 honghe.tan  support "NOCMP" commit
# 12/14/2019 0.75 honghe.tan  distinguish labeled clk and infered clk,
#                             check more than one infered clk
#                             delay output signals without reset
#                             remove gating cell for comparator
# 01/04/2020 0.76 honghe.tan  add checker to optimise
# 01/09/2020 0.77 honghe.tan  fix error: pass the line with "//" head
# 01/15/2020 0.78 honghe.tan  support input default value
#                             add gating cell for dualcore and comparator
# 01/17/2020 0.80 honghe.tan  add --fusaclk option
# 04/17/2022 1.00 sen.li      change to DE version
# 06/02/2022 1.11 sen.li      add multi-reset with fusa condition
# 06/16/2022 1.20 sen.li      change reset and delay scheme
#############################################



import os
import sys
import argparse
import re
import string
import copy



FuSaDefStart = "`ifdef FUSA\n"
FuSaDefEnd   = "`endif //FUSA\n"

DCLSCommitStartStr  = "__AutoGenFuSaDCLS_Start__"
DCLSCommitEndStr    = "__AutoGenFuSaDCLS_End__"
DCLSAutoCommitStr   = "AUTOFUSADCLS"


ErrDCLSPrefix = "err_fusadcls_"
DCLSSuffix = "_fusadcls"
DCLSSuffixI= "_fusadcls_i"
DCLSSuffixO= "_fusadcls_o"
DCLSSuffixD= "_fusadcls_r"
DCLSSuffixCLK = "_fusadcls_clk"

Clockbuffer = ""
ResetRecord = ""
Inferreset  = []
Testlab = ""
Teststn = []
##########################################
# class moduleObj defination
##########################################

class moduleObj(object):
  "class module"


  def __init__(self,name,srcvf):
    self.autoError   = False
    self.autoWarning = False
    self.isSubtop    = False
    self.fusaclk     = False
    #self.multclk    =False
    self.delayEn     = False
    self.debug       = False
    self.verbose     = True
    self.moduleName  = name
    self.moduleFile  = srcvf
    self.srclines    = []
    self.dstlines    = []
    self.inSignals   = []
    self.outSignals  = []
    self.inoutSignals = []
    self.dclsErrSignals= []
    self.insObjs     = []     # record all instances in this module
    self.portsDict   = {}     # TODO
    self.DCLSInsNum  = 0
    self.DCLSDelayNum = 0
    self.allDCLSDelaySignals = []
    self.allDCLSInsLines = []
    self.allDCLSErrLines = []
    self.allDCLSPortLines = []

    f = open(srcvf,"r")
    self.srclines = f.readlines();
    f.close()
    self.dstlines = self.srclines

  #def myprint(self,message):
  #  if self.verbose :
  #    print message

  def display(self,lines):
    for eachline in lines:
      print eachline

  def ClearHistoryDCLS(self):
    "clear history of AutoGen"
    f = open(moduleFile,"r")
    reserved = True
    overwrite= False
    for eachline in f:
      if re.search(DCLSCommitStartStr,eachline):
        reserved = False
        overwrite= True
      if reserved :
        self.srclines.append(eachline)
      if re.search(DCLSCommitEndStr,eachline):
        reserved = True;
    f.close()
    if overwrite:
      f = open(moduleFile,"w")
      f.writelines(self.srclines)
      f.close()
    self.dstlines = self.srclines


  def GetDCLSInsNum(self):
    for eachline in self.srclines:
      if re.search(DCLSAutoCommitStr,eachline) is not None and re.search("^\s*//",eachline) is None:
        self.DCLSInsNum += 1



  def GetPortEndPos(self):
    do = False
    pos = 0;
    for eachline in self.srclines:
      if re.search("module",eachline) is not None:
        do = True
      if re.search("\)\s*;",eachline) is not None:
        if do == True:
          break
      pos += 1
    return pos

  def GetModuleEndPos(self,lines):
    pos = 0;
    for eachline in lines:
      if re.search("endmodule",eachline) is not None:
        break
      pos += 1
    return pos

  def GetInports(self):
    do = False
    for eachline in self.srclines:
      if re.search("module",eachline) is not None:
        do = True
      if re.search("\)\s*;",eachline) is not None:
        if do == True:
          break


  def ProcDCLSInstance(self):

    myprint ("[INFO] *************Phase 1**********************")
    myprint ("[INFO] analyzing")
    for idx in range(0,self.DCLSInsNum):
      self.insObjs.append(instanceObj(self.srclines))   #new object for instance
      self.insObjs[idx].delayEn = self.delayEn
      self.insObjs[idx].debug   = self.debug
      self.insObjs[idx].fatherModule.append(self)
      self.insObjs[idx].fatherIsSubtop   = self.isSubtop
      self.insObjs[idx].insIndex = idx
      self.insObjs[idx].delaySignals = self.allDCLSDelaySignals
      self.insObjs[idx].AnalyzeIns()

    myprint ("[INFO] *************Phase 2**********************")
    myprint ("[INFO] checking and optimizing")
    self.CheckSingleInsCont()
    self.CheckMultiInsCont()

    myprint ("[INFO] *************Phase 3**********************")
    myprint ("[INFO] generating")
    for idx in range(0,self.DCLSInsNum):
      self.insObjs[idx].GenDCLSInsLines()
      self.allDCLSInsLines     += self.insObjs[idx].DCLSLines


      #print "------self.allDCLSDelaySignals"
      #for eachsignal in self.allDCLSDelaySignals:
      #  print eachsignal

    #print(self.allDCLSInsLines)


  def ProcDCLSErr(self):
    "process all error signals in current module"
    allErrSignals = []
    # all err signals generated local
    for idx in range(0,self.DCLSInsNum):
      #allErrSignals += self.insObjs[idx].errSignals
      self.dclsErrSignals += self.insObjs[idx].errSignals
      self.DCLSDelayNum = max(self.DCLSDelayNum,self.insObjs[idx].delayNum)
      print (self.DCLSDelayNum, )
    #TODO
    # all err signals from instances port
    for eachline in self.srclines :
      s = re.search('.*( |\()(err_fusadcls_[a-z0-9_]*).*',eachline)
      if s is not None:
        if self.isInList(s.group(2),self.dclsErrSignals) is False:
          self.dclsErrSignals.append(s.group(2))
          myprint("[INFO] find err signal "+s.group(2))

    # ports added to module defination
    self.allDCLSPortLines.append("    \n")
    #for i in range(1,self.DCLSDelayNum+1):
    #if self.DCLSDelayNum is not 0:
    #  self.allDCLSPortLines.append("  input [`MAX_DCDLY:0]  reset_n_d,\n")
    self.allDCLSPortLines.append("  input   [1:0] dcls_fault_injection,\n")
    #self.insObjs[0].AnalyzeIns()
    #newline = "  output  "+ Clockbuffer+"_dcls"+",\n"
    #self.allDCLSPortLines.append(newline)
    ###monitor change
    newline = "  output  "+ Clockbuffer+"_dcls"+",\n"
    self.allDCLSPortLines.append(newline)
    for eachline in IClockbuffer :
       newline = "   output  "+ eachline +"_dcls"+",\n"
       self.allDCLSPortLines.append(newline)
    ###monitor change
    icg_flag=True
    for eachline in self.srclines :
      s = re.search('^\s*\.([_a-zA-Z0-9]+)\s*\((.*)\)(.*)',eachline)
      if s is not None:
        if re.search('.*//.*',s.group(3)) is None:
          commit = ""
        else:
          commit = re.sub(".*//","",s.group(3))# remove commi
        if re.match('\s*(ICG)\s*',commit) is not None:
          icg_flag=False
          break
    if icg_flag==True:
       newline = "  input   icg_mode,\n"
       self.allDCLSPortLines.append(newline)
    #newline = "  output  dcls_"+ ResetRecord+";\n"
    #self.allDCLSPortLines.append(newline)
#   for cont in self.contObjs:
#     if cont.iotypeplus is "ICHK":
#   for num in range(0,len(Signalchk)-1):
#     for chksignal in Signalchk and for chksigwid in Signalchkwidth:
#       print(Signalchkwidth,chksignal,"!!!!!!!!!!!!!!!!!!!!!!!")
      newline = "  input "+str(Signalchkwidth[num])+" "+str(Signalchk[num])+"_chk,\n"
      self.allDCLSPortLines.append(newline)

    if self.isSubtop:
      self.allDCLSPortLines.append("  output  [15:0] err_dcls_"+self.moduleName+"\n")
    else:
      #for eachErr in allErrSignals:
      for eachErr in self.dclsErrSignals:
        self.allDCLSPortLines.append("  output reg "+eachErr+",\n")
    self.allDCLSPortLines[-1] = self.allDCLSPortLines[-1].replace(","," ") #remove comma symbol
    # set err_dcls output use all error signals
    if self.isSubtop:
      for i in range(0,16):
        #if i < len(allErrSignals):
        #  self.allDCLSErrLines.append("  assign err_dcls_"+self.moduleName+"["+str(i)+"] ="+allErrSignals[i]+";\n")
        if i < len(self.dclsErrSignals):
          self.allDCLSErrLines.append("  assign err_dcls_"+self.moduleName+"["+str(i)+"] = "+self.dclsErrSignals[i]+";\n")
        else:
          self.allDCLSErrLines.append("  assign err_dcls_"+self.moduleName+"["+str(i)+"] = 1'b0;\n")

  def AddCommitLines(self,lines):
    "add commit lines before and after generated code"
    lines.insert(0,"/*********"+DCLSCommitStartStr+"*********/\n")
    lines.insert(1,FuSaDefStart)
    lines.append(FuSaDefEnd)
    lines.append("/*********"+DCLSCommitEndStr+"*********/\n")

  def isInList(self,signal,sigList):
    inlist = False
    for eachsignal in sigList :
      if cmp(eachsignal,signal) is 0:
        inlist = True
    return inlist

  def AutoGenFuSaDCLS(self):
    myprint ("[INFO] Processing DCLS code in design '"+str(self.moduleName)+"'")
    self.GetDCLSInsNum()
    myprint ("[INFO] Total DCLS instance num is "+str(self.DCLSInsNum))
    self.ProcDCLSInstance()
    self.ProcDCLSErr()
    #add DCLS instances lines
    self.allDCLSInsLines = self.allDCLSInsLines + self.allDCLSErrLines
    self.AddCommitLines(self.allDCLSInsLines)
    pos = self.GetModuleEndPos(self.dstlines)
    self.dstlines = self.dstlines[:pos] + self.allDCLSInsLines + self.dstlines[pos:]
    #add ports lines
    self.AddCommitLines(self.allDCLSPortLines)
    pos = self.GetPortEndPos()
    self.dstlines = self.dstlines[:pos] + self.allDCLSPortLines + self.dstlines[pos:]
    for idx in range(0,self.DCLSInsNum):
      if self.insObjs[idx].autoWarning:
        self.autoWarning = True
      if self.insObjs[idx].autoError:
        self.autoError   = True
    if self.autoWarning:
      myprint ("[WARNING] please check all the WARNINGs " )
    if self.autoError:
      myprint ("[FATAL] please fix all the ERRORs and then re-try")
      fatal()
      sys.exit()

  def CheckMultiInsCont(self):
    "Warning when the input signal is connected with a output signal from another DCLS instance"
    if self.DCLSInsNum <= 1:
      return
    for ins in self.insObjs:
      for cont in ins.contObjs:
        if cont.iotype is "IN" or cont.iotype is "FORCEI":
          for ins2 in self.insObjs:
            if ins.insName != ins2.insName:
              for cont2 in ins2.contObjs:
                if cont2.iotype is "OUT" or cont.iotype is "FORCEO":
                  if cont.refname == cont2.refname:
                    myprint ("[WARNING-OPT] connection can be optimized for FUSA , pleas check :")
                    myprint ("               connected signal : "+cont.refname+cont.widthStr)
                    myprint ("               src instance     : "+ins2.insName)
                    myprint ("               code line        : "+cont2.line.rstrip())
                    myprint ("               dst instance     : "+ins.insName)
                    myprint ("               code line        : "+cont.line.rstrip())
                    self.autoWarning = True

  def CheckSingleInsCont(self):
    "Warning when the output signal is not used anywhere"
    for ins in self.insObjs:
      for cont in ins.contObjs:
        if (cont.iotype is "OUT" or cont.iotype is "FORCEO") and cont.refUsed is False:
          myprint ("[WARNING-OPT] output signal is not used in this design, pleas check :")
          myprint ("               comment '//NOCMP' can be used to optimise FUSA cost :")
          myprint ("               instance         : "+ins.insName)
          myprint ("               connected signal : "+cont.refname)
          myprint ("               code line        : "+cont.line.rstrip())
          self.autoWarning = True




##########################################
# End of class moduleObj defination
##########################################




##########################################
# class instanceObj defination
##########################################

class connectObj(object):
  "class connection"
  def __init__(self,line):
    self.line        = line
    self.portname    = ""
    self.iotype      = ""
    self.iotypeplus  = ""
    self.refname     = ""
    self.refnameDCLS = ""
    self.refDeclared = False
    self.refUsed     = False
    self.width       = "0"
    self.widthStr    = ""
    self.defaultValue = ""

class instanceObj(object):
  "class instance"
  def __init__(self,lines):
    self.autoFatal   = False
    self.autoError   = False
    self.autoWarning = False
    self.debug       = False
    self.verbose     = True
    self.srclines    = lines

    self.insIndex    = 0
    self.insStartPos = 0
    self.insEndPos   = 0
    self.insName     = ""
    self.moduleName  = ""
    self.clock   = ""
    self.clockMain   = []
    self.clockMainNum = 0
    self.clockLabled   = []
    self.clockLabledNum = 0
    self.clockInfed    = []
    self.clockInfedNum = 0
    self.resetInfed    = []
    self.resetInfedNum = 0
    self.chksignal     = []
    self.chksignalwidth = []
    self.clockCmp  = ""
    self.reset     = ""
    self.scan        = "scan_mode"
    self.delayNum    = 0
    self.fatherModule = []
    self.fatherIsSubtop = False
    self.cmpDWParam    = ""
    self.cmpD0Clare    = ""
    self.cmpD1Clare    = ""
    self.cmpDWLines    = []
    self.cmpD0Lines    = []
    self.cmpD1Lines    = []
    self.errSignals    = []


    self.insLines    = []
    self.bufLines    = []
    self.sigLines    = []
    self.dlyLines    = []
    self.cmpLines    = []
    self.DCLSLines   = []  # used for fusa

    self.delaySignals = []  # delay signals declared
    self.contObjs    = []  # list of connection
    self.inPorts  = []
    self.outPorts = []
    self.inPortsRef    = []
    self.inPortsRefDCLS  = []
    self.outPortsRef    = []
    self.outPortsRefDCLS = []


  #def myprint(self,message):
  #  if verbose :
  #    print message

  def GetInsPos(self):
    num = 0
    for eachline in self.srclines:
      if re.search(DCLSAutoCommitStr,eachline) is not None and re.search("^\s*//",eachline) is None:
        if num == self.insIndex:
          break
        num += 1
      self.insStartPos += 1
    self.insEndPos = self.insStartPos
    for eachline in self.srclines[self.insEndPos:]:
      if re.search("\)\s*;",eachline) is not None:
        break
      self.insEndPos += 1
    if self.debug :
      print "[INFO-DEBUG] insStartPos = "+str(self.insStartPos)
      print "                  insEndPos   = "+str(self.insEndPos)




  def AnalyzeIns(self):
    "Analyze instance code"
    myprint ("[INFO] ----------------------------------------")
    myprint ("[INFO] Analysing instance with index number "+str(self.insIndex))
    self.GetInsPos()
    self.AnalyzeInsName()
    self.AnalyzeModuleName()
    self.AnalyzeConnection()
    self.errSignals.append(ErrDCLSPrefix+self.moduleName)


  def AnalyzeInsName(self):
    line = self.srclines[self.insStartPos]
    #myprint(str(self.insStartPos)+":"+line)
    assert re.search(DCLSAutoCommitStr,line) is not None,"Error!: wrong position "
    # check
    print (line)
    s = re.search("[_a-zA-Z0-9]+\s*\(\s*/\*"+DCLSAutoCommitStr+"(\+D[0-9])?\*/",line)
    if s is None:
      myprint ("[ERROR][Coding] Instance and FuSa Ker Word should be in the same line")
      myprint (line.rstrip())
      sys.exit();
    elif s.group(1) is not None :
      s1 = re.search("/\*"+DCLSAutoCommitStr+"\+D([0-9])\*/",line)
      print (s1.group(1))
      if self.delayEn is True:
        self.delayNum = int(s1.group(1))
      else:
        self.delayNum = 0
    else:
      self.delayNum = 0


    tmpline = re.sub("\s*\(\s*/\*.*\*/.*","",line) #remove commit

    s = re.search('(\s|\()([_a-zA-Z0-9]+)$',tmpline) #the last word is instance name
    if s is not None:
      self.insName = s.group(2)
      myprint ("[INFO] instance name :  " + self.insName+"  with DCLS delay = "+str(self.delayNum))
    else:
      myprint ("[ERROR] cannot get instance name ")
      myprint (line)
      myprint (tmpline)

  def AnalyzeModuleName(self):
    line = self.srclines[self.insStartPos]
    #process paremeter
    if re.search("\)",line) is None:  # thers is not parameter
      s = re.search('^\s*([_a-zA-Z0-9]+)\s',line) #the first word is module name
      if s is not None:
        self.moduleName = s.group(1)
      else:
        myprint ("[ERROR][Coding] module name should be the first word of the line")
        myprint (line)
      #line = line.replace("/*"+DCLSAutoCommitStr+"*/","") #remove commit
      newline = line.replace(" "+self.insName," "+self.insName+DCLSSuffix)

      self.insLines.append(newline)
    elif re.search("#\s*\(",line) is not None:
      # thers is parameter, and parameter defination in one line
      s = re.search('^\s*([_a-zA-Z0-9]+)\s',line) #the first word is module name
      if s is not None:
        self.moduleName = s.group(1)
      else:
        myprint ("[ERROR][Coding] module name should be the first word of the line")
        myprint (line)
      #line = line.replace("/*"+DCLSAutoCommitStr+"*/","") #remove commit
      newline = line.replace(self.insName,self.insName+DCLSSuffix)
      self.insLines.append(newline)
    else: #parameter defination not in one line
      #line = line.replace("/*"+DCLSAutoCommitStr+"*/","") #remove commit
      newline = line.replace(self.insName,self.insName+DCLSSuffix)
      self.insLines.append(newline)
      searching = True
      lastpos = self.insStartPos
      while searching:
        lastpos -= 1
        lastline = self.srclines[lastpos]
        #myprint ("lastline is "+lastline)
        self.insLines.insert(0,lastline)
        if re.search("#\s*\(",lastline) is not None:
          searching = False
          s = re.search('^\s*([_a-zA-Z0-9]+)\s',lastline) #the first word is module name
          if s is not None:
            self.moduleName = s.group(1)
          else:
            myprint ("[ERROR][Coding] module name should be the first word of the line")
            myprint (line)
        if lastpos == 0:
          myprint ("[ERROR] can not find module name for instance "+self.insName)
          sys.exit()
    myprint ("[INFO] module name :  " + self.moduleName)

  def AnalyzeConnection(self):
    "Analyze connection"
    myprint ("[INFO] analyzing connection ")
    #for eachline in self.srclines[]:
    for eachline in self.srclines[self.insStartPos+1:self.insEndPos+1]:
      if re.search("^\s*\)\s*;",eachline) :
        #end instance in single line
        break

      dbgprint ("line : "+eachline.rstrip(),self.debug)
      # format : .portname (refname)
      s = re.search('^\s*\.([_a-zA-Z0-9]+)\s*\((.*)\)(.*)',eachline)

      #dbgprint ("s0 : "+s.group(0),self.debug)
      #dbgprint ("s1 : "+s.group(1),self.debug)
      #dbgprint ("s2 : "+s.group(2),self.debug)
      #dbgprint ("s3 : "+s.group(3),self.debug)
      if s is not None :
        cont = connectObj(eachline)
        cont.portname = s.group(1)
      else:
        continue
      dbgprint ("portname : "+cont.portname,self.debug)

      if re.search('{.*}',s.group(2)) is not None:
        myprint ("[ERROR] connection with '{ }' is not surported")
        sys.exit()


      if re.search('.*//.*',s.group(3)) is None:
      #if s.group(3) is None:
        # a line with signals but no commit
        cont.iotype = "ND"
        #myprint ("[WARNING] the following line has no commit '//I' or '//O', defaultly considered as '//I' ")
        #myprint (eachline)
        self.autoWarning = True
        commit = ""
      else:
        #commit = s.group(3)
        #commit = re.sub(".*//","",s.group(3))# remove commit
        commitplus = re.sub("//"," ",s.group(3))# remove commit
        commit = re.sub(",","",commitplus).strip()
      dbgprint ("commit : "+commit,self.debug)

      if re.match('\s*(O|OUT|Output)\s*',commit) is not None :
        #for output port
        s = re.search('\(\s*([a-zA-Z][_a-zA-Z0-9]*)',eachline)
        if s is not None:
          cont.iotype      = "OUT"
          cont.refname     = s.group(1)
          #cont.refnameDCLS = cont.refname+DCLSSuffix
          cont.refnameDCLS = cont.refname+DCLSSuffixO
        else:
          # for NC port
          cont.iotype      = "NC"
          cont.refname     = ""
          cont.refnameDCLS = ""
          myprint ("[INFO] not connected output port :")
          myprint ("        "+eachline.rstrip())
      elif re.match('\s*(NOCMP)\s*',commit) is not None :
        cont.iotype    = "NC"
        cont.refname     = ""
        cont.refnameDCLS = ""
      elif re.match('\s*(MCLK)[!a-zA-Z ]*',commit) is not None :
        s = re.search('\(\s*([a-zA-Z][_a-zA-Z0-9]*)',eachline)
        if s is not None:
          cont.iotype      = "MCLK"
          cont.refname     = s.group(1)
          myprint ("[INFO] get labeled DCLS clock signal :"+cont.refname)
          self.clockMain.append(cont.refname)
          self.clockMainNum += 1
      elif re.match('\s*(CLK)[!a-zA-Z ]*',commit) is not None :
        s = re.search('\(\s*([a-zA-Z][_a-zA-Z0-9]*)',eachline)
        if s is not None:
          cont.iotype      = "LCLK"
          cont.refname     = s.group(1)
          myprint ("[INFO] get labeled clock signal :"+cont.refname)
          self.clockLabled.append(cont.refname)
          self.clockLabledNum += 1
      elif re.match('\s*(FORCEI)\s*',commit) is not None :
        s = re.search('\(\s*([a-zA-Z][_a-zA-Z0-9]*)',eachline)
        if s is not None:
          cont.iotype      = "SCAN"
          cont.refname     = s.group(1)
          myprint ("[INFO] get labeled FORCEO signal :"+cont.refname)
          self.scan = cont.refname
      elif re.match('\s*(ICG)\s*',commit) is not None :
        s = re.search('\(\s*([a-zA-Z][_a-zA-Z0-9]*)',eachline)
        if s is not None:
          cont.iotype      = "ICG"
          cont.refname     = s.group(1)
          myprint ("[INFO] get labeled scan signal :"+cont.refname)
          self.reset = cont.refname
      elif re.match('\s*(I|IN|Input)\s*',commit) is not None :
        #for input port
        cont.iotype   = "IN"
        s = re.search('\(\s*([a-zA-Z][_a-zA-Z0-9]*)',eachline)
        if s is not None:
          cont.refname     = s.group(1)
          cont.refnameDCLS = cont.refname+DCLSSuffixI
          if re.search("(clk|clock|mclk)",cont.portname) is not None:
            cont.iotype   = "ICLK"
            myprint ("[INFO] get inferred clock port :"+cont.refname)
            self.clockInfed.append(cont.refname)
            self.clockInfedNum += 1
#
#         elif re.search("(rst_n|reset_n|mreset_n|resetn)",cont.portname) is not None:
#           cont.iotype   = "RST"
#           myprint ("[INFO] get inferred reset port :"+cont.portname)
#           self.reset = cont.refname
          elif re.search("(rst_n|reset_n|mreset_n|resetn)",cont.portname) is not None:
            s = re.search('^\s*\.([_a-zA-Z0-9]+)\s*\((.*)\)(.*)',eachline)
            if s is not None and (s.group(2).strip()==self.reset):
              cont.iotype   = "ISPRST"
              myprint ("[INFO] inferred reset port used labeled reset port:"+s.group(2))
            #else:
            #  cont.iotype   = "IRST"
            #  myprint ("[INFO] get inferred reset port :"+cont.portname)
            #   self.resetInfed.append(cont.refname)
            #   self.resetInfedNum += 1

      else :
        # const input
        s = re.search('\(\s*({*[1-9][0-9`bdh_BDH]*)',eachline)
        if s is not None:
          cont.iotype   = "CONST"
          cont.refname    = s.group(1)
          cont.refnameDCLS = s.group(1)
          myprint ("[INFO] connected to const value :")
          myprint ("     "+eachline.rstrip())
        else:
          cont.refname      = ""
          cont.refnameDCLS = ""
          myprint ("[ERROR] not connected input port :")
          myprint ("     "+eachline.rstrip())
          self.autoError = True
      if re.search('\s*(CHK)\s*',commit) is not None :#match no use
          cont.iotypeplus = "ICHK"
          self.chksignal.append(cont.refname)
    else :
      # a line with signals but no IN/OUT commit
      cont.iotype = "IN"
      myprint ("[WARNING] the following line has no commit '//I' or '//O', defaultly considered as '//I' ")
      myprint (eachline)
      self.autoWarning = True
      s = re.search('\(\s*([a-zA-Z][_a-zA-Z0-9]*)',eachline)
      if s is not None:
        cont.refname    = s.group(1)
        cont.refnameDCLS = cont.refname+DCLSSuffixI
      else:
        cont.refname     = ""
        cont.refnameDCLS = ""
        myprint ("[ERROR] not connected input port :")
        myprint ("    "+eachline.rstrip())
        self.autoError = True

      self.getRefWidth(cont)
      self.getDefaultValue(cont)
      self.contObjs.append(cont)
      if re.search("\)\s*;",eachline) is not None:  #end instance
        #end instance not in single line
        break
    for cont in self.contObjs:
      if cont.iotypeplus is "ICHK":
#       print(cont.widthStr,"@@@@@@@@@@@@@@@@@@@@@@@@@")
        self.chksignalwidth.append(cont.widthStr)

    #check clock
    if self.clockMainNum is 0:
      if self.clockLabledNum is 0 and self.clockInfedNum is 0:
        myprint ("[FATAL] no labeled and inferred clock :")
        #fatal()
        self.autoError = True
        sys.exit()
      elif self.clockLabledNum >= 1:
        self.clock = self.clockLabled[0]
        myprint ("[WARNING] use labled clock "+self.clockLabled[0]+" as comparator clock, please check")
        if self.clockLabledNum > 1:
          myprint ("[FATAL] but more than one 'CLK' clock when no 'MCLK' clock , please check")
          #fatal()
          self.autoError = True
          sys.exit()
      elif self.clockInfedNum >= 1:
        self.clock = self.clockInfed[0]
        myprint ("[WARNING] use inferred clock "+self.clockInfed[0]+" as comparator clock, please check")
        if self.clockInfedNum > 1:
          myprint ("[FATAL] but more than one inferred clock when no 'CLK' and 'MCLK' clock , please check")
          #fatal()
          self.autoError = True
          sys.exit()
    elif self.clockMainNum >= 1:
      self.clock = self.clockMain[0]
      if self.clockMainNum > 1 :
        myprint ("[FATAL] more than one DCLS clock , please check")
        #fatal()
        self.autoError = True
        sys.exit()

    if self.fatherModule[0].fusaclk is True:
      for eachclock in self.clockMain:
        self.checkClockFUSA(eachclock+"_fusa")
      for eachclock in self.clockLabled:
        self.checkClockFUSA(eachclock+"_fusa")
      for eachclock in self.clockInfed:
        self.checkClockFUSA(eachclock+"_fusa")
      self.clockCmp = self.clock+"_fusa"
    else:
      self.clockCmp = self.clock
    myprint ("[INFO] comparator clock is "+self.clockCmp)
    global Clockbuffer
    Clockbuffer = copy.deepcopy(self.clock)
    global IClockbuffer
    IClockbuffer = copy.deepcopy(self.clockInfed)
#   print("xxxxxxxx",Clockbuffer)
    global ResetRecord
    ResetRecord = copy.deepcopy(self.reset)
#   global inferreset
#   Inferreset = copy.deepcopy(self.resetInfed)
#   global inferresetNum
#   InferresetNum = copy.deepcopy(self.resetInfedNum)
#   unbelieve bug
    global Testlab
    Testlab = copy.deepcopy(self.resetInfedNum)
    global Teststn
    Teststn = copy.deepcopy(self.resetInfed)
    global Signalchk
    Signalchk = copy.deepcopy(self.chksignal)
    global Signalchkwidth
    Signalchkwidth = copy.deepcopy(self.chksignalwidth)



    if self.reset is "":
      self.reset = "reset_n"

    outnum = 0
    innum = 0
    for cont in self.contObjs:
      if cont.iotype is "OUT" or cont.iotype is "FORCEO":
        outnum += 1
      elif cont.iotype is "IN" or cont.iotype is "FORCEI":
        innum += 1
      elif cont.iotype is "CONST" :
        innum += 1
      elif cont.iotype is "RST" or cont.iotype is "IRST" or cont.iotype is "ISPRST" or cont.iotype is "SCAN"or cont.iotype is "ICG":
        innum += 1
      elif cont.iotype is "LCLK"  or cont.iotype is "ICLK"  or cont.iotype is "MCLK":
        innum += 1
    dbgprint("num of outport is "+str(outnum),self.debug)
    dbgprint("num of inport is "+str(innum),self.debug)


  def getDefaultValue(self,cont):
    if cont.iotype is "IN" or cont.iotype is "IRST" or cont.iotype is "ISPRST" or cont.iotype is "FORCEI":
      s = re.search('.*//.*default\s*([^\s]*)\s*',cont.line.rstrip())
      if s is None:
        cont.defaultValue = "0"
      else:
        if re.match("ALL_0",s.group(1)) is not None:
          cont.defaultValue = 0
        elif re.match("ALL_1",s.group(1)) is not None:
          cont.defaultValue = "{("+cont.width+"){1'b1}}"
        else:
          cont.defaultValue = s.group(1)

  def getRefWidth(self,cont):
    # signals declaration
    if cont.iotype is "CONST" or cont.iotype is "NC":
      return
    signal = cont.refname
    done = False
    pos = 0
    if cont.iotype is not "OUT" and cont.iotype is not "FORCEO":
      cont.refUsed = True
    for eachline in self.srclines:
      pos += 1
      if pos > self.insStartPos and pos < self.insEndPos :
        continue
      # pre-process
      eachline = re.sub("//.*","",eachline)# remove commit
      eachline = re.sub(" signed "," ",eachline)# remove keyword
      eachline = re.sub(" unsigned"," ",eachline)# remove keyword
      # the first positon is considered as the signal declaration
      if done is False and re.search('(wire|output|reg|input)[^a-zA-Z0-9_]+(.*[^a-zA-Z0-9_]+|\s*)'+signal+'[^a-zA-Z0-9_]',eachline) is not None:
        s= re.search('(wire|output|reg|input)[^a-zA-Z0-9_]+(.*[^a-zA-Z0-9_]+|\s*)',eachline)
        #print(s.group(0),"!!!!!!!!!!!!!!")
        cont.refDeclared = True
        #myprint(signal+" : "+eachline)
        s = re.search('(wire|output|reg|input)\s*(\[.*\])?\s*'+signal,eachline)
        #print signal.rstrip()
        #print eachline.rstrip()
        if s.group(2) is None:  # 1-bit signal
          cont.widthStr = " "
          cont.width = "1"
        else:
          cont.widthStr = s.group(2)
          cont.width = cont.widthStr.replace("[","")
          cont.width = re.sub(':.*\]',"",cont.width)
          cont.width = "("+cont.width+"+1)"
          #print cont.refnameDCLS+"  "+cont.widthStr+" test  "+cont.width
        done = True
        if re.search('(output).*[^a-zA-Z0-9_]'+signal+'[^a-zA-Z0-9_]',eachline) is not None:
          cont.refUsed = True
        #break
      elif done is True:
        tmpline = re.sub('\.'+signal+'\s*\(',"(",eachline)
        if re.search('[^a-zA-Z0-9_]'+signal+'[^a-zA-Z0-9_]',tmpline) is not None:
          cont.refUsed = True
          #myprint(signal+" - "+eachline.rstrip())
          #myprint(signal+" -- "+tmpline.rstrip())
      if done==False:
        if cont.iotype is "IN" or cont.iotype is "FORCEI":
          myprint ("[WARNING] cannot find the declaraion of signal '"+signal+"' for input '"+cont.refname+"'")
          myprint ("                it's will be considered as 1-bit wire")
          self.autoWarning = True
      else :
        myprint ("[ERROR] cannot find the declaraion of signal "+signal)
        self.autoError = True

  def ProcbufLines(self):
    myprint ("[INFO] generating buffer connection")
    #for cont in self.contObjs:
    #   s = re.search('\(\s*'+cont.refname,cont.line)
    #   if s is not None:
    #       if cont.iotype is "LCLK" :
    #         sign= cont.line.split(")")[0].split("(")[1].strip()
#   newline = "cell_ckbuf "+self.insName+"_fusadcls_buf(.I("+self.clock+"), .Z("+self.clock+self.bufferSuffix()+"));\n"
#   self.bufLines.append(newline)
#   newline = "cell_mux2 u_"+self.insName+"_dual_rst(.I0("+"dcls_"+self.reset+self.delaySuffix(self.delayNum)+"), .I1("+self.reset+"), .S("+self.scan+"), .Z(dcls_"+self.reset+self.delaySuffix(self.delayNum)+"_scan));\n"
#   self.bufLines.append(newline)
#   if Testlab is not 0 :
#       for rstext in list(set(Teststn)):
#           newline = "cell_mux2 u_"+self.insName+"_"+rstext+"_dual_rst(.I0(dcls_"+rstext+self.delaySuffix(self.delayNum)+"), .I1("+rstext+"), .S("+self.scan+"),.Z(dcls_"+rstext+self.delaySuffix(self.delayNum)+"_scan));\n"
#           self.bufLines.append(newline)
    if self.delayNum is 0 :
      for cont in self.contObjs:
        s = re.search('\(\s*'+cont.refname,cont.line)
        if s is not None:
          if cont.iotype is "LCLK" :
            newname = cont.line.split(")")[0].split("(")[1].strip()
            newline = "cell_ckinv u_"+newname+"_i(.I("+newname+"), .ZN("+newname+"_buf_inv));\n"
            self.bufLines.append(newline)
          elif cont.iotype is "ICLK" or cont.iotype is "MCLK":
            newname = cont.line.split(")")[0].split("(")[1].strip()
            newline = "cell_ckinv u_"+newname+"_i(.I("+newname+"), .ZN("+newname+"_inv));\n"
            self.bufLines.append(newline)
  def ProcInsLines(self):
    myprint ("[INFO] generating instance connection")
    for cont in self.contObjs:
      s = re.search('\(\s*'+cont.refname,cont.line)
      #print(cont.refname + cont.iotype)
      if s is not None:
        if cont.iotype is "NC" :
          newline = re.sub('\(.*\)',"(   )",cont.line)
          #print cont.line
          #print newline
        elif cont.iotype is "CONST" :
          newline = cont.line
        elif cont.iotype is "LCLK" :
          if self.delayNum is 0 :
            newline = cont.line.replace(s.group(1)+cont.refname,s.group(1)+cont.refname+"_buf_inv" )
          elif self.fatherModule[0].fusaclk is False:
            newline = cont.line.split("(")[0]+"("+cont.line.split(")")[0].split("(")[1].strip()+self.bufferSuffix()+ ")"+cont.line.split(")")[1]
          else:
            newline = cont.line.replace(s.group(1)+cont.refname,s.group(1)+cont.refname+"_fusa" )
        elif  cont.iotype is "ICLK" or cont.iotype is "MCLK":
          if self.delayNum is 0 :
            newline = cont.line.replace(s.group(1)+cont.refname,s.group(1)+cont.refname+"_inv" )
#         elif self.fatherModule[0].multclk is True:
#           newline = cont.line
#           newline = cont.line.replace(s.group(1)+cont.refname,s.group(1)+cont.refname+"_dcls" )
          elif self.fatherModule[0].fusaclk is False:
#           newline = cont.line
            newline = cont.line.replace(s.group(1)+cont.refname,s.group(1)+cont.refname+"_dcls" )
          else:
            newline = cont.line.replace(s.group(1)+cont.refname,s.group(1)+cont.refname+"_fusa" )
        elif cont.iotype is "RST" or cont.iotype is "IRST" or cont.iotype is "ISPRST":
          #newline = cont.line
          #newline = cont.line.split("(")[0]+"("+"dcls_"+cont.line.split(")")[0].split("(")[1].strip()+self.delaySuffix(self.delayNum)+ "_scan"+cont.line.split(")")[1]
          newline = cont.line.split("(")[0]+"("+cont.line.split(")")[0].split("(")[1].strip()+")"+cont.line.split(")")[1]
          #if self.delayNum is 0:
          #  newline = cont.line
          #else:
          #  newline = cont.line.replace(s.group(1)+cont.refname,s.group(1)+"reset_n_d["+str(self.delayNum)+"]" )
        elif cont.iotype is "SCAN" or cont.iotype is "ICG":
          newline = cont.line.replace(s.group(1)+cont.refname,s.group(1)+cont.refname)
        elif cont.iotype is "IN"  or cont.iotype is "FORCEI":
          newline = cont.line.replace(s.group(1)+cont.refname,s.group(1)+cont.refnameDCLS+self.delaySuffix(self.delayNum))
        else:
          newline = cont.line.replace(s.group(1)+cont.refname,s.group(1)+cont.refnameDCLS)
        #add ',' for some special case
        if re.search('\)\s*,',newline) is None:
          newline = newline.replace(")",",")
        self.insLines.append(newline)
      else:
        myprint("[ERROR] port '"+cont.portname+"' has wrong connection ")
        myprint (cont.line)
        self.autoError = True
    self.insLines[-1] = self.insLines[-1].replace("),",",") #replace
    self.insLines[-1] = self.insLines[-1].replace(");","") #replace
    self.insLines.append("     );\n")

  def isClkRst(self,signal):
    if re.search("(clk|clock|rst_n|reset_n)",signal) is not None:
      return True

  def isDeclared(self,signal):
    declared = False
    for eachsignal in self.delaySignals :
      if cmp(eachsignal,signal) is 0:
        declared = True
      #print "compare "+eachsignal+"  =?   "+signal
      #if declared :
      #  print "------------yes "
    return declared

  def isDeclaredAsFatherInPort(self,signal):
    declared = False
    do = True
    for eachline in self.srclines:
      if re.match('\s*function',eachline):
        do = False
        continue
      if re.match('\s*endfunction',eachline):
        do = True
        continue
      if do is False:
        continue
      if re.match('\s*input[^a-zA-Z0-9_]+.*'+signal,eachline) is not None:
        declared = True
        break
    return declared

  #check fusa clock
  def checkClockFUSA(self,clock):
    #myprint("check clock "+clock)
    if self.isDeclaredAsFatherInPort(clock) is False:
      myprint ("[FATAL] no dedicated clock input for FUSA in degin : "+self.fatherModule[0].moduleName)
      myprint ("            function clock   : "+clock.replace('_fusa',""))
      myprint ("            fusa clock needed : "+clock)
      #fatal()
      self.autoError = True


  def ProcSigLines(self):
    "generate signals declaration"
    myprint ("[INFO] generating signals declaration")
    # for DCLS instance connection
    for cont in self.contObjs:
      if cont.iotype is "OUT" or cont.iotype is "FORCEO":
        newline = "wire "+cont.widthStr+" "+cont.refnameDCLS+";\n"
        self.sigLines.append(newline)
      elif cont.iotype is "IN"  or cont.iotype is "FORCEI":#or cont.iotype is "IRST":
        if self.isDeclared(cont.refnameDCLS) is False:
          newline = "wire "+cont.widthStr+" "+cont.refnameDCLS+";\n"
          self.sigLines.append(newline)
    for cont in self.contObjs:
      if cont.iotype is "IN"  or cont.iotype is "FORCEI":#or cont.iotype is "IRST":
      for i in range(1,self.delayNum+1):
        if self.isDeclared(cont.refnameDCLS+self.delaySuffix(i)) is False:
          newline = "reg  "+cont.widthStr+" "+cont.refnameDCLS+self.delaySuffix(i)+";\n"
          self.sigLines.append(newline)
    for cont in self.contObjs:
      if cont.iotype is "OUT" or cont.iotype is "FORCEO":
        for i in range(1,self.delayNum+1):
          newline = "reg  "+cont.widthStr+" "+cont.refname+self.delaySuffix(i)+";\n"
          self.sigLines.append(newline)
#    print("*&^%$#@#$%^&*&^%$#@")
#    for cont in self.contObjs:
#      print(cont.widthStr,"@@@@@@@@@@@@@@@@@@@@@@@@@@@")
#      if cont.iotypeplus is "ICHK":
#        print(cont.widthStr,"@@@@@@@@@@@@@@@@@@@@@@@@@@@")
#        chksignalwidth = cont.widthStr



  def delaySuffix(self,num):
    if num is 0:
      return ""
    else:
      return "_d"+str(num)

  def bufferSuffix(self):
    #return "_buf"
    return "_dcls"

  def ProcDlyLines(self):
    "generate delay signals declaration"
    myprint ("[INFO] generating delay signals declaration")
    for cont in self.contObjs:
      if cont.iotype is "IN"  or cont.iotype is "FORCEI":#or cont.iotype is "IRST":
        if self.isDeclared(cont.refnameDCLS) is False:
          if cont.iotypeplus is "ICHK":
            newline = "assign "+cont.refnameDCLS+"= "+cont.refname+"_chk;\n"
            self.dlyLines.append(newline)
            self.delaySignals.append(cont.refnameDCLS)
          else:
            newline = "assign "+cont.refnameDCLS+"= "+cont.refname+";\n"
            self.dlyLines.append(newline)
            self.delaySignals.append(cont.refnameDCLS)
          #print "add "+cont.refnameDCLS

    if self.delayNum is not 0:
      self.dlyLines.append("always @(posedge "+self.clock+")\n")
      self.dlyLines.append("      begin\n")
      for cont in self.contObjs:
        if cont.iotype is "IN"  or cont.iotype is "FORCEI":#or cont.iotype is "IRST":
          for i in range(1,self.delayNum+1):
            if self.isDeclared(cont.refnameDCLS+self.delaySuffix(i)) is False:
              newline = "        "+cont.refnameDCLS+self.delaySuffix(i)+" <= "+cont.refnameDCLS+self.delaySuffix(i-1)+";\n"
              self.dlyLines.append(newline)
              self.delaySignals.append(cont.refnameDCLS+self.delaySuffix(i))
              #print "add "+cont.refnameDCLS+self.delaySuffix(i)
      for cont in self.contObjs:
        if cont.iotype is "OUT" or cont.iotype is "FORCEO":
          for i in range(1,self.delayNum+1):
            newline = "        "+cont.refname+self.delaySuffix(i)+" <= "+cont.refname+self.delaySuffix(i-1)+";\n"
            self.dlyLines.append(newline)
      self.dlyLines.append("    end\n")
      self.dlyLines.append("\n")

  def ProcSigDlyLines(self):
    "generate signals declaration and assignment"
    myprint ("[INFO] generating delay signals declaration")

    tmpLines = []
    for cont in self.contObjs:
      if cont.iotype is "OUT" or cont.iotype is "FORCEO":
        newline = "wire "+cont.widthStr+" "+cont.refnameDCLS+";\n"
        self.sigLines.append(newline)
        #newline = newline.replace(DCLSSuffixO,DCLSSuffixD)
        #self.sigLines.append(newline)
        #newline = "assign "+cont.refname+DCLSSuffixD+"= "+cont.refname+";\n"
        #self.dlyLines.append(newline)
        #self.delaySignals.append(cont.refname+DCLSSuffixD)
      elif cont.iotype is "IN"  or cont.iotype is "FORCEI":#or cont.iotype is "IRST":
        if self.isDeclared(cont.refnameDCLS) is False:
          newline = "wire "+cont.widthStr+" "+cont.refnameDCLS+";\n"
          self.sigLines.append(newline)
          newline = "assign "+cont.refnameDCLS+"= "+cont.refname+";\n"
          self.dlyLines.append(newline)
          self.delaySignals.append(cont.refnameDCLS)
        #  print "add "+cont.refnameDCLS+" into list"
        #else :
        #  print cont.refnameDCLS+" already in list"

    if self.delayNum is not 0:
      self.dlyLines.append("always @(posedge "+self.clock+" or negedge "+self.reset+")\n")
      #self.dlyLines.append("always @(posedge clk)\n")
      self.dlyLines.append("      if (!"+self.reset+") begin\n")
      for cont in self.contObjs:
        if cont.iotype is "IN"  or cont.iotype is "FORCEI":#or cont.iotype is "IRST":
          for i in range(1,self.delayNum+1):
            if self.isDeclared(cont.refnameDCLS+self.delaySuffix(i)) is False:
              newline = "reg  "+cont.widthStr+" "+cont.refnameDCLS+self.delaySuffix(i)+";\n"
              self.sigLines.append(newline)
              newline = "        "+cont.refnameDCLS+self.delaySuffix(i)+" <= 0;\n"
              self.dlyLines.append(newline)
              newline = "        "+cont.refnameDCLS+self.delaySuffix(i)+" <= "+cont.refnameDCLS+self.delaySuffix(i-1)+";\n"
              tmpLines.append(newline)
              self.delaySignals.append(cont.refnameDCLS+self.delaySuffix(i))
            #  print "add "+cont.refnameDCLS+self.delaySuffix(i)+" into list"
            #else :
            #  print cont.refnameDCLS+self.delaySuffix(i)+" already in list"
      for cont in self.contObjs:
        if cont.iotype is "OUT" or cont.iotype is "FORCEO":
          for i in range(1,self.delayNum+1):
            newline = "reg  "+cont.widthStr+" "+cont.refname+DCLSSuffixD+self.delaySuffix(i)+";\n"
            self.sigLines.append(newline)
            newline = "        "+cont.refname+DCLSSuffixD+self.delaySuffix(i)+" <= 0;\n"
            self.dlyLines.append(newline)
            if i is 1:
              newline = "        "+cont.refname+DCLSSuffixD+self.delaySuffix(i)+" <= "+cont.refname+self.delaySuffix(i-1)+";\n"
            else:
              newline = "        "+cont.refname+DCLSSuffixD+self.delaySuffix(i)+" <= "+cont.refname+DCLSSuffixD+self.delaySuffix(i-1)+";\n"
            tmpLines.append(newline)
            print str(i)
            print newline

      self.dlyLines.append("    end else if (dcls_fault_injection) begin\n")
      for eachline in tmpLines:
        self.dlyLines.append(eachline)
      self.dlyLines.append("    end\n")
      self.dlyLines.append("\n")

  def ProcCmpLines(self):
    "generate comparator logic"
    myprint ("[INFO] generating comparator logic")


    if self.delayNum is not 0:

      for i in range(1,self.delayNum+1):
        if self.isDeclared("dcls_fault_injection"+self.delaySuffix(i)) is False:
          self.delaySignals.append("dcls_fault_injection"+self.delaySuffix(i))
          self.dlyLines.append("reg dcls_fault_injection"+self.delaySuffix(i)+";\n")
          self.dlyLines.append("always @(posedge "+self.clock+" or negedge "+self.reset+")\n")
          self.dlyLines.append("      if (!"+self.reset+")\n")
          self.dlyLines.append("        dcls_fault_injection"+self.delaySuffix(i)+" <= 2'b00;\n")
          self.dlyLines.append("      else\n")
          self.dlyLines.append("        dcls_fault_injection"+self.delaySuffix(i)+" <= dcls_fault_injection"+self.delaySuffix(i-1)+";\n")
      if self.isDeclared(self.clockGated) is False:
        self.delaySignals.append(self.clockGated)
        self.dlyLines.append("wire "+self.clockGated+";\n")
        self.dlyLines.append("cell_ckgate u_cg_"+self.insName+" (.TE(1'b0),.CP("+self.clock+"),.E(dcls_fault_injection"+self.delaySuffix(self.delayNum)+"),.Q("+self.clockGated+"));\n")

      if self.fatherIsSubtop :
        self.cmpLines.append("wire   "+self.errSignals[0]+" ; \n");
      self.cmpLines.append("assign "+self.errSignals[0]+" = \n");
      self.cmpLines.append("            dcls_fault_injection"+self.delaySuffix(self.delayNum)+" && ( \n");
      for cont in self.contObjs:
        if cont.iotype is "OUT" or cont.iotype is "FORCEO":
          self.cmpLines.append("           ("+cont.refname+DCLSSuffixD+self.delaySuffix(self.delayNum)+" != "+cont.refnameDCLS+") || \n" )
      self.cmpLines[-1] = self.cmpLines[-1].replace("||",");") #replace '||' symbol

  def NewProcSigDlyLines(self):
    "generate signals declaration and assignment"
    myprint ("[INFO] generating delay signals declaration")

    tmpLines = []
    for cont in self.contObjs:
      if cont.iotype is "OUT" or cont.iotype is "FORCEO":
        newline = "wire "+cont.widthStr+" "+cont.refnameDCLS+";\n"
        self.sigLines.append(newline)
      elif cont.iotype is "IN"  or cont.iotype is "FORCEI":
        if self.isDeclared(cont.refnameDCLS) is False:
          newline = "wire "+cont.widthStr+" "+cont.refnameDCLS+";\n"
          self.sigLines.append(newline)
          if cont.iotypeplus is "ICHK":
            newline = "assign "+cont.refnameDCLS+"= "+cont.refname+"_chk;\n"
            self.dlyLines.append(newline)
            self.delaySignals.append(cont.refnameDCLS)
          else:
            newline = "assign "+cont.refnameDCLS+"= "+cont.refname+";\n"
            self.dlyLines.append(newline)
            self.delaySignals.append(cont.refnameDCLS)
      elif cont.iotype is "LCLK" :
        newline = "wire "+cont.widthStr+" "+self.clock+self.bufferSuffix()+";\n"
        self.sigLines.append(newline)
        if self.delayNum is 0 :
          newline = "wire "+cont.widthStr+" "+self.clock+self.bufferSuffix()+"_inv";\n"
          self.sigLines.append(newline)
        #  newline = "assign "+"\""+self.clock+self.bufferSuffix()+"_inv = ~"+self.clock+self.bufferSuffix()+";\n"
        #  self.dlyLines.append(newline)
#     elif cont.iotype is "RST" :
#       newline = "wire "+cont.widthStr+" "+"dcls_"+self.reset+";\n"
#       self.sigLines.append(newline)
#       newline = "wire "+cont.widthStr+" "+"dcls_"+self.reset+self.delaySuffix(self.delayNum)+"_scan;\n"
#       self.sigLines.append(newline)
#       newline = "assign "+"\""+"dcls_"+self.reset+" = "+self.reset+";\n"
#       self.dlyLines.append(newline)
#     elif cont.iotype is "IRST" :
#       if self.isDeclared(cont.refnameDCLS) is False:
#         newline = "wire "+cont.widthStr+" "+cont.refnameDCLS+";\n"
#         self.sigLines.append(newline)
#         newline = "wire "+cont.widthStr+" "+"dcls_"+cont.refname+self.delaySuffix(self.delayNum)+"_scan;\n"
#         self.sigLines.append(newline)
#         newline = "assign "+cont.refnameDCLS+"= "+cont.refname+";\n"
#         self.dlyLines.append(newline)
#         self.delaySignals.append(cont.refnameDCLS)
      elif cont.iotype is "ICLK" or cont.iotype is "MCLK":
        if self.delayNum is 0 :
          newname = cont.line.split(")")[0].split("(")[1].strip()
          newline = "wire "+cont.widthStr+" "+newname+"_inv;\n"
          self.sigLines.append(newline)
        else:
          newname = cont.line.split(")")[0].split("(")[1].strip()
          newline = "wire "+cont.widthStr+" "+newname+"_dcls;\n"
          self.sigLines.append(newline)
    if self.delayNum is not 0:
      self.dlyLines.append("//input delay\n")
      #### delay without reset
      #self.dlyLines.append("always @(posedge clk) \n")
      #self.dlyLines.append("    if (dcls_fault_injection) begin\n")
      #for cont in self.contObjs:
      # if cont.iotype is "IN":
      #   for i in range(1,self.delayNum+1):
      #     if self.isDeclared(cont.refnameDCLS+self.delaySuffix(i)) is False:
      #       newline = "reg "+cont.widthStr+" "+cont.refnameDCLS+self.delaySuffix(i)+";\n"
      #       self.sigLines.append(newline)
      #       newline = "        "+cont.refnameDCLS+self.delaySuffix(i)+" <= "+cont.refnameDCLS+self.delaySuffix(i-1)+";\n"
      #       self.dlyLines.append(newline)
      #       self.delaySignals.append(cont.refnameDCLS+self.delaySuffix(i))
      #self.dlyLines.append("    end\n")
      #self.dlyLines.append("\n")

      #### delay with reset
      #self.dlyLines.append("always @(posedge "+self.clock+self.bufferSuffix()+" or negedge "+self.reset+")\n")
      self.dlyLines.append("always @(posedge "+self.clock+" or negedge "+self.reset+")\n")
      self.dlyLines.append("    if (!"+self.reset+") begin\n")
      #### 1.2.0 add
      for cont in self.contObjs:
        if cont.iotype is "LCLK" :
            for i in range(1,self.delayNum+1):
#        if self.isDeclared(cont.refnameDCLS+self.delaySuffix(i)) is False:
              newline = "reg    "+"main_clk_en_dcls"+self.delaySuffix(i)+";\n"
              self.sigLines.append(newline)
              newline = "        "+"main_clk_en_dcls"+self.delaySuffix(i)+" <= "+"0;\n"
              self.dlyLines.append(newline)
              if i == 1:
                newline = "        "+"main_clk_en_dcls"+self.delaySuffix(i)+" <= 1'b1;\n"
                tmpLines.append(newline)
              else:
                newline = "        "+"main_clk_en_dcls"+self.delaySuffix(i)+" <= "+"main_clk_en_dcls"+self.delaySuffix(i-1)+";\n"
                tmpLines.append(newline)
              self.delaySignals.append("main_clk_en_dcls"+self.delaySuffix(i))
        if cont.iotype is "ICLK" :
            for i in range(1,self.delayNum+1):
#        if self.isDeclared(cont.refnameDCLS+self.delaySuffix(i)) is False:
              newline = "reg    "+cont.refname+"_en_dcls"+self.delaySuffix(i)+";\n"
              self.sigLines.append(newline)
              newline = "        "+cont.refname+"_en_dcls"+self.delaySuffix(i)+" <= "+"0;\n"
              self.dlyLines.append(newline)
              if i == 1:
                newline = "        "+cont.refname+"_en_dcls"+self.delaySuffix(i)+" <= 1'b1;\n"
                tmpLines.append(newline)
              else:
                newline = "        "+cont.refname+"_en_dcls"+self.delaySuffix(i)+" <= "+cont.refname+"_en_dcls"+self.delaySuffix(i-1)+";\n"
                tmpLines.append(newline)
              self.delaySignals.append(cont.refname+"_en_dcls"+self.delaySuffix(i))

      #### 1.2.0 add
      for cont in self.contObjs:
        if cont.iotype is "IN"  or cont.iotype is "FORCEI":
          for i in range(1,self.delayNum+1):
            if self.isDeclared(cont.refnameDCLS+self.delaySuffix(i)) is False:
              newline = "reg "+cont.widthStr+" "+cont.refnameDCLS+self.delaySuffix(i)+";\n"
              self.sigLines.append(newline)
              newline = "        "+cont.refnameDCLS+self.delaySuffix(i)+" <= "+cont.defaultValue+";\n"
              self.dlyLines.append(newline)
              newline = "        "+cont.refnameDCLS+self.delaySuffix(i)+" <= "+cont.refnameDCLS+self.delaySuffix(i-1)+";\n"
              tmpLines.append(newline)
              self.delaySignals.append(cont.refnameDCLS+self.delaySuffix(i))
#     for cont in self.contObjs:
#       if cont.iotype is "IRST":
#         for i in range(1,self.delayNum+1):
#           if self.isDeclared(cont.refnameDCLS+self.delaySuffix(i)) is False:
#             newline = "reg "+cont.widthStr+" "+cont.refnameDCLS+self.delaySuffix(i)+";\n"
#             self.sigLines.append(newline)
#             #newline = "        "+cont.refnameDCLS+self.delaySuffix(i)+" <= "+cont.defaultValue+";\n"
#             newline = "        "+cont.refnameDCLS+self.delaySuffix(i)+" <= 1;\n"
#             self.dlyLines.append(newline)
#             newline = "        "+cont.refnameDCLS+self.delaySuffix(i)+" <= "+cont.refnameDCLS+self.delaySuffix(i-1)+";\n"
#             tmpLines.append(newline)
#             self.delaySignals.append(cont.refnameDCLS+self.delaySuffix(i))
#
#     for cont in self.contObjs:
#       if cont.iotype is "RST":
#         for i in range(1,self.delayNum+1):
#           if self.isDeclared(cont.refnameDCLS+self.delaySuffix(i)) is False:
#             newline = "reg "+cont.widthStr+" "+"dcls_"+self.reset+self.delaySuffix(i)+";\n"
#             self.sigLines.append(newline)
#             newline = "        "+"dcls_"+self.reset+self.delaySuffix(i)+" <= 1"+cont.defaultValue+";\n"
#             self.dlyLines.append(newline)
#             newline = "        "+"dcls_"+self.reset+self.delaySuffix(i)+" <= "+"dcls_"+self.reset+self.delaySuffix(i-1)+";\n"
#             tmpLines.append(newline)
#             self.delaySignals.append("dcls_"+self.reset+self.delaySuffix(i))
      if self.fatherModule[0].fusaclk is True:
        self.dlyLines.append("    end else if (dcls_fault_injection) begin\n")
      else:
        self.dlyLines.append("    end else begin\n")

      for eachline in tmpLines:
        self.dlyLines.append(eachline)
      self.dlyLines.append("    end\n")
      self.dlyLines.append("\n")
      #### 1.2.0 add
      for cont in self.contObjs:
        if cont.iotype is "LCLK" :
