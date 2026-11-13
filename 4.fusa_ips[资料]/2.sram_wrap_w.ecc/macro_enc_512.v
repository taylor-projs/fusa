//*###############################################################################
//*#         Compiler Name    : tsmc_ecc_gen
//*#	     Compiler Version : 140b
//*#         ECC type         : SEC/DED
//*#         Generated Time   : 2026/06/18, 14:53:47
//*###############################################################################
//*#
//*#
//*# STATEMENT OF USE
//*#
//*# This information contains confidential and proprietary information of TSMC.
//*# No part of this information may be reproduced, transmitted, transcribed,
//*# stored in a retrieval system, or translated into any human or computer
//*# language, in any form or by any means, electronic, mechanical, magnetic,
//*# optical, chemical, manual, or otherwise, without the prior written permission
//*# of TSMC. This information was prepared for informational purpose and is for
//*# use by TSMC's customers only. TSMC reserves the right to make changes in the
//*# information at any time and without notice.
//*#
//*###############################################################################
//* 
module macro_enc_513(
input  ecc_encoder_bypass,
input  [512:0] ecc_encoder_data_in,
input  [10:0] ecc_encoder_parity_in,
output [523:0] ecc_encoder_data_out,
output [10:0] ecc_encoder_parity_out
);

wire [512:0] ecc_enc_in;

wire [10:0] parity_enc;
//=========================================
//============== ECC Encoder ===============
//=========================================

//Hamming Code -- Parity Check Encoding
assign ecc_enc_in = ecc_encoder_data_in;

assign parity_enc[00] = ~( ecc_enc_in[000] ^ ecc_enc_in[001] ^ ecc_enc_in[002] ^
                          ecc_enc_in[004] ^ ecc_enc_in[005] ^ ecc_enc_in[007] ^
                          ecc_enc_in[010] ^ ecc_enc_in[011] ^ ecc_enc_in[012] ^
                          ecc_enc_in[014] ^ ecc_enc_in[017] ^ ecc_enc_in[018] ^
                          ecc_enc_in[021] ^ ecc_enc_in[023] ^ ecc_enc_in[025] ^
                          ecc_enc_in[026] ^ ecc_enc_in[028] ^ ecc_enc_in[031] ^
                          ecc_enc_in[034] ^ ecc_enc_in[037] ^ ecc_enc_in[040] ^
                          ecc_enc_in[043] ^ ecc_enc_in[044] ^ ecc_enc_in[048] ^
                          ecc_enc_in[049] ^ ecc_enc_in[051] ^ ecc_enc_in[054] ^
                          ecc_enc_in[055] ^ ecc_enc_in[058] ^ ecc_enc_in[060] ^
                          ecc_enc_in[061] ^ ecc_enc_in[062] ^ ecc_enc_in[065] ^
                          ecc_enc_in[067] ^ ecc_enc_in[068] ^ ecc_enc_in[071] ^
                          ecc_enc_in[072] ^ ecc_enc_in[074] ^ ecc_enc_in[077] ^
                          ecc_enc_in[080] ^ ecc_enc_in[082] ^ ecc_enc_in[083] ^
                          ecc_enc_in[086] ^ ecc_enc_in[087] ^ ecc_enc_in[089] ^
                          ecc_enc_in[093] ^ ecc_enc_in[094] ^ ecc_enc_in[096] ^
                          ecc_enc_in[099] ^ ecc_enc_in[100] ^ ecc_enc_in[102] ^
                          ecc_enc_in[105] ^ ecc_enc_in[106] ^ ecc_enc_in[109] ^
                          ecc_enc_in[111] ^ ecc_enc_in[112] ^ ecc_enc_in[114] ^
                          ecc_enc_in[117] ^ ecc_enc_in[119] ^ ecc_enc_in[120] ^
                          ecc_enc_in[123] ^ ecc_enc_in[124] ^ ecc_enc_in[125] ^
                          ecc_enc_in[128] ^ ecc_enc_in[131] ^ ecc_enc_in[133] ^
                          ecc_enc_in[134] ^ ecc_enc_in[137] ^ ecc_enc_in[138] ^
                          ecc_enc_in[139] ^ ecc_enc_in[142] ^ ecc_enc_in[143] ^
                          ecc_enc_in[145] ^ ecc_enc_in[150] ^ ecc_enc_in[154] ^
                          ecc_enc_in[161] ^ ecc_enc_in[162] ^ ecc_enc_in[167] ^
                          ecc_enc_in[169] ^ ecc_enc_in[172] ^ ecc_enc_in[174] ^
                          ecc_enc_in[178] ^ ecc_enc_in[179] ^ ecc_enc_in[181] ^
                          ecc_enc_in[184] ^ ecc_enc_in[185] ^ ecc_enc_in[189] ^
                          ecc_enc_in[191] ^ ecc_enc_in[195] ^ ecc_enc_in[196] ^
                          ecc_enc_in[198] ^ ecc_enc_in[199] ^ ecc_enc_in[201] ^
                          ecc_enc_in[202] ^ ecc_enc_in[205] ^ ecc_enc_in[207] ^
                          ecc_enc_in[208] ^ ecc_enc_in[211] ^ ecc_enc_in[212] ^
                          ecc_enc_in[214] ^ ecc_enc_in[218] ^ ecc_enc_in[219] ^
                          ecc_enc_in[223] ^ ecc_enc_in[226] ^ ecc_enc_in[229] ^
                          ecc_enc_in[231] ^ ecc_enc_in[232] ^ ecc_enc_in[235] ^
                          ecc_enc_in[236] ^ ecc_enc_in[240] ^ ecc_enc_in[241] ^
                          ecc_enc_in[243] ^ ecc_enc_in[246] ^ ecc_enc_in[251] ^
                          ecc_enc_in[258] ^ ecc_enc_in[261] ^ ecc_enc_in[263] ^
                          ecc_enc_in[266] ^ ecc_enc_in[267] ^ ecc_enc_in[271] ^
                          ecc_enc_in[277] ^ ecc_enc_in[278] ^ ecc_enc_in[280] ^
                          ecc_enc_in[283] ^ ecc_enc_in[286] ^ ecc_enc_in[291] ^
                          ecc_enc_in[292] ^ ecc_enc_in[294] ^ ecc_enc_in[296] ^
                          ecc_enc_in[300] ^ ecc_enc_in[304] ^ ecc_enc_in[309] ^
                          ecc_enc_in[310] ^ ecc_enc_in[312] ^ ecc_enc_in[315] ^
                          ecc_enc_in[316] ^ ecc_enc_in[319] ^ ecc_enc_in[321] ^
                          ecc_enc_in[322] ^ ecc_enc_in[324] ^ ecc_enc_in[328] ^
                          ecc_enc_in[329] ^ ecc_enc_in[332] ^ ecc_enc_in[333] ^
                          ecc_enc_in[336] ^ ecc_enc_in[340] ^ ecc_enc_in[341] ^
                          ecc_enc_in[343] ^ ecc_enc_in[344] ^ ecc_enc_in[348] ^
                          ecc_enc_in[349] ^ ecc_enc_in[353] ^ ecc_enc_in[356] ^
                          ecc_enc_in[359] ^ ecc_enc_in[361] ^ ecc_enc_in[363] ^
                          ecc_enc_in[364] ^ ecc_enc_in[366] ^ ecc_enc_in[369] ^
                          ecc_enc_in[371] ^ ecc_enc_in[377] ^ ecc_enc_in[378] ^
                          ecc_enc_in[381] ^ ecc_enc_in[385] ^ ecc_enc_in[389] ^
                          ecc_enc_in[392] ^ ecc_enc_in[394] ^ ecc_enc_in[397] ^
                          ecc_enc_in[398] ^ ecc_enc_in[402] ^ ecc_enc_in[403] ^
                          ecc_enc_in[406] ^ ecc_enc_in[410] ^ ecc_enc_in[412] ^
                          ecc_enc_in[415] ^ ecc_enc_in[418] ^ ecc_enc_in[423] ^
                          ecc_enc_in[424] ^ ecc_enc_in[426] ^ ecc_enc_in[435] ^
                          ecc_enc_in[440] ^ ecc_enc_in[443] ^ ecc_enc_in[445] ^
                          ecc_enc_in[446] ^ ecc_enc_in[449] ^ ecc_enc_in[450] ^
                          ecc_enc_in[452] ^ ecc_enc_in[456] ^ ecc_enc_in[457] ^
                          ecc_enc_in[459] ^ ecc_enc_in[463] ^ ecc_enc_in[466] ^
                          ecc_enc_in[469] ^ ecc_enc_in[475] ^ ecc_enc_in[476] ^
                          ecc_enc_in[478] ^ ecc_enc_in[482] ^ ecc_enc_in[492] ^
                          ecc_enc_in[493] ^ ecc_enc_in[496] ^ ecc_enc_in[500] ^
                          ecc_enc_in[504] ^ ecc_enc_in[508]) ;
assign parity_enc[01] = ~( ecc_enc_in[000] ^ ecc_enc_in[001] ^ ecc_enc_in[003] ^
                          ecc_enc_in[004] ^ ecc_enc_in[006] ^ ecc_enc_in[008] ^
                          ecc_enc_in[010] ^ ecc_enc_in[011] ^ ecc_enc_in[013] ^
                          ecc_enc_in[015] ^ ecc_enc_in[017] ^ ecc_enc_in[019] ^
                          ecc_enc_in[021] ^ ecc_enc_in[024] ^ ecc_enc_in[025] ^
                          ecc_enc_in[027] ^ ecc_enc_in[029] ^ ecc_enc_in[032] ^
                          ecc_enc_in[034] ^ ecc_enc_in[036] ^ ecc_enc_in[038] ^
                          ecc_enc_in[040] ^ ecc_enc_in[043] ^ ecc_enc_in[045] ^
                          ecc_enc_in[046] ^ ecc_enc_in[048] ^ ecc_enc_in[050] ^
                          ecc_enc_in[052] ^ ecc_enc_in[054] ^ ecc_enc_in[056] ^
                          ecc_enc_in[058] ^ ecc_enc_in[060] ^ ecc_enc_in[063] ^
                          ecc_enc_in[065] ^ ecc_enc_in[067] ^ ecc_enc_in[069] ^
                          ecc_enc_in[071] ^ ecc_enc_in[073] ^ ecc_enc_in[075] ^
                          ecc_enc_in[078] ^ ecc_enc_in[080] ^ ecc_enc_in[082] ^
                          ecc_enc_in[084] ^ ecc_enc_in[086] ^ ecc_enc_in[088] ^
                          ecc_enc_in[090] ^ ecc_enc_in[093] ^ ecc_enc_in[095] ^
                          ecc_enc_in[097] ^ ecc_enc_in[099] ^ ecc_enc_in[101] ^
                          ecc_enc_in[103] ^ ecc_enc_in[105] ^ ecc_enc_in[107] ^
                          ecc_enc_in[109] ^ ecc_enc_in[111] ^ ecc_enc_in[113] ^
                          ecc_enc_in[115] ^ ecc_enc_in[117] ^ ecc_enc_in[119] ^
                          ecc_enc_in[121] ^ ecc_enc_in[123] ^ ecc_enc_in[126] ^
                          ecc_enc_in[129] ^ ecc_enc_in[131] ^ ecc_enc_in[133] ^
                          ecc_enc_in[135] ^ ecc_enc_in[137] ^ ecc_enc_in[140] ^
                          ecc_enc_in[142] ^ ecc_enc_in[144] ^ ecc_enc_in[147] ^
                          ecc_enc_in[151] ^ ecc_enc_in[154] ^ ecc_enc_in[155] ^
                          ecc_enc_in[157] ^ ecc_enc_in[160] ^ ecc_enc_in[163] ^
                          ecc_enc_in[168] ^ ecc_enc_in[170] ^ ecc_enc_in[175] ^
                          ecc_enc_in[178] ^ ecc_enc_in[180] ^ ecc_enc_in[182] ^
                          ecc_enc_in[184] ^ ecc_enc_in[186] ^ ecc_enc_in[190] ^
                          ecc_enc_in[192] ^ ecc_enc_in[195] ^ ecc_enc_in[198] ^
                          ecc_enc_in[200] ^ ecc_enc_in[203] ^ ecc_enc_in[205] ^
                          ecc_enc_in[207] ^ ecc_enc_in[209] ^ ecc_enc_in[211] ^
                          ecc_enc_in[213] ^ ecc_enc_in[215] ^ ecc_enc_in[218] ^
                          ecc_enc_in[220] ^ ecc_enc_in[221] ^ ecc_enc_in[224] ^
                          ecc_enc_in[227] ^ ecc_enc_in[229] ^ ecc_enc_in[231] ^
                          ecc_enc_in[233] ^ ecc_enc_in[235] ^ ecc_enc_in[237] ^
                          ecc_enc_in[238] ^ ecc_enc_in[240] ^ ecc_enc_in[242] ^
                          ecc_enc_in[244] ^ ecc_enc_in[247] ^ ecc_enc_in[252] ^
                          ecc_enc_in[259] ^ ecc_enc_in[261] ^ ecc_enc_in[263] ^
                          ecc_enc_in[264] ^ ecc_enc_in[266] ^ ecc_enc_in[268] ^
                          ecc_enc_in[270] ^ ecc_enc_in[272] ^ ecc_enc_in[274] ^
                          ecc_enc_in[277] ^ ecc_enc_in[279] ^ ecc_enc_in[281] ^
                          ecc_enc_in[284] ^ ecc_enc_in[287] ^ ecc_enc_in[291] ^
                          ecc_enc_in[293] ^ ecc_enc_in[297] ^ ecc_enc_in[309] ^
                          ecc_enc_in[311] ^ ecc_enc_in[313] ^ ecc_enc_in[315] ^
                          ecc_enc_in[317] ^ ecc_enc_in[319] ^ ecc_enc_in[321] ^
                          ecc_enc_in[323] ^ ecc_enc_in[325] ^ ecc_enc_in[328] ^
                          ecc_enc_in[330] ^ ecc_enc_in[332] ^ ecc_enc_in[334] ^
                          ecc_enc_in[337] ^ ecc_enc_in[340] ^ ecc_enc_in[343] ^
                          ecc_enc_in[345] ^ ecc_enc_in[348] ^ ecc_enc_in[350] ^
                          ecc_enc_in[351] ^ ecc_enc_in[354] ^ ecc_enc_in[357] ^
                          ecc_enc_in[359] ^ ecc_enc_in[361] ^ ecc_enc_in[363] ^
                          ecc_enc_in[365] ^ ecc_enc_in[367] ^ ecc_enc_in[370] ^
                          ecc_enc_in[372] ^ ecc_enc_in[377] ^ ecc_enc_in[379] ^
                          ecc_enc_in[382] ^ ecc_enc_in[386] ^ ecc_enc_in[390] ^
                          ecc_enc_in[392] ^ ecc_enc_in[395] ^ ecc_enc_in[397] ^
                          ecc_enc_in[399] ^ ecc_enc_in[402] ^ ecc_enc_in[404] ^
                          ecc_enc_in[407] ^ ecc_enc_in[410] ^ ecc_enc_in[411] ^
                          ecc_enc_in[413] ^ ecc_enc_in[416] ^ ecc_enc_in[423] ^
                          ecc_enc_in[425] ^ ecc_enc_in[427] ^ ecc_enc_in[431] ^
                          ecc_enc_in[436] ^ ecc_enc_in[441] ^ ecc_enc_in[443] ^
                          ecc_enc_in[445] ^ ecc_enc_in[447] ^ ecc_enc_in[449] ^
                          ecc_enc_in[451] ^ ecc_enc_in[453] ^ ecc_enc_in[456] ^
                          ecc_enc_in[458] ^ ecc_enc_in[460] ^ ecc_enc_in[464] ^
                          ecc_enc_in[467] ^ ecc_enc_in[470] ^ ecc_enc_in[475] ^
                          ecc_enc_in[477] ^ ecc_enc_in[479] ^ ecc_enc_in[486] ^
                          ecc_enc_in[492] ^ ecc_enc_in[494] ^ ecc_enc_in[495] ^
                          ecc_enc_in[497] ^ ecc_enc_in[505]) ;
assign parity_enc[02] = ~( ecc_enc_in[000] ^ ecc_enc_in[002] ^ ecc_enc_in[003] ^
                          ecc_enc_in[005] ^ ecc_enc_in[006] ^ ecc_enc_in[009] ^
                          ecc_enc_in[010] ^ ecc_enc_in[012] ^ ecc_enc_in[013] ^
                          ecc_enc_in[016] ^ ecc_enc_in[017] ^ ecc_enc_in[020] ^
                          ecc_enc_in[021] ^ ecc_enc_in[023] ^ ecc_enc_in[024] ^
                          ecc_enc_in[026] ^ ecc_enc_in[027] ^ ecc_enc_in[030] ^
                          ecc_enc_in[033] ^ ecc_enc_in[034] ^ ecc_enc_in[036] ^
                          ecc_enc_in[039] ^ ecc_enc_in[040] ^ ecc_enc_in[044] ^
                          ecc_enc_in[045] ^ ecc_enc_in[047] ^ ecc_enc_in[049] ^
                          ecc_enc_in[050] ^ ecc_enc_in[053] ^ ecc_enc_in[054] ^
                          ecc_enc_in[057] ^ ecc_enc_in[058] ^ ecc_enc_in[061] ^
                          ecc_enc_in[064] ^ ecc_enc_in[065] ^ ecc_enc_in[068] ^
                          ecc_enc_in[069] ^ ecc_enc_in[072] ^ ecc_enc_in[073] ^
                          ecc_enc_in[076] ^ ecc_enc_in[079] ^ ecc_enc_in[080] ^
                          ecc_enc_in[083] ^ ecc_enc_in[084] ^ ecc_enc_in[087] ^
                          ecc_enc_in[088] ^ ecc_enc_in[091] ^ ecc_enc_in[094] ^
                          ecc_enc_in[095] ^ ecc_enc_in[098] ^ ecc_enc_in[100] ^
                          ecc_enc_in[101] ^ ecc_enc_in[104] ^ ecc_enc_in[105] ^
                          ecc_enc_in[108] ^ ecc_enc_in[109] ^ ecc_enc_in[112] ^
                          ecc_enc_in[113] ^ ecc_enc_in[116] ^ ecc_enc_in[117] ^
                          ecc_enc_in[120] ^ ecc_enc_in[121] ^ ecc_enc_in[124] ^
                          ecc_enc_in[127] ^ ecc_enc_in[130] ^ ecc_enc_in[131] ^
                          ecc_enc_in[134] ^ ecc_enc_in[135] ^ ecc_enc_in[138] ^
                          ecc_enc_in[143] ^ ecc_enc_in[144] ^ ecc_enc_in[146] ^
                          ecc_enc_in[148] ^ ecc_enc_in[152] ^ ecc_enc_in[155] ^
                          ecc_enc_in[158] ^ ecc_enc_in[160] ^ ecc_enc_in[164] ^
                          ecc_enc_in[167] ^ ecc_enc_in[168] ^ ecc_enc_in[171] ^
                          ecc_enc_in[176] ^ ecc_enc_in[179] ^ ecc_enc_in[180] ^
                          ecc_enc_in[183] ^ ecc_enc_in[184] ^ ecc_enc_in[187] ^
                          ecc_enc_in[189] ^ ecc_enc_in[190] ^ ecc_enc_in[193] ^
                          ecc_enc_in[196] ^ ecc_enc_in[199] ^ ecc_enc_in[200] ^
                          ecc_enc_in[204] ^ ecc_enc_in[205] ^ ecc_enc_in[208] ^
                          ecc_enc_in[209] ^ ecc_enc_in[212] ^ ecc_enc_in[213] ^
                          ecc_enc_in[216] ^ ecc_enc_in[219] ^ ecc_enc_in[220] ^
                          ecc_enc_in[222] ^ ecc_enc_in[225] ^ ecc_enc_in[228] ^
                          ecc_enc_in[229] ^ ecc_enc_in[232] ^ ecc_enc_in[233] ^
                          ecc_enc_in[236] ^ ecc_enc_in[237] ^ ecc_enc_in[241] ^
                          ecc_enc_in[242] ^ ecc_enc_in[245] ^ ecc_enc_in[248] ^
                          ecc_enc_in[253] ^ ecc_enc_in[254] ^ ecc_enc_in[260] ^
                          ecc_enc_in[261] ^ ecc_enc_in[264] ^ ecc_enc_in[270] ^
                          ecc_enc_in[273] ^ ecc_enc_in[275] ^ ecc_enc_in[278] ^
                          ecc_enc_in[279] ^ ecc_enc_in[282] ^ ecc_enc_in[292] ^
                          ecc_enc_in[293] ^ ecc_enc_in[295] ^ ecc_enc_in[298] ^
                          ecc_enc_in[301] ^ ecc_enc_in[305] ^ ecc_enc_in[310] ^
                          ecc_enc_in[311] ^ ecc_enc_in[314] ^ ecc_enc_in[315] ^
                          ecc_enc_in[318] ^ ecc_enc_in[319] ^ ecc_enc_in[322] ^
                          ecc_enc_in[323] ^ ecc_enc_in[326] ^ ecc_enc_in[329] ^
                          ecc_enc_in[330] ^ ecc_enc_in[333] ^ ecc_enc_in[334] ^
                          ecc_enc_in[335] ^ ecc_enc_in[338] ^ ecc_enc_in[341] ^
                          ecc_enc_in[346] ^ ecc_enc_in[349] ^ ecc_enc_in[350] ^
                          ecc_enc_in[352] ^ ecc_enc_in[355] ^ ecc_enc_in[358] ^
                          ecc_enc_in[359] ^ ecc_enc_in[364] ^ ecc_enc_in[365] ^
                          ecc_enc_in[369] ^ ecc_enc_in[370] ^ ecc_enc_in[373] ^
                          ecc_enc_in[374] ^ ecc_enc_in[378] ^ ecc_enc_in[380] ^
                          ecc_enc_in[383] ^ ecc_enc_in[387] ^ ecc_enc_in[391] ^
                          ecc_enc_in[392] ^ ecc_enc_in[394] ^ ecc_enc_in[395] ^
                          ecc_enc_in[398] ^ ecc_enc_in[399] ^ ecc_enc_in[400] ^
                          ecc_enc_in[405] ^ ecc_enc_in[411] ^ ecc_enc_in[414] ^
                          ecc_enc_in[417] ^ ecc_enc_in[419] ^ ecc_enc_in[424] ^
                          ecc_enc_in[425] ^ ecc_enc_in[428] ^ ecc_enc_in[429] ^
                          ecc_enc_in[432] ^ ecc_enc_in[442] ^ ecc_enc_in[443] ^
                          ecc_enc_in[446] ^ ecc_enc_in[447] ^ ecc_enc_in[450] ^
                          ecc_enc_in[451] ^ ecc_enc_in[454] ^ ecc_enc_in[457] ^
                          ecc_enc_in[458] ^ ecc_enc_in[461] ^ ecc_enc_in[465] ^
                          ecc_enc_in[471] ^ ecc_enc_in[476] ^ ecc_enc_in[477] ^
                          ecc_enc_in[480] ^ ecc_enc_in[483] ^ ecc_enc_in[487] ^
                          ecc_enc_in[493] ^ ecc_enc_in[494] ^ ecc_enc_in[498] ^
                          ecc_enc_in[501] ^ ecc_enc_in[509]) ;
assign parity_enc[03] = ~( ecc_enc_in[001] ^ ecc_enc_in[002] ^ ecc_enc_in[003] ^
                          ecc_enc_in[007] ^ ecc_enc_in[008] ^ ecc_enc_in[009] ^
                          ecc_enc_in[010] ^ ecc_enc_in[014] ^ ecc_enc_in[015] ^
                          ecc_enc_in[016] ^ ecc_enc_in[017] ^ ecc_enc_in[022] ^
                          ecc_enc_in[023] ^ ecc_enc_in[024] ^ ecc_enc_in[028] ^
                          ecc_enc_in[029] ^ ecc_enc_in[030] ^ ecc_enc_in[035] ^
                          ecc_enc_in[036] ^ ecc_enc_in[041] ^ ecc_enc_in[046] ^
                          ecc_enc_in[047] ^ ecc_enc_in[051] ^ ecc_enc_in[052] ^
                          ecc_enc_in[053] ^ ecc_enc_in[054] ^ ecc_enc_in[059] ^
                          ecc_enc_in[060] ^ ecc_enc_in[061] ^ ecc_enc_in[066] ^
                          ecc_enc_in[067] ^ ecc_enc_in[068] ^ ecc_enc_in[069] ^
                          ecc_enc_in[074] ^ ecc_enc_in[075] ^ ecc_enc_in[076] ^
                          ecc_enc_in[081] ^ ecc_enc_in[082] ^ ecc_enc_in[083] ^
                          ecc_enc_in[084] ^ ecc_enc_in[089] ^ ecc_enc_in[090] ^
                          ecc_enc_in[091] ^ ecc_enc_in[102] ^ ecc_enc_in[103] ^
                          ecc_enc_in[104] ^ ecc_enc_in[105] ^ ecc_enc_in[110] ^
                          ecc_enc_in[111] ^ ecc_enc_in[112] ^ ecc_enc_in[113] ^
                          ecc_enc_in[118] ^ ecc_enc_in[119] ^ ecc_enc_in[120] ^
                          ecc_enc_in[121] ^ ecc_enc_in[125] ^ ecc_enc_in[126] ^
                          ecc_enc_in[127] ^ ecc_enc_in[132] ^ ecc_enc_in[133] ^
                          ecc_enc_in[134] ^ ecc_enc_in[135] ^ ecc_enc_in[139] ^
                          ecc_enc_in[140] ^ ecc_enc_in[145] ^ ecc_enc_in[146] ^
                          ecc_enc_in[149] ^ ecc_enc_in[153] ^ ecc_enc_in[154] ^
                          ecc_enc_in[155] ^ ecc_enc_in[157] ^ ecc_enc_in[158] ^
                          ecc_enc_in[161] ^ ecc_enc_in[165] ^ ecc_enc_in[169] ^
                          ecc_enc_in[170] ^ ecc_enc_in[171] ^ ecc_enc_in[173] ^
                          ecc_enc_in[177] ^ ecc_enc_in[181] ^ ecc_enc_in[182] ^
                          ecc_enc_in[183] ^ ecc_enc_in[184] ^ ecc_enc_in[188] ^
                          ecc_enc_in[189] ^ ecc_enc_in[190] ^ ecc_enc_in[194] ^
                          ecc_enc_in[195] ^ ecc_enc_in[196] ^ ecc_enc_in[201] ^
                          ecc_enc_in[206] ^ ecc_enc_in[207] ^ ecc_enc_in[208] ^
                          ecc_enc_in[209] ^ ecc_enc_in[214] ^ ecc_enc_in[215] ^
                          ecc_enc_in[216] ^ ecc_enc_in[221] ^ ecc_enc_in[222] ^
                          ecc_enc_in[230] ^ ecc_enc_in[231] ^ ecc_enc_in[232] ^
                          ecc_enc_in[233] ^ ecc_enc_in[238] ^ ecc_enc_in[243] ^
                          ecc_enc_in[244] ^ ecc_enc_in[245] ^ ecc_enc_in[249] ^
                          ecc_enc_in[251] ^ ecc_enc_in[252] ^ ecc_enc_in[253] ^
                          ecc_enc_in[255] ^ ecc_enc_in[256] ^ ecc_enc_in[262] ^
                          ecc_enc_in[263] ^ ecc_enc_in[264] ^ ecc_enc_in[267] ^
                          ecc_enc_in[268] ^ ecc_enc_in[271] ^ ecc_enc_in[272] ^
                          ecc_enc_in[273] ^ ecc_enc_in[280] ^ ecc_enc_in[281] ^
                          ecc_enc_in[282] ^ ecc_enc_in[285] ^ ecc_enc_in[288] ^
                          ecc_enc_in[294] ^ ecc_enc_in[295] ^ ecc_enc_in[299] ^
                          ecc_enc_in[302] ^ ecc_enc_in[306] ^ ecc_enc_in[312] ^
                          ecc_enc_in[313] ^ ecc_enc_in[314] ^ ecc_enc_in[315] ^
                          ecc_enc_in[320] ^ ecc_enc_in[321] ^ ecc_enc_in[322] ^
                          ecc_enc_in[323] ^ ecc_enc_in[327] ^ ecc_enc_in[328] ^
                          ecc_enc_in[329] ^ ecc_enc_in[330] ^ ecc_enc_in[335] ^
                          ecc_enc_in[339] ^ ecc_enc_in[340] ^ ecc_enc_in[341] ^
                          ecc_enc_in[344] ^ ecc_enc_in[345] ^ ecc_enc_in[346] ^
                          ecc_enc_in[351] ^ ecc_enc_in[352] ^ ecc_enc_in[360] ^
                          ecc_enc_in[361] ^ ecc_enc_in[366] ^ ecc_enc_in[367] ^
                          ecc_enc_in[371] ^ ecc_enc_in[372] ^ ecc_enc_in[373] ^
                          ecc_enc_in[375] ^ ecc_enc_in[379] ^ ecc_enc_in[380] ^
                          ecc_enc_in[384] ^ ecc_enc_in[388] ^ ecc_enc_in[393] ^
                          ecc_enc_in[394] ^ ecc_enc_in[395] ^ ecc_enc_in[400] ^
                          ecc_enc_in[403] ^ ecc_enc_in[404] ^ ecc_enc_in[405] ^
                          ecc_enc_in[408] ^ ecc_enc_in[412] ^ ecc_enc_in[413] ^
                          ecc_enc_in[414] ^ ecc_enc_in[420] ^ ecc_enc_in[426] ^
                          ecc_enc_in[427] ^ ecc_enc_in[428] ^ ecc_enc_in[430] ^
                          ecc_enc_in[433] ^ ecc_enc_in[437] ^ ecc_enc_in[444] ^
                          ecc_enc_in[445] ^ ecc_enc_in[446] ^ ecc_enc_in[447] ^
                          ecc_enc_in[452] ^ ecc_enc_in[453] ^ ecc_enc_in[454] ^
                          ecc_enc_in[463] ^ ecc_enc_in[464] ^ ecc_enc_in[465] ^
                          ecc_enc_in[468] ^ ecc_enc_in[472] ^ ecc_enc_in[478] ^
                          ecc_enc_in[479] ^ ecc_enc_in[481] ^ ecc_enc_in[484] ^
                          ecc_enc_in[488] ^ ecc_enc_in[495] ^ ecc_enc_in[499] ^
                          ecc_enc_in[502] ^ ecc_enc_in[506]) ;
assign parity_enc[04] = ~( ecc_enc_in[004] ^ ecc_enc_in[005] ^ ecc_enc_in[006] ^
                          ecc_enc_in[007] ^ ecc_enc_in[008] ^ ecc_enc_in[009] ^
                          ecc_enc_in[010] ^ ecc_enc_in[018] ^ ecc_enc_in[019] ^
                          ecc_enc_in[020] ^ ecc_enc_in[021] ^ ecc_enc_in[022] ^
                          ecc_enc_in[023] ^ ecc_enc_in[024] ^ ecc_enc_in[031] ^
                          ecc_enc_in[032] ^ ecc_enc_in[033] ^ ecc_enc_in[034] ^
                          ecc_enc_in[035] ^ ecc_enc_in[036] ^ ecc_enc_in[042] ^
                          ecc_enc_in[043] ^ ecc_enc_in[044] ^ ecc_enc_in[045] ^
                          ecc_enc_in[046] ^ ecc_enc_in[047] ^ ecc_enc_in[055] ^
                          ecc_enc_in[056] ^ ecc_enc_in[057] ^ ecc_enc_in[058] ^
                          ecc_enc_in[059] ^ ecc_enc_in[060] ^ ecc_enc_in[061] ^
                          ecc_enc_in[070] ^ ecc_enc_in[071] ^ ecc_enc_in[072] ^
                          ecc_enc_in[073] ^ ecc_enc_in[074] ^ ecc_enc_in[075] ^
                          ecc_enc_in[076] ^ ecc_enc_in[085] ^ ecc_enc_in[086] ^
                          ecc_enc_in[087] ^ ecc_enc_in[088] ^ ecc_enc_in[089] ^
                          ecc_enc_in[090] ^ ecc_enc_in[091] ^ ecc_enc_in[096] ^
                          ecc_enc_in[097] ^ ecc_enc_in[098] ^ ecc_enc_in[106] ^
                          ecc_enc_in[107] ^ ecc_enc_in[108] ^ ecc_enc_in[109] ^
                          ecc_enc_in[110] ^ ecc_enc_in[111] ^ ecc_enc_in[112] ^
                          ecc_enc_in[113] ^ ecc_enc_in[122] ^ ecc_enc_in[123] ^
                          ecc_enc_in[124] ^ ecc_enc_in[125] ^ ecc_enc_in[126] ^
                          ecc_enc_in[127] ^ ecc_enc_in[136] ^ ecc_enc_in[137] ^
                          ecc_enc_in[138] ^ ecc_enc_in[139] ^ ecc_enc_in[140] ^
                          ecc_enc_in[147] ^ ecc_enc_in[148] ^ ecc_enc_in[149] ^
                          ecc_enc_in[156] ^ ecc_enc_in[157] ^ ecc_enc_in[158] ^
                          ecc_enc_in[162] ^ ecc_enc_in[163] ^ ecc_enc_in[164] ^
                          ecc_enc_in[165] ^ ecc_enc_in[172] ^ ecc_enc_in[173] ^
                          ecc_enc_in[185] ^ ecc_enc_in[186] ^ ecc_enc_in[187] ^
                          ecc_enc_in[188] ^ ecc_enc_in[189] ^ ecc_enc_in[190] ^
                          ecc_enc_in[197] ^ ecc_enc_in[198] ^ ecc_enc_in[199] ^
                          ecc_enc_in[200] ^ ecc_enc_in[201] ^ ecc_enc_in[210] ^
                          ecc_enc_in[211] ^ ecc_enc_in[212] ^ ecc_enc_in[213] ^
                          ecc_enc_in[214] ^ ecc_enc_in[215] ^ ecc_enc_in[216] ^
                          ecc_enc_in[223] ^ ecc_enc_in[224] ^ ecc_enc_in[225] ^
                          ecc_enc_in[234] ^ ecc_enc_in[235] ^ ecc_enc_in[236] ^
                          ecc_enc_in[237] ^ ecc_enc_in[238] ^ ecc_enc_in[246] ^
                          ecc_enc_in[247] ^ ecc_enc_in[248] ^ ecc_enc_in[249] ^
                          ecc_enc_in[254] ^ ecc_enc_in[255] ^ ecc_enc_in[257] ^
                          ecc_enc_in[265] ^ ecc_enc_in[266] ^ ecc_enc_in[267] ^
                          ecc_enc_in[268] ^ ecc_enc_in[274] ^ ecc_enc_in[275] ^
                          ecc_enc_in[283] ^ ecc_enc_in[284] ^ ecc_enc_in[285] ^
                          ecc_enc_in[289] ^ ecc_enc_in[296] ^ ecc_enc_in[297] ^
                          ecc_enc_in[298] ^ ecc_enc_in[299] ^ ecc_enc_in[303] ^
                          ecc_enc_in[307] ^ ecc_enc_in[316] ^ ecc_enc_in[317] ^
                          ecc_enc_in[318] ^ ecc_enc_in[319] ^ ecc_enc_in[320] ^
                          ecc_enc_in[321] ^ ecc_enc_in[322] ^ ecc_enc_in[323] ^
                          ecc_enc_in[331] ^ ecc_enc_in[332] ^ ecc_enc_in[333] ^
                          ecc_enc_in[334] ^ ecc_enc_in[335] ^ ecc_enc_in[342] ^
                          ecc_enc_in[343] ^ ecc_enc_in[344] ^ ecc_enc_in[345] ^
                          ecc_enc_in[346] ^ ecc_enc_in[353] ^ ecc_enc_in[354] ^
                          ecc_enc_in[355] ^ ecc_enc_in[362] ^ ecc_enc_in[363] ^
                          ecc_enc_in[364] ^ ecc_enc_in[365] ^ ecc_enc_in[366] ^
                          ecc_enc_in[367] ^ ecc_enc_in[374] ^ ecc_enc_in[375] ^
                          ecc_enc_in[381] ^ ecc_enc_in[382] ^ ecc_enc_in[383] ^
                          ecc_enc_in[384] ^ ecc_enc_in[396] ^ ecc_enc_in[397] ^
                          ecc_enc_in[398] ^ ecc_enc_in[399] ^ ecc_enc_in[400] ^
                          ecc_enc_in[406] ^ ecc_enc_in[407] ^ ecc_enc_in[408] ^
                          ecc_enc_in[415] ^ ecc_enc_in[416] ^ ecc_enc_in[417] ^
                          ecc_enc_in[421] ^ ecc_enc_in[429] ^ ecc_enc_in[430] ^
                          ecc_enc_in[434] ^ ecc_enc_in[438] ^ ecc_enc_in[448] ^
                          ecc_enc_in[449] ^ ecc_enc_in[450] ^ ecc_enc_in[451] ^
                          ecc_enc_in[452] ^ ecc_enc_in[453] ^ ecc_enc_in[454] ^
                          ecc_enc_in[459] ^ ecc_enc_in[460] ^ ecc_enc_in[461] ^
                          ecc_enc_in[466] ^ ecc_enc_in[467] ^ ecc_enc_in[468] ^
                          ecc_enc_in[473] ^ ecc_enc_in[480] ^ ecc_enc_in[481] ^
                          ecc_enc_in[485] ^ ecc_enc_in[489] ^ ecc_enc_in[496] ^
                          ecc_enc_in[497] ^ ecc_enc_in[498] ^ ecc_enc_in[499] ^
                          ecc_enc_in[503] ^ ecc_enc_in[510]) ;
assign parity_enc[05] = ~( ecc_enc_in[011] ^ ecc_enc_in[012] ^ ecc_enc_in[013] ^
                          ecc_enc_in[014] ^ ecc_enc_in[015] ^ ecc_enc_in[016] ^
                          ecc_enc_in[017] ^ ecc_enc_in[018] ^ ecc_enc_in[019] ^
                          ecc_enc_in[020] ^ ecc_enc_in[021] ^ ecc_enc_in[022] ^
                          ecc_enc_in[023] ^ ecc_enc_in[024] ^ ecc_enc_in[037] ^
                          ecc_enc_in[038] ^ ecc_enc_in[039] ^ ecc_enc_in[040] ^
                          ecc_enc_in[041] ^ ecc_enc_in[042] ^ ecc_enc_in[043] ^
                          ecc_enc_in[044] ^ ecc_enc_in[045] ^ ecc_enc_in[046] ^
                          ecc_enc_in[047] ^ ecc_enc_in[062] ^ ecc_enc_in[063] ^
                          ecc_enc_in[064] ^ ecc_enc_in[065] ^ ecc_enc_in[066] ^
                          ecc_enc_in[067] ^ ecc_enc_in[068] ^ ecc_enc_in[069] ^
                          ecc_enc_in[070] ^ ecc_enc_in[071] ^ ecc_enc_in[072] ^
                          ecc_enc_in[073] ^ ecc_enc_in[074] ^ ecc_enc_in[075] ^
                          ecc_enc_in[076] ^ ecc_enc_in[092] ^ ecc_enc_in[093] ^
                          ecc_enc_in[094] ^ ecc_enc_in[095] ^ ecc_enc_in[096] ^
                          ecc_enc_in[097] ^ ecc_enc_in[098] ^ ecc_enc_in[114] ^
                          ecc_enc_in[115] ^ ecc_enc_in[116] ^ ecc_enc_in[117] ^
                          ecc_enc_in[118] ^ ecc_enc_in[119] ^ ecc_enc_in[120] ^
                          ecc_enc_in[121] ^ ecc_enc_in[122] ^ ecc_enc_in[123] ^
                          ecc_enc_in[124] ^ ecc_enc_in[125] ^ ecc_enc_in[126] ^
                          ecc_enc_in[127] ^ ecc_enc_in[141] ^ ecc_enc_in[142] ^
                          ecc_enc_in[143] ^ ecc_enc_in[144] ^ ecc_enc_in[145] ^
                          ecc_enc_in[146] ^ ecc_enc_in[147] ^ ecc_enc_in[148] ^
                          ecc_enc_in[149] ^ ecc_enc_in[159] ^ ecc_enc_in[160] ^
                          ecc_enc_in[161] ^ ecc_enc_in[162] ^ ecc_enc_in[163] ^
                          ecc_enc_in[164] ^ ecc_enc_in[165] ^ ecc_enc_in[174] ^
                          ecc_enc_in[175] ^ ecc_enc_in[176] ^ ecc_enc_in[177] ^
                          ecc_enc_in[191] ^ ecc_enc_in[192] ^ ecc_enc_in[193] ^
                          ecc_enc_in[194] ^ ecc_enc_in[195] ^ ecc_enc_in[196] ^
                          ecc_enc_in[197] ^ ecc_enc_in[198] ^ ecc_enc_in[199] ^
                          ecc_enc_in[200] ^ ecc_enc_in[201] ^ ecc_enc_in[217] ^
                          ecc_enc_in[218] ^ ecc_enc_in[219] ^ ecc_enc_in[220] ^
                          ecc_enc_in[221] ^ ecc_enc_in[222] ^ ecc_enc_in[223] ^
                          ecc_enc_in[224] ^ ecc_enc_in[225] ^ ecc_enc_in[239] ^
                          ecc_enc_in[240] ^ ecc_enc_in[241] ^ ecc_enc_in[242] ^
                          ecc_enc_in[243] ^ ecc_enc_in[244] ^ ecc_enc_in[245] ^
                          ecc_enc_in[246] ^ ecc_enc_in[247] ^ ecc_enc_in[248] ^
                          ecc_enc_in[249] ^ ecc_enc_in[256] ^ ecc_enc_in[257] ^
                          ecc_enc_in[269] ^ ecc_enc_in[270] ^ ecc_enc_in[271] ^
                          ecc_enc_in[272] ^ ecc_enc_in[273] ^ ecc_enc_in[274] ^
                          ecc_enc_in[275] ^ ecc_enc_in[286] ^ ecc_enc_in[287] ^
                          ecc_enc_in[288] ^ ecc_enc_in[289] ^ ecc_enc_in[300] ^
                          ecc_enc_in[301] ^ ecc_enc_in[302] ^ ecc_enc_in[303] ^
                          ecc_enc_in[308] ^ ecc_enc_in[324] ^ ecc_enc_in[325] ^
                          ecc_enc_in[326] ^ ecc_enc_in[327] ^ ecc_enc_in[328] ^
                          ecc_enc_in[329] ^ ecc_enc_in[330] ^ ecc_enc_in[331] ^
                          ecc_enc_in[332] ^ ecc_enc_in[333] ^ ecc_enc_in[334] ^
                          ecc_enc_in[335] ^ ecc_enc_in[347] ^ ecc_enc_in[348] ^
                          ecc_enc_in[349] ^ ecc_enc_in[350] ^ ecc_enc_in[351] ^
                          ecc_enc_in[352] ^ ecc_enc_in[353] ^ ecc_enc_in[354] ^
                          ecc_enc_in[355] ^ ecc_enc_in[368] ^ ecc_enc_in[369] ^
                          ecc_enc_in[370] ^ ecc_enc_in[371] ^ ecc_enc_in[372] ^
                          ecc_enc_in[373] ^ ecc_enc_in[374] ^ ecc_enc_in[375] ^
                          ecc_enc_in[385] ^ ecc_enc_in[386] ^ ecc_enc_in[387] ^
                          ecc_enc_in[388] ^ ecc_enc_in[401] ^ ecc_enc_in[402] ^
                          ecc_enc_in[403] ^ ecc_enc_in[404] ^ ecc_enc_in[405] ^
                          ecc_enc_in[406] ^ ecc_enc_in[407] ^ ecc_enc_in[408] ^
                          ecc_enc_in[418] ^ ecc_enc_in[419] ^ ecc_enc_in[420] ^
                          ecc_enc_in[421] ^ ecc_enc_in[431] ^ ecc_enc_in[432] ^
                          ecc_enc_in[433] ^ ecc_enc_in[434] ^ ecc_enc_in[439] ^
                          ecc_enc_in[455] ^ ecc_enc_in[456] ^ ecc_enc_in[457] ^
                          ecc_enc_in[458] ^ ecc_enc_in[459] ^ ecc_enc_in[460] ^
                          ecc_enc_in[461] ^ ecc_enc_in[469] ^ ecc_enc_in[470] ^
                          ecc_enc_in[471] ^ ecc_enc_in[472] ^ ecc_enc_in[473] ^
                          ecc_enc_in[482] ^ ecc_enc_in[483] ^ ecc_enc_in[484] ^
                          ecc_enc_in[485] ^ ecc_enc_in[490] ^ ecc_enc_in[500] ^
                          ecc_enc_in[501] ^ ecc_enc_in[502] ^ ecc_enc_in[503] ^
                          ecc_enc_in[507] ^ ecc_enc_in[511]) ;
assign parity_enc[06] = ~( ecc_enc_in[025] ^ ecc_enc_in[026] ^ ecc_enc_in[027] ^
                          ecc_enc_in[028] ^ ecc_enc_in[029] ^ ecc_enc_in[030] ^
                          ecc_enc_in[031] ^ ecc_enc_in[032] ^ ecc_enc_in[033] ^
                          ecc_enc_in[034] ^ ecc_enc_in[035] ^ ecc_enc_in[036] ^
                          ecc_enc_in[037] ^ ecc_enc_in[038] ^ ecc_enc_in[039] ^
                          ecc_enc_in[040] ^ ecc_enc_in[041] ^ ecc_enc_in[042] ^
                          ecc_enc_in[043] ^ ecc_enc_in[044] ^ ecc_enc_in[045] ^
                          ecc_enc_in[046] ^ ecc_enc_in[047] ^ ecc_enc_in[077] ^
                          ecc_enc_in[078] ^ ecc_enc_in[079] ^ ecc_enc_in[080] ^
                          ecc_enc_in[081] ^ ecc_enc_in[082] ^ ecc_enc_in[083] ^
                          ecc_enc_in[084] ^ ecc_enc_in[085] ^ ecc_enc_in[086] ^
                          ecc_enc_in[087] ^ ecc_enc_in[088] ^ ecc_enc_in[089] ^
                          ecc_enc_in[090] ^ ecc_enc_in[091] ^ ecc_enc_in[092] ^
                          ecc_enc_in[093] ^ ecc_enc_in[094] ^ ecc_enc_in[095] ^
                          ecc_enc_in[096] ^ ecc_enc_in[097] ^ ecc_enc_in[098] ^
                          ecc_enc_in[128] ^ ecc_enc_in[129] ^ ecc_enc_in[130] ^
                          ecc_enc_in[131] ^ ecc_enc_in[132] ^ ecc_enc_in[133] ^
                          ecc_enc_in[134] ^ ecc_enc_in[135] ^ ecc_enc_in[136] ^
                          ecc_enc_in[137] ^ ecc_enc_in[138] ^ ecc_enc_in[139] ^
                          ecc_enc_in[140] ^ ecc_enc_in[141] ^ ecc_enc_in[142] ^
                          ecc_enc_in[143] ^ ecc_enc_in[144] ^ ecc_enc_in[145] ^
                          ecc_enc_in[146] ^ ecc_enc_in[147] ^ ecc_enc_in[148] ^
                          ecc_enc_in[149] ^ ecc_enc_in[166] ^ ecc_enc_in[167] ^
                          ecc_enc_in[168] ^ ecc_enc_in[169] ^ ecc_enc_in[170] ^
                          ecc_enc_in[171] ^ ecc_enc_in[172] ^ ecc_enc_in[173] ^
                          ecc_enc_in[174] ^ ecc_enc_in[175] ^ ecc_enc_in[176] ^
                          ecc_enc_in[177] ^ ecc_enc_in[202] ^ ecc_enc_in[203] ^
                          ecc_enc_in[204] ^ ecc_enc_in[205] ^ ecc_enc_in[206] ^
                          ecc_enc_in[207] ^ ecc_enc_in[208] ^ ecc_enc_in[209] ^
                          ecc_enc_in[210] ^ ecc_enc_in[211] ^ ecc_enc_in[212] ^
                          ecc_enc_in[213] ^ ecc_enc_in[214] ^ ecc_enc_in[215] ^
                          ecc_enc_in[216] ^ ecc_enc_in[217] ^ ecc_enc_in[218] ^
                          ecc_enc_in[219] ^ ecc_enc_in[220] ^ ecc_enc_in[221] ^
                          ecc_enc_in[222] ^ ecc_enc_in[223] ^ ecc_enc_in[224] ^
                          ecc_enc_in[225] ^ ecc_enc_in[250] ^ ecc_enc_in[251] ^
                          ecc_enc_in[252] ^ ecc_enc_in[253] ^ ecc_enc_in[254] ^
                          ecc_enc_in[255] ^ ecc_enc_in[256] ^ ecc_enc_in[257] ^
                          ecc_enc_in[276] ^ ecc_enc_in[277] ^ ecc_enc_in[278] ^
                          ecc_enc_in[279] ^ ecc_enc_in[280] ^ ecc_enc_in[281] ^
                          ecc_enc_in[282] ^ ecc_enc_in[283] ^ ecc_enc_in[284] ^
                          ecc_enc_in[285] ^ ecc_enc_in[286] ^ ecc_enc_in[287] ^
                          ecc_enc_in[288] ^ ecc_enc_in[289] ^ ecc_enc_in[304] ^
                          ecc_enc_in[305] ^ ecc_enc_in[306] ^ ecc_enc_in[307] ^
                          ecc_enc_in[308] ^ ecc_enc_in[336] ^ ecc_enc_in[337] ^
                          ecc_enc_in[338] ^ ecc_enc_in[339] ^ ecc_enc_in[340] ^
                          ecc_enc_in[341] ^ ecc_enc_in[342] ^ ecc_enc_in[343] ^
                          ecc_enc_in[344] ^ ecc_enc_in[345] ^ ecc_enc_in[346] ^
                          ecc_enc_in[347] ^ ecc_enc_in[348] ^ ecc_enc_in[349] ^
                          ecc_enc_in[350] ^ ecc_enc_in[351] ^ ecc_enc_in[352] ^
                          ecc_enc_in[353] ^ ecc_enc_in[354] ^ ecc_enc_in[355] ^
                          ecc_enc_in[376] ^ ecc_enc_in[377] ^ ecc_enc_in[378] ^
                          ecc_enc_in[379] ^ ecc_enc_in[380] ^ ecc_enc_in[381] ^
                          ecc_enc_in[382] ^ ecc_enc_in[383] ^ ecc_enc_in[384] ^
                          ecc_enc_in[385] ^ ecc_enc_in[386] ^ ecc_enc_in[387] ^
                          ecc_enc_in[388] ^ ecc_enc_in[409] ^ ecc_enc_in[410] ^
                          ecc_enc_in[411] ^ ecc_enc_in[412] ^ ecc_enc_in[413] ^
                          ecc_enc_in[414] ^ ecc_enc_in[415] ^ ecc_enc_in[416] ^
                          ecc_enc_in[417] ^ ecc_enc_in[418] ^ ecc_enc_in[419] ^
                          ecc_enc_in[420] ^ ecc_enc_in[421] ^ ecc_enc_in[435] ^
                          ecc_enc_in[436] ^ ecc_enc_in[437] ^ ecc_enc_in[438] ^
                          ecc_enc_in[439] ^ ecc_enc_in[462] ^ ecc_enc_in[463] ^
                          ecc_enc_in[464] ^ ecc_enc_in[465] ^ ecc_enc_in[466] ^
                          ecc_enc_in[467] ^ ecc_enc_in[468] ^ ecc_enc_in[469] ^
                          ecc_enc_in[470] ^ ecc_enc_in[471] ^ ecc_enc_in[472] ^
                          ecc_enc_in[473] ^ ecc_enc_in[486] ^ ecc_enc_in[487] ^
                          ecc_enc_in[488] ^ ecc_enc_in[489] ^ ecc_enc_in[490] ^
                          ecc_enc_in[504] ^ ecc_enc_in[505] ^ ecc_enc_in[506] ^
                          ecc_enc_in[507] ^ ecc_enc_in[512]) ;
assign parity_enc[07] = ~( ecc_enc_in[048] ^ ecc_enc_in[049] ^ ecc_enc_in[050] ^
                          ecc_enc_in[051] ^ ecc_enc_in[052] ^ ecc_enc_in[053] ^
                          ecc_enc_in[054] ^ ecc_enc_in[055] ^ ecc_enc_in[056] ^
                          ecc_enc_in[057] ^ ecc_enc_in[058] ^ ecc_enc_in[059] ^
                          ecc_enc_in[060] ^ ecc_enc_in[061] ^ ecc_enc_in[062] ^
                          ecc_enc_in[063] ^ ecc_enc_in[064] ^ ecc_enc_in[065] ^
                          ecc_enc_in[066] ^ ecc_enc_in[067] ^ ecc_enc_in[068] ^
                          ecc_enc_in[069] ^ ecc_enc_in[070] ^ ecc_enc_in[071] ^
                          ecc_enc_in[072] ^ ecc_enc_in[073] ^ ecc_enc_in[074] ^
                          ecc_enc_in[075] ^ ecc_enc_in[076] ^ ecc_enc_in[077] ^
                          ecc_enc_in[078] ^ ecc_enc_in[079] ^ ecc_enc_in[080] ^
                          ecc_enc_in[081] ^ ecc_enc_in[082] ^ ecc_enc_in[083] ^
                          ecc_enc_in[084] ^ ecc_enc_in[085] ^ ecc_enc_in[086] ^
                          ecc_enc_in[087] ^ ecc_enc_in[088] ^ ecc_enc_in[089] ^
                          ecc_enc_in[090] ^ ecc_enc_in[091] ^ ecc_enc_in[092] ^
                          ecc_enc_in[093] ^ ecc_enc_in[094] ^ ecc_enc_in[095] ^
                          ecc_enc_in[096] ^ ecc_enc_in[097] ^ ecc_enc_in[098] ^
                          ecc_enc_in[150] ^ ecc_enc_in[151] ^ ecc_enc_in[152] ^
                          ecc_enc_in[153] ^ ecc_enc_in[154] ^ ecc_enc_in[155] ^
                          ecc_enc_in[156] ^ ecc_enc_in[157] ^ ecc_enc_in[158] ^
                          ecc_enc_in[159] ^ ecc_enc_in[160] ^ ecc_enc_in[161] ^
                          ecc_enc_in[162] ^ ecc_enc_in[163] ^ ecc_enc_in[164] ^
                          ecc_enc_in[165] ^ ecc_enc_in[166] ^ ecc_enc_in[167] ^
                          ecc_enc_in[168] ^ ecc_enc_in[169] ^ ecc_enc_in[170] ^
                          ecc_enc_in[171] ^ ecc_enc_in[172] ^ ecc_enc_in[173] ^
                          ecc_enc_in[174] ^ ecc_enc_in[175] ^ ecc_enc_in[176] ^
                          ecc_enc_in[177] ^ ecc_enc_in[226] ^ ecc_enc_in[227] ^
                          ecc_enc_in[228] ^ ecc_enc_in[229] ^ ecc_enc_in[230] ^
                          ecc_enc_in[231] ^ ecc_enc_in[232] ^ ecc_enc_in[233] ^
                          ecc_enc_in[234] ^ ecc_enc_in[235] ^ ecc_enc_in[236] ^
                          ecc_enc_in[237] ^ ecc_enc_in[238] ^ ecc_enc_in[239] ^
                          ecc_enc_in[240] ^ ecc_enc_in[241] ^ ecc_enc_in[242] ^
                          ecc_enc_in[243] ^ ecc_enc_in[244] ^ ecc_enc_in[245] ^
                          ecc_enc_in[246] ^ ecc_enc_in[247] ^ ecc_enc_in[248] ^
                          ecc_enc_in[249] ^ ecc_enc_in[250] ^ ecc_enc_in[251] ^
                          ecc_enc_in[252] ^ ecc_enc_in[253] ^ ecc_enc_in[254] ^
                          ecc_enc_in[255] ^ ecc_enc_in[256] ^ ecc_enc_in[257] ^
                          ecc_enc_in[290] ^ ecc_enc_in[291] ^ ecc_enc_in[292] ^
                          ecc_enc_in[293] ^ ecc_enc_in[294] ^ ecc_enc_in[295] ^
                          ecc_enc_in[296] ^ ecc_enc_in[297] ^ ecc_enc_in[298] ^
                          ecc_enc_in[299] ^ ecc_enc_in[300] ^ ecc_enc_in[301] ^
                          ecc_enc_in[302] ^ ecc_enc_in[303] ^ ecc_enc_in[304] ^
                          ecc_enc_in[305] ^ ecc_enc_in[306] ^ ecc_enc_in[307] ^
                          ecc_enc_in[308] ^ ecc_enc_in[356] ^ ecc_enc_in[357] ^
                          ecc_enc_in[358] ^ ecc_enc_in[359] ^ ecc_enc_in[360] ^
                          ecc_enc_in[361] ^ ecc_enc_in[362] ^ ecc_enc_in[363] ^
                          ecc_enc_in[364] ^ ecc_enc_in[365] ^ ecc_enc_in[366] ^
                          ecc_enc_in[367] ^ ecc_enc_in[368] ^ ecc_enc_in[369] ^
                          ecc_enc_in[370] ^ ecc_enc_in[371] ^ ecc_enc_in[372] ^
                          ecc_enc_in[373] ^ ecc_enc_in[374] ^ ecc_enc_in[375] ^
                          ecc_enc_in[376] ^ ecc_enc_in[377] ^ ecc_enc_in[378] ^
                          ecc_enc_in[379] ^ ecc_enc_in[380] ^ ecc_enc_in[381] ^
                          ecc_enc_in[382] ^ ecc_enc_in[383] ^ ecc_enc_in[384] ^
                          ecc_enc_in[385] ^ ecc_enc_in[386] ^ ecc_enc_in[387] ^
                          ecc_enc_in[388] ^ ecc_enc_in[422] ^ ecc_enc_in[423] ^
                          ecc_enc_in[424] ^ ecc_enc_in[425] ^ ecc_enc_in[426] ^
                          ecc_enc_in[427] ^ ecc_enc_in[428] ^ ecc_enc_in[429] ^
                          ecc_enc_in[430] ^ ecc_enc_in[431] ^ ecc_enc_in[432] ^
                          ecc_enc_in[433] ^ ecc_enc_in[434] ^ ecc_enc_in[435] ^
                          ecc_enc_in[436] ^ ecc_enc_in[437] ^ ecc_enc_in[438] ^
                          ecc_enc_in[439] ^ ecc_enc_in[474] ^ ecc_enc_in[475] ^
                          ecc_enc_in[476] ^ ecc_enc_in[477] ^ ecc_enc_in[478] ^
                          ecc_enc_in[479] ^ ecc_enc_in[480] ^ ecc_enc_in[481] ^
                          ecc_enc_in[482] ^ ecc_enc_in[483] ^ ecc_enc_in[484] ^
                          ecc_enc_in[485] ^ ecc_enc_in[486] ^ ecc_enc_in[487] ^
                          ecc_enc_in[488] ^ ecc_enc_in[489] ^ ecc_enc_in[490] ^
                          ecc_enc_in[508] ^ ecc_enc_in[509] ^ ecc_enc_in[510] ^
                          ecc_enc_in[511] ^ ecc_enc_in[512]) ;
assign parity_enc[08] = ~( ecc_enc_in[099] ^ ecc_enc_in[100] ^ ecc_enc_in[101] ^
                          ecc_enc_in[102] ^ ecc_enc_in[103] ^ ecc_enc_in[104] ^
                          ecc_enc_in[105] ^ ecc_enc_in[106] ^ ecc_enc_in[107] ^
                          ecc_enc_in[108] ^ ecc_enc_in[109] ^ ecc_enc_in[110] ^
                          ecc_enc_in[111] ^ ecc_enc_in[112] ^ ecc_enc_in[113] ^
                          ecc_enc_in[114] ^ ecc_enc_in[115] ^ ecc_enc_in[116] ^
                          ecc_enc_in[117] ^ ecc_enc_in[118] ^ ecc_enc_in[119] ^
                          ecc_enc_in[120] ^ ecc_enc_in[121] ^ ecc_enc_in[122] ^
                          ecc_enc_in[123] ^ ecc_enc_in[124] ^ ecc_enc_in[125] ^
                          ecc_enc_in[126] ^ ecc_enc_in[127] ^ ecc_enc_in[128] ^
                          ecc_enc_in[129] ^ ecc_enc_in[130] ^ ecc_enc_in[131] ^
                          ecc_enc_in[132] ^ ecc_enc_in[133] ^ ecc_enc_in[134] ^
                          ecc_enc_in[135] ^ ecc_enc_in[136] ^ ecc_enc_in[137] ^
                          ecc_enc_in[138] ^ ecc_enc_in[139] ^ ecc_enc_in[140] ^
                          ecc_enc_in[141] ^ ecc_enc_in[142] ^ ecc_enc_in[143] ^
                          ecc_enc_in[144] ^ ecc_enc_in[145] ^ ecc_enc_in[146] ^
                          ecc_enc_in[147] ^ ecc_enc_in[148] ^ ecc_enc_in[149] ^
                          ecc_enc_in[150] ^ ecc_enc_in[151] ^ ecc_enc_in[152] ^
                          ecc_enc_in[153] ^ ecc_enc_in[154] ^ ecc_enc_in[155] ^
                          ecc_enc_in[156] ^ ecc_enc_in[157] ^ ecc_enc_in[158] ^
                          ecc_enc_in[159] ^ ecc_enc_in[160] ^ ecc_enc_in[161] ^
                          ecc_enc_in[162] ^ ecc_enc_in[163] ^ ecc_enc_in[164] ^
                          ecc_enc_in[165] ^ ecc_enc_in[166] ^ ecc_enc_in[167] ^
                          ecc_enc_in[168] ^ ecc_enc_in[169] ^ ecc_enc_in[170] ^
                          ecc_enc_in[171] ^ ecc_enc_in[172] ^ ecc_enc_in[173] ^
                          ecc_enc_in[174] ^ ecc_enc_in[175] ^ ecc_enc_in[176] ^
                          ecc_enc_in[177] ^ ecc_enc_in[258] ^ ecc_enc_in[259] ^
                          ecc_enc_in[260] ^ ecc_enc_in[261] ^ ecc_enc_in[262] ^
                          ecc_enc_in[263] ^ ecc_enc_in[264] ^ ecc_enc_in[265] ^
                          ecc_enc_in[266] ^ ecc_enc_in[267] ^ ecc_enc_in[268] ^
                          ecc_enc_in[269] ^ ecc_enc_in[270] ^ ecc_enc_in[271] ^
                          ecc_enc_in[272] ^ ecc_enc_in[273] ^ ecc_enc_in[274] ^
                          ecc_enc_in[275] ^ ecc_enc_in[276] ^ ecc_enc_in[277] ^
                          ecc_enc_in[278] ^ ecc_enc_in[279] ^ ecc_enc_in[280] ^
                          ecc_enc_in[281] ^ ecc_enc_in[282] ^ ecc_enc_in[283] ^
                          ecc_enc_in[284] ^ ecc_enc_in[285] ^ ecc_enc_in[286] ^
                          ecc_enc_in[287] ^ ecc_enc_in[288] ^ ecc_enc_in[289] ^
                          ecc_enc_in[290] ^ ecc_enc_in[291] ^ ecc_enc_in[292] ^
                          ecc_enc_in[293] ^ ecc_enc_in[294] ^ ecc_enc_in[295] ^
                          ecc_enc_in[296] ^ ecc_enc_in[297] ^ ecc_enc_in[298] ^
                          ecc_enc_in[299] ^ ecc_enc_in[300] ^ ecc_enc_in[301] ^
                          ecc_enc_in[302] ^ ecc_enc_in[303] ^ ecc_enc_in[304] ^
                          ecc_enc_in[305] ^ ecc_enc_in[306] ^ ecc_enc_in[307] ^
                          ecc_enc_in[308] ^ ecc_enc_in[389] ^ ecc_enc_in[390] ^
                          ecc_enc_in[391] ^ ecc_enc_in[392] ^ ecc_enc_in[393] ^
                          ecc_enc_in[394] ^ ecc_enc_in[395] ^ ecc_enc_in[396] ^
                          ecc_enc_in[397] ^ ecc_enc_in[398] ^ ecc_enc_in[399] ^
                          ecc_enc_in[400] ^ ecc_enc_in[401] ^ ecc_enc_in[402] ^
                          ecc_enc_in[403] ^ ecc_enc_in[404] ^ ecc_enc_in[405] ^
                          ecc_enc_in[406] ^ ecc_enc_in[407] ^ ecc_enc_in[408] ^
                          ecc_enc_in[409] ^ ecc_enc_in[410] ^ ecc_enc_in[411] ^
                          ecc_enc_in[412] ^ ecc_enc_in[413] ^ ecc_enc_in[414] ^
                          ecc_enc_in[415] ^ ecc_enc_in[416] ^ ecc_enc_in[417] ^
                          ecc_enc_in[418] ^ ecc_enc_in[419] ^ ecc_enc_in[420] ^
                          ecc_enc_in[421] ^ ecc_enc_in[422] ^ ecc_enc_in[423] ^
                          ecc_enc_in[424] ^ ecc_enc_in[425] ^ ecc_enc_in[426] ^
                          ecc_enc_in[427] ^ ecc_enc_in[428] ^ ecc_enc_in[429] ^
                          ecc_enc_in[430] ^ ecc_enc_in[431] ^ ecc_enc_in[432] ^
                          ecc_enc_in[433] ^ ecc_enc_in[434] ^ ecc_enc_in[435] ^
                          ecc_enc_in[436] ^ ecc_enc_in[437] ^ ecc_enc_in[438] ^
                          ecc_enc_in[439] ^ ecc_enc_in[491] ^ ecc_enc_in[492] ^
                          ecc_enc_in[493] ^ ecc_enc_in[494] ^ ecc_enc_in[495] ^
                          ecc_enc_in[496] ^ ecc_enc_in[497] ^ ecc_enc_in[498] ^
                          ecc_enc_in[499] ^ ecc_enc_in[500] ^ ecc_enc_in[501] ^
                          ecc_enc_in[502] ^ ecc_enc_in[503] ^ ecc_enc_in[504] ^
                          ecc_enc_in[505] ^ ecc_enc_in[506] ^ ecc_enc_in[507] ^
                          ecc_enc_in[508] ^ ecc_enc_in[509] ^ ecc_enc_in[510] ^
                          ecc_enc_in[511] ^ ecc_enc_in[512]) ;
assign parity_enc[09] = ~( ecc_enc_in[178] ^ ecc_enc_in[179] ^ ecc_enc_in[180] ^
                          ecc_enc_in[181] ^ ecc_enc_in[182] ^ ecc_enc_in[183] ^
                          ecc_enc_in[184] ^ ecc_enc_in[185] ^ ecc_enc_in[186] ^
                          ecc_enc_in[187] ^ ecc_enc_in[188] ^ ecc_enc_in[189] ^
                          ecc_enc_in[190] ^ ecc_enc_in[191] ^ ecc_enc_in[192] ^
                          ecc_enc_in[193] ^ ecc_enc_in[194] ^ ecc_enc_in[195] ^
                          ecc_enc_in[196] ^ ecc_enc_in[197] ^ ecc_enc_in[198] ^
                          ecc_enc_in[199] ^ ecc_enc_in[200] ^ ecc_enc_in[201] ^
                          ecc_enc_in[202] ^ ecc_enc_in[203] ^ ecc_enc_in[204] ^
                          ecc_enc_in[205] ^ ecc_enc_in[206] ^ ecc_enc_in[207] ^
                          ecc_enc_in[208] ^ ecc_enc_in[209] ^ ecc_enc_in[210] ^
                          ecc_enc_in[211] ^ ecc_enc_in[212] ^ ecc_enc_in[213] ^
                          ecc_enc_in[214] ^ ecc_enc_in[215] ^ ecc_enc_in[216] ^
                          ecc_enc_in[217] ^ ecc_enc_in[218] ^ ecc_enc_in[219] ^
                          ecc_enc_in[220] ^ ecc_enc_in[221] ^ ecc_enc_in[222] ^
                          ecc_enc_in[223] ^ ecc_enc_in[224] ^ ecc_enc_in[225] ^
                          ecc_enc_in[226] ^ ecc_enc_in[227] ^ ecc_enc_in[228] ^
                          ecc_enc_in[229] ^ ecc_enc_in[230] ^ ecc_enc_in[231] ^
                          ecc_enc_in[232] ^ ecc_enc_in[233] ^ ecc_enc_in[234] ^
                          ecc_enc_in[235] ^ ecc_enc_in[236] ^ ecc_enc_in[237] ^
                          ecc_enc_in[238] ^ ecc_enc_in[239] ^ ecc_enc_in[240] ^
                          ecc_enc_in[241] ^ ecc_enc_in[242] ^ ecc_enc_in[243] ^
                          ecc_enc_in[244] ^ ecc_enc_in[245] ^ ecc_enc_in[246] ^
                          ecc_enc_in[247] ^ ecc_enc_in[248] ^ ecc_enc_in[249] ^
                          ecc_enc_in[250] ^ ecc_enc_in[251] ^ ecc_enc_in[252] ^
                          ecc_enc_in[253] ^ ecc_enc_in[254] ^ ecc_enc_in[255] ^
                          ecc_enc_in[256] ^ ecc_enc_in[257] ^ ecc_enc_in[258] ^
                          ecc_enc_in[259] ^ ecc_enc_in[260] ^ ecc_enc_in[261] ^
                          ecc_enc_in[262] ^ ecc_enc_in[263] ^ ecc_enc_in[264] ^
                          ecc_enc_in[265] ^ ecc_enc_in[266] ^ ecc_enc_in[267] ^
                          ecc_enc_in[268] ^ ecc_enc_in[269] ^ ecc_enc_in[270] ^
                          ecc_enc_in[271] ^ ecc_enc_in[272] ^ ecc_enc_in[273] ^
                          ecc_enc_in[274] ^ ecc_enc_in[275] ^ ecc_enc_in[276] ^
                          ecc_enc_in[277] ^ ecc_enc_in[278] ^ ecc_enc_in[279] ^
                          ecc_enc_in[280] ^ ecc_enc_in[281] ^ ecc_enc_in[282] ^
                          ecc_enc_in[283] ^ ecc_enc_in[284] ^ ecc_enc_in[285] ^
                          ecc_enc_in[286] ^ ecc_enc_in[287] ^ ecc_enc_in[288] ^
                          ecc_enc_in[289] ^ ecc_enc_in[290] ^ ecc_enc_in[291] ^
                          ecc_enc_in[292] ^ ecc_enc_in[293] ^ ecc_enc_in[294] ^
                          ecc_enc_in[295] ^ ecc_enc_in[296] ^ ecc_enc_in[297] ^
                          ecc_enc_in[298] ^ ecc_enc_in[299] ^ ecc_enc_in[300] ^
                          ecc_enc_in[301] ^ ecc_enc_in[302] ^ ecc_enc_in[303] ^
                          ecc_enc_in[304] ^ ecc_enc_in[305] ^ ecc_enc_in[306] ^
                          ecc_enc_in[307] ^ ecc_enc_in[308] ^ ecc_enc_in[440] ^
                          ecc_enc_in[441] ^ ecc_enc_in[442] ^ ecc_enc_in[443] ^
                          ecc_enc_in[444] ^ ecc_enc_in[445] ^ ecc_enc_in[446] ^
                          ecc_enc_in[447] ^ ecc_enc_in[448] ^ ecc_enc_in[449] ^
                          ecc_enc_in[450] ^ ecc_enc_in[451] ^ ecc_enc_in[452] ^
                          ecc_enc_in[453] ^ ecc_enc_in[454] ^ ecc_enc_in[455] ^
                          ecc_enc_in[456] ^ ecc_enc_in[457] ^ ecc_enc_in[458] ^
                          ecc_enc_in[459] ^ ecc_enc_in[460] ^ ecc_enc_in[461] ^
                          ecc_enc_in[462] ^ ecc_enc_in[463] ^ ecc_enc_in[464] ^
                          ecc_enc_in[465] ^ ecc_enc_in[466] ^ ecc_enc_in[467] ^
                          ecc_enc_in[468] ^ ecc_enc_in[469] ^ ecc_enc_in[470] ^
                          ecc_enc_in[471] ^ ecc_enc_in[472] ^ ecc_enc_in[473] ^
                          ecc_enc_in[474] ^ ecc_enc_in[475] ^ ecc_enc_in[476] ^
                          ecc_enc_in[477] ^ ecc_enc_in[478] ^ ecc_enc_in[479] ^
                          ecc_enc_in[480] ^ ecc_enc_in[481] ^ ecc_enc_in[482] ^
                          ecc_enc_in[483] ^ ecc_enc_in[484] ^ ecc_enc_in[485] ^
                          ecc_enc_in[486] ^ ecc_enc_in[487] ^ ecc_enc_in[488] ^
                          ecc_enc_in[489] ^ ecc_enc_in[490] ^ ecc_enc_in[491] ^
                          ecc_enc_in[492] ^ ecc_enc_in[493] ^ ecc_enc_in[494] ^
                          ecc_enc_in[495] ^ ecc_enc_in[496] ^ ecc_enc_in[497] ^
                          ecc_enc_in[498] ^ ecc_enc_in[499] ^ ecc_enc_in[500] ^
                          ecc_enc_in[501] ^ ecc_enc_in[502] ^ ecc_enc_in[503] ^
                          ecc_enc_in[504] ^ ecc_enc_in[505] ^ ecc_enc_in[506] ^
                          ecc_enc_in[507] ^ ecc_enc_in[508] ^ ecc_enc_in[509] ^
                          ecc_enc_in[510] ^ ecc_enc_in[511] ^ ecc_enc_in[512]) ;
assign parity_enc[10] = ~( ecc_enc_in[309] ^ ecc_enc_in[310] ^ ecc_enc_in[311] ^
                          ecc_enc_in[312] ^ ecc_enc_in[313] ^ ecc_enc_in[314] ^
                          ecc_enc_in[315] ^ ecc_enc_in[316] ^ ecc_enc_in[317] ^
                          ecc_enc_in[318] ^ ecc_enc_in[319] ^ ecc_enc_in[320] ^
                          ecc_enc_in[321] ^ ecc_enc_in[322] ^ ecc_enc_in[323] ^
                          ecc_enc_in[324] ^ ecc_enc_in[325] ^ ecc_enc_in[326] ^
                          ecc_enc_in[327] ^ ecc_enc_in[328] ^ ecc_enc_in[329] ^
                          ecc_enc_in[330] ^ ecc_enc_in[331] ^ ecc_enc_in[332] ^
                          ecc_enc_in[333] ^ ecc_enc_in[334] ^ ecc_enc_in[335] ^
                          ecc_enc_in[336] ^ ecc_enc_in[337] ^ ecc_enc_in[338] ^
                          ecc_enc_in[339] ^ ecc_enc_in[340] ^ ecc_enc_in[341] ^
                          ecc_enc_in[342] ^ ecc_enc_in[343] ^ ecc_enc_in[344] ^
                          ecc_enc_in[345] ^ ecc_enc_in[346] ^ ecc_enc_in[347] ^
                          ecc_enc_in[348] ^ ecc_enc_in[349] ^ ecc_enc_in[350] ^
                          ecc_enc_in[351] ^ ecc_enc_in[352] ^ ecc_enc_in[353] ^
                          ecc_enc_in[354] ^ ecc_enc_in[355] ^ ecc_enc_in[356] ^
                          ecc_enc_in[357] ^ ecc_enc_in[358] ^ ecc_enc_in[359] ^
                          ecc_enc_in[360] ^ ecc_enc_in[361] ^ ecc_enc_in[362] ^
                          ecc_enc_in[363] ^ ecc_enc_in[364] ^ ecc_enc_in[365] ^
                          ecc_enc_in[366] ^ ecc_enc_in[367] ^ ecc_enc_in[368] ^
                          ecc_enc_in[369] ^ ecc_enc_in[370] ^ ecc_enc_in[371] ^
                          ecc_enc_in[372] ^ ecc_enc_in[373] ^ ecc_enc_in[374] ^
                          ecc_enc_in[375] ^ ecc_enc_in[376] ^ ecc_enc_in[377] ^
                          ecc_enc_in[378] ^ ecc_enc_in[379] ^ ecc_enc_in[380] ^
                          ecc_enc_in[381] ^ ecc_enc_in[382] ^ ecc_enc_in[383] ^
                          ecc_enc_in[384] ^ ecc_enc_in[385] ^ ecc_enc_in[386] ^
                          ecc_enc_in[387] ^ ecc_enc_in[388] ^ ecc_enc_in[389] ^
                          ecc_enc_in[390] ^ ecc_enc_in[391] ^ ecc_enc_in[392] ^
                          ecc_enc_in[393] ^ ecc_enc_in[394] ^ ecc_enc_in[395] ^
                          ecc_enc_in[396] ^ ecc_enc_in[397] ^ ecc_enc_in[398] ^
                          ecc_enc_in[399] ^ ecc_enc_in[400] ^ ecc_enc_in[401] ^
                          ecc_enc_in[402] ^ ecc_enc_in[403] ^ ecc_enc_in[404] ^
                          ecc_enc_in[405] ^ ecc_enc_in[406] ^ ecc_enc_in[407] ^
                          ecc_enc_in[408] ^ ecc_enc_in[409] ^ ecc_enc_in[410] ^
                          ecc_enc_in[411] ^ ecc_enc_in[412] ^ ecc_enc_in[413] ^
                          ecc_enc_in[414] ^ ecc_enc_in[415] ^ ecc_enc_in[416] ^
                          ecc_enc_in[417] ^ ecc_enc_in[418] ^ ecc_enc_in[419] ^
                          ecc_enc_in[420] ^ ecc_enc_in[421] ^ ecc_enc_in[422] ^
                          ecc_enc_in[423] ^ ecc_enc_in[424] ^ ecc_enc_in[425] ^
                          ecc_enc_in[426] ^ ecc_enc_in[427] ^ ecc_enc_in[428] ^
                          ecc_enc_in[429] ^ ecc_enc_in[430] ^ ecc_enc_in[431] ^
                          ecc_enc_in[432] ^ ecc_enc_in[433] ^ ecc_enc_in[434] ^
                          ecc_enc_in[435] ^ ecc_enc_in[436] ^ ecc_enc_in[437] ^
                          ecc_enc_in[438] ^ ecc_enc_in[439] ^ ecc_enc_in[440] ^
                          ecc_enc_in[441] ^ ecc_enc_in[442] ^ ecc_enc_in[443] ^
                          ecc_enc_in[444] ^ ecc_enc_in[445] ^ ecc_enc_in[446] ^
                          ecc_enc_in[447] ^ ecc_enc_in[448] ^ ecc_enc_in[449] ^
                          ecc_enc_in[450] ^ ecc_enc_in[451] ^ ecc_enc_in[452] ^
                          ecc_enc_in[453] ^ ecc_enc_in[454] ^ ecc_enc_in[455] ^
                          ecc_enc_in[456] ^ ecc_enc_in[457] ^ ecc_enc_in[458] ^
                          ecc_enc_in[459] ^ ecc_enc_in[460] ^ ecc_enc_in[461] ^
                          ecc_enc_in[462] ^ ecc_enc_in[463] ^ ecc_enc_in[464] ^
                          ecc_enc_in[465] ^ ecc_enc_in[466] ^ ecc_enc_in[467] ^
                          ecc_enc_in[468] ^ ecc_enc_in[469] ^ ecc_enc_in[470] ^
                          ecc_enc_in[471] ^ ecc_enc_in[472] ^ ecc_enc_in[473] ^
                          ecc_enc_in[474] ^ ecc_enc_in[475] ^ ecc_enc_in[476] ^
                          ecc_enc_in[477] ^ ecc_enc_in[478] ^ ecc_enc_in[479] ^
                          ecc_enc_in[480] ^ ecc_enc_in[481] ^ ecc_enc_in[482] ^
                          ecc_enc_in[483] ^ ecc_enc_in[484] ^ ecc_enc_in[485] ^
                          ecc_enc_in[486] ^ ecc_enc_in[487] ^ ecc_enc_in[488] ^
                          ecc_enc_in[489] ^ ecc_enc_in[490] ^ ecc_enc_in[491] ^
                          ecc_enc_in[492] ^ ecc_enc_in[493] ^ ecc_enc_in[494] ^
                          ecc_enc_in[495] ^ ecc_enc_in[496] ^ ecc_enc_in[497] ^
                          ecc_enc_in[498] ^ ecc_enc_in[499] ^ ecc_enc_in[500] ^
                          ecc_enc_in[501] ^ ecc_enc_in[502] ^ ecc_enc_in[503] ^
                          ecc_enc_in[504] ^ ecc_enc_in[505] ^ ecc_enc_in[506] ^
                          ecc_enc_in[507] ^ ecc_enc_in[508] ^ ecc_enc_in[509] ^
                          ecc_enc_in[510] ^ ecc_enc_in[511] ^ ecc_enc_in[512]) ;
assign ecc_encoder_parity_out = ecc_encoder_bypass ? ecc_encoder_parity_in : parity_enc;
assign ecc_encoder_data_out	= {ecc_encoder_parity_out, ecc_enc_in};




//synopsys translate_off
parameter numOfCodewordBit = 524;
parameter numOfDataBit = 513;
parameter numOfParityBits = 11;
reg [(numOfParityBits-1):0] G [0:(numOfDataBit-1)] ;


task GenerateGMatrix;
begin

    G[512] = 1984; G[511] = 1952; G[510] = 1936; G[509] = 1924; G[508] = 1921;  G[507] = 1888;  G[506] = 1864;  G[505] = 1858;
    G[504] = 1857; G[503] = 1840; G[502] = 1832; G[501] = 1828; G[500] = 1825;  G[499] = 1816;  G[498] = 1812;  G[497] = 1810;
    G[496] = 1809; G[495] = 1802; G[494] = 1798; G[493] = 1797; G[492] = 1795;  G[491] = 1792;  G[490] = 1760;  G[489] = 1744;
    G[488] = 1736; G[487] = 1732; G[486] = 1730; G[485] = 1712; G[484] = 1704;  G[483] = 1700;  G[482] = 1697;  G[481] = 1688;
    G[480] = 1684; G[479] = 1674; G[478] = 1673; G[477] = 1670; G[476] = 1669;  G[475] = 1667;  G[474] = 1664;  G[473] = 1648;
    G[472] = 1640; G[471] = 1636; G[470] = 1634; G[469] = 1633; G[468] = 1624;  G[467] = 1618;  G[466] = 1617;  G[465] = 1612;
    G[464] = 1610; G[463] = 1609; G[462] = 1600; G[461] = 1588; G[460] = 1586;  G[459] = 1585;  G[458] = 1574;  G[457] = 1573;
    G[456] = 1571; G[455] = 1568; G[454] = 1564; G[453] = 1562; G[452] = 1561;  G[451] = 1558;  G[450] = 1557;  G[449] = 1555;
    G[448] = 1552; G[447] = 1550; G[446] = 1549; G[445] = 1547; G[444] = 1544;  G[443] = 1543;  G[442] = 1540;  G[441] = 1538;
    G[440] = 1537; G[439] = 1504; G[438] = 1488; G[437] = 1480; G[436] = 1474;  G[435] = 1473;  G[434] = 1456;  G[433] = 1448;
    G[432] = 1444; G[431] = 1442; G[430] = 1432; G[429] = 1428; G[428] = 1420;  G[427] = 1418;  G[426] = 1417;  G[425] = 1414;
    G[424] = 1413; G[423] = 1411; G[422] = 1408; G[421] = 1392; G[420] = 1384;  G[419] = 1380;  G[418] = 1377;  G[417] = 1364;
    G[416] = 1362; G[415] = 1361; G[414] = 1356; G[413] = 1354; G[412] = 1353;  G[411] = 1350;  G[410] = 1347;  G[409] = 1344;
    G[408] = 1336; G[407] = 1330; G[406] = 1329; G[405] = 1324; G[404] = 1322;  G[403] = 1321;  G[402] = 1315;  G[401] = 1312;
    G[400] = 1308; G[399] = 1302; G[398] = 1301; G[397] = 1299; G[396] = 1296;  G[395] = 1294;  G[394] = 1293;  G[393] = 1288;
    G[392] = 1287; G[391] = 1284; G[390] = 1282; G[389] = 1281; G[388] = 1256;  G[387] = 1252;  G[386] = 1250;  G[385] = 1249;
    G[384] = 1240; G[383] = 1236; G[382] = 1234; G[381] = 1233; G[380] = 1228;  G[379] = 1226;  G[378] = 1221;  G[377] = 1219;
    G[376] = 1216; G[375] = 1208; G[374] = 1204; G[373] = 1196; G[372] = 1194;  G[371] = 1193;  G[370] = 1190;  G[369] = 1189;
    G[368] = 1184; G[367] = 1178; G[366] = 1177; G[365] = 1174; G[364] = 1173;  G[363] = 1171;  G[362] = 1168;  G[361] = 1163;
    G[360] = 1160; G[359] = 1159; G[358] = 1156; G[357] = 1154; G[356] = 1153;  G[355] = 1140;  G[354] = 1138;  G[353] = 1137;
    G[352] = 1132; G[351] = 1130; G[350] = 1126; G[349] = 1125; G[348] = 1123;  G[347] = 1120;  G[346] = 1116;  G[345] = 1114;
    G[344] = 1113; G[343] = 1107; G[342] = 1104; G[341] = 1101; G[340] = 1099;  G[339] = 1096;  G[338] = 1092;  G[337] = 1090;
    G[336] = 1089; G[335] = 1084; G[334] = 1078; G[333] = 1077; G[332] = 1075;  G[331] = 1072;  G[330] = 1070;  G[329] = 1069;
    G[328] = 1067; G[327] = 1064; G[326] = 1060; G[325] = 1058; G[324] = 1057;  G[323] = 1054;  G[322] = 1053;  G[321] = 1051;
    G[320] = 1048; G[319] = 1047; G[318] = 1044; G[317] = 1042; G[316] = 1041;  G[315] = 1039;  G[314] = 1036;  G[313] = 1034;
    G[312] = 1033; G[311] = 1030; G[310] = 1029; G[309] = 1027; G[308] = 992;  G[307] = 976;  G[306] = 968;  G[305] = 964;
    G[304] = 961; G[303] = 944; G[302] = 936; G[301] = 932; G[300] = 929;  G[299] = 920;  G[298] = 916;  G[297] = 914;
    G[296] = 913; G[295] = 908; G[294] = 905; G[293] = 902; G[292] = 901;  G[291] = 899;  G[290] = 896;  G[289] = 880;
    G[288] = 872; G[287] = 866; G[286] = 865; G[285] = 856; G[284] = 850;  G[283] = 849;  G[282] = 844;  G[281] = 842;
    G[280] = 841; G[279] = 838; G[278] = 837; G[277] = 835; G[276] = 832;  G[275] = 820;  G[274] = 818;  G[273] = 812;
    G[272] = 810; G[271] = 809; G[270] = 806; G[269] = 800; G[268] = 794;  G[267] = 793;  G[266] = 787;  G[265] = 784;
    G[264] = 782; G[263] = 779; G[262] = 776; G[261] = 775; G[260] = 772;  G[259] = 770;  G[258] = 769;  G[257] = 752;
    G[256] = 744; G[255] = 728; G[254] = 724; G[253] = 716; G[252] = 714;  G[251] = 713;  G[250] = 704;  G[249] = 696;
    G[248] = 692; G[247] = 690; G[246] = 689; G[245] = 684; G[244] = 682;  G[243] = 681;  G[242] = 678;  G[241] = 677;
    G[240] = 675; G[239] = 672; G[238] = 666; G[237] = 662; G[236] = 661;  G[235] = 659;  G[234] = 656;  G[233] = 654;
    G[232] = 653; G[231] = 651; G[230] = 648; G[229] = 647; G[228] = 644;  G[227] = 642;  G[226] = 641;  G[225] = 628;
    G[224] = 626; G[223] = 625; G[222] = 620; G[221] = 618; G[220] = 614;  G[219] = 613;  G[218] = 611;  G[217] = 608;
    G[216] = 604; G[215] = 602; G[214] = 601; G[213] = 598; G[212] = 597;  G[211] = 595;  G[210] = 592;  G[209] = 590;
    G[208] = 589; G[207] = 587; G[206] = 584; G[205] = 583; G[204] = 580;  G[203] = 578;  G[202] = 577;  G[201] = 569;
    G[200] = 566; G[199] = 565; G[198] = 563; G[197] = 560; G[196] = 557;  G[195] = 555;  G[194] = 552;  G[193] = 548;
    G[192] = 546; G[191] = 545; G[190] = 542; G[189] = 541; G[188] = 536;  G[187] = 532;  G[186] = 530;  G[185] = 529;
    G[184] = 527; G[183] = 524; G[182] = 522; G[181] = 521; G[180] = 518;  G[179] = 517;  G[178] = 515;  G[177] = 488;
    G[176] = 484; G[175] = 482; G[174] = 481; G[173] = 472; G[172] = 465;  G[171] = 460;  G[170] = 458;  G[169] = 457;
    G[168] = 454; G[167] = 453; G[166] = 448; G[165] = 440; G[164] = 436;  G[163] = 434;  G[162] = 433;  G[161] = 425;
    G[160] = 422; G[159] = 416; G[158] = 412; G[157] = 410; G[156] = 400;  G[155] = 398;  G[154] = 395;  G[153] = 392;
    G[152] = 388; G[151] = 386; G[150] = 385; G[149] = 376; G[148] = 372;  G[147] = 370;  G[146] = 364;  G[145] = 361;
    G[144] = 358; G[143] = 357; G[142] = 355; G[141] = 352; G[140] = 346;  G[139] = 345;  G[138] = 341;  G[137] = 339;
    G[136] = 336; G[135] = 334; G[134] = 333; G[133] = 331; G[132] = 328;  G[131] = 327;  G[130] = 324;  G[129] = 322;
    G[128] = 321; G[127] = 316; G[126] = 314; G[125] = 313; G[124] = 309;  G[123] = 307;  G[122] = 304;  G[121] = 302;
    G[120] = 301; G[119] = 299; G[118] = 296; G[117] = 295; G[116] = 292;  G[115] = 290;  G[114] = 289;  G[113] = 286;
    G[112] = 285; G[111] = 283; G[110] = 280; G[109] = 279; G[108] = 276;  G[107] = 274;  G[106] = 273;  G[105] = 271;
    G[104] = 268; G[103] = 266; G[102] = 265; G[101] = 262; G[100] = 261;  G[99] = 259;  G[98] = 244;  G[97] = 242;
    G[96] = 241; G[95] = 230; G[94] = 229; G[93] = 227; G[92] = 224;  G[91] = 220;  G[90] = 218;  G[89] = 217;
    G[88] = 214; G[87] = 213; G[86] = 211; G[85] = 208; G[84] = 206;  G[83] = 205;  G[82] = 203;  G[81] = 200;
    G[80] = 199; G[79] = 196; G[78] = 194; G[77] = 193; G[76] = 188;  G[75] = 186;  G[74] = 185;  G[73] = 182;
    G[72] = 181; G[71] = 179; G[70] = 176; G[69] = 174; G[68] = 173;  G[67] = 171;  G[66] = 168;  G[65] = 167;
    G[64] = 164; G[63] = 162; G[62] = 161; G[61] = 157; G[60] = 155;  G[59] = 152;  G[58] = 151;  G[57] = 148;
    G[56] = 146; G[55] = 145; G[54] = 143; G[53] = 140; G[52] = 138;  G[51] = 137;  G[50] = 134;  G[49] = 133;
    G[48] = 131; G[47] = 124; G[46] = 122; G[45] = 118; G[44] = 117;  G[43] = 115;  G[42] = 112;  G[41] = 104;
    G[40] = 103; G[39] = 100; G[38] = 98; G[37] = 97; G[36] = 94;  G[35] = 88;  G[34] = 87;  G[33] = 84;
    G[32] = 82; G[31] = 81; G[30] = 76; G[29] = 74; G[28] = 73;  G[27] = 70;  G[26] = 69;  G[25] = 67;
    G[24] = 62; G[23] = 61; G[22] = 56; G[21] = 55; G[20] = 52;  G[19] = 50;  G[18] = 49;  G[17] = 47;
    G[16] = 44; G[15] = 42; G[14] = 41; G[13] = 38; G[12] = 37;  G[11] = 35;  G[10] = 31;  G[9] = 28;
    G[8] = 26; G[7] = 25; G[6] = 22; G[5] = 21; G[4] = 19;  G[3] = 14;  G[2] = 13;  G[1] = 11;
    G[0] = 7;

end
endtask

task add_ecc_task;
integer p,q;
input [(numOfDataBit - 1):0]  ecc_encoder_data_in;
output [(numOfCodewordBit - 1):0] ecc_encoder_data_out;

reg [(numOfParityBits -1):0] parity;
reg [(numOfDataBit - 1):0]  G_col;

begin
  if (^ecc_encoder_data_in === 1'bx) $display("[%m]: <ERROR>[%0t]  UNKNOWN ecc_encoder_data_in = %b ", $time, ecc_encoder_data_in);
  else
  for (p = 0; p < numOfParityBits; p++) begin
    for (q = 0; q < numOfDataBit; q++) G_col[q] = G[q][p];
    parity[p] = ~^(G_col & ecc_encoder_data_in);
  end
  ecc_encoder_data_out = {parity,ecc_encoder_data_in};
end
endtask

initial begin
  GenerateGMatrix;
end
//synopsys translate_on



endmodule
