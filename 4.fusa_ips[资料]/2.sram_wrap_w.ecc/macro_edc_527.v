//*###############################################################################
//*#         Compiler Name    : tsmc_ecc_gen
//*#	     Compiler Version : 140b
//*#         ECC type         : SEC/DED
//*#         Generated Time   : 2026/06/18, 14:56:04
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
module macro_enc_527(
input  ecc_encoder_bypass,
input  [526:0] ecc_encoder_data_in,
input  [10:0] ecc_encoder_parity_in,
output [537:0] ecc_encoder_data_out,
output [10:0] ecc_encoder_parity_out
);



wire [526:0] ecc_enc_in;

wire [10:0] parity_enc;
//=========================================
//============== ECC Encoder ===============
//=========================================

//Hamming Code -- Parity Check Encoding
assign ecc_enc_in = ecc_encoder_data_in;

assign parity_enc[00] = ~( ecc_enc_in[000] ^ ecc_enc_in[001] ^ ecc_enc_in[002] ^
                          ecc_enc_in[004] ^ ecc_enc_in[005] ^ ecc_enc_in[007] ^
                          ecc_enc_in[010] ^ ecc_enc_in[011] ^ ecc_enc_in[012] ^
                          ecc_enc_in[014] ^ ecc_enc_in[017] ^ ecc_enc_in[020] ^
                          ecc_enc_in[022] ^ ecc_enc_in[023] ^ ecc_enc_in[024] ^
                          ecc_enc_in[025] ^ ecc_enc_in[027] ^ ecc_enc_in[030] ^
                          ecc_enc_in[031] ^ ecc_enc_in[034] ^ ecc_enc_in[036] ^
                          ecc_enc_in[037] ^ ecc_enc_in[038] ^ ecc_enc_in[041] ^
                          ecc_enc_in[043] ^ ecc_enc_in[044] ^ ecc_enc_in[047] ^
                          ecc_enc_in[051] ^ ecc_enc_in[052] ^ ecc_enc_in[054] ^
                          ecc_enc_in[057] ^ ecc_enc_in[058] ^ ecc_enc_in[061] ^
                          ecc_enc_in[063] ^ ecc_enc_in[064] ^ ecc_enc_in[067] ^
                          ecc_enc_in[069] ^ ecc_enc_in[070] ^ ecc_enc_in[073] ^
                          ecc_enc_in[074] ^ ecc_enc_in[076] ^ ecc_enc_in[078] ^
                          ecc_enc_in[081] ^ ecc_enc_in[083] ^ ecc_enc_in[086] ^
                          ecc_enc_in[087] ^ ecc_enc_in[092] ^ ecc_enc_in[093] ^
                          ecc_enc_in[095] ^ ecc_enc_in[098] ^ ecc_enc_in[100] ^
                          ecc_enc_in[101] ^ ecc_enc_in[103] ^ ecc_enc_in[106] ^
                          ecc_enc_in[107] ^ ecc_enc_in[111] ^ ecc_enc_in[113] ^
                          ecc_enc_in[116] ^ ecc_enc_in[118] ^ ecc_enc_in[119] ^
                          ecc_enc_in[121] ^ ecc_enc_in[123] ^ ecc_enc_in[126] ^
                          ecc_enc_in[130] ^ ecc_enc_in[131] ^ ecc_enc_in[134] ^
                          ecc_enc_in[135] ^ ecc_enc_in[136] ^ ecc_enc_in[140] ^
                          ecc_enc_in[141] ^ ecc_enc_in[143] ^ ecc_enc_in[144] ^
                          ecc_enc_in[148] ^ ecc_enc_in[151] ^ ecc_enc_in[153] ^
                          ecc_enc_in[154] ^ ecc_enc_in[156] ^ ecc_enc_in[157] ^
                          ecc_enc_in[159] ^ ecc_enc_in[163] ^ ecc_enc_in[167] ^
                          ecc_enc_in[171] ^ ecc_enc_in[173] ^ ecc_enc_in[182] ^
                          ecc_enc_in[183] ^ ecc_enc_in[185] ^ ecc_enc_in[188] ^
                          ecc_enc_in[191] ^ ecc_enc_in[193] ^ ecc_enc_in[194] ^
                          ecc_enc_in[196] ^ ecc_enc_in[199] ^ ecc_enc_in[201] ^
                          ecc_enc_in[202] ^ ecc_enc_in[205] ^ ecc_enc_in[206] ^
                          ecc_enc_in[208] ^ ecc_enc_in[211] ^ ecc_enc_in[214] ^
                          ecc_enc_in[216] ^ ecc_enc_in[217] ^ ecc_enc_in[220] ^
                          ecc_enc_in[222] ^ ecc_enc_in[225] ^ ecc_enc_in[226] ^
                          ecc_enc_in[231] ^ ecc_enc_in[234] ^ ecc_enc_in[236] ^
                          ecc_enc_in[237] ^ ecc_enc_in[239] ^ ecc_enc_in[241] ^
                          ecc_enc_in[244] ^ ecc_enc_in[247] ^ ecc_enc_in[251] ^
                          ecc_enc_in[252] ^ ecc_enc_in[255] ^ ecc_enc_in[259] ^
                          ecc_enc_in[264] ^ ecc_enc_in[268] ^ ecc_enc_in[269] ^
                          ecc_enc_in[272] ^ ecc_enc_in[273] ^ ecc_enc_in[278] ^
                          ecc_enc_in[280] ^ ecc_enc_in[283] ^ ecc_enc_in[287] ^
                          ecc_enc_in[288] ^ ecc_enc_in[291] ^ ecc_enc_in[294] ^
                          ecc_enc_in[299] ^ ecc_enc_in[300] ^ ecc_enc_in[304] ^
                          ecc_enc_in[307] ^ ecc_enc_in[311] ^ ecc_enc_in[317] ^
                          ecc_enc_in[318] ^ ecc_enc_in[320] ^ ecc_enc_in[323] ^
                          ecc_enc_in[324] ^ ecc_enc_in[327] ^ ecc_enc_in[329] ^
                          ecc_enc_in[331] ^ ecc_enc_in[335] ^ ecc_enc_in[336] ^
                          ecc_enc_in[339] ^ ecc_enc_in[341] ^ ecc_enc_in[343] ^
                          ecc_enc_in[346] ^ ecc_enc_in[348] ^ ecc_enc_in[349] ^
                          ecc_enc_in[352] ^ ecc_enc_in[353] ^ ecc_enc_in[357] ^
                          ecc_enc_in[358] ^ ecc_enc_in[361] ^ ecc_enc_in[365] ^
                          ecc_enc_in[368] ^ ecc_enc_in[370] ^ ecc_enc_in[371] ^
                          ecc_enc_in[375] ^ ecc_enc_in[379] ^ ecc_enc_in[380] ^
                          ecc_enc_in[381] ^ ecc_enc_in[383] ^ ecc_enc_in[388] ^
                          ecc_enc_in[389] ^ ecc_enc_in[392] ^ ecc_enc_in[395] ^
                          ecc_enc_in[399] ^ ecc_enc_in[402] ^ ecc_enc_in[404] ^
                          ecc_enc_in[406] ^ ecc_enc_in[407] ^ ecc_enc_in[409] ^
                          ecc_enc_in[413] ^ ecc_enc_in[414] ^ ecc_enc_in[415] ^
                          ecc_enc_in[417] ^ ecc_enc_in[420] ^ ecc_enc_in[422] ^
                          ecc_enc_in[425] ^ ecc_enc_in[428] ^ ecc_enc_in[434] ^
                          ecc_enc_in[436] ^ ecc_enc_in[439] ^ ecc_enc_in[443] ^
                          ecc_enc_in[448] ^ ecc_enc_in[452] ^ ecc_enc_in[455] ^
                          ecc_enc_in[457] ^ ecc_enc_in[458] ^ ecc_enc_in[461] ^
                          ecc_enc_in[463] ^ ecc_enc_in[467] ^ ecc_enc_in[468] ^
                          ecc_enc_in[472] ^ ecc_enc_in[476] ^ ecc_enc_in[477] ^
                          ecc_enc_in[479] ^ ecc_enc_in[483] ^ ecc_enc_in[488] ^
                          ecc_enc_in[490] ^ ecc_enc_in[492] ^ ecc_enc_in[499] ^
                          ecc_enc_in[506] ^ ecc_enc_in[507] ^ ecc_enc_in[511] ^
                          ecc_enc_in[518] ^ ecc_enc_in[523]) ;
assign parity_enc[01] = ~( ecc_enc_in[000] ^ ecc_enc_in[001] ^ ecc_enc_in[003] ^
                          ecc_enc_in[004] ^ ecc_enc_in[006] ^ ecc_enc_in[008] ^
                          ecc_enc_in[010] ^ ecc_enc_in[011] ^ ecc_enc_in[013] ^
                          ecc_enc_in[015] ^ ecc_enc_in[018] ^ ecc_enc_in[020] ^
                          ecc_enc_in[022] ^ ecc_enc_in[024] ^ ecc_enc_in[026] ^
                          ecc_enc_in[028] ^ ecc_enc_in[030] ^ ecc_enc_in[032] ^
                          ecc_enc_in[034] ^ ecc_enc_in[036] ^ ecc_enc_in[039] ^
                          ecc_enc_in[041] ^ ecc_enc_in[043] ^ ecc_enc_in[045] ^
                          ecc_enc_in[047] ^ ecc_enc_in[048] ^ ecc_enc_in[049] ^
                          ecc_enc_in[051] ^ ecc_enc_in[053] ^ ecc_enc_in[055] ^
                          ecc_enc_in[057] ^ ecc_enc_in[059] ^ ecc_enc_in[061] ^
                          ecc_enc_in[065] ^ ecc_enc_in[067] ^ ecc_enc_in[069] ^
                          ecc_enc_in[071] ^ ecc_enc_in[073] ^ ecc_enc_in[075] ^
                          ecc_enc_in[077] ^ ecc_enc_in[079] ^ ecc_enc_in[081] ^
                          ecc_enc_in[084] ^ ecc_enc_in[086] ^ ecc_enc_in[088] ^
                          ecc_enc_in[089] ^ ecc_enc_in[092] ^ ecc_enc_in[094] ^
                          ecc_enc_in[096] ^ ecc_enc_in[100] ^ ecc_enc_in[102] ^
                          ecc_enc_in[104] ^ ecc_enc_in[106] ^ ecc_enc_in[108] ^
                          ecc_enc_in[111] ^ ecc_enc_in[112] ^ ecc_enc_in[114] ^
                          ecc_enc_in[116] ^ ecc_enc_in[118] ^ ecc_enc_in[122] ^
                          ecc_enc_in[124] ^ ecc_enc_in[127] ^ ecc_enc_in[130] ^
                          ecc_enc_in[132] ^ ecc_enc_in[134] ^ ecc_enc_in[137] ^
                          ecc_enc_in[140] ^ ecc_enc_in[142] ^ ecc_enc_in[145] ^
                          ecc_enc_in[149] ^ ecc_enc_in[151] ^ ecc_enc_in[153] ^
                          ecc_enc_in[156] ^ ecc_enc_in[158] ^ ecc_enc_in[160] ^
                          ecc_enc_in[163] ^ ecc_enc_in[164] ^ ecc_enc_in[165] ^
                          ecc_enc_in[171] ^ ecc_enc_in[172] ^ ecc_enc_in[174] ^
                          ecc_enc_in[176] ^ ecc_enc_in[178] ^ ecc_enc_in[182] ^
                          ecc_enc_in[184] ^ ecc_enc_in[186] ^ ecc_enc_in[189] ^
                          ecc_enc_in[191] ^ ecc_enc_in[193] ^ ecc_enc_in[195] ^
                          ecc_enc_in[197] ^ ecc_enc_in[199] ^ ecc_enc_in[201] ^
                          ecc_enc_in[203] ^ ecc_enc_in[205] ^ ecc_enc_in[207] ^
                          ecc_enc_in[209] ^ ecc_enc_in[212] ^ ecc_enc_in[214] ^
                          ecc_enc_in[216] ^ ecc_enc_in[218] ^ ecc_enc_in[221] ^
                          ecc_enc_in[223] ^ ecc_enc_in[227] ^ ecc_enc_in[229] ^
                          ecc_enc_in[232] ^ ecc_enc_in[234] ^ ecc_enc_in[236] ^
                          ecc_enc_in[240] ^ ecc_enc_in[245] ^ ecc_enc_in[248] ^
                          ecc_enc_in[251] ^ ecc_enc_in[253] ^ ecc_enc_in[256] ^
                          ecc_enc_in[260] ^ ecc_enc_in[265] ^ ecc_enc_in[268] ^
                          ecc_enc_in[270] ^ ecc_enc_in[272] ^ ecc_enc_in[274] ^
                          ecc_enc_in[275] ^ ecc_enc_in[278] ^ ecc_enc_in[279] ^
                          ecc_enc_in[281] ^ ecc_enc_in[287] ^ ecc_enc_in[289] ^
                          ecc_enc_in[292] ^ ecc_enc_in[295] ^ ecc_enc_in[299] ^
                          ecc_enc_in[301] ^ ecc_enc_in[302] ^ ecc_enc_in[305] ^
                          ecc_enc_in[308] ^ ecc_enc_in[312] ^ ecc_enc_in[317] ^
                          ecc_enc_in[319] ^ ecc_enc_in[321] ^ ecc_enc_in[323] ^
                          ecc_enc_in[325] ^ ecc_enc_in[327] ^ ecc_enc_in[330] ^
                          ecc_enc_in[332] ^ ecc_enc_in[335] ^ ecc_enc_in[337] ^
                          ecc_enc_in[339] ^ ecc_enc_in[340] ^ ecc_enc_in[342] ^
                          ecc_enc_in[344] ^ ecc_enc_in[346] ^ ecc_enc_in[348] ^
                          ecc_enc_in[350] ^ ecc_enc_in[354] ^ ecc_enc_in[357] ^
                          ecc_enc_in[359] ^ ecc_enc_in[362] ^ ecc_enc_in[366] ^
                          ecc_enc_in[368] ^ ecc_enc_in[370] ^ ecc_enc_in[372] ^
                          ecc_enc_in[374] ^ ecc_enc_in[376] ^ ecc_enc_in[379] ^
                          ecc_enc_in[382] ^ ecc_enc_in[384] ^ ecc_enc_in[388] ^
                          ecc_enc_in[390] ^ ecc_enc_in[393] ^ ecc_enc_in[396] ^
                          ecc_enc_in[400] ^ ecc_enc_in[402] ^ ecc_enc_in[404] ^
                          ecc_enc_in[406] ^ ecc_enc_in[408] ^ ecc_enc_in[410] ^
                          ecc_enc_in[413] ^ ecc_enc_in[420] ^ ecc_enc_in[421] ^
                          ecc_enc_in[423] ^ ecc_enc_in[426] ^ ecc_enc_in[429] ^
                          ecc_enc_in[434] ^ ecc_enc_in[435] ^ ecc_enc_in[437] ^
                          ecc_enc_in[440] ^ ecc_enc_in[444] ^ ecc_enc_in[449] ^
                          ecc_enc_in[453] ^ ecc_enc_in[455] ^ ecc_enc_in[457] ^
                          ecc_enc_in[459] ^ ecc_enc_in[462] ^ ecc_enc_in[464] ^
                          ecc_enc_in[467] ^ ecc_enc_in[469] ^ ecc_enc_in[470] ^
                          ecc_enc_in[473] ^ ecc_enc_in[478] ^ ecc_enc_in[480] ^
                          ecc_enc_in[484] ^ ecc_enc_in[489] ^ ecc_enc_in[493] ^
                          ecc_enc_in[495] ^ ecc_enc_in[500] ^ ecc_enc_in[506] ^
                          ecc_enc_in[508] ^ ecc_enc_in[509] ^ ecc_enc_in[512] ^
                          ecc_enc_in[514] ^ ecc_enc_in[519]) ;
assign parity_enc[02] = ~( ecc_enc_in[000] ^ ecc_enc_in[002] ^ ecc_enc_in[003] ^
                          ecc_enc_in[005] ^ ecc_enc_in[006] ^ ecc_enc_in[009] ^
                          ecc_enc_in[010] ^ ecc_enc_in[012] ^ ecc_enc_in[013] ^
                          ecc_enc_in[016] ^ ecc_enc_in[019] ^ ecc_enc_in[020] ^
                          ecc_enc_in[023] ^ ecc_enc_in[025] ^ ecc_enc_in[026] ^
                          ecc_enc_in[029] ^ ecc_enc_in[030] ^ ecc_enc_in[033] ^
                          ecc_enc_in[034] ^ ecc_enc_in[037] ^ ecc_enc_in[040] ^
                          ecc_enc_in[041] ^ ecc_enc_in[044] ^ ecc_enc_in[045] ^
                          ecc_enc_in[048] ^ ecc_enc_in[050] ^ ecc_enc_in[052] ^
                          ecc_enc_in[053] ^ ecc_enc_in[056] ^ ecc_enc_in[057] ^
                          ecc_enc_in[060] ^ ecc_enc_in[061] ^ ecc_enc_in[063] ^
                          ecc_enc_in[066] ^ ecc_enc_in[067] ^ ecc_enc_in[070] ^
                          ecc_enc_in[071] ^ ecc_enc_in[074] ^ ecc_enc_in[075] ^
                          ecc_enc_in[080] ^ ecc_enc_in[081] ^ ecc_enc_in[083] ^
                          ecc_enc_in[084] ^ ecc_enc_in[087] ^ ecc_enc_in[088] ^
                          ecc_enc_in[090] ^ ecc_enc_in[093] ^ ecc_enc_in[094] ^
                          ecc_enc_in[097] ^ ecc_enc_in[101] ^ ecc_enc_in[102] ^
                          ecc_enc_in[105] ^ ecc_enc_in[106] ^ ecc_enc_in[109] ^
                          ecc_enc_in[112] ^ ecc_enc_in[115] ^ ecc_enc_in[116] ^
                          ecc_enc_in[119] ^ ecc_enc_in[121] ^ ecc_enc_in[122] ^
                          ecc_enc_in[125] ^ ecc_enc_in[128] ^ ecc_enc_in[131] ^
                          ecc_enc_in[132] ^ ecc_enc_in[135] ^ ecc_enc_in[138] ^
                          ecc_enc_in[141] ^ ecc_enc_in[142] ^ ecc_enc_in[146] ^
                          ecc_enc_in[150] ^ ecc_enc_in[151] ^ ecc_enc_in[154] ^
                          ecc_enc_in[157] ^ ecc_enc_in[158] ^ ecc_enc_in[161] ^
                          ecc_enc_in[164] ^ ecc_enc_in[166] ^ ecc_enc_in[168] ^
                          ecc_enc_in[172] ^ ecc_enc_in[175] ^ ecc_enc_in[177] ^
                          ecc_enc_in[179] ^ ecc_enc_in[183] ^ ecc_enc_in[184] ^
                          ecc_enc_in[187] ^ ecc_enc_in[190] ^ ecc_enc_in[191] ^
                          ecc_enc_in[194] ^ ecc_enc_in[195] ^ ecc_enc_in[198] ^
                          ecc_enc_in[199] ^ ecc_enc_in[202] ^ ecc_enc_in[203] ^
                          ecc_enc_in[206] ^ ecc_enc_in[207] ^ ecc_enc_in[210] ^
                          ecc_enc_in[213] ^ ecc_enc_in[214] ^ ecc_enc_in[217] ^
                          ecc_enc_in[218] ^ ecc_enc_in[220] ^ ecc_enc_in[221] ^
                          ecc_enc_in[225] ^ ecc_enc_in[228] ^ ecc_enc_in[230] ^
                          ecc_enc_in[233] ^ ecc_enc_in[234] ^ ecc_enc_in[237] ^
                          ecc_enc_in[239] ^ ecc_enc_in[240] ^ ecc_enc_in[242] ^
                          ecc_enc_in[244] ^ ecc_enc_in[246] ^ ecc_enc_in[252] ^
                          ecc_enc_in[253] ^ ecc_enc_in[254] ^ ecc_enc_in[257] ^
                          ecc_enc_in[261] ^ ecc_enc_in[266] ^ ecc_enc_in[269] ^
                          ecc_enc_in[270] ^ ecc_enc_in[273] ^ ecc_enc_in[274] ^
                          ecc_enc_in[276] ^ ecc_enc_in[279] ^ ecc_enc_in[282] ^
                          ecc_enc_in[284] ^ ecc_enc_in[290] ^ ecc_enc_in[296] ^
                          ecc_enc_in[300] ^ ecc_enc_in[301] ^ ecc_enc_in[303] ^
                          ecc_enc_in[309] ^ ecc_enc_in[313] ^ ecc_enc_in[318] ^
                          ecc_enc_in[319] ^ ecc_enc_in[322] ^ ecc_enc_in[323] ^
                          ecc_enc_in[326] ^ ecc_enc_in[327] ^ ecc_enc_in[329] ^
                          ecc_enc_in[330] ^ ecc_enc_in[333] ^ ecc_enc_in[336] ^
                          ecc_enc_in[337] ^ ecc_enc_in[340] ^ ecc_enc_in[345] ^
                          ecc_enc_in[346] ^ ecc_enc_in[349] ^ ecc_enc_in[350] ^
                          ecc_enc_in[352] ^ ecc_enc_in[355] ^ ecc_enc_in[358] ^
                          ecc_enc_in[359] ^ ecc_enc_in[360] ^ ecc_enc_in[363] ^
                          ecc_enc_in[367] ^ ecc_enc_in[368] ^ ecc_enc_in[371] ^
                          ecc_enc_in[372] ^ ecc_enc_in[374] ^ ecc_enc_in[377] ^
                          ecc_enc_in[380] ^ ecc_enc_in[385] ^ ecc_enc_in[389] ^
                          ecc_enc_in[390] ^ ecc_enc_in[391] ^ ecc_enc_in[394] ^
                          ecc_enc_in[397] ^ ecc_enc_in[401] ^ ecc_enc_in[402] ^
                          ecc_enc_in[407] ^ ecc_enc_in[408] ^ ecc_enc_in[411] ^
                          ecc_enc_in[414] ^ ecc_enc_in[416] ^ ecc_enc_in[418] ^
                          ecc_enc_in[421] ^ ecc_enc_in[424] ^ ecc_enc_in[427] ^
                          ecc_enc_in[430] ^ ecc_enc_in[435] ^ ecc_enc_in[438] ^
                          ecc_enc_in[441] ^ ecc_enc_in[445] ^ ecc_enc_in[454] ^
                          ecc_enc_in[455] ^ ecc_enc_in[458] ^ ecc_enc_in[459] ^
                          ecc_enc_in[461] ^ ecc_enc_in[462] ^ ecc_enc_in[465] ^
                          ecc_enc_in[468] ^ ecc_enc_in[469] ^ ecc_enc_in[471] ^
                          ecc_enc_in[476] ^ ecc_enc_in[481] ^ ecc_enc_in[488] ^
                          ecc_enc_in[489] ^ ecc_enc_in[491] ^ ecc_enc_in[494] ^
                          ecc_enc_in[496] ^ ecc_enc_in[501] ^ ecc_enc_in[507] ^
                          ecc_enc_in[508] ^ ecc_enc_in[510] ^ ecc_enc_in[515] ^
                          ecc_enc_in[520] ^ ecc_enc_in[524]) ;
assign parity_enc[03] = ~( ecc_enc_in[001] ^ ecc_enc_in[002] ^ ecc_enc_in[003] ^
                          ecc_enc_in[007] ^ ecc_enc_in[008] ^ ecc_enc_in[009] ^
                          ecc_enc_in[010] ^ ecc_enc_in[014] ^ ecc_enc_in[015] ^
                          ecc_enc_in[016] ^ ecc_enc_in[021] ^ ecc_enc_in[022] ^
                          ecc_enc_in[023] ^ ecc_enc_in[027] ^ ecc_enc_in[028] ^
                          ecc_enc_in[029] ^ ecc_enc_in[030] ^ ecc_enc_in[035] ^
                          ecc_enc_in[036] ^ ecc_enc_in[037] ^ ecc_enc_in[042] ^
                          ecc_enc_in[043] ^ ecc_enc_in[044] ^ ecc_enc_in[045] ^
                          ecc_enc_in[049] ^ ecc_enc_in[050] ^ ecc_enc_in[054] ^
                          ecc_enc_in[055] ^ ecc_enc_in[056] ^ ecc_enc_in[057] ^
                          ecc_enc_in[062] ^ ecc_enc_in[063] ^ ecc_enc_in[068] ^
                          ecc_enc_in[069] ^ ecc_enc_in[070] ^ ecc_enc_in[071] ^
                          ecc_enc_in[076] ^ ecc_enc_in[077] ^ ecc_enc_in[082] ^
                          ecc_enc_in[083] ^ ecc_enc_in[084] ^ ecc_enc_in[089] ^
                          ecc_enc_in[090] ^ ecc_enc_in[095] ^ ecc_enc_in[096] ^
                          ecc_enc_in[097] ^ ecc_enc_in[099] ^ ecc_enc_in[103] ^
                          ecc_enc_in[104] ^ ecc_enc_in[105] ^ ecc_enc_in[106] ^
                          ecc_enc_in[110] ^ ecc_enc_in[111] ^ ecc_enc_in[112] ^
                          ecc_enc_in[117] ^ ecc_enc_in[118] ^ ecc_enc_in[119] ^
                          ecc_enc_in[123] ^ ecc_enc_in[124] ^ ecc_enc_in[125] ^
                          ecc_enc_in[129] ^ ecc_enc_in[130] ^ ecc_enc_in[131] ^
                          ecc_enc_in[132] ^ ecc_enc_in[136] ^ ecc_enc_in[137] ^
                          ecc_enc_in[138] ^ ecc_enc_in[143] ^ ecc_enc_in[147] ^
                          ecc_enc_in[152] ^ ecc_enc_in[153] ^ ecc_enc_in[154] ^
                          ecc_enc_in[159] ^ ecc_enc_in[160] ^ ecc_enc_in[161] ^
                          ecc_enc_in[165] ^ ecc_enc_in[166] ^ ecc_enc_in[169] ^
                          ecc_enc_in[173] ^ ecc_enc_in[174] ^ ecc_enc_in[175] ^
                          ecc_enc_in[180] ^ ecc_enc_in[185] ^ ecc_enc_in[186] ^
                          ecc_enc_in[187] ^ ecc_enc_in[192] ^ ecc_enc_in[193] ^
                          ecc_enc_in[194] ^ ecc_enc_in[195] ^ ecc_enc_in[200] ^
                          ecc_enc_in[201] ^ ecc_enc_in[202] ^ ecc_enc_in[203] ^
                          ecc_enc_in[208] ^ ecc_enc_in[209] ^ ecc_enc_in[210] ^
                          ecc_enc_in[215] ^ ecc_enc_in[216] ^ ecc_enc_in[217] ^
                          ecc_enc_in[218] ^ ecc_enc_in[222] ^ ecc_enc_in[223] ^
                          ecc_enc_in[226] ^ ecc_enc_in[227] ^ ecc_enc_in[228] ^
                          ecc_enc_in[235] ^ ecc_enc_in[236] ^ ecc_enc_in[237] ^
                          ecc_enc_in[241] ^ ecc_enc_in[242] ^ ecc_enc_in[245] ^
                          ecc_enc_in[246] ^ ecc_enc_in[249] ^ ecc_enc_in[254] ^
                          ecc_enc_in[258] ^ ecc_enc_in[262] ^ ecc_enc_in[267] ^
                          ecc_enc_in[268] ^ ecc_enc_in[269] ^ ecc_enc_in[270] ^
                          ecc_enc_in[275] ^ ecc_enc_in[276] ^ ecc_enc_in[280] ^
                          ecc_enc_in[281] ^ ecc_enc_in[282] ^ ecc_enc_in[285] ^
                          ecc_enc_in[288] ^ ecc_enc_in[289] ^ ecc_enc_in[290] ^
                          ecc_enc_in[293] ^ ecc_enc_in[302] ^ ecc_enc_in[303] ^
                          ecc_enc_in[306] ^ ecc_enc_in[314] ^ ecc_enc_in[320] ^
                          ecc_enc_in[321] ^ ecc_enc_in[322] ^ ecc_enc_in[323] ^
                          ecc_enc_in[328] ^ ecc_enc_in[329] ^ ecc_enc_in[330] ^
                          ecc_enc_in[334] ^ ecc_enc_in[335] ^ ecc_enc_in[336] ^
                          ecc_enc_in[337] ^ ecc_enc_in[341] ^ ecc_enc_in[342] ^
                          ecc_enc_in[347] ^ ecc_enc_in[348] ^ ecc_enc_in[349] ^
                          ecc_enc_in[350] ^ ecc_enc_in[353] ^ ecc_enc_in[354] ^
                          ecc_enc_in[355] ^ ecc_enc_in[360] ^ ecc_enc_in[364] ^
                          ecc_enc_in[369] ^ ecc_enc_in[370] ^ ecc_enc_in[371] ^
                          ecc_enc_in[372] ^ ecc_enc_in[375] ^ ecc_enc_in[376] ^
                          ecc_enc_in[377] ^ ecc_enc_in[381] ^ ecc_enc_in[382] ^
                          ecc_enc_in[386] ^ ecc_enc_in[391] ^ ecc_enc_in[398] ^
                          ecc_enc_in[403] ^ ecc_enc_in[404] ^ ecc_enc_in[409] ^
                          ecc_enc_in[410] ^ ecc_enc_in[411] ^ ecc_enc_in[415] ^
                          ecc_enc_in[416] ^ ecc_enc_in[422] ^ ecc_enc_in[423] ^
                          ecc_enc_in[424] ^ ecc_enc_in[431] ^ ecc_enc_in[436] ^
                          ecc_enc_in[437] ^ ecc_enc_in[438] ^ ecc_enc_in[442] ^
                          ecc_enc_in[446] ^ ecc_enc_in[450] ^ ecc_enc_in[456] ^
                          ecc_enc_in[457] ^ ecc_enc_in[458] ^ ecc_enc_in[459] ^
                          ecc_enc_in[463] ^ ecc_enc_in[464] ^ ecc_enc_in[465] ^
                          ecc_enc_in[470] ^ ecc_enc_in[471] ^ ecc_enc_in[474] ^
                          ecc_enc_in[477] ^ ecc_enc_in[478] ^ ecc_enc_in[482] ^
                          ecc_enc_in[485] ^ ecc_enc_in[490] ^ ecc_enc_in[491] ^
                          ecc_enc_in[497] ^ ecc_enc_in[502] ^ ecc_enc_in[509] ^
                          ecc_enc_in[510] ^ ecc_enc_in[513] ^ ecc_enc_in[516] ^
                          ecc_enc_in[521] ^ ecc_enc_in[525]) ;
assign parity_enc[04] = ~( ecc_enc_in[004] ^ ecc_enc_in[005] ^ ecc_enc_in[006] ^
                          ecc_enc_in[007] ^ ecc_enc_in[008] ^ ecc_enc_in[009] ^
                          ecc_enc_in[010] ^ ecc_enc_in[017] ^ ecc_enc_in[018] ^
                          ecc_enc_in[019] ^ ecc_enc_in[020] ^ ecc_enc_in[021] ^
                          ecc_enc_in[022] ^ ecc_enc_in[023] ^ ecc_enc_in[031] ^
                          ecc_enc_in[032] ^ ecc_enc_in[033] ^ ecc_enc_in[034] ^
                          ecc_enc_in[035] ^ ecc_enc_in[036] ^ ecc_enc_in[037] ^
                          ecc_enc_in[046] ^ ecc_enc_in[047] ^ ecc_enc_in[048] ^
                          ecc_enc_in[049] ^ ecc_enc_in[050] ^ ecc_enc_in[058] ^
                          ecc_enc_in[059] ^ ecc_enc_in[060] ^ ecc_enc_in[061] ^
                          ecc_enc_in[062] ^ ecc_enc_in[063] ^ ecc_enc_in[072] ^
                          ecc_enc_in[073] ^ ecc_enc_in[074] ^ ecc_enc_in[075] ^
                          ecc_enc_in[076] ^ ecc_enc_in[077] ^ ecc_enc_in[085] ^
                          ecc_enc_in[086] ^ ecc_enc_in[087] ^ ecc_enc_in[088] ^
                          ecc_enc_in[089] ^ ecc_enc_in[090] ^ ecc_enc_in[098] ^
                          ecc_enc_in[099] ^ ecc_enc_in[107] ^ ecc_enc_in[108] ^
                          ecc_enc_in[109] ^ ecc_enc_in[110] ^ ecc_enc_in[111] ^
                          ecc_enc_in[112] ^ ecc_enc_in[120] ^ ecc_enc_in[121] ^
                          ecc_enc_in[122] ^ ecc_enc_in[123] ^ ecc_enc_in[124] ^
                          ecc_enc_in[125] ^ ecc_enc_in[133] ^ ecc_enc_in[134] ^
                          ecc_enc_in[135] ^ ecc_enc_in[136] ^ ecc_enc_in[137] ^
                          ecc_enc_in[138] ^ ecc_enc_in[144] ^ ecc_enc_in[145] ^
                          ecc_enc_in[146] ^ ecc_enc_in[147] ^ ecc_enc_in[155] ^
                          ecc_enc_in[156] ^ ecc_enc_in[157] ^ ecc_enc_in[158] ^
                          ecc_enc_in[159] ^ ecc_enc_in[160] ^ ecc_enc_in[161] ^
                          ecc_enc_in[167] ^ ecc_enc_in[168] ^ ecc_enc_in[169] ^
                          ecc_enc_in[176] ^ ecc_enc_in[177] ^ ecc_enc_in[181] ^
                          ecc_enc_in[188] ^ ecc_enc_in[189] ^ ecc_enc_in[190] ^
                          ecc_enc_in[191] ^ ecc_enc_in[192] ^ ecc_enc_in[193] ^
                          ecc_enc_in[194] ^ ecc_enc_in[195] ^ ecc_enc_in[204] ^
                          ecc_enc_in[205] ^ ecc_enc_in[206] ^ ecc_enc_in[207] ^
                          ecc_enc_in[208] ^ ecc_enc_in[209] ^ ecc_enc_in[210] ^
                          ecc_enc_in[219] ^ ecc_enc_in[220] ^ ecc_enc_in[221] ^
                          ecc_enc_in[222] ^ ecc_enc_in[223] ^ ecc_enc_in[229] ^
                          ecc_enc_in[230] ^ ecc_enc_in[238] ^ ecc_enc_in[239] ^
                          ecc_enc_in[240] ^ ecc_enc_in[241] ^ ecc_enc_in[242] ^
                          ecc_enc_in[247] ^ ecc_enc_in[248] ^ ecc_enc_in[249] ^
                          ecc_enc_in[255] ^ ecc_enc_in[256] ^ ecc_enc_in[257] ^
                          ecc_enc_in[258] ^ ecc_enc_in[263] ^ ecc_enc_in[271] ^
                          ecc_enc_in[272] ^ ecc_enc_in[273] ^ ecc_enc_in[274] ^
                          ecc_enc_in[275] ^ ecc_enc_in[276] ^ ecc_enc_in[283] ^
                          ecc_enc_in[284] ^ ecc_enc_in[285] ^ ecc_enc_in[291] ^
                          ecc_enc_in[292] ^ ecc_enc_in[293] ^ ecc_enc_in[297] ^
                          ecc_enc_in[304] ^ ecc_enc_in[305] ^ ecc_enc_in[306] ^
                          ecc_enc_in[310] ^ ecc_enc_in[315] ^ ecc_enc_in[324] ^
                          ecc_enc_in[325] ^ ecc_enc_in[326] ^ ecc_enc_in[327] ^
                          ecc_enc_in[328] ^ ecc_enc_in[329] ^ ecc_enc_in[330] ^
                          ecc_enc_in[338] ^ ecc_enc_in[339] ^ ecc_enc_in[340] ^
                          ecc_enc_in[341] ^ ecc_enc_in[342] ^ ecc_enc_in[351] ^
                          ecc_enc_in[352] ^ ecc_enc_in[353] ^ ecc_enc_in[354] ^
                          ecc_enc_in[355] ^ ecc_enc_in[361] ^ ecc_enc_in[362] ^
                          ecc_enc_in[363] ^ ecc_enc_in[364] ^ ecc_enc_in[373] ^
                          ecc_enc_in[374] ^ ecc_enc_in[375] ^ ecc_enc_in[376] ^
                          ecc_enc_in[377] ^ ecc_enc_in[383] ^ ecc_enc_in[384] ^
                          ecc_enc_in[385] ^ ecc_enc_in[386] ^ ecc_enc_in[392] ^
                          ecc_enc_in[393] ^ ecc_enc_in[394] ^ ecc_enc_in[405] ^
                          ecc_enc_in[406] ^ ecc_enc_in[407] ^ ecc_enc_in[408] ^
                          ecc_enc_in[409] ^ ecc_enc_in[410] ^ ecc_enc_in[411] ^
                          ecc_enc_in[417] ^ ecc_enc_in[418] ^ ecc_enc_in[425] ^
                          ecc_enc_in[426] ^ ecc_enc_in[427] ^ ecc_enc_in[432] ^
                          ecc_enc_in[439] ^ ecc_enc_in[440] ^ ecc_enc_in[441] ^
                          ecc_enc_in[442] ^ ecc_enc_in[447] ^ ecc_enc_in[451] ^
                          ecc_enc_in[460] ^ ecc_enc_in[461] ^ ecc_enc_in[462] ^
                          ecc_enc_in[463] ^ ecc_enc_in[464] ^ ecc_enc_in[465] ^
                          ecc_enc_in[472] ^ ecc_enc_in[473] ^ ecc_enc_in[474] ^
                          ecc_enc_in[479] ^ ecc_enc_in[480] ^ ecc_enc_in[481] ^
                          ecc_enc_in[482] ^ ecc_enc_in[486] ^ ecc_enc_in[492] ^
                          ecc_enc_in[493] ^ ecc_enc_in[494] ^ ecc_enc_in[498] ^
                          ecc_enc_in[503] ^ ecc_enc_in[511] ^ ecc_enc_in[512] ^
                          ecc_enc_in[513] ^ ecc_enc_in[517]) ;
assign parity_enc[05] = ~( ecc_enc_in[011] ^ ecc_enc_in[012] ^ ecc_enc_in[013] ^
                          ecc_enc_in[014] ^ ecc_enc_in[015] ^ ecc_enc_in[016] ^
                          ecc_enc_in[017] ^ ecc_enc_in[018] ^ ecc_enc_in[019] ^
                          ecc_enc_in[020] ^ ecc_enc_in[021] ^ ecc_enc_in[022] ^
                          ecc_enc_in[023] ^ ecc_enc_in[038] ^ ecc_enc_in[039] ^
                          ecc_enc_in[040] ^ ecc_enc_in[041] ^ ecc_enc_in[042] ^
                          ecc_enc_in[043] ^ ecc_enc_in[044] ^ ecc_enc_in[045] ^
                          ecc_enc_in[046] ^ ecc_enc_in[047] ^ ecc_enc_in[048] ^
                          ecc_enc_in[049] ^ ecc_enc_in[050] ^ ecc_enc_in[064] ^
                          ecc_enc_in[065] ^ ecc_enc_in[066] ^ ecc_enc_in[067] ^
                          ecc_enc_in[068] ^ ecc_enc_in[069] ^ ecc_enc_in[070] ^
                          ecc_enc_in[071] ^ ecc_enc_in[072] ^ ecc_enc_in[073] ^
                          ecc_enc_in[074] ^ ecc_enc_in[075] ^ ecc_enc_in[076] ^
                          ecc_enc_in[077] ^ ecc_enc_in[091] ^ ecc_enc_in[092] ^
                          ecc_enc_in[093] ^ ecc_enc_in[094] ^ ecc_enc_in[095] ^
                          ecc_enc_in[096] ^ ecc_enc_in[097] ^ ecc_enc_in[098] ^
                          ecc_enc_in[099] ^ ecc_enc_in[113] ^ ecc_enc_in[114] ^
                          ecc_enc_in[115] ^ ecc_enc_in[116] ^ ecc_enc_in[117] ^
                          ecc_enc_in[118] ^ ecc_enc_in[119] ^ ecc_enc_in[120] ^
                          ecc_enc_in[121] ^ ecc_enc_in[122] ^ ecc_enc_in[123] ^
                          ecc_enc_in[124] ^ ecc_enc_in[125] ^ ecc_enc_in[139] ^
                          ecc_enc_in[140] ^ ecc_enc_in[141] ^ ecc_enc_in[142] ^
                          ecc_enc_in[143] ^ ecc_enc_in[144] ^ ecc_enc_in[145] ^
                          ecc_enc_in[146] ^ ecc_enc_in[147] ^ ecc_enc_in[162] ^
                          ecc_enc_in[163] ^ ecc_enc_in[164] ^ ecc_enc_in[165] ^
                          ecc_enc_in[166] ^ ecc_enc_in[167] ^ ecc_enc_in[168] ^
                          ecc_enc_in[169] ^ ecc_enc_in[178] ^ ecc_enc_in[179] ^
                          ecc_enc_in[180] ^ ecc_enc_in[181] ^ ecc_enc_in[196] ^
                          ecc_enc_in[197] ^ ecc_enc_in[198] ^ ecc_enc_in[199] ^
                          ecc_enc_in[200] ^ ecc_enc_in[201] ^ ecc_enc_in[202] ^
                          ecc_enc_in[203] ^ ecc_enc_in[204] ^ ecc_enc_in[205] ^
                          ecc_enc_in[206] ^ ecc_enc_in[207] ^ ecc_enc_in[208] ^
                          ecc_enc_in[209] ^ ecc_enc_in[210] ^ ecc_enc_in[224] ^
                          ecc_enc_in[225] ^ ecc_enc_in[226] ^ ecc_enc_in[227] ^
                          ecc_enc_in[228] ^ ecc_enc_in[229] ^ ecc_enc_in[230] ^
                          ecc_enc_in[243] ^ ecc_enc_in[244] ^ ecc_enc_in[245] ^
                          ecc_enc_in[246] ^ ecc_enc_in[247] ^ ecc_enc_in[248] ^
                          ecc_enc_in[249] ^ ecc_enc_in[259] ^ ecc_enc_in[260] ^
                          ecc_enc_in[261] ^ ecc_enc_in[262] ^ ecc_enc_in[263] ^
                          ecc_enc_in[277] ^ ecc_enc_in[278] ^ ecc_enc_in[279] ^
                          ecc_enc_in[280] ^ ecc_enc_in[281] ^ ecc_enc_in[282] ^
                          ecc_enc_in[283] ^ ecc_enc_in[284] ^ ecc_enc_in[285] ^
                          ecc_enc_in[294] ^ ecc_enc_in[295] ^ ecc_enc_in[296] ^
                          ecc_enc_in[297] ^ ecc_enc_in[307] ^ ecc_enc_in[308] ^
                          ecc_enc_in[309] ^ ecc_enc_in[310] ^ ecc_enc_in[316] ^
                          ecc_enc_in[331] ^ ecc_enc_in[332] ^ ecc_enc_in[333] ^
                          ecc_enc_in[334] ^ ecc_enc_in[335] ^ ecc_enc_in[336] ^
                          ecc_enc_in[337] ^ ecc_enc_in[338] ^ ecc_enc_in[339] ^
                          ecc_enc_in[340] ^ ecc_enc_in[341] ^ ecc_enc_in[342] ^
                          ecc_enc_in[356] ^ ecc_enc_in[357] ^ ecc_enc_in[358] ^
                          ecc_enc_in[359] ^ ecc_enc_in[360] ^ ecc_enc_in[361] ^
                          ecc_enc_in[362] ^ ecc_enc_in[363] ^ ecc_enc_in[364] ^
                          ecc_enc_in[378] ^ ecc_enc_in[379] ^ ecc_enc_in[380] ^
                          ecc_enc_in[381] ^ ecc_enc_in[382] ^ ecc_enc_in[383] ^
                          ecc_enc_in[384] ^ ecc_enc_in[385] ^ ecc_enc_in[386] ^
                          ecc_enc_in[395] ^ ecc_enc_in[396] ^ ecc_enc_in[397] ^
                          ecc_enc_in[398] ^ ecc_enc_in[412] ^ ecc_enc_in[413] ^
                          ecc_enc_in[414] ^ ecc_enc_in[415] ^ ecc_enc_in[416] ^
                          ecc_enc_in[417] ^ ecc_enc_in[418] ^ ecc_enc_in[428] ^
                          ecc_enc_in[429] ^ ecc_enc_in[430] ^ ecc_enc_in[431] ^
                          ecc_enc_in[432] ^ ecc_enc_in[443] ^ ecc_enc_in[444] ^
                          ecc_enc_in[445] ^ ecc_enc_in[446] ^ ecc_enc_in[447] ^
                          ecc_enc_in[466] ^ ecc_enc_in[467] ^ ecc_enc_in[468] ^
                          ecc_enc_in[469] ^ ecc_enc_in[470] ^ ecc_enc_in[471] ^
                          ecc_enc_in[472] ^ ecc_enc_in[473] ^ ecc_enc_in[474] ^
                          ecc_enc_in[483] ^ ecc_enc_in[484] ^ ecc_enc_in[485] ^
                          ecc_enc_in[486] ^ ecc_enc_in[495] ^ ecc_enc_in[496] ^
                          ecc_enc_in[497] ^ ecc_enc_in[498] ^ ecc_enc_in[504] ^
                          ecc_enc_in[514] ^ ecc_enc_in[515] ^ ecc_enc_in[516] ^
                          ecc_enc_in[517] ^ ecc_enc_in[522] ^ ecc_enc_in[526]) ;
assign parity_enc[06] = ~( ecc_enc_in[024] ^ ecc_enc_in[025] ^ ecc_enc_in[026] ^
                          ecc_enc_in[027] ^ ecc_enc_in[028] ^ ecc_enc_in[029] ^
                          ecc_enc_in[030] ^ ecc_enc_in[031] ^ ecc_enc_in[032] ^
                          ecc_enc_in[033] ^ ecc_enc_in[034] ^ ecc_enc_in[035] ^
                          ecc_enc_in[036] ^ ecc_enc_in[037] ^ ecc_enc_in[038] ^
                          ecc_enc_in[039] ^ ecc_enc_in[040] ^ ecc_enc_in[041] ^
                          ecc_enc_in[042] ^ ecc_enc_in[043] ^ ecc_enc_in[044] ^
                          ecc_enc_in[045] ^ ecc_enc_in[046] ^ ecc_enc_in[047] ^
                          ecc_enc_in[048] ^ ecc_enc_in[049] ^ ecc_enc_in[050] ^
                          ecc_enc_in[078] ^ ecc_enc_in[079] ^ ecc_enc_in[080] ^
                          ecc_enc_in[081] ^ ecc_enc_in[082] ^ ecc_enc_in[083] ^
                          ecc_enc_in[084] ^ ecc_enc_in[085] ^ ecc_enc_in[086] ^
                          ecc_enc_in[087] ^ ecc_enc_in[088] ^ ecc_enc_in[089] ^
                          ecc_enc_in[090] ^ ecc_enc_in[091] ^ ecc_enc_in[092] ^
                          ecc_enc_in[093] ^ ecc_enc_in[094] ^ ecc_enc_in[095] ^
                          ecc_enc_in[096] ^ ecc_enc_in[097] ^ ecc_enc_in[098] ^
                          ecc_enc_in[099] ^ ecc_enc_in[126] ^ ecc_enc_in[127] ^
                          ecc_enc_in[128] ^ ecc_enc_in[129] ^ ecc_enc_in[130] ^
                          ecc_enc_in[131] ^ ecc_enc_in[132] ^ ecc_enc_in[133] ^
                          ecc_enc_in[134] ^ ecc_enc_in[135] ^ ecc_enc_in[136] ^
                          ecc_enc_in[137] ^ ecc_enc_in[138] ^ ecc_enc_in[139] ^
                          ecc_enc_in[140] ^ ecc_enc_in[141] ^ ecc_enc_in[142] ^
                          ecc_enc_in[143] ^ ecc_enc_in[144] ^ ecc_enc_in[145] ^
                          ecc_enc_in[146] ^ ecc_enc_in[147] ^ ecc_enc_in[170] ^
                          ecc_enc_in[171] ^ ecc_enc_in[172] ^ ecc_enc_in[173] ^
                          ecc_enc_in[174] ^ ecc_enc_in[175] ^ ecc_enc_in[176] ^
                          ecc_enc_in[177] ^ ecc_enc_in[178] ^ ecc_enc_in[179] ^
                          ecc_enc_in[180] ^ ecc_enc_in[181] ^ ecc_enc_in[211] ^
                          ecc_enc_in[212] ^ ecc_enc_in[213] ^ ecc_enc_in[214] ^
                          ecc_enc_in[215] ^ ecc_enc_in[216] ^ ecc_enc_in[217] ^
                          ecc_enc_in[218] ^ ecc_enc_in[219] ^ ecc_enc_in[220] ^
                          ecc_enc_in[221] ^ ecc_enc_in[222] ^ ecc_enc_in[223] ^
                          ecc_enc_in[224] ^ ecc_enc_in[225] ^ ecc_enc_in[226] ^
                          ecc_enc_in[227] ^ ecc_enc_in[228] ^ ecc_enc_in[229] ^
                          ecc_enc_in[230] ^ ecc_enc_in[250] ^ ecc_enc_in[251] ^
                          ecc_enc_in[252] ^ ecc_enc_in[253] ^ ecc_enc_in[254] ^
                          ecc_enc_in[255] ^ ecc_enc_in[256] ^ ecc_enc_in[257] ^
                          ecc_enc_in[258] ^ ecc_enc_in[259] ^ ecc_enc_in[260] ^
                          ecc_enc_in[261] ^ ecc_enc_in[262] ^ ecc_enc_in[263] ^
                          ecc_enc_in[286] ^ ecc_enc_in[287] ^ ecc_enc_in[288] ^
                          ecc_enc_in[289] ^ ecc_enc_in[290] ^ ecc_enc_in[291] ^
                          ecc_enc_in[292] ^ ecc_enc_in[293] ^ ecc_enc_in[294] ^
                          ecc_enc_in[295] ^ ecc_enc_in[296] ^ ecc_enc_in[297] ^
                          ecc_enc_in[311] ^ ecc_enc_in[312] ^ ecc_enc_in[313] ^
                          ecc_enc_in[314] ^ ecc_enc_in[315] ^ ecc_enc_in[316] ^
                          ecc_enc_in[343] ^ ecc_enc_in[344] ^ ecc_enc_in[345] ^
                          ecc_enc_in[346] ^ ecc_enc_in[347] ^ ecc_enc_in[348] ^
                          ecc_enc_in[349] ^ ecc_enc_in[350] ^ ecc_enc_in[351] ^
                          ecc_enc_in[352] ^ ecc_enc_in[353] ^ ecc_enc_in[354] ^
                          ecc_enc_in[355] ^ ecc_enc_in[356] ^ ecc_enc_in[357] ^
                          ecc_enc_in[358] ^ ecc_enc_in[359] ^ ecc_enc_in[360] ^
                          ecc_enc_in[361] ^ ecc_enc_in[362] ^ ecc_enc_in[363] ^
                          ecc_enc_in[364] ^ ecc_enc_in[387] ^ ecc_enc_in[388] ^
                          ecc_enc_in[389] ^ ecc_enc_in[390] ^ ecc_enc_in[391] ^
                          ecc_enc_in[392] ^ ecc_enc_in[393] ^ ecc_enc_in[394] ^
                          ecc_enc_in[395] ^ ecc_enc_in[396] ^ ecc_enc_in[397] ^
                          ecc_enc_in[398] ^ ecc_enc_in[419] ^ ecc_enc_in[420] ^
                          ecc_enc_in[421] ^ ecc_enc_in[422] ^ ecc_enc_in[423] ^
                          ecc_enc_in[424] ^ ecc_enc_in[425] ^ ecc_enc_in[426] ^
                          ecc_enc_in[427] ^ ecc_enc_in[428] ^ ecc_enc_in[429] ^
                          ecc_enc_in[430] ^ ecc_enc_in[431] ^ ecc_enc_in[432] ^
                          ecc_enc_in[448] ^ ecc_enc_in[449] ^ ecc_enc_in[450] ^
                          ecc_enc_in[451] ^ ecc_enc_in[475] ^ ecc_enc_in[476] ^
                          ecc_enc_in[477] ^ ecc_enc_in[478] ^ ecc_enc_in[479] ^
                          ecc_enc_in[480] ^ ecc_enc_in[481] ^ ecc_enc_in[482] ^
                          ecc_enc_in[483] ^ ecc_enc_in[484] ^ ecc_enc_in[485] ^
                          ecc_enc_in[486] ^ ecc_enc_in[499] ^ ecc_enc_in[500] ^
                          ecc_enc_in[501] ^ ecc_enc_in[502] ^ ecc_enc_in[503] ^
                          ecc_enc_in[504] ^ ecc_enc_in[518] ^ ecc_enc_in[519] ^
                          ecc_enc_in[520] ^ ecc_enc_in[521] ^ ecc_enc_in[522]) ;
assign parity_enc[07] = ~( ecc_enc_in[051] ^ ecc_enc_in[052] ^ ecc_enc_in[053] ^
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
                          ecc_enc_in[099] ^ ecc_enc_in[148] ^ ecc_enc_in[149] ^
                          ecc_enc_in[150] ^ ecc_enc_in[151] ^ ecc_enc_in[152] ^
                          ecc_enc_in[153] ^ ecc_enc_in[154] ^ ecc_enc_in[155] ^
                          ecc_enc_in[156] ^ ecc_enc_in[157] ^ ecc_enc_in[158] ^
                          ecc_enc_in[159] ^ ecc_enc_in[160] ^ ecc_enc_in[161] ^
                          ecc_enc_in[162] ^ ecc_enc_in[163] ^ ecc_enc_in[164] ^
                          ecc_enc_in[165] ^ ecc_enc_in[166] ^ ecc_enc_in[167] ^
                          ecc_enc_in[168] ^ ecc_enc_in[169] ^ ecc_enc_in[170] ^
                          ecc_enc_in[171] ^ ecc_enc_in[172] ^ ecc_enc_in[173] ^
                          ecc_enc_in[174] ^ ecc_enc_in[175] ^ ecc_enc_in[176] ^
                          ecc_enc_in[177] ^ ecc_enc_in[178] ^ ecc_enc_in[179] ^
                          ecc_enc_in[180] ^ ecc_enc_in[181] ^ ecc_enc_in[231] ^
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
                          ecc_enc_in[262] ^ ecc_enc_in[263] ^ ecc_enc_in[298] ^
                          ecc_enc_in[299] ^ ecc_enc_in[300] ^ ecc_enc_in[301] ^
                          ecc_enc_in[302] ^ ecc_enc_in[303] ^ ecc_enc_in[304] ^
                          ecc_enc_in[305] ^ ecc_enc_in[306] ^ ecc_enc_in[307] ^
                          ecc_enc_in[308] ^ ecc_enc_in[309] ^ ecc_enc_in[310] ^
                          ecc_enc_in[311] ^ ecc_enc_in[312] ^ ecc_enc_in[313] ^
                          ecc_enc_in[314] ^ ecc_enc_in[315] ^ ecc_enc_in[316] ^
                          ecc_enc_in[365] ^ ecc_enc_in[366] ^ ecc_enc_in[367] ^
                          ecc_enc_in[368] ^ ecc_enc_in[369] ^ ecc_enc_in[370] ^
                          ecc_enc_in[371] ^ ecc_enc_in[372] ^ ecc_enc_in[373] ^
                          ecc_enc_in[374] ^ ecc_enc_in[375] ^ ecc_enc_in[376] ^
                          ecc_enc_in[377] ^ ecc_enc_in[378] ^ ecc_enc_in[379] ^
                          ecc_enc_in[380] ^ ecc_enc_in[381] ^ ecc_enc_in[382] ^
                          ecc_enc_in[383] ^ ecc_enc_in[384] ^ ecc_enc_in[385] ^
                          ecc_enc_in[386] ^ ecc_enc_in[387] ^ ecc_enc_in[388] ^
                          ecc_enc_in[389] ^ ecc_enc_in[390] ^ ecc_enc_in[391] ^
                          ecc_enc_in[392] ^ ecc_enc_in[393] ^ ecc_enc_in[394] ^
                          ecc_enc_in[395] ^ ecc_enc_in[396] ^ ecc_enc_in[397] ^
                          ecc_enc_in[398] ^ ecc_enc_in[433] ^ ecc_enc_in[434] ^
                          ecc_enc_in[435] ^ ecc_enc_in[436] ^ ecc_enc_in[437] ^
                          ecc_enc_in[438] ^ ecc_enc_in[439] ^ ecc_enc_in[440] ^
                          ecc_enc_in[441] ^ ecc_enc_in[442] ^ ecc_enc_in[443] ^
                          ecc_enc_in[444] ^ ecc_enc_in[445] ^ ecc_enc_in[446] ^
                          ecc_enc_in[447] ^ ecc_enc_in[448] ^ ecc_enc_in[449] ^
                          ecc_enc_in[450] ^ ecc_enc_in[451] ^ ecc_enc_in[487] ^
                          ecc_enc_in[488] ^ ecc_enc_in[489] ^ ecc_enc_in[490] ^
                          ecc_enc_in[491] ^ ecc_enc_in[492] ^ ecc_enc_in[493] ^
                          ecc_enc_in[494] ^ ecc_enc_in[495] ^ ecc_enc_in[496] ^
                          ecc_enc_in[497] ^ ecc_enc_in[498] ^ ecc_enc_in[499] ^
                          ecc_enc_in[500] ^ ecc_enc_in[501] ^ ecc_enc_in[502] ^
                          ecc_enc_in[503] ^ ecc_enc_in[504] ^ ecc_enc_in[523] ^
                          ecc_enc_in[524] ^ ecc_enc_in[525] ^ ecc_enc_in[526]) ;
assign parity_enc[08] = ~( ecc_enc_in[100] ^ ecc_enc_in[101] ^ ecc_enc_in[102] ^
                          ecc_enc_in[103] ^ ecc_enc_in[104] ^ ecc_enc_in[105] ^
                          ecc_enc_in[106] ^ ecc_enc_in[107] ^ ecc_enc_in[108] ^
                          ecc_enc_in[109] ^ ecc_enc_in[110] ^ ecc_enc_in[111] ^
                          ecc_enc_in[112] ^ ecc_enc_in[113] ^ ecc_enc_in[114] ^
                          ecc_enc_in[115] ^ ecc_enc_in[116] ^ ecc_enc_in[117] ^
                          ecc_enc_in[118] ^ ecc_enc_in[119] ^ ecc_enc_in[120] ^
                          ecc_enc_in[121] ^ ecc_enc_in[122] ^ ecc_enc_in[123] ^
                          ecc_enc_in[124] ^ ecc_enc_in[125] ^ ecc_enc_in[126] ^
                          ecc_enc_in[127] ^ ecc_enc_in[128] ^ ecc_enc_in[129] ^
                          ecc_enc_in[130] ^ ecc_enc_in[131] ^ ecc_enc_in[132] ^
                          ecc_enc_in[133] ^ ecc_enc_in[134] ^ ecc_enc_in[135] ^
                          ecc_enc_in[136] ^ ecc_enc_in[137] ^ ecc_enc_in[138] ^
                          ecc_enc_in[139] ^ ecc_enc_in[140] ^ ecc_enc_in[141] ^
                          ecc_enc_in[142] ^ ecc_enc_in[143] ^ ecc_enc_in[144] ^
                          ecc_enc_in[145] ^ ecc_enc_in[146] ^ ecc_enc_in[147] ^
                          ecc_enc_in[148] ^ ecc_enc_in[149] ^ ecc_enc_in[150] ^
                          ecc_enc_in[151] ^ ecc_enc_in[152] ^ ecc_enc_in[153] ^
                          ecc_enc_in[154] ^ ecc_enc_in[155] ^ ecc_enc_in[156] ^
                          ecc_enc_in[157] ^ ecc_enc_in[158] ^ ecc_enc_in[159] ^
                          ecc_enc_in[160] ^ ecc_enc_in[161] ^ ecc_enc_in[162] ^
                          ecc_enc_in[163] ^ ecc_enc_in[164] ^ ecc_enc_in[165] ^
                          ecc_enc_in[166] ^ ecc_enc_in[167] ^ ecc_enc_in[168] ^
                          ecc_enc_in[169] ^ ecc_enc_in[170] ^ ecc_enc_in[171] ^
                          ecc_enc_in[172] ^ ecc_enc_in[173] ^ ecc_enc_in[174] ^
                          ecc_enc_in[175] ^ ecc_enc_in[176] ^ ecc_enc_in[177] ^
                          ecc_enc_in[178] ^ ecc_enc_in[179] ^ ecc_enc_in[180] ^
                          ecc_enc_in[181] ^ ecc_enc_in[264] ^ ecc_enc_in[265] ^
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
                          ecc_enc_in[308] ^ ecc_enc_in[309] ^ ecc_enc_in[310] ^
                          ecc_enc_in[311] ^ ecc_enc_in[312] ^ ecc_enc_in[313] ^
                          ecc_enc_in[314] ^ ecc_enc_in[315] ^ ecc_enc_in[316] ^
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
                          ecc_enc_in[450] ^ ecc_enc_in[451] ^ ecc_enc_in[505] ^
                          ecc_enc_in[506] ^ ecc_enc_in[507] ^ ecc_enc_in[508] ^
                          ecc_enc_in[509] ^ ecc_enc_in[510] ^ ecc_enc_in[511] ^
                          ecc_enc_in[512] ^ ecc_enc_in[513] ^ ecc_enc_in[514] ^
                          ecc_enc_in[515] ^ ecc_enc_in[516] ^ ecc_enc_in[517] ^
                          ecc_enc_in[518] ^ ecc_enc_in[519] ^ ecc_enc_in[520] ^
                          ecc_enc_in[521] ^ ecc_enc_in[522] ^ ecc_enc_in[523] ^
                          ecc_enc_in[524] ^ ecc_enc_in[525] ^ ecc_enc_in[526]) ;
assign parity_enc[09] = ~( ecc_enc_in[182] ^ ecc_enc_in[183] ^ ecc_enc_in[184] ^
                          ecc_enc_in[185] ^ ecc_enc_in[186] ^ ecc_enc_in[187] ^
                          ecc_enc_in[188] ^ ecc_enc_in[189] ^ ecc_enc_in[190] ^
                          ecc_enc_in[191] ^ ecc_enc_in[192] ^ ecc_enc_in[193] ^
                          ecc_enc_in[194] ^ ecc_enc_in[195] ^ ecc_enc_in[196] ^
                          ecc_enc_in[197] ^ ecc_enc_in[198] ^ ecc_enc_in[199] ^
                          ecc_enc_in[200] ^ ecc_enc_in[201] ^ ecc_enc_in[202] ^
                          ecc_enc_in[203] ^ ecc_enc_in[204] ^ ecc_enc_in[205] ^
                          ecc_enc_in[206] ^ ecc_enc_in[207] ^ ecc_enc_in[208] ^
                          ecc_enc_in[209] ^ ecc_enc_in[210] ^ ecc_enc_in[211] ^
                          ecc_enc_in[212] ^ ecc_enc_in[213] ^ ecc_enc_in[214] ^
                          ecc_enc_in[215] ^ ecc_enc_in[216] ^ ecc_enc_in[217] ^
                          ecc_enc_in[218] ^ ecc_enc_in[219] ^ ecc_enc_in[220] ^
                          ecc_enc_in[221] ^ ecc_enc_in[222] ^ ecc_enc_in[223] ^
                          ecc_enc_in[224] ^ ecc_enc_in[225] ^ ecc_enc_in[226] ^
                          ecc_enc_in[227] ^ ecc_enc_in[228] ^ ecc_enc_in[229] ^
                          ecc_enc_in[230] ^ ecc_enc_in[231] ^ ecc_enc_in[232] ^
                          ecc_enc_in[233] ^ ecc_enc_in[234] ^ ecc_enc_in[235] ^
                          ecc_enc_in[236] ^ ecc_enc_in[237] ^ ecc_enc_in[238] ^
                          ecc_enc_in[239] ^ ecc_enc_in[240] ^ ecc_enc_in[241] ^
                          ecc_enc_in[242] ^ ecc_enc_in[243] ^ ecc_enc_in[244] ^
                          ecc_enc_in[245] ^ ecc_enc_in[246] ^ ecc_enc_in[247] ^
                          ecc_enc_in[248] ^ ecc_enc_in[249] ^ ecc_enc_in[250] ^
                          ecc_enc_in[251] ^ ecc_enc_in[252] ^ ecc_enc_in[253] ^
                          ecc_enc_in[254] ^ ecc_enc_in[255] ^ ecc_enc_in[256] ^
                          ecc_enc_in[257] ^ ecc_enc_in[258] ^ ecc_enc_in[259] ^
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
                          ecc_enc_in[308] ^ ecc_enc_in[309] ^ ecc_enc_in[310] ^
                          ecc_enc_in[311] ^ ecc_enc_in[312] ^ ecc_enc_in[313] ^
                          ecc_enc_in[314] ^ ecc_enc_in[315] ^ ecc_enc_in[316] ^
                          ecc_enc_in[452] ^ ecc_enc_in[453] ^ ecc_enc_in[454] ^
                          ecc_enc_in[455] ^ ecc_enc_in[456] ^ ecc_enc_in[457] ^
                          ecc_enc_in[458] ^ ecc_enc_in[459] ^ ecc_enc_in[460] ^
                          ecc_enc_in[461] ^ ecc_enc_in[462] ^ ecc_enc_in[463] ^
                          ecc_enc_in[464] ^ ecc_enc_in[465] ^ ecc_enc_in[466] ^
                          ecc_enc_in[467] ^ ecc_enc_in[468] ^ ecc_enc_in[469] ^
                          ecc_enc_in[470] ^ ecc_enc_in[471] ^ ecc_enc_in[472] ^
                          ecc_enc_in[473] ^ ecc_enc_in[474] ^ ecc_enc_in[475] ^
                          ecc_enc_in[476] ^ ecc_enc_in[477] ^ ecc_enc_in[478] ^
                          ecc_enc_in[479] ^ ecc_enc_in[480] ^ ecc_enc_in[481] ^
                          ecc_enc_in[482] ^ ecc_enc_in[483] ^ ecc_enc_in[484] ^
                          ecc_enc_in[485] ^ ecc_enc_in[486] ^ ecc_enc_in[487] ^
                          ecc_enc_in[488] ^ ecc_enc_in[489] ^ ecc_enc_in[490] ^
                          ecc_enc_in[491] ^ ecc_enc_in[492] ^ ecc_enc_in[493] ^
                          ecc_enc_in[494] ^ ecc_enc_in[495] ^ ecc_enc_in[496] ^
                          ecc_enc_in[497] ^ ecc_enc_in[498] ^ ecc_enc_in[499] ^
                          ecc_enc_in[500] ^ ecc_enc_in[501] ^ ecc_enc_in[502] ^
                          ecc_enc_in[503] ^ ecc_enc_in[504] ^ ecc_enc_in[505] ^
                          ecc_enc_in[506] ^ ecc_enc_in[507] ^ ecc_enc_in[508] ^
                          ecc_enc_in[509] ^ ecc_enc_in[510] ^ ecc_enc_in[511] ^
                          ecc_enc_in[512] ^ ecc_enc_in[513] ^ ecc_enc_in[514] ^
                          ecc_enc_in[515] ^ ecc_enc_in[516] ^ ecc_enc_in[517] ^
                          ecc_enc_in[518] ^ ecc_enc_in[519] ^ ecc_enc_in[520] ^
                          ecc_enc_in[521] ^ ecc_enc_in[522] ^ ecc_enc_in[523] ^
                          ecc_enc_in[524] ^ ecc_enc_in[525] ^ ecc_enc_in[526]) ;
assign parity_enc[10] = ~( ecc_enc_in[317] ^ ecc_enc_in[318] ^ ecc_enc_in[319] ^
                          ecc_enc_in[320] ^ ecc_enc_in[321] ^ ecc_enc_in[322] ^
                          ecc_enc_in[323] ^ ecc_enc_in[324] ^ ecc_enc_in[325] ^
                          ecc_enc_in[326] ^ ecc_enc_in[327] ^ ecc_enc_in[328] ^
                          ecc_enc_in[329] ^ ecc_enc_in[330] ^ ecc_enc_in[331] ^
                          ecc_enc_in[332] ^ ecc_enc_in[333] ^ ecc_enc_in[334] ^
                          ecc_enc_in[335] ^ ecc_enc_in[336] ^ ecc_enc_in[337] ^
                          ecc_enc_in[338] ^ ecc_enc_in[339] ^ ecc_enc_in[340] ^
                          ecc_enc_in[341] ^ ecc_enc_in[342] ^ ecc_enc_in[343] ^
                          ecc_enc_in[344] ^ ecc_enc_in[345] ^ ecc_enc_in[346] ^
                          ecc_enc_in[347] ^ ecc_enc_in[348] ^ ecc_enc_in[349] ^
                          ecc_enc_in[350] ^ ecc_enc_in[351] ^ ecc_enc_in[352] ^
                          ecc_enc_in[353] ^ ecc_enc_in[354] ^ ecc_enc_in[355] ^
                          ecc_enc_in[356] ^ ecc_enc_in[357] ^ ecc_enc_in[358] ^
                          ecc_enc_in[359] ^ ecc_enc_in[360] ^ ecc_enc_in[361] ^
                          ecc_enc_in[362] ^ ecc_enc_in[363] ^ ecc_enc_in[364] ^
                          ecc_enc_in[365] ^ ecc_enc_in[366] ^ ecc_enc_in[367] ^
                          ecc_enc_in[368] ^ ecc_enc_in[369] ^ ecc_enc_in[370] ^
                          ecc_enc_in[371] ^ ecc_enc_in[372] ^ ecc_enc_in[373] ^
                          ecc_enc_in[374] ^ ecc_enc_in[375] ^ ecc_enc_in[376] ^
                          ecc_enc_in[377] ^ ecc_enc_in[378] ^ ecc_enc_in[379] ^
                          ecc_enc_in[380] ^ ecc_enc_in[381] ^ ecc_enc_in[382] ^
                          ecc_enc_in[383] ^ ecc_enc_in[384] ^ ecc_enc_in[385] ^
                          ecc_enc_in[386] ^ ecc_enc_in[387] ^ ecc_enc_in[388] ^
                          ecc_enc_in[389] ^ ecc_enc_in[390] ^ ecc_enc_in[391] ^
                          ecc_enc_in[392] ^ ecc_enc_in[393] ^ ecc_enc_in[394] ^
                          ecc_enc_in[395] ^ ecc_enc_in[396] ^ ecc_enc_in[397] ^
                          ecc_enc_in[398] ^ ecc_enc_in[399] ^ ecc_enc_in[400] ^
                          ecc_enc_in[401] ^ ecc_enc_in[402] ^ ecc_enc_in[403] ^
                          ecc_enc_in[404] ^ ecc_enc_in[405] ^ ecc_enc_in[406] ^
                          ecc_enc_in[407] ^ ecc_enc_in[408] ^ ecc_enc_in[409] ^
                          ecc_enc_in[410] ^ ecc_enc_in[411] ^ ecc_enc_in[412] ^
                          ecc_enc_in[413] ^ ecc_enc_in[414] ^ ecc_enc_in[415] ^
                          ecc_enc_in[416] ^ ecc_enc_in[417] ^ ecc_enc_in[418] ^
                          ecc_enc_in[419] ^ ecc_enc_in[420] ^ ecc_enc_in[421] ^
                          ecc_enc_in[422] ^ ecc_enc_in[423] ^ ecc_enc_in[424] ^
                          ecc_enc_in[425] ^ ecc_enc_in[426] ^ ecc_enc_in[427] ^
                          ecc_enc_in[428] ^ ecc_enc_in[429] ^ ecc_enc_in[430] ^
                          ecc_enc_in[431] ^ ecc_enc_in[432] ^ ecc_enc_in[433] ^
                          ecc_enc_in[434] ^ ecc_enc_in[435] ^ ecc_enc_in[436] ^
                          ecc_enc_in[437] ^ ecc_enc_in[438] ^ ecc_enc_in[439] ^
                          ecc_enc_in[440] ^ ecc_enc_in[441] ^ ecc_enc_in[442] ^
                          ecc_enc_in[443] ^ ecc_enc_in[444] ^ ecc_enc_in[445] ^
                          ecc_enc_in[446] ^ ecc_enc_in[447] ^ ecc_enc_in[448] ^
                          ecc_enc_in[449] ^ ecc_enc_in[450] ^ ecc_enc_in[451] ^
                          ecc_enc_in[452] ^ ecc_enc_in[453] ^ ecc_enc_in[454] ^
                          ecc_enc_in[455] ^ ecc_enc_in[456] ^ ecc_enc_in[457] ^
                          ecc_enc_in[458] ^ ecc_enc_in[459] ^ ecc_enc_in[460] ^
                          ecc_enc_in[461] ^ ecc_enc_in[462] ^ ecc_enc_in[463] ^
                          ecc_enc_in[464] ^ ecc_enc_in[465] ^ ecc_enc_in[466] ^
                          ecc_enc_in[467] ^ ecc_enc_in[468] ^ ecc_enc_in[469] ^
                          ecc_enc_in[470] ^ ecc_enc_in[471] ^ ecc_enc_in[472] ^
                          ecc_enc_in[473] ^ ecc_enc_in[474] ^ ecc_enc_in[475] ^
                          ecc_enc_in[476] ^ ecc_enc_in[477] ^ ecc_enc_in[478] ^
                          ecc_enc_in[479] ^ ecc_enc_in[480] ^ ecc_enc_in[481] ^
                          ecc_enc_in[482] ^ ecc_enc_in[483] ^ ecc_enc_in[484] ^
                          ecc_enc_in[485] ^ ecc_enc_in[486] ^ ecc_enc_in[487] ^
                          ecc_enc_in[488] ^ ecc_enc_in[489] ^ ecc_enc_in[490] ^
                          ecc_enc_in[491] ^ ecc_enc_in[492] ^ ecc_enc_in[493] ^
                          ecc_enc_in[494] ^ ecc_enc_in[495] ^ ecc_enc_in[496] ^
                          ecc_enc_in[497] ^ ecc_enc_in[498] ^ ecc_enc_in[499] ^
                          ecc_enc_in[500] ^ ecc_enc_in[501] ^ ecc_enc_in[502] ^
                          ecc_enc_in[503] ^ ecc_enc_in[504] ^ ecc_enc_in[505] ^
                          ecc_enc_in[506] ^ ecc_enc_in[507] ^ ecc_enc_in[508] ^
                          ecc_enc_in[509] ^ ecc_enc_in[510] ^ ecc_enc_in[511] ^
                          ecc_enc_in[512] ^ ecc_enc_in[513] ^ ecc_enc_in[514] ^
                          ecc_enc_in[515] ^ ecc_enc_in[516] ^ ecc_enc_in[517] ^
                          ecc_enc_in[518] ^ ecc_enc_in[519] ^ ecc_enc_in[520] ^
                          ecc_enc_in[521] ^ ecc_enc_in[522] ^ ecc_enc_in[523] ^
                          ecc_enc_in[524] ^ ecc_enc_in[525] ^ ecc_enc_in[526]) ;
assign ecc_encoder_parity_out = ecc_encoder_bypass ? ecc_encoder_parity_in : parity_enc;
assign ecc_encoder_data_out	= {ecc_encoder_parity_out, ecc_enc_in};




//synopsys translate_off
parameter numOfCodewordBit = 538;
parameter numOfDataBit = 527;
parameter numOfParityBits = 11;
reg [(numOfParityBits-1):0] G [0:(numOfDataBit-1)] ;


task GenerateGMatrix;
begin

    G[526] = 1952; G[525] = 1928; G[524] = 1924; G[523] = 1921; G[522] = 1888;  G[521] = 1864;  G[520] = 1860;  G[519] = 1858;
    G[518] = 1857; G[517] = 1840; G[516] = 1832; G[515] = 1828; G[514] = 1826;  G[513] = 1816;  G[512] = 1810;  G[511] = 1809;
    G[510] = 1804; G[509] = 1802; G[508] = 1798; G[507] = 1797; G[506] = 1795;  G[505] = 1792;  G[504] = 1760;  G[503] = 1744;
    G[502] = 1736; G[501] = 1732; G[500] = 1730; G[499] = 1729; G[498] = 1712;  G[497] = 1704;  G[496] = 1700;  G[495] = 1698;
    G[494] = 1684; G[493] = 1682; G[492] = 1681; G[491] = 1676; G[490] = 1673;  G[489] = 1670;  G[488] = 1669;  G[487] = 1664;
    G[486] = 1648; G[485] = 1640; G[484] = 1634; G[483] = 1633; G[482] = 1624;  G[481] = 1620;  G[480] = 1618;  G[479] = 1617;
    G[478] = 1610; G[477] = 1609; G[476] = 1605; G[475] = 1600; G[474] = 1592;  G[473] = 1586;  G[472] = 1585;  G[471] = 1580;
    G[470] = 1578; G[469] = 1574; G[468] = 1573; G[467] = 1571; G[466] = 1568;  G[465] = 1564;  G[464] = 1562;  G[463] = 1561;
    G[462] = 1558; G[461] = 1557; G[460] = 1552; G[459] = 1550; G[458] = 1549;  G[457] = 1547;  G[456] = 1544;  G[455] = 1543;
    G[454] = 1540; G[453] = 1538; G[452] = 1537; G[451] = 1488; G[450] = 1480;  G[449] = 1474;  G[448] = 1473;  G[447] = 1456;
    G[446] = 1448; G[445] = 1444; G[444] = 1442; G[443] = 1441; G[442] = 1432;  G[441] = 1428;  G[440] = 1426;  G[439] = 1425;
    G[438] = 1420; G[437] = 1418; G[436] = 1417; G[435] = 1414; G[434] = 1411;  G[433] = 1408;  G[432] = 1392;  G[431] = 1384;
    G[430] = 1380; G[429] = 1378; G[428] = 1377; G[427] = 1364; G[426] = 1362;  G[425] = 1361;  G[424] = 1356;  G[423] = 1354;
    G[422] = 1353; G[421] = 1350; G[420] = 1347; G[419] = 1344; G[418] = 1332;  G[417] = 1329;  G[416] = 1324;  G[415] = 1321;
    G[414] = 1317; G[413] = 1315; G[412] = 1312; G[411] = 1308; G[410] = 1306;  G[409] = 1305;  G[408] = 1302;  G[407] = 1301;
    G[406] = 1299; G[405] = 1296; G[404] = 1291; G[403] = 1288; G[402] = 1287;  G[401] = 1284;  G[400] = 1282;  G[399] = 1281;
    G[398] = 1256; G[397] = 1252; G[396] = 1250; G[395] = 1249; G[394] = 1236;  G[393] = 1234;  G[392] = 1233;  G[391] = 1228;
    G[390] = 1222; G[389] = 1221; G[388] = 1219; G[387] = 1216; G[386] = 1208;  G[385] = 1204;  G[384] = 1202;  G[383] = 1201;
    G[382] = 1194; G[381] = 1193; G[380] = 1189; G[379] = 1187; G[378] = 1184;  G[377] = 1180;  G[376] = 1178;  G[375] = 1177;
    G[374] = 1174; G[373] = 1168; G[372] = 1166; G[371] = 1165; G[370] = 1163;  G[369] = 1160;  G[368] = 1159;  G[367] = 1156;
    G[366] = 1154; G[365] = 1153; G[364] = 1144; G[363] = 1140; G[362] = 1138;  G[361] = 1137;  G[360] = 1132;  G[359] = 1126;
    G[358] = 1125; G[357] = 1123; G[356] = 1120; G[355] = 1116; G[354] = 1114;  G[353] = 1113;  G[352] = 1109;  G[351] = 1104;
    G[350] = 1102; G[349] = 1101; G[348] = 1099; G[347] = 1096; G[346] = 1095;  G[345] = 1092;  G[344] = 1090;  G[343] = 1089;
    G[342] = 1082; G[341] = 1081; G[340] = 1078; G[339] = 1075; G[338] = 1072;  G[337] = 1070;  G[336] = 1069;  G[335] = 1067;
    G[334] = 1064; G[333] = 1060; G[332] = 1058; G[331] = 1057; G[330] = 1054;  G[329] = 1053;  G[328] = 1048;  G[327] = 1047;
    G[326] = 1044; G[325] = 1042; G[324] = 1041; G[323] = 1039; G[322] = 1036;  G[321] = 1034;  G[320] = 1033;  G[319] = 1030;
    G[318] = 1029; G[317] = 1027; G[316] = 992; G[315] = 976; G[314] = 968;  G[313] = 964;  G[312] = 962;  G[311] = 961;
    G[310] = 944; G[309] = 932; G[308] = 930; G[307] = 929; G[306] = 920;  G[305] = 914;  G[304] = 913;  G[303] = 908;
    G[302] = 906; G[301] = 902; G[300] = 901; G[299] = 899; G[298] = 896;  G[297] = 880;  G[296] = 868;  G[295] = 866;
    G[294] = 865; G[293] = 856; G[292] = 850; G[291] = 849; G[290] = 844;  G[289] = 842;  G[288] = 841;  G[287] = 835;
    G[286] = 832; G[285] = 824; G[284] = 820; G[283] = 817; G[282] = 812;  G[281] = 810;  G[280] = 809;  G[279] = 806;
    G[278] = 803; G[277] = 800; G[276] = 796; G[275] = 794; G[274] = 790;  G[273] = 789;  G[272] = 787;  G[271] = 784;
    G[270] = 782; G[269] = 781; G[268] = 779; G[267] = 776; G[266] = 772;  G[265] = 770;  G[264] = 769;  G[263] = 752;
    G[262] = 744; G[261] = 740; G[260] = 738; G[259] = 737; G[258] = 728;  G[257] = 724;  G[256] = 722;  G[255] = 721;
    G[254] = 716; G[253] = 710; G[252] = 709; G[251] = 707; G[250] = 704;  G[249] = 696;  G[248] = 690;  G[247] = 689;
    G[246] = 684; G[245] = 682; G[244] = 677; G[243] = 672; G[242] = 668;  G[241] = 665;  G[240] = 662;  G[239] = 661;
    G[238] = 656; G[237] = 653; G[236] = 651; G[235] = 648; G[234] = 647;  G[233] = 644;  G[232] = 642;  G[231] = 641;
    G[230] = 628; G[229] = 626; G[228] = 620; G[227] = 618; G[226] = 617;  G[225] = 613;  G[224] = 608;  G[223] = 602;
    G[222] = 601; G[221] = 598; G[220] = 597; G[219] = 592; G[218] = 590;  G[217] = 589;  G[216] = 587;  G[215] = 584;
    G[214] = 583; G[213] = 580; G[212] = 578; G[211] = 577; G[210] = 572;  G[209] = 570;  G[208] = 569;  G[207] = 566;
    G[206] = 565; G[205] = 563; G[204] = 560; G[203] = 558; G[202] = 557;  G[201] = 555;  G[200] = 552;  G[199] = 551;
    G[198] = 548; G[197] = 546; G[196] = 545; G[195] = 542; G[194] = 541;  G[193] = 539;  G[192] = 536;  G[191] = 535;
    G[190] = 532; G[189] = 530; G[188] = 529; G[187] = 524; G[186] = 522;  G[185] = 521;  G[184] = 518;  G[183] = 517;
    G[182] = 515; G[181] = 496; G[180] = 488; G[179] = 484; G[178] = 482;  G[177] = 468;  G[176] = 466;  G[175] = 460;
    G[174] = 458; G[173] = 457; G[172] = 454; G[171] = 451; G[170] = 448;  G[169] = 440;  G[168] = 436;  G[167] = 433;
    G[166] = 428; G[165] = 426; G[164] = 422; G[163] = 419; G[162] = 416;  G[161] = 412;  G[160] = 410;  G[159] = 409;
    G[158] = 406; G[157] = 405; G[156] = 403; G[155] = 400; G[154] = 397;  G[153] = 395;  G[152] = 392;  G[151] = 391;
    G[150] = 388; G[149] = 386; G[148] = 385; G[147] = 376; G[146] = 372;  G[145] = 370;  G[144] = 369;  G[143] = 361;
    G[142] = 358; G[141] = 357; G[140] = 355; G[139] = 352; G[138] = 348;  G[137] = 346;  G[136] = 345;  G[135] = 341;
    G[134] = 339; G[133] = 336; G[132] = 334; G[131] = 333; G[130] = 331;  G[129] = 328;  G[128] = 324;  G[127] = 322;
    G[126] = 321; G[125] = 316; G[124] = 314; G[123] = 313; G[122] = 310;  G[121] = 309;  G[120] = 304;  G[119] = 301;
    G[118] = 299; G[117] = 296; G[116] = 295; G[115] = 292; G[114] = 290;  G[113] = 289;  G[112] = 286;  G[111] = 283;
    G[110] = 280; G[109] = 276; G[108] = 274; G[107] = 273; G[106] = 271;  G[105] = 268;  G[104] = 266;  G[103] = 265;
    G[102] = 262; G[101] = 261; G[100] = 259; G[99] = 248; G[98] = 241;  G[97] = 236;  G[96] = 234;  G[95] = 233;
    G[94] = 230; G[93] = 229; G[92] = 227; G[91] = 224; G[90] = 220;  G[89] = 218;  G[88] = 214;  G[87] = 213;
    G[86] = 211; G[85] = 208; G[84] = 206; G[83] = 205; G[82] = 200;  G[81] = 199;  G[80] = 196;  G[79] = 194;
    G[78] = 193; G[77] = 186; G[76] = 185; G[75] = 182; G[74] = 181;  G[73] = 179;  G[72] = 176;  G[71] = 174;
    G[70] = 173; G[69] = 171; G[68] = 168; G[67] = 167; G[66] = 164;  G[65] = 162;  G[64] = 161;  G[63] = 157;
    G[62] = 152; G[61] = 151; G[60] = 148; G[59] = 146; G[58] = 145;  G[57] = 143;  G[56] = 140;  G[55] = 138;
    G[54] = 137; G[53] = 134; G[52] = 133; G[51] = 131; G[50] = 124;  G[49] = 122;  G[48] = 118;  G[47] = 115;
    G[46] = 112; G[45] = 110; G[44] = 109; G[43] = 107; G[42] = 104;  G[41] = 103;  G[40] = 100;  G[39] = 98;
    G[38] = 97; G[37] = 93; G[36] = 91; G[35] = 88; G[34] = 87;  G[33] = 84;  G[32] = 82;  G[31] = 81;
    G[30] = 79; G[29] = 76; G[28] = 74; G[27] = 73; G[26] = 70;  G[25] = 69;  G[24] = 67;  G[23] = 61;
    G[22] = 59; G[21] = 56; G[20] = 55; G[19] = 52; G[18] = 50;  G[17] = 49;  G[16] = 44;  G[15] = 42;
    G[14] = 41; G[13] = 38; G[12] = 37; G[11] = 35; G[10] = 31;  G[9] = 28;  G[8] = 26;  G[7] = 25;
    G[6] = 22;
    G[5] = 21;
    G[4] = 19;
    G[3] = 14;
    G[2] = 13;
    G[1] = 11;
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
