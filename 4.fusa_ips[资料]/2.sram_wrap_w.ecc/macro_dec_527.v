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
module macro_dec_527(
input  [537:0] ecc_decoder_data_in,
input ecc_decoder_bypass,

output reg [526:0] ecc_decoder_data_out,
output [10:0] ecc_decoder_parity_out,
output [10:0] syndrom
);



wire [537:0] ecc_dec_in;

reg  [526:0] corrected_bit_p;


//=========================================
//============== ECC Decoder ===============
//=========================================

//Hamming Code -- Parity Check Decoding
assign ecc_dec_in = ecc_decoder_data_in;
assign ecc_decoder_parity_out = ecc_decoder_data_in[537:527];
assign syndrom[00] = ~( ecc_dec_in[000] ^ ecc_dec_in[001] ^ ecc_dec_in[002] ^
                        ecc_dec_in[004] ^ ecc_dec_in[005] ^ ecc_dec_in[007] ^
                        ecc_dec_in[010] ^ ecc_dec_in[011] ^ ecc_dec_in[012] ^
                        ecc_dec_in[014] ^ ecc_dec_in[017] ^ ecc_dec_in[020] ^
                        ecc_dec_in[022] ^ ecc_dec_in[023] ^ ecc_dec_in[024] ^
                        ecc_dec_in[025] ^ ecc_dec_in[027] ^ ecc_dec_in[030] ^
                        ecc_dec_in[031] ^ ecc_dec_in[034] ^ ecc_dec_in[036] ^
                        ecc_dec_in[037] ^ ecc_dec_in[038] ^ ecc_dec_in[041] ^
                        ecc_dec_in[043] ^ ecc_dec_in[044] ^ ecc_dec_in[047] ^
                        ecc_dec_in[051] ^ ecc_dec_in[052] ^ ecc_dec_in[054] ^
                        ecc_dec_in[057] ^ ecc_dec_in[058] ^ ecc_dec_in[061] ^
                        ecc_dec_in[063] ^ ecc_dec_in[064] ^ ecc_dec_in[067] ^
                        ecc_dec_in[069] ^ ecc_dec_in[070] ^ ecc_dec_in[073] ^
                        ecc_dec_in[074] ^ ecc_dec_in[076] ^ ecc_dec_in[078] ^
                        ecc_dec_in[081] ^ ecc_dec_in[083] ^ ecc_dec_in[086] ^
                        ecc_dec_in[087] ^ ecc_dec_in[092] ^ ecc_dec_in[093] ^
                        ecc_dec_in[095] ^ ecc_dec_in[098] ^ ecc_dec_in[100] ^
                        ecc_dec_in[101] ^ ecc_dec_in[103] ^ ecc_dec_in[106] ^
                        ecc_dec_in[107] ^ ecc_dec_in[111] ^ ecc_dec_in[113] ^
                        ecc_dec_in[116] ^ ecc_dec_in[118] ^ ecc_dec_in[119] ^
                        ecc_dec_in[121] ^ ecc_dec_in[123] ^ ecc_dec_in[126] ^
                        ecc_dec_in[130] ^ ecc_dec_in[131] ^ ecc_dec_in[134] ^
                        ecc_dec_in[135] ^ ecc_dec_in[136] ^ ecc_dec_in[140] ^
                        ecc_dec_in[141] ^ ecc_dec_in[143] ^ ecc_dec_in[144] ^
                        ecc_dec_in[148] ^ ecc_dec_in[151] ^ ecc_dec_in[153] ^
                        ecc_dec_in[154] ^ ecc_dec_in[156] ^ ecc_dec_in[157] ^
                        ecc_dec_in[159] ^ ecc_dec_in[163] ^ ecc_dec_in[167] ^
                        ecc_dec_in[171] ^ ecc_dec_in[173] ^ ecc_dec_in[182] ^
                        ecc_dec_in[183] ^ ecc_dec_in[185] ^ ecc_dec_in[188] ^
                        ecc_dec_in[191] ^ ecc_dec_in[193] ^ ecc_dec_in[194] ^
                        ecc_dec_in[196] ^ ecc_dec_in[199] ^ ecc_dec_in[201] ^
                        ecc_dec_in[202] ^ ecc_dec_in[205] ^ ecc_dec_in[206] ^
                        ecc_dec_in[208] ^ ecc_dec_in[211] ^ ecc_dec_in[214] ^
                        ecc_dec_in[216] ^ ecc_dec_in[217] ^ ecc_dec_in[220] ^
                        ecc_dec_in[222] ^ ecc_dec_in[225] ^ ecc_dec_in[226] ^
                        ecc_dec_in[231] ^ ecc_dec_in[234] ^ ecc_dec_in[236] ^
                        ecc_dec_in[237] ^ ecc_dec_in[239] ^ ecc_dec_in[241] ^
                        ecc_dec_in[244] ^ ecc_dec_in[247] ^ ecc_dec_in[251] ^
                        ecc_dec_in[252] ^ ecc_dec_in[255] ^ ecc_dec_in[259] ^
                        ecc_dec_in[264] ^ ecc_dec_in[268] ^ ecc_dec_in[269] ^
                        ecc_dec_in[272] ^ ecc_dec_in[273] ^ ecc_dec_in[278] ^
                        ecc_dec_in[280] ^ ecc_dec_in[283] ^ ecc_dec_in[287] ^
                        ecc_dec_in[288] ^ ecc_dec_in[291] ^ ecc_dec_in[294] ^
                        ecc_dec_in[299] ^ ecc_dec_in[300] ^ ecc_dec_in[304] ^
                        ecc_dec_in[307] ^ ecc_dec_in[311] ^ ecc_dec_in[317] ^
                        ecc_dec_in[318] ^ ecc_dec_in[320] ^ ecc_dec_in[323] ^
                        ecc_dec_in[324] ^ ecc_dec_in[327] ^ ecc_dec_in[329] ^
                        ecc_dec_in[331] ^ ecc_dec_in[335] ^ ecc_dec_in[336] ^
                        ecc_dec_in[339] ^ ecc_dec_in[341] ^ ecc_dec_in[343] ^
                        ecc_dec_in[346] ^ ecc_dec_in[348] ^ ecc_dec_in[349] ^
                        ecc_dec_in[352] ^ ecc_dec_in[353] ^ ecc_dec_in[357] ^
                        ecc_dec_in[358] ^ ecc_dec_in[361] ^ ecc_dec_in[365] ^
                        ecc_dec_in[368] ^ ecc_dec_in[370] ^ ecc_dec_in[371] ^
                        ecc_dec_in[375] ^ ecc_dec_in[379] ^ ecc_dec_in[380] ^
                        ecc_dec_in[381] ^ ecc_dec_in[383] ^ ecc_dec_in[388] ^
                        ecc_dec_in[389] ^ ecc_dec_in[392] ^ ecc_dec_in[395] ^
                        ecc_dec_in[399] ^ ecc_dec_in[402] ^ ecc_dec_in[404] ^
                        ecc_dec_in[406] ^ ecc_dec_in[407] ^ ecc_dec_in[409] ^
                        ecc_dec_in[413] ^ ecc_dec_in[414] ^ ecc_dec_in[415] ^
                        ecc_dec_in[417] ^ ecc_dec_in[420] ^ ecc_dec_in[422] ^
                        ecc_dec_in[425] ^ ecc_dec_in[428] ^ ecc_dec_in[434] ^
                        ecc_dec_in[436] ^ ecc_dec_in[439] ^ ecc_dec_in[443] ^
                        ecc_dec_in[448] ^ ecc_dec_in[452] ^ ecc_dec_in[455] ^
                        ecc_dec_in[457] ^ ecc_dec_in[458] ^ ecc_dec_in[461] ^
                        ecc_dec_in[463] ^ ecc_dec_in[467] ^ ecc_dec_in[468] ^
                        ecc_dec_in[472] ^ ecc_dec_in[476] ^ ecc_dec_in[477] ^
                        ecc_dec_in[479] ^ ecc_dec_in[483] ^ ecc_dec_in[488] ^
                        ecc_dec_in[490] ^ ecc_dec_in[492] ^ ecc_dec_in[499] ^
                        ecc_dec_in[506] ^ ecc_dec_in[507] ^ ecc_dec_in[511] ^
                        ecc_dec_in[518] ^ ecc_dec_in[523] ^ ecc_dec_in[527]) ;
assign syndrom[01] = ~( ecc_dec_in[000] ^ ecc_dec_in[001] ^ ecc_dec_in[003] ^
                        ecc_dec_in[004] ^ ecc_dec_in[006] ^ ecc_dec_in[008] ^
                        ecc_dec_in[010] ^ ecc_dec_in[011] ^ ecc_dec_in[013] ^
                        ecc_dec_in[015] ^ ecc_dec_in[018] ^ ecc_dec_in[020] ^
                        ecc_dec_in[022] ^ ecc_dec_in[024] ^ ecc_dec_in[026] ^
                        ecc_dec_in[028] ^ ecc_dec_in[030] ^ ecc_dec_in[032] ^
                        ecc_dec_in[034] ^ ecc_dec_in[036] ^ ecc_dec_in[039] ^
                        ecc_dec_in[041] ^ ecc_dec_in[043] ^ ecc_dec_in[045] ^
                        ecc_dec_in[047] ^ ecc_dec_in[048] ^ ecc_dec_in[049] ^
                        ecc_dec_in[051] ^ ecc_dec_in[053] ^ ecc_dec_in[055] ^
                        ecc_dec_in[057] ^ ecc_dec_in[059] ^ ecc_dec_in[061] ^
                        ecc_dec_in[065] ^ ecc_dec_in[067] ^ ecc_dec_in[069] ^
                        ecc_dec_in[071] ^ ecc_dec_in[073] ^ ecc_dec_in[075] ^
                        ecc_dec_in[077] ^ ecc_dec_in[079] ^ ecc_dec_in[081] ^
                        ecc_dec_in[084] ^ ecc_dec_in[086] ^ ecc_dec_in[088] ^
                        ecc_dec_in[089] ^ ecc_dec_in[092] ^ ecc_dec_in[094] ^
                        ecc_dec_in[096] ^ ecc_dec_in[100] ^ ecc_dec_in[102] ^
                        ecc_dec_in[104] ^ ecc_dec_in[106] ^ ecc_dec_in[108] ^
                        ecc_dec_in[111] ^ ecc_dec_in[112] ^ ecc_dec_in[114] ^
                        ecc_dec_in[116] ^ ecc_dec_in[118] ^ ecc_dec_in[122] ^
                        ecc_dec_in[124] ^ ecc_dec_in[127] ^ ecc_dec_in[130] ^
                        ecc_dec_in[132] ^ ecc_dec_in[134] ^ ecc_dec_in[137] ^
                        ecc_dec_in[140] ^ ecc_dec_in[142] ^ ecc_dec_in[145] ^
                        ecc_dec_in[149] ^ ecc_dec_in[151] ^ ecc_dec_in[153] ^
                        ecc_dec_in[156] ^ ecc_dec_in[158] ^ ecc_dec_in[160] ^
                        ecc_dec_in[163] ^ ecc_dec_in[164] ^ ecc_dec_in[165] ^
                        ecc_dec_in[171] ^ ecc_dec_in[172] ^ ecc_dec_in[174] ^
                        ecc_dec_in[176] ^ ecc_dec_in[178] ^ ecc_dec_in[182] ^
                        ecc_dec_in[184] ^ ecc_dec_in[186] ^ ecc_dec_in[189] ^
                        ecc_dec_in[191] ^ ecc_dec_in[193] ^ ecc_dec_in[195] ^
                        ecc_dec_in[197] ^ ecc_dec_in[199] ^ ecc_dec_in[201] ^
                        ecc_dec_in[203] ^ ecc_dec_in[205] ^ ecc_dec_in[207] ^
                        ecc_dec_in[209] ^ ecc_dec_in[212] ^ ecc_dec_in[214] ^
                        ecc_dec_in[216] ^ ecc_dec_in[218] ^ ecc_dec_in[221] ^
                        ecc_dec_in[223] ^ ecc_dec_in[227] ^ ecc_dec_in[229] ^
                        ecc_dec_in[232] ^ ecc_dec_in[234] ^ ecc_dec_in[236] ^
                        ecc_dec_in[240] ^ ecc_dec_in[245] ^ ecc_dec_in[248] ^
                        ecc_dec_in[251] ^ ecc_dec_in[253] ^ ecc_dec_in[256] ^
                        ecc_dec_in[260] ^ ecc_dec_in[265] ^ ecc_dec_in[268] ^
                        ecc_dec_in[270] ^ ecc_dec_in[272] ^ ecc_dec_in[274] ^
                        ecc_dec_in[275] ^ ecc_dec_in[278] ^ ecc_dec_in[279] ^
                        ecc_dec_in[281] ^ ecc_dec_in[287] ^ ecc_dec_in[289] ^
                        ecc_dec_in[292] ^ ecc_dec_in[295] ^ ecc_dec_in[299] ^
                        ecc_dec_in[301] ^ ecc_dec_in[302] ^ ecc_dec_in[305] ^
                        ecc_dec_in[308] ^ ecc_dec_in[312] ^ ecc_dec_in[317] ^
                        ecc_dec_in[319] ^ ecc_dec_in[321] ^ ecc_dec_in[323] ^
                        ecc_dec_in[325] ^ ecc_dec_in[327] ^ ecc_dec_in[330] ^
                        ecc_dec_in[332] ^ ecc_dec_in[335] ^ ecc_dec_in[337] ^
                        ecc_dec_in[339] ^ ecc_dec_in[340] ^ ecc_dec_in[342] ^
                        ecc_dec_in[344] ^ ecc_dec_in[346] ^ ecc_dec_in[348] ^
                        ecc_dec_in[350] ^ ecc_dec_in[354] ^ ecc_dec_in[357] ^
                        ecc_dec_in[359] ^ ecc_dec_in[362] ^ ecc_dec_in[366] ^
                        ecc_dec_in[368] ^ ecc_dec_in[370] ^ ecc_dec_in[372] ^
                        ecc_dec_in[374] ^ ecc_dec_in[376] ^ ecc_dec_in[379] ^
                        ecc_dec_in[382] ^ ecc_dec_in[384] ^ ecc_dec_in[388] ^
                        ecc_dec_in[390] ^ ecc_dec_in[393] ^ ecc_dec_in[396] ^
                        ecc_dec_in[400] ^ ecc_dec_in[402] ^ ecc_dec_in[404] ^
                        ecc_dec_in[406] ^ ecc_dec_in[408] ^ ecc_dec_in[410] ^
                        ecc_dec_in[413] ^ ecc_dec_in[420] ^ ecc_dec_in[421] ^
                        ecc_dec_in[423] ^ ecc_dec_in[426] ^ ecc_dec_in[429] ^
                        ecc_dec_in[434] ^ ecc_dec_in[435] ^ ecc_dec_in[437] ^
                        ecc_dec_in[440] ^ ecc_dec_in[444] ^ ecc_dec_in[449] ^
                        ecc_dec_in[453] ^ ecc_dec_in[455] ^ ecc_dec_in[457] ^
                        ecc_dec_in[459] ^ ecc_dec_in[462] ^ ecc_dec_in[464] ^
                        ecc_dec_in[467] ^ ecc_dec_in[469] ^ ecc_dec_in[470] ^
                        ecc_dec_in[473] ^ ecc_dec_in[478] ^ ecc_dec_in[480] ^
                        ecc_dec_in[484] ^ ecc_dec_in[489] ^ ecc_dec_in[493] ^
                        ecc_dec_in[495] ^ ecc_dec_in[500] ^ ecc_dec_in[506] ^
                        ecc_dec_in[508] ^ ecc_dec_in[509] ^ ecc_dec_in[512] ^
                        ecc_dec_in[514] ^ ecc_dec_in[519] ^ ecc_dec_in[528]) ;
assign syndrom[02] = ~( ecc_dec_in[000] ^ ecc_dec_in[002] ^ ecc_dec_in[003] ^
                        ecc_dec_in[005] ^ ecc_dec_in[006] ^ ecc_dec_in[009] ^
                        ecc_dec_in[010] ^ ecc_dec_in[012] ^ ecc_dec_in[013] ^
                        ecc_dec_in[016] ^ ecc_dec_in[019] ^ ecc_dec_in[020] ^
                        ecc_dec_in[023] ^ ecc_dec_in[025] ^ ecc_dec_in[026] ^
                        ecc_dec_in[029] ^ ecc_dec_in[030] ^ ecc_dec_in[033] ^
                        ecc_dec_in[034] ^ ecc_dec_in[037] ^ ecc_dec_in[040] ^
                        ecc_dec_in[041] ^ ecc_dec_in[044] ^ ecc_dec_in[045] ^
                        ecc_dec_in[048] ^ ecc_dec_in[050] ^ ecc_dec_in[052] ^
                        ecc_dec_in[053] ^ ecc_dec_in[056] ^ ecc_dec_in[057] ^
                        ecc_dec_in[060] ^ ecc_dec_in[061] ^ ecc_dec_in[063] ^
                        ecc_dec_in[066] ^ ecc_dec_in[067] ^ ecc_dec_in[070] ^
                        ecc_dec_in[071] ^ ecc_dec_in[074] ^ ecc_dec_in[075] ^
                        ecc_dec_in[080] ^ ecc_dec_in[081] ^ ecc_dec_in[083] ^
                        ecc_dec_in[084] ^ ecc_dec_in[087] ^ ecc_dec_in[088] ^
                        ecc_dec_in[090] ^ ecc_dec_in[093] ^ ecc_dec_in[094] ^
                        ecc_dec_in[097] ^ ecc_dec_in[101] ^ ecc_dec_in[102] ^
                        ecc_dec_in[105] ^ ecc_dec_in[106] ^ ecc_dec_in[109] ^
                        ecc_dec_in[112] ^ ecc_dec_in[115] ^ ecc_dec_in[116] ^
                        ecc_dec_in[119] ^ ecc_dec_in[121] ^ ecc_dec_in[122] ^
                        ecc_dec_in[125] ^ ecc_dec_in[128] ^ ecc_dec_in[131] ^
                        ecc_dec_in[132] ^ ecc_dec_in[135] ^ ecc_dec_in[138] ^
                        ecc_dec_in[141] ^ ecc_dec_in[142] ^ ecc_dec_in[146] ^
                        ecc_dec_in[150] ^ ecc_dec_in[151] ^ ecc_dec_in[154] ^
                        ecc_dec_in[157] ^ ecc_dec_in[158] ^ ecc_dec_in[161] ^
                        ecc_dec_in[164] ^ ecc_dec_in[166] ^ ecc_dec_in[168] ^
                        ecc_dec_in[172] ^ ecc_dec_in[175] ^ ecc_dec_in[177] ^
                        ecc_dec_in[179] ^ ecc_dec_in[183] ^ ecc_dec_in[184] ^
                        ecc_dec_in[187] ^ ecc_dec_in[190] ^ ecc_dec_in[191] ^
                        ecc_dec_in[194] ^ ecc_dec_in[195] ^ ecc_dec_in[198] ^
                        ecc_dec_in[199] ^ ecc_dec_in[202] ^ ecc_dec_in[203] ^
                        ecc_dec_in[206] ^ ecc_dec_in[207] ^ ecc_dec_in[210] ^
                        ecc_dec_in[213] ^ ecc_dec_in[214] ^ ecc_dec_in[217] ^
                        ecc_dec_in[218] ^ ecc_dec_in[220] ^ ecc_dec_in[221] ^
                        ecc_dec_in[225] ^ ecc_dec_in[228] ^ ecc_dec_in[230] ^
                        ecc_dec_in[233] ^ ecc_dec_in[234] ^ ecc_dec_in[237] ^
                        ecc_dec_in[239] ^ ecc_dec_in[240] ^ ecc_dec_in[242] ^
                        ecc_dec_in[244] ^ ecc_dec_in[246] ^ ecc_dec_in[252] ^
                        ecc_dec_in[253] ^ ecc_dec_in[254] ^ ecc_dec_in[257] ^
                        ecc_dec_in[261] ^ ecc_dec_in[266] ^ ecc_dec_in[269] ^
                        ecc_dec_in[270] ^ ecc_dec_in[273] ^ ecc_dec_in[274] ^
                        ecc_dec_in[276] ^ ecc_dec_in[279] ^ ecc_dec_in[282] ^
                        ecc_dec_in[284] ^ ecc_dec_in[290] ^ ecc_dec_in[296] ^
                        ecc_dec_in[300] ^ ecc_dec_in[301] ^ ecc_dec_in[303] ^
                        ecc_dec_in[309] ^ ecc_dec_in[313] ^ ecc_dec_in[318] ^
                        ecc_dec_in[319] ^ ecc_dec_in[322] ^ ecc_dec_in[323] ^
                        ecc_dec_in[326] ^ ecc_dec_in[327] ^ ecc_dec_in[329] ^
                        ecc_dec_in[330] ^ ecc_dec_in[333] ^ ecc_dec_in[336] ^
                        ecc_dec_in[337] ^ ecc_dec_in[340] ^ ecc_dec_in[345] ^
                        ecc_dec_in[346] ^ ecc_dec_in[349] ^ ecc_dec_in[350] ^
                        ecc_dec_in[352] ^ ecc_dec_in[355] ^ ecc_dec_in[358] ^
                        ecc_dec_in[359] ^ ecc_dec_in[360] ^ ecc_dec_in[363] ^
                        ecc_dec_in[367] ^ ecc_dec_in[368] ^ ecc_dec_in[371] ^
                        ecc_dec_in[372] ^ ecc_dec_in[374] ^ ecc_dec_in[377] ^
                        ecc_dec_in[380] ^ ecc_dec_in[385] ^ ecc_dec_in[389] ^
                        ecc_dec_in[390] ^ ecc_dec_in[391] ^ ecc_dec_in[394] ^
                        ecc_dec_in[397] ^ ecc_dec_in[401] ^ ecc_dec_in[402] ^
                        ecc_dec_in[407] ^ ecc_dec_in[408] ^ ecc_dec_in[411] ^
                        ecc_dec_in[414] ^ ecc_dec_in[416] ^ ecc_dec_in[418] ^
                        ecc_dec_in[421] ^ ecc_dec_in[424] ^ ecc_dec_in[427] ^
                        ecc_dec_in[430] ^ ecc_dec_in[435] ^ ecc_dec_in[438] ^
                        ecc_dec_in[441] ^ ecc_dec_in[445] ^ ecc_dec_in[454] ^
                        ecc_dec_in[455] ^ ecc_dec_in[458] ^ ecc_dec_in[459] ^
                        ecc_dec_in[461] ^ ecc_dec_in[462] ^ ecc_dec_in[465] ^
                        ecc_dec_in[468] ^ ecc_dec_in[469] ^ ecc_dec_in[471] ^
                        ecc_dec_in[476] ^ ecc_dec_in[481] ^ ecc_dec_in[488] ^
                        ecc_dec_in[489] ^ ecc_dec_in[491] ^ ecc_dec_in[494] ^
                        ecc_dec_in[496] ^ ecc_dec_in[501] ^ ecc_dec_in[507] ^
                        ecc_dec_in[508] ^ ecc_dec_in[510] ^ ecc_dec_in[515] ^
                        ecc_dec_in[520] ^ ecc_dec_in[524] ^ ecc_dec_in[529]) ;
assign syndrom[03] = ~( ecc_dec_in[001] ^ ecc_dec_in[002] ^ ecc_dec_in[003] ^
                        ecc_dec_in[007] ^ ecc_dec_in[008] ^ ecc_dec_in[009] ^
                        ecc_dec_in[010] ^ ecc_dec_in[014] ^ ecc_dec_in[015] ^
                        ecc_dec_in[016] ^ ecc_dec_in[021] ^ ecc_dec_in[022] ^
                        ecc_dec_in[023] ^ ecc_dec_in[027] ^ ecc_dec_in[028] ^
                        ecc_dec_in[029] ^ ecc_dec_in[030] ^ ecc_dec_in[035] ^
                        ecc_dec_in[036] ^ ecc_dec_in[037] ^ ecc_dec_in[042] ^
                        ecc_dec_in[043] ^ ecc_dec_in[044] ^ ecc_dec_in[045] ^
                        ecc_dec_in[049] ^ ecc_dec_in[050] ^ ecc_dec_in[054] ^
                        ecc_dec_in[055] ^ ecc_dec_in[056] ^ ecc_dec_in[057] ^
                        ecc_dec_in[062] ^ ecc_dec_in[063] ^ ecc_dec_in[068] ^
                        ecc_dec_in[069] ^ ecc_dec_in[070] ^ ecc_dec_in[071] ^
                        ecc_dec_in[076] ^ ecc_dec_in[077] ^ ecc_dec_in[082] ^
                        ecc_dec_in[083] ^ ecc_dec_in[084] ^ ecc_dec_in[089] ^
                        ecc_dec_in[090] ^ ecc_dec_in[095] ^ ecc_dec_in[096] ^
                        ecc_dec_in[097] ^ ecc_dec_in[099] ^ ecc_dec_in[103] ^
                        ecc_dec_in[104] ^ ecc_dec_in[105] ^ ecc_dec_in[106] ^
                        ecc_dec_in[110] ^ ecc_dec_in[111] ^ ecc_dec_in[112] ^
                        ecc_dec_in[117] ^ ecc_dec_in[118] ^ ecc_dec_in[119] ^
                        ecc_dec_in[123] ^ ecc_dec_in[124] ^ ecc_dec_in[125] ^
                        ecc_dec_in[129] ^ ecc_dec_in[130] ^ ecc_dec_in[131] ^
                        ecc_dec_in[132] ^ ecc_dec_in[136] ^ ecc_dec_in[137] ^
                        ecc_dec_in[138] ^ ecc_dec_in[143] ^ ecc_dec_in[147] ^
                        ecc_dec_in[152] ^ ecc_dec_in[153] ^ ecc_dec_in[154] ^
                        ecc_dec_in[159] ^ ecc_dec_in[160] ^ ecc_dec_in[161] ^
                        ecc_dec_in[165] ^ ecc_dec_in[166] ^ ecc_dec_in[169] ^
                        ecc_dec_in[173] ^ ecc_dec_in[174] ^ ecc_dec_in[175] ^
                        ecc_dec_in[180] ^ ecc_dec_in[185] ^ ecc_dec_in[186] ^
                        ecc_dec_in[187] ^ ecc_dec_in[192] ^ ecc_dec_in[193] ^
                        ecc_dec_in[194] ^ ecc_dec_in[195] ^ ecc_dec_in[200] ^
                        ecc_dec_in[201] ^ ecc_dec_in[202] ^ ecc_dec_in[203] ^
                        ecc_dec_in[208] ^ ecc_dec_in[209] ^ ecc_dec_in[210] ^
                        ecc_dec_in[215] ^ ecc_dec_in[216] ^ ecc_dec_in[217] ^
                        ecc_dec_in[218] ^ ecc_dec_in[222] ^ ecc_dec_in[223] ^
                        ecc_dec_in[226] ^ ecc_dec_in[227] ^ ecc_dec_in[228] ^
                        ecc_dec_in[235] ^ ecc_dec_in[236] ^ ecc_dec_in[237] ^
                        ecc_dec_in[241] ^ ecc_dec_in[242] ^ ecc_dec_in[245] ^
                        ecc_dec_in[246] ^ ecc_dec_in[249] ^ ecc_dec_in[254] ^
                        ecc_dec_in[258] ^ ecc_dec_in[262] ^ ecc_dec_in[267] ^
                        ecc_dec_in[268] ^ ecc_dec_in[269] ^ ecc_dec_in[270] ^
                        ecc_dec_in[275] ^ ecc_dec_in[276] ^ ecc_dec_in[280] ^
                        ecc_dec_in[281] ^ ecc_dec_in[282] ^ ecc_dec_in[285] ^
                        ecc_dec_in[288] ^ ecc_dec_in[289] ^ ecc_dec_in[290] ^
                        ecc_dec_in[293] ^ ecc_dec_in[302] ^ ecc_dec_in[303] ^
                        ecc_dec_in[306] ^ ecc_dec_in[314] ^ ecc_dec_in[320] ^
                        ecc_dec_in[321] ^ ecc_dec_in[322] ^ ecc_dec_in[323] ^
                        ecc_dec_in[328] ^ ecc_dec_in[329] ^ ecc_dec_in[330] ^
                        ecc_dec_in[334] ^ ecc_dec_in[335] ^ ecc_dec_in[336] ^
                        ecc_dec_in[337] ^ ecc_dec_in[341] ^ ecc_dec_in[342] ^
                        ecc_dec_in[347] ^ ecc_dec_in[348] ^ ecc_dec_in[349] ^
                        ecc_dec_in[350] ^ ecc_dec_in[353] ^ ecc_dec_in[354] ^
                        ecc_dec_in[355] ^ ecc_dec_in[360] ^ ecc_dec_in[364] ^
                        ecc_dec_in[369] ^ ecc_dec_in[370] ^ ecc_dec_in[371] ^
                        ecc_dec_in[372] ^ ecc_dec_in[375] ^ ecc_dec_in[376] ^
                        ecc_dec_in[377] ^ ecc_dec_in[381] ^ ecc_dec_in[382] ^
                        ecc_dec_in[386] ^ ecc_dec_in[391] ^ ecc_dec_in[398] ^
                        ecc_dec_in[403] ^ ecc_dec_in[404] ^ ecc_dec_in[409] ^
                        ecc_dec_in[410] ^ ecc_dec_in[411] ^ ecc_dec_in[415] ^
                        ecc_dec_in[416] ^ ecc_dec_in[422] ^ ecc_dec_in[423] ^
                        ecc_dec_in[424] ^ ecc_dec_in[431] ^ ecc_dec_in[436] ^
                        ecc_dec_in[437] ^ ecc_dec_in[438] ^ ecc_dec_in[442] ^
                        ecc_dec_in[446] ^ ecc_dec_in[450] ^ ecc_dec_in[456] ^
                        ecc_dec_in[457] ^ ecc_dec_in[458] ^ ecc_dec_in[459] ^
                        ecc_dec_in[463] ^ ecc_dec_in[464] ^ ecc_dec_in[465] ^
                        ecc_dec_in[470] ^ ecc_dec_in[471] ^ ecc_dec_in[474] ^
                        ecc_dec_in[477] ^ ecc_dec_in[478] ^ ecc_dec_in[482] ^
                        ecc_dec_in[485] ^ ecc_dec_in[490] ^ ecc_dec_in[491] ^
                        ecc_dec_in[497] ^ ecc_dec_in[502] ^ ecc_dec_in[509] ^
                        ecc_dec_in[510] ^ ecc_dec_in[513] ^ ecc_dec_in[516] ^
                        ecc_dec_in[521] ^ ecc_dec_in[525] ^ ecc_dec_in[530]) ;
assign syndrom[04] = ~( ecc_dec_in[004] ^ ecc_dec_in[005] ^ ecc_dec_in[006] ^
                        ecc_dec_in[007] ^ ecc_dec_in[008] ^ ecc_dec_in[009] ^
                        ecc_dec_in[010] ^ ecc_dec_in[017] ^ ecc_dec_in[018] ^
                        ecc_dec_in[019] ^ ecc_dec_in[020] ^ ecc_dec_in[021] ^
                        ecc_dec_in[022] ^ ecc_dec_in[023] ^ ecc_dec_in[031] ^
                        ecc_dec_in[032] ^ ecc_dec_in[033] ^ ecc_dec_in[034] ^
                        ecc_dec_in[035] ^ ecc_dec_in[036] ^ ecc_dec_in[037] ^
                        ecc_dec_in[046] ^ ecc_dec_in[047] ^ ecc_dec_in[048] ^
                        ecc_dec_in[049] ^ ecc_dec_in[050] ^ ecc_dec_in[058] ^
                        ecc_dec_in[059] ^ ecc_dec_in[060] ^ ecc_dec_in[061] ^
                        ecc_dec_in[062] ^ ecc_dec_in[063] ^ ecc_dec_in[072] ^
                        ecc_dec_in[073] ^ ecc_dec_in[074] ^ ecc_dec_in[075] ^
                        ecc_dec_in[076] ^ ecc_dec_in[077] ^ ecc_dec_in[085] ^
                        ecc_dec_in[086] ^ ecc_dec_in[087] ^ ecc_dec_in[088] ^
                        ecc_dec_in[089] ^ ecc_dec_in[090] ^ ecc_dec_in[098] ^
                        ecc_dec_in[099] ^ ecc_dec_in[107] ^ ecc_dec_in[108] ^
                        ecc_dec_in[109] ^ ecc_dec_in[110] ^ ecc_dec_in[111] ^
                        ecc_dec_in[112] ^ ecc_dec_in[120] ^ ecc_dec_in[121] ^
                        ecc_dec_in[122] ^ ecc_dec_in[123] ^ ecc_dec_in[124] ^
                        ecc_dec_in[125] ^ ecc_dec_in[133] ^ ecc_dec_in[134] ^
                        ecc_dec_in[135] ^ ecc_dec_in[136] ^ ecc_dec_in[137] ^
                        ecc_dec_in[138] ^ ecc_dec_in[144] ^ ecc_dec_in[145] ^
                        ecc_dec_in[146] ^ ecc_dec_in[147] ^ ecc_dec_in[155] ^
                        ecc_dec_in[156] ^ ecc_dec_in[157] ^ ecc_dec_in[158] ^
                        ecc_dec_in[159] ^ ecc_dec_in[160] ^ ecc_dec_in[161] ^
                        ecc_dec_in[167] ^ ecc_dec_in[168] ^ ecc_dec_in[169] ^
                        ecc_dec_in[176] ^ ecc_dec_in[177] ^ ecc_dec_in[181] ^
                        ecc_dec_in[188] ^ ecc_dec_in[189] ^ ecc_dec_in[190] ^
                        ecc_dec_in[191] ^ ecc_dec_in[192] ^ ecc_dec_in[193] ^
                        ecc_dec_in[194] ^ ecc_dec_in[195] ^ ecc_dec_in[204] ^
                        ecc_dec_in[205] ^ ecc_dec_in[206] ^ ecc_dec_in[207] ^
                        ecc_dec_in[208] ^ ecc_dec_in[209] ^ ecc_dec_in[210] ^
                        ecc_dec_in[219] ^ ecc_dec_in[220] ^ ecc_dec_in[221] ^
                        ecc_dec_in[222] ^ ecc_dec_in[223] ^ ecc_dec_in[229] ^
                        ecc_dec_in[230] ^ ecc_dec_in[238] ^ ecc_dec_in[239] ^
                        ecc_dec_in[240] ^ ecc_dec_in[241] ^ ecc_dec_in[242] ^
                        ecc_dec_in[247] ^ ecc_dec_in[248] ^ ecc_dec_in[249] ^
                        ecc_dec_in[255] ^ ecc_dec_in[256] ^ ecc_dec_in[257] ^
                        ecc_dec_in[258] ^ ecc_dec_in[263] ^ ecc_dec_in[271] ^
                        ecc_dec_in[272] ^ ecc_dec_in[273] ^ ecc_dec_in[274] ^
                        ecc_dec_in[275] ^ ecc_dec_in[276] ^ ecc_dec_in[283] ^
                        ecc_dec_in[284] ^ ecc_dec_in[285] ^ ecc_dec_in[291] ^
                        ecc_dec_in[292] ^ ecc_dec_in[293] ^ ecc_dec_in[297] ^
                        ecc_dec_in[304] ^ ecc_dec_in[305] ^ ecc_dec_in[306] ^
                        ecc_dec_in[310] ^ ecc_dec_in[315] ^ ecc_dec_in[324] ^
                        ecc_dec_in[325] ^ ecc_dec_in[326] ^ ecc_dec_in[327] ^
                        ecc_dec_in[328] ^ ecc_dec_in[329] ^ ecc_dec_in[330] ^
                        ecc_dec_in[338] ^ ecc_dec_in[339] ^ ecc_dec_in[340] ^
                        ecc_dec_in[341] ^ ecc_dec_in[342] ^ ecc_dec_in[351] ^
                        ecc_dec_in[352] ^ ecc_dec_in[353] ^ ecc_dec_in[354] ^
                        ecc_dec_in[355] ^ ecc_dec_in[361] ^ ecc_dec_in[362] ^
                        ecc_dec_in[363] ^ ecc_dec_in[364] ^ ecc_dec_in[373] ^
                        ecc_dec_in[374] ^ ecc_dec_in[375] ^ ecc_dec_in[376] ^
                        ecc_dec_in[377] ^ ecc_dec_in[383] ^ ecc_dec_in[384] ^
                        ecc_dec_in[385] ^ ecc_dec_in[386] ^ ecc_dec_in[392] ^
                        ecc_dec_in[393] ^ ecc_dec_in[394] ^ ecc_dec_in[405] ^
                        ecc_dec_in[406] ^ ecc_dec_in[407] ^ ecc_dec_in[408] ^
                        ecc_dec_in[409] ^ ecc_dec_in[410] ^ ecc_dec_in[411] ^
                        ecc_dec_in[417] ^ ecc_dec_in[418] ^ ecc_dec_in[425] ^
                        ecc_dec_in[426] ^ ecc_dec_in[427] ^ ecc_dec_in[432] ^
                        ecc_dec_in[439] ^ ecc_dec_in[440] ^ ecc_dec_in[441] ^
                        ecc_dec_in[442] ^ ecc_dec_in[447] ^ ecc_dec_in[451] ^
                        ecc_dec_in[460] ^ ecc_dec_in[461] ^ ecc_dec_in[462] ^
                        ecc_dec_in[463] ^ ecc_dec_in[464] ^ ecc_dec_in[465] ^
                        ecc_dec_in[472] ^ ecc_dec_in[473] ^ ecc_dec_in[474] ^
                        ecc_dec_in[479] ^ ecc_dec_in[480] ^ ecc_dec_in[481] ^
                        ecc_dec_in[482] ^ ecc_dec_in[486] ^ ecc_dec_in[492] ^
                        ecc_dec_in[493] ^ ecc_dec_in[494] ^ ecc_dec_in[498] ^
                        ecc_dec_in[503] ^ ecc_dec_in[511] ^ ecc_dec_in[512] ^
                        ecc_dec_in[513] ^ ecc_dec_in[517] ^ ecc_dec_in[531]) ;
assign syndrom[05] = ~( ecc_dec_in[011] ^ ecc_dec_in[012] ^ ecc_dec_in[013] ^
                        ecc_dec_in[014] ^ ecc_dec_in[015] ^ ecc_dec_in[016] ^
                        ecc_dec_in[017] ^ ecc_dec_in[018] ^ ecc_dec_in[019] ^
                        ecc_dec_in[020] ^ ecc_dec_in[021] ^ ecc_dec_in[022] ^
                        ecc_dec_in[023] ^ ecc_dec_in[038] ^ ecc_dec_in[039] ^
                        ecc_dec_in[040] ^ ecc_dec_in[041] ^ ecc_dec_in[042] ^
                        ecc_dec_in[043] ^ ecc_dec_in[044] ^ ecc_dec_in[045] ^
                        ecc_dec_in[046] ^ ecc_dec_in[047] ^ ecc_dec_in[048] ^
                        ecc_dec_in[049] ^ ecc_dec_in[050] ^ ecc_dec_in[064] ^
                        ecc_dec_in[065] ^ ecc_dec_in[066] ^ ecc_dec_in[067] ^
                        ecc_dec_in[068] ^ ecc_dec_in[069] ^ ecc_dec_in[070] ^
                        ecc_dec_in[071] ^ ecc_dec_in[072] ^ ecc_dec_in[073] ^
                        ecc_dec_in[074] ^ ecc_dec_in[075] ^ ecc_dec_in[076] ^
                        ecc_dec_in[077] ^ ecc_dec_in[091] ^ ecc_dec_in[092] ^
                        ecc_dec_in[093] ^ ecc_dec_in[094] ^ ecc_dec_in[095] ^
                        ecc_dec_in[096] ^ ecc_dec_in[097] ^ ecc_dec_in[098] ^
                        ecc_dec_in[099] ^ ecc_dec_in[113] ^ ecc_dec_in[114] ^
                        ecc_dec_in[115] ^ ecc_dec_in[116] ^ ecc_dec_in[117] ^
                        ecc_dec_in[118] ^ ecc_dec_in[119] ^ ecc_dec_in[120] ^
                        ecc_dec_in[121] ^ ecc_dec_in[122] ^ ecc_dec_in[123] ^
                        ecc_dec_in[124] ^ ecc_dec_in[125] ^ ecc_dec_in[139] ^
                        ecc_dec_in[140] ^ ecc_dec_in[141] ^ ecc_dec_in[142] ^
                        ecc_dec_in[143] ^ ecc_dec_in[144] ^ ecc_dec_in[145] ^
                        ecc_dec_in[146] ^ ecc_dec_in[147] ^ ecc_dec_in[162] ^
                        ecc_dec_in[163] ^ ecc_dec_in[164] ^ ecc_dec_in[165] ^
                        ecc_dec_in[166] ^ ecc_dec_in[167] ^ ecc_dec_in[168] ^
                        ecc_dec_in[169] ^ ecc_dec_in[178] ^ ecc_dec_in[179] ^
                        ecc_dec_in[180] ^ ecc_dec_in[181] ^ ecc_dec_in[196] ^
                        ecc_dec_in[197] ^ ecc_dec_in[198] ^ ecc_dec_in[199] ^
                        ecc_dec_in[200] ^ ecc_dec_in[201] ^ ecc_dec_in[202] ^
                        ecc_dec_in[203] ^ ecc_dec_in[204] ^ ecc_dec_in[205] ^
                        ecc_dec_in[206] ^ ecc_dec_in[207] ^ ecc_dec_in[208] ^
                        ecc_dec_in[209] ^ ecc_dec_in[210] ^ ecc_dec_in[224] ^
                        ecc_dec_in[225] ^ ecc_dec_in[226] ^ ecc_dec_in[227] ^
                        ecc_dec_in[228] ^ ecc_dec_in[229] ^ ecc_dec_in[230] ^
                        ecc_dec_in[243] ^ ecc_dec_in[244] ^ ecc_dec_in[245] ^
                        ecc_dec_in[246] ^ ecc_dec_in[247] ^ ecc_dec_in[248] ^
                        ecc_dec_in[249] ^ ecc_dec_in[259] ^ ecc_dec_in[260] ^
                        ecc_dec_in[261] ^ ecc_dec_in[262] ^ ecc_dec_in[263] ^
                        ecc_dec_in[277] ^ ecc_dec_in[278] ^ ecc_dec_in[279] ^
                        ecc_dec_in[280] ^ ecc_dec_in[281] ^ ecc_dec_in[282] ^
                        ecc_dec_in[283] ^ ecc_dec_in[284] ^ ecc_dec_in[285] ^
                        ecc_dec_in[294] ^ ecc_dec_in[295] ^ ecc_dec_in[296] ^
                        ecc_dec_in[297] ^ ecc_dec_in[307] ^ ecc_dec_in[308] ^
                        ecc_dec_in[309] ^ ecc_dec_in[310] ^ ecc_dec_in[316] ^
                        ecc_dec_in[331] ^ ecc_dec_in[332] ^ ecc_dec_in[333] ^
                        ecc_dec_in[334] ^ ecc_dec_in[335] ^ ecc_dec_in[336] ^
                        ecc_dec_in[337] ^ ecc_dec_in[338] ^ ecc_dec_in[339] ^
                        ecc_dec_in[340] ^ ecc_dec_in[341] ^ ecc_dec_in[342] ^
                        ecc_dec_in[356] ^ ecc_dec_in[357] ^ ecc_dec_in[358] ^
                        ecc_dec_in[359] ^ ecc_dec_in[360] ^ ecc_dec_in[361] ^
                        ecc_dec_in[362] ^ ecc_dec_in[363] ^ ecc_dec_in[364] ^
                        ecc_dec_in[378] ^ ecc_dec_in[379] ^ ecc_dec_in[380] ^
                        ecc_dec_in[381] ^ ecc_dec_in[382] ^ ecc_dec_in[383] ^
                        ecc_dec_in[384] ^ ecc_dec_in[385] ^ ecc_dec_in[386] ^
                        ecc_dec_in[395] ^ ecc_dec_in[396] ^ ecc_dec_in[397] ^
                        ecc_dec_in[398] ^ ecc_dec_in[412] ^ ecc_dec_in[413] ^
                        ecc_dec_in[414] ^ ecc_dec_in[415] ^ ecc_dec_in[416] ^
                        ecc_dec_in[417] ^ ecc_dec_in[418] ^ ecc_dec_in[428] ^
                        ecc_dec_in[429] ^ ecc_dec_in[430] ^ ecc_dec_in[431] ^
                        ecc_dec_in[432] ^ ecc_dec_in[443] ^ ecc_dec_in[444] ^
                        ecc_dec_in[445] ^ ecc_dec_in[446] ^ ecc_dec_in[447] ^
                        ecc_dec_in[466] ^ ecc_dec_in[467] ^ ecc_dec_in[468] ^
                        ecc_dec_in[469] ^ ecc_dec_in[470] ^ ecc_dec_in[471] ^
                        ecc_dec_in[472] ^ ecc_dec_in[473] ^ ecc_dec_in[474] ^
                        ecc_dec_in[483] ^ ecc_dec_in[484] ^ ecc_dec_in[485] ^
                        ecc_dec_in[486] ^ ecc_dec_in[495] ^ ecc_dec_in[496] ^
                        ecc_dec_in[497] ^ ecc_dec_in[498] ^ ecc_dec_in[504] ^
                        ecc_dec_in[514] ^ ecc_dec_in[515] ^ ecc_dec_in[516] ^
                        ecc_dec_in[517] ^ ecc_dec_in[522] ^ ecc_dec_in[526] ^
                        ecc_dec_in[532]) ;
assign syndrom[06] = ~( ecc_dec_in[024] ^ ecc_dec_in[025] ^ ecc_dec_in[026] ^
                        ecc_dec_in[027] ^ ecc_dec_in[028] ^ ecc_dec_in[029] ^
                        ecc_dec_in[030] ^ ecc_dec_in[031] ^ ecc_dec_in[032] ^
                        ecc_dec_in[033] ^ ecc_dec_in[034] ^ ecc_dec_in[035] ^
                        ecc_dec_in[036] ^ ecc_dec_in[037] ^ ecc_dec_in[038] ^
                        ecc_dec_in[039] ^ ecc_dec_in[040] ^ ecc_dec_in[041] ^
                        ecc_dec_in[042] ^ ecc_dec_in[043] ^ ecc_dec_in[044] ^
                        ecc_dec_in[045] ^ ecc_dec_in[046] ^ ecc_dec_in[047] ^
                        ecc_dec_in[048] ^ ecc_dec_in[049] ^ ecc_dec_in[050] ^
                        ecc_dec_in[078] ^ ecc_dec_in[079] ^ ecc_dec_in[080] ^
                        ecc_dec_in[081] ^ ecc_dec_in[082] ^ ecc_dec_in[083] ^
                        ecc_dec_in[084] ^ ecc_dec_in[085] ^ ecc_dec_in[086] ^
                        ecc_dec_in[087] ^ ecc_dec_in[088] ^ ecc_dec_in[089] ^
                        ecc_dec_in[090] ^ ecc_dec_in[091] ^ ecc_dec_in[092] ^
                        ecc_dec_in[093] ^ ecc_dec_in[094] ^ ecc_dec_in[095] ^
                        ecc_dec_in[096] ^ ecc_dec_in[097] ^ ecc_dec_in[098] ^
                        ecc_dec_in[099] ^ ecc_dec_in[126] ^ ecc_dec_in[127] ^
                        ecc_dec_in[128] ^ ecc_dec_in[129] ^ ecc_dec_in[130] ^
                        ecc_dec_in[131] ^ ecc_dec_in[132] ^ ecc_dec_in[133] ^
                        ecc_dec_in[134] ^ ecc_dec_in[135] ^ ecc_dec_in[136] ^
                        ecc_dec_in[137] ^ ecc_dec_in[138] ^ ecc_dec_in[139] ^
                        ecc_dec_in[140] ^ ecc_dec_in[141] ^ ecc_dec_in[142] ^
                        ecc_dec_in[143] ^ ecc_dec_in[144] ^ ecc_dec_in[145] ^
                        ecc_dec_in[146] ^ ecc_dec_in[147] ^ ecc_dec_in[170] ^
                        ecc_dec_in[171] ^ ecc_dec_in[172] ^ ecc_dec_in[173] ^
                        ecc_dec_in[174] ^ ecc_dec_in[175] ^ ecc_dec_in[176] ^
                        ecc_dec_in[177] ^ ecc_dec_in[178] ^ ecc_dec_in[179] ^
                        ecc_dec_in[180] ^ ecc_dec_in[181] ^ ecc_dec_in[211] ^
                        ecc_dec_in[212] ^ ecc_dec_in[213] ^ ecc_dec_in[214] ^
                        ecc_dec_in[215] ^ ecc_dec_in[216] ^ ecc_dec_in[217] ^
                        ecc_dec_in[218] ^ ecc_dec_in[219] ^ ecc_dec_in[220] ^
                        ecc_dec_in[221] ^ ecc_dec_in[222] ^ ecc_dec_in[223] ^
                        ecc_dec_in[224] ^ ecc_dec_in[225] ^ ecc_dec_in[226] ^
                        ecc_dec_in[227] ^ ecc_dec_in[228] ^ ecc_dec_in[229] ^
                        ecc_dec_in[230] ^ ecc_dec_in[250] ^ ecc_dec_in[251] ^
                        ecc_dec_in[252] ^ ecc_dec_in[253] ^ ecc_dec_in[254] ^
                        ecc_dec_in[255] ^ ecc_dec_in[256] ^ ecc_dec_in[257] ^
                        ecc_dec_in[258] ^ ecc_dec_in[259] ^ ecc_dec_in[260] ^
                        ecc_dec_in[261] ^ ecc_dec_in[262] ^ ecc_dec_in[263] ^
                        ecc_dec_in[286] ^ ecc_dec_in[287] ^ ecc_dec_in[288] ^
                        ecc_dec_in[289] ^ ecc_dec_in[290] ^ ecc_dec_in[291] ^
                        ecc_dec_in[292] ^ ecc_dec_in[293] ^ ecc_dec_in[294] ^
                        ecc_dec_in[295] ^ ecc_dec_in[296] ^ ecc_dec_in[297] ^
                        ecc_dec_in[311] ^ ecc_dec_in[312] ^ ecc_dec_in[313] ^
                        ecc_dec_in[314] ^ ecc_dec_in[315] ^ ecc_dec_in[316] ^
                        ecc_dec_in[343] ^ ecc_dec_in[344] ^ ecc_dec_in[345] ^
                        ecc_dec_in[346] ^ ecc_dec_in[347] ^ ecc_dec_in[348] ^
                        ecc_dec_in[349] ^ ecc_dec_in[350] ^ ecc_dec_in[351] ^
                        ecc_dec_in[352] ^ ecc_dec_in[353] ^ ecc_dec_in[354] ^
                        ecc_dec_in[355] ^ ecc_dec_in[356] ^ ecc_dec_in[357] ^
                        ecc_dec_in[358] ^ ecc_dec_in[359] ^ ecc_dec_in[360] ^
                        ecc_dec_in[361] ^ ecc_dec_in[362] ^ ecc_dec_in[363] ^
                        ecc_dec_in[364] ^ ecc_dec_in[387] ^ ecc_dec_in[388] ^
                        ecc_dec_in[389] ^ ecc_dec_in[390] ^ ecc_dec_in[391] ^
                        ecc_dec_in[392] ^ ecc_dec_in[393] ^ ecc_dec_in[394] ^
                        ecc_dec_in[395] ^ ecc_dec_in[396] ^ ecc_dec_in[397] ^
                        ecc_dec_in[398] ^ ecc_dec_in[419] ^ ecc_dec_in[420] ^
                        ecc_dec_in[421] ^ ecc_dec_in[422] ^ ecc_dec_in[423] ^
                        ecc_dec_in[424] ^ ecc_dec_in[425] ^ ecc_dec_in[426] ^
                        ecc_dec_in[427] ^ ecc_dec_in[428] ^ ecc_dec_in[429] ^
                        ecc_dec_in[430] ^ ecc_dec_in[431] ^ ecc_dec_in[432] ^
                        ecc_dec_in[448] ^ ecc_dec_in[449] ^ ecc_dec_in[450] ^
                        ecc_dec_in[451] ^ ecc_dec_in[475] ^ ecc_dec_in[476] ^
                        ecc_dec_in[477] ^ ecc_dec_in[478] ^ ecc_dec_in[479] ^
                        ecc_dec_in[480] ^ ecc_dec_in[481] ^ ecc_dec_in[482] ^
                        ecc_dec_in[483] ^ ecc_dec_in[484] ^ ecc_dec_in[485] ^
                        ecc_dec_in[486] ^ ecc_dec_in[499] ^ ecc_dec_in[500] ^
                        ecc_dec_in[501] ^ ecc_dec_in[502] ^ ecc_dec_in[503] ^
                        ecc_dec_in[504] ^ ecc_dec_in[518] ^ ecc_dec_in[519] ^
                        ecc_dec_in[520] ^ ecc_dec_in[521] ^ ecc_dec_in[522] ^
                        ecc_dec_in[533]) ;
assign syndrom[07] = ~( ecc_dec_in[051] ^ ecc_dec_in[052] ^ ecc_dec_in[053] ^
                        ecc_dec_in[054] ^ ecc_dec_in[055] ^ ecc_dec_in[056] ^
                        ecc_dec_in[057] ^ ecc_dec_in[058] ^ ecc_dec_in[059] ^
                        ecc_dec_in[060] ^ ecc_dec_in[061] ^ ecc_dec_in[062] ^
                        ecc_dec_in[063] ^ ecc_dec_in[064] ^ ecc_dec_in[065] ^
                        ecc_dec_in[066] ^ ecc_dec_in[067] ^ ecc_dec_in[068] ^
                        ecc_dec_in[069] ^ ecc_dec_in[070] ^ ecc_dec_in[071] ^
                        ecc_dec_in[072] ^ ecc_dec_in[073] ^ ecc_dec_in[074] ^
                        ecc_dec_in[075] ^ ecc_dec_in[076] ^ ecc_dec_in[077] ^
                        ecc_dec_in[078] ^ ecc_dec_in[079] ^ ecc_dec_in[080] ^
                        ecc_dec_in[081] ^ ecc_dec_in[082] ^ ecc_dec_in[083] ^
                        ecc_dec_in[084] ^ ecc_dec_in[085] ^ ecc_dec_in[086] ^
                        ecc_dec_in[087] ^ ecc_dec_in[088] ^ ecc_dec_in[089] ^
                        ecc_dec_in[090] ^ ecc_dec_in[091] ^ ecc_dec_in[092] ^
                        ecc_dec_in[093] ^ ecc_dec_in[094] ^ ecc_dec_in[095] ^
                        ecc_dec_in[096] ^ ecc_dec_in[097] ^ ecc_dec_in[098] ^
                        ecc_dec_in[099] ^ ecc_dec_in[148] ^ ecc_dec_in[149] ^
                        ecc_dec_in[150] ^ ecc_dec_in[151] ^ ecc_dec_in[152] ^
                        ecc_dec_in[153] ^ ecc_dec_in[154] ^ ecc_dec_in[155] ^
                        ecc_dec_in[156] ^ ecc_dec_in[157] ^ ecc_dec_in[158] ^
                        ecc_dec_in[159] ^ ecc_dec_in[160] ^ ecc_dec_in[161] ^
                        ecc_dec_in[162] ^ ecc_dec_in[163] ^ ecc_dec_in[164] ^
                        ecc_dec_in[165] ^ ecc_dec_in[166] ^ ecc_dec_in[167] ^
                        ecc_dec_in[168] ^ ecc_dec_in[169] ^ ecc_dec_in[170] ^
                        ecc_dec_in[171] ^ ecc_dec_in[172] ^ ecc_dec_in[173] ^
                        ecc_dec_in[174] ^ ecc_dec_in[175] ^ ecc_dec_in[176] ^
                        ecc_dec_in[177] ^ ecc_dec_in[178] ^ ecc_dec_in[179] ^
                        ecc_dec_in[180] ^ ecc_dec_in[181] ^ ecc_dec_in[231] ^
                        ecc_dec_in[232] ^ ecc_dec_in[233] ^ ecc_dec_in[234] ^
                        ecc_dec_in[235] ^ ecc_dec_in[236] ^ ecc_dec_in[237] ^
                        ecc_dec_in[238] ^ ecc_dec_in[239] ^ ecc_dec_in[240] ^
                        ecc_dec_in[241] ^ ecc_dec_in[242] ^ ecc_dec_in[243] ^
                        ecc_dec_in[244] ^ ecc_dec_in[245] ^ ecc_dec_in[246] ^
                        ecc_dec_in[247] ^ ecc_dec_in[248] ^ ecc_dec_in[249] ^
                        ecc_dec_in[250] ^ ecc_dec_in[251] ^ ecc_dec_in[252] ^
                        ecc_dec_in[253] ^ ecc_dec_in[254] ^ ecc_dec_in[255] ^
                        ecc_dec_in[256] ^ ecc_dec_in[257] ^ ecc_dec_in[258] ^
                        ecc_dec_in[259] ^ ecc_dec_in[260] ^ ecc_dec_in[261] ^
                        ecc_dec_in[262] ^ ecc_dec_in[263] ^ ecc_dec_in[298] ^
                        ecc_dec_in[299] ^ ecc_dec_in[300] ^ ecc_dec_in[301] ^
                        ecc_dec_in[302] ^ ecc_dec_in[303] ^ ecc_dec_in[304] ^
                        ecc_dec_in[305] ^ ecc_dec_in[306] ^ ecc_dec_in[307] ^
                        ecc_dec_in[308] ^ ecc_dec_in[309] ^ ecc_dec_in[310] ^
                        ecc_dec_in[311] ^ ecc_dec_in[312] ^ ecc_dec_in[313] ^
                        ecc_dec_in[314] ^ ecc_dec_in[315] ^ ecc_dec_in[316] ^
                        ecc_dec_in[365] ^ ecc_dec_in[366] ^ ecc_dec_in[367] ^
                        ecc_dec_in[368] ^ ecc_dec_in[369] ^ ecc_dec_in[370] ^
                        ecc_dec_in[371] ^ ecc_dec_in[372] ^ ecc_dec_in[373] ^
                        ecc_dec_in[374] ^ ecc_dec_in[375] ^ ecc_dec_in[376] ^
                        ecc_dec_in[377] ^ ecc_dec_in[378] ^ ecc_dec_in[379] ^
                        ecc_dec_in[380] ^ ecc_dec_in[381] ^ ecc_dec_in[382] ^
                        ecc_dec_in[383] ^ ecc_dec_in[384] ^ ecc_dec_in[385] ^
                        ecc_dec_in[386] ^ ecc_dec_in[387] ^ ecc_dec_in[388] ^
                        ecc_dec_in[389] ^ ecc_dec_in[390] ^ ecc_dec_in[391] ^
                        ecc_dec_in[392] ^ ecc_dec_in[393] ^ ecc_dec_in[394] ^
                        ecc_dec_in[395] ^ ecc_dec_in[396] ^ ecc_dec_in[397] ^
                        ecc_dec_in[398] ^ ecc_dec_in[433] ^ ecc_dec_in[434] ^
                        ecc_dec_in[435] ^ ecc_dec_in[436] ^ ecc_dec_in[437] ^
                        ecc_dec_in[438] ^ ecc_dec_in[439] ^ ecc_dec_in[440] ^
                        ecc_dec_in[441] ^ ecc_dec_in[442] ^ ecc_dec_in[443] ^
                        ecc_dec_in[444] ^ ecc_dec_in[445] ^ ecc_dec_in[446] ^
                        ecc_dec_in[447] ^ ecc_dec_in[448] ^ ecc_dec_in[449] ^
                        ecc_dec_in[450] ^ ecc_dec_in[451] ^ ecc_dec_in[487] ^
                        ecc_dec_in[488] ^ ecc_dec_in[489] ^ ecc_dec_in[490] ^
                        ecc_dec_in[491] ^ ecc_dec_in[492] ^ ecc_dec_in[493] ^
                        ecc_dec_in[494] ^ ecc_dec_in[495] ^ ecc_dec_in[496] ^
                        ecc_dec_in[497] ^ ecc_dec_in[498] ^ ecc_dec_in[499] ^
                        ecc_dec_in[500] ^ ecc_dec_in[501] ^ ecc_dec_in[502] ^
                        ecc_dec_in[503] ^ ecc_dec_in[504] ^ ecc_dec_in[523] ^
                        ecc_dec_in[524] ^ ecc_dec_in[525] ^ ecc_dec_in[526] ^
                        ecc_dec_in[534]) ;
assign syndrom[08] = ~( ecc_dec_in[100] ^ ecc_dec_in[101] ^ ecc_dec_in[102] ^
                        ecc_dec_in[103] ^ ecc_dec_in[104] ^ ecc_dec_in[105] ^
                        ecc_dec_in[106] ^ ecc_dec_in[107] ^ ecc_dec_in[108] ^
                        ecc_dec_in[109] ^ ecc_dec_in[110] ^ ecc_dec_in[111] ^
                        ecc_dec_in[112] ^ ecc_dec_in[113] ^ ecc_dec_in[114] ^
                        ecc_dec_in[115] ^ ecc_dec_in[116] ^ ecc_dec_in[117] ^
                        ecc_dec_in[118] ^ ecc_dec_in[119] ^ ecc_dec_in[120] ^
                        ecc_dec_in[121] ^ ecc_dec_in[122] ^ ecc_dec_in[123] ^
                        ecc_dec_in[124] ^ ecc_dec_in[125] ^ ecc_dec_in[126] ^
                        ecc_dec_in[127] ^ ecc_dec_in[128] ^ ecc_dec_in[129] ^
                        ecc_dec_in[130] ^ ecc_dec_in[131] ^ ecc_dec_in[132] ^
                        ecc_dec_in[133] ^ ecc_dec_in[134] ^ ecc_dec_in[135] ^
                        ecc_dec_in[136] ^ ecc_dec_in[137] ^ ecc_dec_in[138] ^
                        ecc_dec_in[139] ^ ecc_dec_in[140] ^ ecc_dec_in[141] ^
                        ecc_dec_in[142] ^ ecc_dec_in[143] ^ ecc_dec_in[144] ^
                        ecc_dec_in[145] ^ ecc_dec_in[146] ^ ecc_dec_in[147] ^
                        ecc_dec_in[148] ^ ecc_dec_in[149] ^ ecc_dec_in[150] ^
                        ecc_dec_in[151] ^ ecc_dec_in[152] ^ ecc_dec_in[153] ^
                        ecc_dec_in[154] ^ ecc_dec_in[155] ^ ecc_dec_in[156] ^
                        ecc_dec_in[157] ^ ecc_dec_in[158] ^ ecc_dec_in[159] ^
                        ecc_dec_in[160] ^ ecc_dec_in[161] ^ ecc_dec_in[162] ^
                        ecc_dec_in[163] ^ ecc_dec_in[164] ^ ecc_dec_in[165] ^
                        ecc_dec_in[166] ^ ecc_dec_in[167] ^ ecc_dec_in[168] ^
                        ecc_dec_in[169] ^ ecc_dec_in[170] ^ ecc_dec_in[171] ^
                        ecc_dec_in[172] ^ ecc_dec_in[173] ^ ecc_dec_in[174] ^
                        ecc_dec_in[175] ^ ecc_dec_in[176] ^ ecc_dec_in[177] ^
                        ecc_dec_in[178] ^ ecc_dec_in[179] ^ ecc_dec_in[180] ^
                        ecc_dec_in[181] ^ ecc_dec_in[264] ^ ecc_dec_in[265] ^
                        ecc_dec_in[266] ^ ecc_dec_in[267] ^ ecc_dec_in[268] ^
                        ecc_dec_in[269] ^ ecc_dec_in[270] ^ ecc_dec_in[271] ^
                        ecc_dec_in[272] ^ ecc_dec_in[273] ^ ecc_dec_in[274] ^
                        ecc_dec_in[275] ^ ecc_dec_in[276] ^ ecc_dec_in[277] ^
                        ecc_dec_in[278] ^ ecc_dec_in[279] ^ ecc_dec_in[280] ^
                        ecc_dec_in[281] ^ ecc_dec_in[282] ^ ecc_dec_in[283] ^
                        ecc_dec_in[284] ^ ecc_dec_in[285] ^ ecc_dec_in[286] ^
                        ecc_dec_in[287] ^ ecc_dec_in[288] ^ ecc_dec_in[289] ^
                        ecc_dec_in[290] ^ ecc_dec_in[291] ^ ecc_dec_in[292] ^
                        ecc_dec_in[293] ^ ecc_dec_in[294] ^ ecc_dec_in[295] ^
                        ecc_dec_in[296] ^ ecc_dec_in[297] ^ ecc_dec_in[298] ^
                        ecc_dec_in[299] ^ ecc_dec_in[300] ^ ecc_dec_in[301] ^
                        ecc_dec_in[302] ^ ecc_dec_in[303] ^ ecc_dec_in[304] ^
                        ecc_dec_in[305] ^ ecc_dec_in[306] ^ ecc_dec_in[307] ^
                        ecc_dec_in[308] ^ ecc_dec_in[309] ^ ecc_dec_in[310] ^
                        ecc_dec_in[311] ^ ecc_dec_in[312] ^ ecc_dec_in[313] ^
                        ecc_dec_in[314] ^ ecc_dec_in[315] ^ ecc_dec_in[316] ^
                        ecc_dec_in[399] ^ ecc_dec_in[400] ^ ecc_dec_in[401] ^
                        ecc_dec_in[402] ^ ecc_dec_in[403] ^ ecc_dec_in[404] ^
                        ecc_dec_in[405] ^ ecc_dec_in[406] ^ ecc_dec_in[407] ^
                        ecc_dec_in[408] ^ ecc_dec_in[409] ^ ecc_dec_in[410] ^
                        ecc_dec_in[411] ^ ecc_dec_in[412] ^ ecc_dec_in[413] ^
                        ecc_dec_in[414] ^ ecc_dec_in[415] ^ ecc_dec_in[416] ^
                        ecc_dec_in[417] ^ ecc_dec_in[418] ^ ecc_dec_in[419] ^
                        ecc_dec_in[420] ^ ecc_dec_in[421] ^ ecc_dec_in[422] ^
                        ecc_dec_in[423] ^ ecc_dec_in[424] ^ ecc_dec_in[425] ^
                        ecc_dec_in[426] ^ ecc_dec_in[427] ^ ecc_dec_in[428] ^
                        ecc_dec_in[429] ^ ecc_dec_in[430] ^ ecc_dec_in[431] ^
                        ecc_dec_in[432] ^ ecc_dec_in[433] ^ ecc_dec_in[434] ^
                        ecc_dec_in[435] ^ ecc_dec_in[436] ^ ecc_dec_in[437] ^
                        ecc_dec_in[438] ^ ecc_dec_in[439] ^ ecc_dec_in[440] ^
                        ecc_dec_in[441] ^ ecc_dec_in[442] ^ ecc_dec_in[443] ^
                        ecc_dec_in[444] ^ ecc_dec_in[445] ^ ecc_dec_in[446] ^
                        ecc_dec_in[447] ^ ecc_dec_in[448] ^ ecc_dec_in[449] ^
                        ecc_dec_in[450] ^ ecc_dec_in[451] ^ ecc_dec_in[505] ^
                        ecc_dec_in[506] ^ ecc_dec_in[507] ^ ecc_dec_in[508] ^
                        ecc_dec_in[509] ^ ecc_dec_in[510] ^ ecc_dec_in[511] ^
                        ecc_dec_in[512] ^ ecc_dec_in[513] ^ ecc_dec_in[514] ^
                        ecc_dec_in[515] ^ ecc_dec_in[516] ^ ecc_dec_in[517] ^
                        ecc_dec_in[518] ^ ecc_dec_in[519] ^ ecc_dec_in[520] ^
                        ecc_dec_in[521] ^ ecc_dec_in[522] ^ ecc_dec_in[523] ^
                        ecc_dec_in[524] ^ ecc_dec_in[525] ^ ecc_dec_in[526] ^
                        ecc_dec_in[535]) ;
assign syndrom[09] = ~( ecc_dec_in[182] ^ ecc_dec_in[183] ^ ecc_dec_in[184] ^
                        ecc_dec_in[185] ^ ecc_dec_in[186] ^ ecc_dec_in[187] ^
                        ecc_dec_in[188] ^ ecc_dec_in[189] ^ ecc_dec_in[190] ^
                        ecc_dec_in[191] ^ ecc_dec_in[192] ^ ecc_dec_in[193] ^
                        ecc_dec_in[194] ^ ecc_dec_in[195] ^ ecc_dec_in[196] ^
                        ecc_dec_in[197] ^ ecc_dec_in[198] ^ ecc_dec_in[199] ^
                        ecc_dec_in[200] ^ ecc_dec_in[201] ^ ecc_dec_in[202] ^
                        ecc_dec_in[203] ^ ecc_dec_in[204] ^ ecc_dec_in[205] ^
                        ecc_dec_in[206] ^ ecc_dec_in[207] ^ ecc_dec_in[208] ^
                        ecc_dec_in[209] ^ ecc_dec_in[210] ^ ecc_dec_in[211] ^
                        ecc_dec_in[212] ^ ecc_dec_in[213] ^ ecc_dec_in[214] ^
                        ecc_dec_in[215] ^ ecc_dec_in[216] ^ ecc_dec_in[217] ^
                        ecc_dec_in[218] ^ ecc_dec_in[219] ^ ecc_dec_in[220] ^
                        ecc_dec_in[221] ^ ecc_dec_in[222] ^ ecc_dec_in[223] ^
                        ecc_dec_in[224] ^ ecc_dec_in[225] ^ ecc_dec_in[226] ^
                        ecc_dec_in[227] ^ ecc_dec_in[228] ^ ecc_dec_in[229] ^
                        ecc_dec_in[230] ^ ecc_dec_in[231] ^ ecc_dec_in[232] ^
                        ecc_dec_in[233] ^ ecc_dec_in[234] ^ ecc_dec_in[235] ^
                        ecc_dec_in[236] ^ ecc_dec_in[237] ^ ecc_dec_in[238] ^
                        ecc_dec_in[239] ^ ecc_dec_in[240] ^ ecc_dec_in[241] ^
                        ecc_dec_in[242] ^ ecc_dec_in[243] ^ ecc_dec_in[244] ^
                        ecc_dec_in[245] ^ ecc_dec_in[246] ^ ecc_dec_in[247] ^
                        ecc_dec_in[248] ^ ecc_dec_in[249] ^ ecc_dec_in[250] ^
                        ecc_dec_in[251] ^ ecc_dec_in[252] ^ ecc_dec_in[253] ^
                        ecc_dec_in[254] ^ ecc_dec_in[255] ^ ecc_dec_in[256] ^
                        ecc_dec_in[257] ^ ecc_dec_in[258] ^ ecc_dec_in[259] ^
                        ecc_dec_in[260] ^ ecc_dec_in[261] ^ ecc_dec_in[262] ^
                        ecc_dec_in[263] ^ ecc_dec_in[264] ^ ecc_dec_in[265] ^
                        ecc_dec_in[266] ^ ecc_dec_in[267] ^ ecc_dec_in[268] ^
                        ecc_dec_in[269] ^ ecc_dec_in[270] ^ ecc_dec_in[271] ^
                        ecc_dec_in[272] ^ ecc_dec_in[273] ^ ecc_dec_in[274] ^
                        ecc_dec_in[275] ^ ecc_dec_in[276] ^ ecc_dec_in[277] ^
                        ecc_dec_in[278] ^ ecc_dec_in[279] ^ ecc_dec_in[280] ^
                        ecc_dec_in[281] ^ ecc_dec_in[282] ^ ecc_dec_in[283] ^
                        ecc_dec_in[284] ^ ecc_dec_in[285] ^ ecc_dec_in[286] ^
                        ecc_dec_in[287] ^ ecc_dec_in[288] ^ ecc_dec_in[289] ^
                        ecc_dec_in[290] ^ ecc_dec_in[291] ^ ecc_dec_in[292] ^
                        ecc_dec_in[293] ^ ecc_dec_in[294] ^ ecc_dec_in[295] ^
                        ecc_dec_in[296] ^ ecc_dec_in[297] ^ ecc_dec_in[298] ^
                        ecc_dec_in[299] ^ ecc_dec_in[300] ^ ecc_dec_in[301] ^
                        ecc_dec_in[302] ^ ecc_dec_in[303] ^ ecc_dec_in[304] ^
                        ecc_dec_in[305] ^ ecc_dec_in[306] ^ ecc_dec_in[307] ^
                        ecc_dec_in[308] ^ ecc_dec_in[309] ^ ecc_dec_in[310] ^
                        ecc_dec_in[311] ^ ecc_dec_in[312] ^ ecc_dec_in[313] ^
                        ecc_dec_in[314] ^ ecc_dec_in[315] ^ ecc_dec_in[316] ^
                        ecc_dec_in[452] ^ ecc_dec_in[453] ^ ecc_dec_in[454] ^
                        ecc_dec_in[455] ^ ecc_dec_in[456] ^ ecc_dec_in[457] ^
                        ecc_dec_in[458] ^ ecc_dec_in[459] ^ ecc_dec_in[460] ^
                        ecc_dec_in[461] ^ ecc_dec_in[462] ^ ecc_dec_in[463] ^
                        ecc_dec_in[464] ^ ecc_dec_in[465] ^ ecc_dec_in[466] ^
                        ecc_dec_in[467] ^ ecc_dec_in[468] ^ ecc_dec_in[469] ^
                        ecc_dec_in[470] ^ ecc_dec_in[471] ^ ecc_dec_in[472] ^
                        ecc_dec_in[473] ^ ecc_dec_in[474] ^ ecc_dec_in[475] ^
                        ecc_dec_in[476] ^ ecc_dec_in[477] ^ ecc_dec_in[478] ^
                        ecc_dec_in[479] ^ ecc_dec_in[480] ^ ecc_dec_in[481] ^
                        ecc_dec_in[482] ^ ecc_dec_in[483] ^ ecc_dec_in[484] ^
                        ecc_dec_in[485] ^ ecc_dec_in[486] ^ ecc_dec_in[487] ^
                        ecc_dec_in[488] ^ ecc_dec_in[489] ^ ecc_dec_in[490] ^
                        ecc_dec_in[491] ^ ecc_dec_in[492] ^ ecc_dec_in[493] ^
                        ecc_dec_in[494] ^ ecc_dec_in[495] ^ ecc_dec_in[496] ^
                        ecc_dec_in[497] ^ ecc_dec_in[498] ^ ecc_dec_in[499] ^
                        ecc_dec_in[500] ^ ecc_dec_in[501] ^ ecc_dec_in[502] ^
                        ecc_dec_in[503] ^ ecc_dec_in[504] ^ ecc_dec_in[505] ^
                        ecc_dec_in[506] ^ ecc_dec_in[507] ^ ecc_dec_in[508] ^
                        ecc_dec_in[509] ^ ecc_dec_in[510] ^ ecc_dec_in[511] ^
                        ecc_dec_in[512] ^ ecc_dec_in[513] ^ ecc_dec_in[514] ^
                        ecc_dec_in[515] ^ ecc_dec_in[516] ^ ecc_dec_in[517] ^
                        ecc_dec_in[518] ^ ecc_dec_in[519] ^ ecc_dec_in[520] ^
                        ecc_dec_in[521] ^ ecc_dec_in[522] ^ ecc_dec_in[523] ^
                        ecc_dec_in[524] ^ ecc_dec_in[525] ^ ecc_dec_in[526] ^
                        ecc_dec_in[536]) ;
assign syndrom[10] = ~( ecc_dec_in[317] ^ ecc_dec_in[318] ^ ecc_dec_in[319] ^
                        ecc_dec_in[320] ^ ecc_dec_in[321] ^ ecc_dec_in[322] ^
                        ecc_dec_in[323] ^ ecc_dec_in[324] ^ ecc_dec_in[325] ^
                        ecc_dec_in[326] ^ ecc_dec_in[327] ^ ecc_dec_in[328] ^
                        ecc_dec_in[329] ^ ecc_dec_in[330] ^ ecc_dec_in[331] ^
                        ecc_dec_in[332] ^ ecc_dec_in[333] ^ ecc_dec_in[334] ^
                        ecc_dec_in[335] ^ ecc_dec_in[336] ^ ecc_dec_in[337] ^
                        ecc_dec_in[338] ^ ecc_dec_in[339] ^ ecc_dec_in[340] ^
                        ecc_dec_in[341] ^ ecc_dec_in[342] ^ ecc_dec_in[343] ^
                        ecc_dec_in[344] ^ ecc_dec_in[345] ^ ecc_dec_in[346] ^
                        ecc_dec_in[347] ^ ecc_dec_in[348] ^ ecc_dec_in[349] ^
                        ecc_dec_in[350] ^ ecc_dec_in[351] ^ ecc_dec_in[352] ^
                        ecc_dec_in[353] ^ ecc_dec_in[354] ^ ecc_dec_in[355] ^
                        ecc_dec_in[356] ^ ecc_dec_in[357] ^ ecc_dec_in[358] ^
                        ecc_dec_in[359] ^ ecc_dec_in[360] ^ ecc_dec_in[361] ^
                        ecc_dec_in[362] ^ ecc_dec_in[363] ^ ecc_dec_in[364] ^
                        ecc_dec_in[365] ^ ecc_dec_in[366] ^ ecc_dec_in[367] ^
                        ecc_dec_in[368] ^ ecc_dec_in[369] ^ ecc_dec_in[370] ^
                        ecc_dec_in[371] ^ ecc_dec_in[372] ^ ecc_dec_in[373] ^
                        ecc_dec_in[374] ^ ecc_dec_in[375] ^ ecc_dec_in[376] ^
                        ecc_dec_in[377] ^ ecc_dec_in[378] ^ ecc_dec_in[379] ^
                        ecc_dec_in[380] ^ ecc_dec_in[381] ^ ecc_dec_in[382] ^
                        ecc_dec_in[383] ^ ecc_dec_in[384] ^ ecc_dec_in[385] ^
                        ecc_dec_in[386] ^ ecc_dec_in[387] ^ ecc_dec_in[388] ^
                        ecc_dec_in[389] ^ ecc_dec_in[390] ^ ecc_dec_in[391] ^
                        ecc_dec_in[392] ^ ecc_dec_in[393] ^ ecc_dec_in[394] ^
                        ecc_dec_in[395] ^ ecc_dec_in[396] ^ ecc_dec_in[397] ^
                        ecc_dec_in[398] ^ ecc_dec_in[399] ^ ecc_dec_in[400] ^
                        ecc_dec_in[401] ^ ecc_dec_in[402] ^ ecc_dec_in[403] ^
                        ecc_dec_in[404] ^ ecc_dec_in[405] ^ ecc_dec_in[406] ^
                        ecc_dec_in[407] ^ ecc_dec_in[408] ^ ecc_dec_in[409] ^
                        ecc_dec_in[410] ^ ecc_dec_in[411] ^ ecc_dec_in[412] ^
                        ecc_dec_in[413] ^ ecc_dec_in[414] ^ ecc_dec_in[415] ^
                        ecc_dec_in[416] ^ ecc_dec_in[417] ^ ecc_dec_in[418] ^
                        ecc_dec_in[419] ^ ecc_dec_in[420] ^ ecc_dec_in[421] ^
                        ecc_dec_in[422] ^ ecc_dec_in[423] ^ ecc_dec_in[424] ^
                        ecc_dec_in[425] ^ ecc_dec_in[426] ^ ecc_dec_in[427] ^
                        ecc_dec_in[428] ^ ecc_dec_in[429] ^ ecc_dec_in[430] ^
                        ecc_dec_in[431] ^ ecc_dec_in[432] ^ ecc_dec_in[433] ^
                        ecc_dec_in[434] ^ ecc_dec_in[435] ^ ecc_dec_in[436] ^
                        ecc_dec_in[437] ^ ecc_dec_in[438] ^ ecc_dec_in[439] ^
                        ecc_dec_in[440] ^ ecc_dec_in[441] ^ ecc_dec_in[442] ^
                        ecc_dec_in[443] ^ ecc_dec_in[444] ^ ecc_dec_in[445] ^
                        ecc_dec_in[446] ^ ecc_dec_in[447] ^ ecc_dec_in[448] ^
                        ecc_dec_in[449] ^ ecc_dec_in[450] ^ ecc_dec_in[451] ^
                        ecc_dec_in[452] ^ ecc_dec_in[453] ^ ecc_dec_in[454] ^
                        ecc_dec_in[455] ^ ecc_dec_in[456] ^ ecc_dec_in[457] ^
                        ecc_dec_in[458] ^ ecc_dec_in[459] ^ ecc_dec_in[460] ^
                        ecc_dec_in[461] ^ ecc_dec_in[462] ^ ecc_dec_in[463] ^
                        ecc_dec_in[464] ^ ecc_dec_in[465] ^ ecc_dec_in[466] ^
                        ecc_dec_in[467] ^ ecc_dec_in[468] ^ ecc_dec_in[469] ^
                        ecc_dec_in[470] ^ ecc_dec_in[471] ^ ecc_dec_in[472] ^
                        ecc_dec_in[473] ^ ecc_dec_in[474] ^ ecc_dec_in[475] ^
                        ecc_dec_in[476] ^ ecc_dec_in[477] ^ ecc_dec_in[478] ^
                        ecc_dec_in[479] ^ ecc_dec_in[480] ^ ecc_dec_in[481] ^
                        ecc_dec_in[482] ^ ecc_dec_in[483] ^ ecc_dec_in[484] ^
                        ecc_dec_in[485] ^ ecc_dec_in[486] ^ ecc_dec_in[487] ^
                        ecc_dec_in[488] ^ ecc_dec_in[489] ^ ecc_dec_in[490] ^
                        ecc_dec_in[491] ^ ecc_dec_in[492] ^ ecc_dec_in[493] ^
                        ecc_dec_in[494] ^ ecc_dec_in[495] ^ ecc_dec_in[496] ^
                        ecc_dec_in[497] ^ ecc_dec_in[498] ^ ecc_dec_in[499] ^
                        ecc_dec_in[500] ^ ecc_dec_in[501] ^ ecc_dec_in[502] ^
                        ecc_dec_in[503] ^ ecc_dec_in[504] ^ ecc_dec_in[505] ^
                        ecc_dec_in[506] ^ ecc_dec_in[507] ^ ecc_dec_in[508] ^
                        ecc_dec_in[509] ^ ecc_dec_in[510] ^ ecc_dec_in[511] ^
                        ecc_dec_in[512] ^ ecc_dec_in[513] ^ ecc_dec_in[514] ^
                        ecc_dec_in[515] ^ ecc_dec_in[516] ^ ecc_dec_in[517] ^
                        ecc_dec_in[518] ^ ecc_dec_in[519] ^ ecc_dec_in[520] ^
                        ecc_dec_in[521] ^ ecc_dec_in[522] ^ ecc_dec_in[523] ^
                        ecc_dec_in[524] ^ ecc_dec_in[525] ^ ecc_dec_in[526] ^
                        ecc_dec_in[537]) ;

//Decoded Error Bit Position

always	@(*)
begin
corrected_bit_p[526] = syndrom == 1952;
corrected_bit_p[525] = syndrom == 1928;
corrected_bit_p[524] = syndrom == 1924;
corrected_bit_p[523] = syndrom == 1921;
corrected_bit_p[522] = syndrom == 1888;
corrected_bit_p[521] = syndrom == 1864;
corrected_bit_p[520] = syndrom == 1860;
corrected_bit_p[519] = syndrom == 1858;
corrected_bit_p[518] = syndrom == 1857;
corrected_bit_p[517] = syndrom == 1840;
corrected_bit_p[516] = syndrom == 1832;
corrected_bit_p[515] = syndrom == 1828;
corrected_bit_p[514] = syndrom == 1826;
corrected_bit_p[513] = syndrom == 1816;
corrected_bit_p[512] = syndrom == 1810;
corrected_bit_p[511] = syndrom == 1809;
corrected_bit_p[510] = syndrom == 1804;
corrected_bit_p[509] = syndrom == 1802;
corrected_bit_p[508] = syndrom == 1798;
corrected_bit_p[507] = syndrom == 1797;
corrected_bit_p[506] = syndrom == 1795;
corrected_bit_p[505] = syndrom == 1792;
corrected_bit_p[504] = syndrom == 1760;
corrected_bit_p[503] = syndrom == 1744;
corrected_bit_p[502] = syndrom == 1736;
corrected_bit_p[501] = syndrom == 1732;
corrected_bit_p[500] = syndrom == 1730;
corrected_bit_p[499] = syndrom == 1729;
corrected_bit_p[498] = syndrom == 1712;
corrected_bit_p[497] = syndrom == 1704;
corrected_bit_p[496] = syndrom == 1700;
corrected_bit_p[495] = syndrom == 1698;
corrected_bit_p[494] = syndrom == 1684;
corrected_bit_p[493] = syndrom == 1682;
corrected_bit_p[492] = syndrom == 1681;
corrected_bit_p[491] = syndrom == 1676;
corrected_bit_p[490] = syndrom == 1673;
corrected_bit_p[489] = syndrom == 1670;
corrected_bit_p[488] = syndrom == 1669;
corrected_bit_p[487] = syndrom == 1664;
corrected_bit_p[486] = syndrom == 1648;
corrected_bit_p[485] = syndrom == 1640;
corrected_bit_p[484] = syndrom == 1634;
corrected_bit_p[483] = syndrom == 1633;
corrected_bit_p[482] = syndrom == 1624;
corrected_bit_p[481] = syndrom == 1620;
corrected_bit_p[480] = syndrom == 1618;
corrected_bit_p[479] = syndrom == 1617;
corrected_bit_p[478] = syndrom == 1610;
corrected_bit_p[477] = syndrom == 1609;
corrected_bit_p[476] = syndrom == 1605;
corrected_bit_p[475] = syndrom == 1600;
corrected_bit_p[474] = syndrom == 1592;
corrected_bit_p[473] = syndrom == 1586;
corrected_bit_p[472] = syndrom == 1585;
corrected_bit_p[471] = syndrom == 1580;
corrected_bit_p[470] = syndrom == 1578;
corrected_bit_p[469] = syndrom == 1574;
corrected_bit_p[468] = syndrom == 1573;
corrected_bit_p[467] = syndrom == 1571;
corrected_bit_p[466] = syndrom == 1568;
corrected_bit_p[465] = syndrom == 1564;
corrected_bit_p[464] = syndrom == 1562;
corrected_bit_p[463] = syndrom == 1561;
corrected_bit_p[462] = syndrom == 1558;
corrected_bit_p[461] = syndrom == 1557;
corrected_bit_p[460] = syndrom == 1552;
corrected_bit_p[459] = syndrom == 1550;
corrected_bit_p[458] = syndrom == 1549;
corrected_bit_p[457] = syndrom == 1547;
corrected_bit_p[456] = syndrom == 1544;
corrected_bit_p[455] = syndrom == 1543;
corrected_bit_p[454] = syndrom == 1540;
corrected_bit_p[453] = syndrom == 1538;
corrected_bit_p[452] = syndrom == 1537;
corrected_bit_p[451] = syndrom == 1488;
corrected_bit_p[450] = syndrom == 1480;
corrected_bit_p[449] = syndrom == 1474;
corrected_bit_p[448] = syndrom == 1473;
corrected_bit_p[447] = syndrom == 1456;
corrected_bit_p[446] = syndrom == 1448;
corrected_bit_p[445] = syndrom == 1444;
corrected_bit_p[444] = syndrom == 1442;
corrected_bit_p[443] = syndrom == 1441;
corrected_bit_p[442] = syndrom == 1432;
corrected_bit_p[441] = syndrom == 1428;
corrected_bit_p[440] = syndrom == 1426;
corrected_bit_p[439] = syndrom == 1425;
corrected_bit_p[438] = syndrom == 1420;
corrected_bit_p[437] = syndrom == 1418;
corrected_bit_p[436] = syndrom == 1417;
corrected_bit_p[435] = syndrom == 1414;
corrected_bit_p[434] = syndrom == 1411;
corrected_bit_p[433] = syndrom == 1408;
corrected_bit_p[432] = syndrom == 1392;
corrected_bit_p[431] = syndrom == 1384;
corrected_bit_p[430] = syndrom == 1380;
corrected_bit_p[429] = syndrom == 1378;
corrected_bit_p[428] = syndrom == 1377;
corrected_bit_p[427] = syndrom == 1364;
corrected_bit_p[426] = syndrom == 1362;
corrected_bit_p[425] = syndrom == 1361;
corrected_bit_p[424] = syndrom == 1356;
corrected_bit_p[423] = syndrom == 1354;
corrected_bit_p[422] = syndrom == 1353;
corrected_bit_p[421] = syndrom == 1350;
corrected_bit_p[420] = syndrom == 1347;
corrected_bit_p[419] = syndrom == 1344;
corrected_bit_p[418] = syndrom == 1332;
corrected_bit_p[417] = syndrom == 1329;
corrected_bit_p[416] = syndrom == 1324;
corrected_bit_p[415] = syndrom == 1321;
corrected_bit_p[414] = syndrom == 1317;
corrected_bit_p[413] = syndrom == 1315;
corrected_bit_p[412] = syndrom == 1312;
corrected_bit_p[411] = syndrom == 1308;
corrected_bit_p[410] = syndrom == 1306;
corrected_bit_p[409] = syndrom == 1305;
corrected_bit_p[408] = syndrom == 1302;
corrected_bit_p[407] = syndrom == 1301;
corrected_bit_p[406] = syndrom == 1299;
corrected_bit_p[405] = syndrom == 1296;
corrected_bit_p[404] = syndrom == 1291;
corrected_bit_p[403] = syndrom == 1288;
corrected_bit_p[402] = syndrom == 1287;
corrected_bit_p[401] = syndrom == 1284;
corrected_bit_p[400] = syndrom == 1282;
corrected_bit_p[399] = syndrom == 1281;
corrected_bit_p[398] = syndrom == 1256;
corrected_bit_p[397] = syndrom == 1252;
corrected_bit_p[396] = syndrom == 1250;
corrected_bit_p[395] = syndrom == 1249;
corrected_bit_p[394] = syndrom == 1236;
corrected_bit_p[393] = syndrom == 1234;
corrected_bit_p[392] = syndrom == 1233;
corrected_bit_p[391] = syndrom == 1228;
corrected_bit_p[390] = syndrom == 1222;
corrected_bit_p[389] = syndrom == 1221;
corrected_bit_p[388] = syndrom == 1219;
corrected_bit_p[387] = syndrom == 1216;
corrected_bit_p[386] = syndrom == 1208;
corrected_bit_p[385] = syndrom == 1204;
corrected_bit_p[384] = syndrom == 1202;
corrected_bit_p[383] = syndrom == 1201;
corrected_bit_p[382] = syndrom == 1194;
corrected_bit_p[381] = syndrom == 1193;
corrected_bit_p[380] = syndrom == 1189;
corrected_bit_p[379] = syndrom == 1187;
corrected_bit_p[378] = syndrom == 1184;
corrected_bit_p[377] = syndrom == 1180;
corrected_bit_p[376] = syndrom == 1178;
corrected_bit_p[375] = syndrom == 1177;
corrected_bit_p[374] = syndrom == 1174;
corrected_bit_p[373] = syndrom == 1168;
corrected_bit_p[372] = syndrom == 1166;
corrected_bit_p[371] = syndrom == 1165;
corrected_bit_p[370] = syndrom == 1163;
corrected_bit_p[369] = syndrom == 1160;
corrected_bit_p[368] = syndrom == 1159;
corrected_bit_p[367] = syndrom == 1156;
corrected_bit_p[366] = syndrom == 1154;
corrected_bit_p[365] = syndrom == 1153;
corrected_bit_p[364] = syndrom == 1144;
corrected_bit_p[363] = syndrom == 1140;
corrected_bit_p[362] = syndrom == 1138;
corrected_bit_p[361] = syndrom == 1137;
corrected_bit_p[360] = syndrom == 1132;
corrected_bit_p[359] = syndrom == 1126;
corrected_bit_p[358] = syndrom == 1125;
corrected_bit_p[357] = syndrom == 1123;
corrected_bit_p[356] = syndrom == 1120;
corrected_bit_p[355] = syndrom == 1116;
corrected_bit_p[354] = syndrom == 1114;
corrected_bit_p[353] = syndrom == 1113;
corrected_bit_p[352] = syndrom == 1109;
corrected_bit_p[351] = syndrom == 1104;
corrected_bit_p[350] = syndrom == 1102;
corrected_bit_p[349] = syndrom == 1101;
corrected_bit_p[348] = syndrom == 1099;
corrected_bit_p[347] = syndrom == 1096;
corrected_bit_p[346] = syndrom == 1095;
corrected_bit_p[345] = syndrom == 1092;
corrected_bit_p[344] = syndrom == 1090;
corrected_bit_p[343] = syndrom == 1089;
corrected_bit_p[342] = syndrom == 1082;
corrected_bit_p[341] = syndrom == 1081;
corrected_bit_p[340] = syndrom == 1078;
corrected_bit_p[339] = syndrom == 1075;
corrected_bit_p[338] = syndrom == 1072;
corrected_bit_p[337] = syndrom == 1070;
corrected_bit_p[336] = syndrom == 1069;
corrected_bit_p[335] = syndrom == 1067;
corrected_bit_p[334] = syndrom == 1064;
corrected_bit_p[333] = syndrom == 1060;
corrected_bit_p[332] = syndrom == 1058;
corrected_bit_p[331] = syndrom == 1057;
corrected_bit_p[330] = syndrom == 1054;
corrected_bit_p[329] = syndrom == 1053;
corrected_bit_p[328] = syndrom == 1048;
corrected_bit_p[327] = syndrom == 1047;
corrected_bit_p[326] = syndrom == 1044;
corrected_bit_p[325] = syndrom == 1042;
corrected_bit_p[324] = syndrom == 1041;
corrected_bit_p[323] = syndrom == 1039;
corrected_bit_p[322] = syndrom == 1036;
corrected_bit_p[321] = syndrom == 1034;
corrected_bit_p[320] = syndrom == 1033;
corrected_bit_p[319] = syndrom == 1030;
corrected_bit_p[318] = syndrom == 1029;
corrected_bit_p[317] = syndrom == 1027;
corrected_bit_p[316] = syndrom == 992;
corrected_bit_p[315] = syndrom == 976;
corrected_bit_p[314] = syndrom == 968;
corrected_bit_p[313] = syndrom == 964;
corrected_bit_p[312] = syndrom == 962;
corrected_bit_p[311] = syndrom == 961;
corrected_bit_p[310] = syndrom == 944;
corrected_bit_p[309] = syndrom == 932;
corrected_bit_p[308] = syndrom == 930;
corrected_bit_p[307] = syndrom == 929;
corrected_bit_p[306] = syndrom == 920;
corrected_bit_p[305] = syndrom == 914;
corrected_bit_p[304] = syndrom == 913;
corrected_bit_p[303] = syndrom == 908;
corrected_bit_p[302] = syndrom == 906;
corrected_bit_p[301] = syndrom == 902;
corrected_bit_p[300] = syndrom == 901;
corrected_bit_p[299] = syndrom == 899;
corrected_bit_p[298] = syndrom == 896;
corrected_bit_p[297] = syndrom == 880;
corrected_bit_p[296] = syndrom == 868;
corrected_bit_p[295] = syndrom == 866;
corrected_bit_p[294] = syndrom == 865;
corrected_bit_p[293] = syndrom == 856;
corrected_bit_p[292] = syndrom == 850;
corrected_bit_p[291] = syndrom == 849;
corrected_bit_p[290] = syndrom == 844;
corrected_bit_p[289] = syndrom == 842;
corrected_bit_p[288] = syndrom == 841;
corrected_bit_p[287] = syndrom == 835;
corrected_bit_p[286] = syndrom == 832;
corrected_bit_p[285] = syndrom == 824;
corrected_bit_p[284] = syndrom == 820;
corrected_bit_p[283] = syndrom == 817;
corrected_bit_p[282] = syndrom == 812;
corrected_bit_p[281] = syndrom == 810;
corrected_bit_p[280] = syndrom == 809;
corrected_bit_p[279] = syndrom == 806;
corrected_bit_p[278] = syndrom == 803;
corrected_bit_p[277] = syndrom == 800;
corrected_bit_p[276] = syndrom == 796;
corrected_bit_p[275] = syndrom == 794;
corrected_bit_p[274] = syndrom == 790;
corrected_bit_p[273] = syndrom == 789;
corrected_bit_p[272] = syndrom == 787;
corrected_bit_p[271] = syndrom == 784;
corrected_bit_p[270] = syndrom == 782;
corrected_bit_p[269] = syndrom == 781;
corrected_bit_p[268] = syndrom == 779;
corrected_bit_p[267] = syndrom == 776;
corrected_bit_p[266] = syndrom == 772;
corrected_bit_p[265] = syndrom == 770;
corrected_bit_p[264] = syndrom == 769;
corrected_bit_p[263] = syndrom == 752;
corrected_bit_p[262] = syndrom == 744;
corrected_bit_p[261] = syndrom == 740;
corrected_bit_p[260] = syndrom == 738;
corrected_bit_p[259] = syndrom == 737;
corrected_bit_p[258] = syndrom == 728;
corrected_bit_p[257] = syndrom == 724;
corrected_bit_p[256] = syndrom == 722;
corrected_bit_p[255] = syndrom == 721;
corrected_bit_p[254] = syndrom == 716;
corrected_bit_p[253] = syndrom == 710;
corrected_bit_p[252] = syndrom == 709;
corrected_bit_p[251] = syndrom == 707;
corrected_bit_p[250] = syndrom == 704;
corrected_bit_p[249] = syndrom == 696;
corrected_bit_p[248] = syndrom == 690;
corrected_bit_p[247] = syndrom == 689;
corrected_bit_p[246] = syndrom == 684;
corrected_bit_p[245] = syndrom == 682;
corrected_bit_p[244] = syndrom == 677;
corrected_bit_p[243] = syndrom == 672;
corrected_bit_p[242] = syndrom == 668;
corrected_bit_p[241] = syndrom == 665;
corrected_bit_p[240] = syndrom == 662;
corrected_bit_p[239] = syndrom == 661;
corrected_bit_p[238] = syndrom == 656;
corrected_bit_p[237] = syndrom == 653;
corrected_bit_p[236] = syndrom == 651;
corrected_bit_p[235] = syndrom == 648;
corrected_bit_p[234] = syndrom == 647;
corrected_bit_p[233] = syndrom == 644;
corrected_bit_p[232] = syndrom == 642;
corrected_bit_p[231] = syndrom == 641;
corrected_bit_p[230] = syndrom == 628;
corrected_bit_p[229] = syndrom == 626;
corrected_bit_p[228] = syndrom == 620;
corrected_bit_p[227] = syndrom == 618;
corrected_bit_p[226] = syndrom == 617;
corrected_bit_p[225] = syndrom == 613;
corrected_bit_p[224] = syndrom == 608;
corrected_bit_p[223] = syndrom == 602;
corrected_bit_p[222] = syndrom == 601;
corrected_bit_p[221] = syndrom == 598;
corrected_bit_p[220] = syndrom == 597;
corrected_bit_p[219] = syndrom == 592;
corrected_bit_p[218] = syndrom == 590;
corrected_bit_p[217] = syndrom == 589;
corrected_bit_p[216] = syndrom == 587;
corrected_bit_p[215] = syndrom == 584;
corrected_bit_p[214] = syndrom == 583;
corrected_bit_p[213] = syndrom == 580;
corrected_bit_p[212] = syndrom == 578;
corrected_bit_p[211] = syndrom == 577;
corrected_bit_p[210] = syndrom == 572;
corrected_bit_p[209] = syndrom == 570;
corrected_bit_p[208] = syndrom == 569;
corrected_bit_p[207] = syndrom == 566;
corrected_bit_p[206] = syndrom == 565;
corrected_bit_p[205] = syndrom == 563;
corrected_bit_p[204] = syndrom == 560;
corrected_bit_p[203] = syndrom == 558;
corrected_bit_p[202] = syndrom == 557;
corrected_bit_p[201] = syndrom == 555;
corrected_bit_p[200] = syndrom == 552;
corrected_bit_p[199] = syndrom == 551;
corrected_bit_p[198] = syndrom == 548;
corrected_bit_p[197] = syndrom == 546;
corrected_bit_p[196] = syndrom == 545;
corrected_bit_p[195] = syndrom == 542;
corrected_bit_p[194] = syndrom == 541;
corrected_bit_p[193] = syndrom == 539;
corrected_bit_p[192] = syndrom == 536;
corrected_bit_p[191] = syndrom == 535;
corrected_bit_p[190] = syndrom == 532;
corrected_bit_p[189] = syndrom == 530;
corrected_bit_p[188] = syndrom == 529;
corrected_bit_p[187] = syndrom == 524;
corrected_bit_p[186] = syndrom == 522;
corrected_bit_p[185] = syndrom == 521;
corrected_bit_p[184] = syndrom == 518;
corrected_bit_p[183] = syndrom == 517;
corrected_bit_p[182] = syndrom == 515;
corrected_bit_p[181] = syndrom == 496;
corrected_bit_p[180] = syndrom == 488;
corrected_bit_p[179] = syndrom == 484;
corrected_bit_p[178] = syndrom == 482;
corrected_bit_p[177] = syndrom == 468;
corrected_bit_p[176] = syndrom == 466;
corrected_bit_p[175] = syndrom == 460;
corrected_bit_p[174] = syndrom == 458;
corrected_bit_p[173] = syndrom == 457;
corrected_bit_p[172] = syndrom == 454;
corrected_bit_p[171] = syndrom == 451;
corrected_bit_p[170] = syndrom == 448;
corrected_bit_p[169] = syndrom == 440;
corrected_bit_p[168] = syndrom == 436;
corrected_bit_p[167] = syndrom == 433;
corrected_bit_p[166] = syndrom == 428;
corrected_bit_p[165] = syndrom == 426;
corrected_bit_p[164] = syndrom == 422;
corrected_bit_p[163] = syndrom == 419;
corrected_bit_p[162] = syndrom == 416;
corrected_bit_p[161] = syndrom == 412;
corrected_bit_p[160] = syndrom == 410;
corrected_bit_p[159] = syndrom == 409;
corrected_bit_p[158] = syndrom == 406;
corrected_bit_p[157] = syndrom == 405;
corrected_bit_p[156] = syndrom == 403;
corrected_bit_p[155] = syndrom == 400;
corrected_bit_p[154] = syndrom == 397;
corrected_bit_p[153] = syndrom == 395;
corrected_bit_p[152] = syndrom == 392;
corrected_bit_p[151] = syndrom == 391;
corrected_bit_p[150] = syndrom == 388;
corrected_bit_p[149] = syndrom == 386;
corrected_bit_p[148] = syndrom == 385;
corrected_bit_p[147] = syndrom == 376;
corrected_bit_p[146] = syndrom == 372;
corrected_bit_p[145] = syndrom == 370;
corrected_bit_p[144] = syndrom == 369;
corrected_bit_p[143] = syndrom == 361;
corrected_bit_p[142] = syndrom == 358;
corrected_bit_p[141] = syndrom == 357;
corrected_bit_p[140] = syndrom == 355;
corrected_bit_p[139] = syndrom == 352;
corrected_bit_p[138] = syndrom == 348;
corrected_bit_p[137] = syndrom == 346;
corrected_bit_p[136] = syndrom == 345;
corrected_bit_p[135] = syndrom == 341;
corrected_bit_p[134] = syndrom == 339;
corrected_bit_p[133] = syndrom == 336;
corrected_bit_p[132] = syndrom == 334;
corrected_bit_p[131] = syndrom == 333;
corrected_bit_p[130] = syndrom == 331;
corrected_bit_p[129] = syndrom == 328;
corrected_bit_p[128] = syndrom == 324;
corrected_bit_p[127] = syndrom == 322;
corrected_bit_p[126] = syndrom == 321;
corrected_bit_p[125] = syndrom == 316;
corrected_bit_p[124] = syndrom == 314;
corrected_bit_p[123] = syndrom == 313;
corrected_bit_p[122] = syndrom == 310;
corrected_bit_p[121] = syndrom == 309;
corrected_bit_p[120] = syndrom == 304;
corrected_bit_p[119] = syndrom == 301;
corrected_bit_p[118] = syndrom == 299;
corrected_bit_p[117] = syndrom == 296;
corrected_bit_p[116] = syndrom == 295;
corrected_bit_p[115] = syndrom == 292;
corrected_bit_p[114] = syndrom == 290;
corrected_bit_p[113] = syndrom == 289;
corrected_bit_p[112] = syndrom == 286;
corrected_bit_p[111] = syndrom == 283;
corrected_bit_p[110] = syndrom == 280;
corrected_bit_p[109] = syndrom == 276;
corrected_bit_p[108] = syndrom == 274;
corrected_bit_p[107] = syndrom == 273;
corrected_bit_p[106] = syndrom == 271;
corrected_bit_p[105] = syndrom == 268;
corrected_bit_p[104] = syndrom == 266;
corrected_bit_p[103] = syndrom == 265;
corrected_bit_p[102] = syndrom == 262;
corrected_bit_p[101] = syndrom == 261;
corrected_bit_p[100] = syndrom == 259;
corrected_bit_p[99] = syndrom == 248;
corrected_bit_p[98] = syndrom == 241;
corrected_bit_p[97] = syndrom == 236;
corrected_bit_p[96] = syndrom == 234;
corrected_bit_p[95] = syndrom == 233;
corrected_bit_p[94] = syndrom == 230;
corrected_bit_p[93] = syndrom == 229;
corrected_bit_p[92] = syndrom == 227;
corrected_bit_p[91] = syndrom == 224;
corrected_bit_p[90] = syndrom == 220;
corrected_bit_p[89] = syndrom == 218;
corrected_bit_p[88] = syndrom == 214;
corrected_bit_p[87] = syndrom == 213;
corrected_bit_p[86] = syndrom == 211;
corrected_bit_p[85] = syndrom == 208;
corrected_bit_p[84] = syndrom == 206;
corrected_bit_p[83] = syndrom == 205;
corrected_bit_p[82] = syndrom == 200;
corrected_bit_p[81] = syndrom == 199;
corrected_bit_p[80] = syndrom == 196;
corrected_bit_p[79] = syndrom == 194;
corrected_bit_p[78] = syndrom == 193;
corrected_bit_p[77] = syndrom == 186;
corrected_bit_p[76] = syndrom == 185;
corrected_bit_p[75] = syndrom == 182;
corrected_bit_p[74] = syndrom == 181;
corrected_bit_p[73] = syndrom == 179;
corrected_bit_p[72] = syndrom == 176;
corrected_bit_p[71] = syndrom == 174;
corrected_bit_p[70] = syndrom == 173;
corrected_bit_p[69] = syndrom == 171;
corrected_bit_p[68] = syndrom == 168;
corrected_bit_p[67] = syndrom == 167;
corrected_bit_p[66] = syndrom == 164;
corrected_bit_p[65] = syndrom == 162;
corrected_bit_p[64] = syndrom == 161;
corrected_bit_p[63] = syndrom == 157;
corrected_bit_p[62] = syndrom == 152;
corrected_bit_p[61] = syndrom == 151;
corrected_bit_p[60] = syndrom == 148;
corrected_bit_p[59] = syndrom == 146;
corrected_bit_p[58] = syndrom == 145;
corrected_bit_p[57] = syndrom == 143;
corrected_bit_p[56] = syndrom == 140;
corrected_bit_p[55] = syndrom == 138;
corrected_bit_p[54] = syndrom == 137;
corrected_bit_p[53] = syndrom == 134;
corrected_bit_p[52] = syndrom == 133;
corrected_bit_p[51] = syndrom == 131;
corrected_bit_p[50] = syndrom == 124;
corrected_bit_p[49] = syndrom == 122;
corrected_bit_p[48] = syndrom == 118;
corrected_bit_p[47] = syndrom == 115;
corrected_bit_p[46] = syndrom == 112;
corrected_bit_p[45] = syndrom == 110;
corrected_bit_p[44] = syndrom == 109;
corrected_bit_p[43] = syndrom == 107;
corrected_bit_p[42] = syndrom == 104;
corrected_bit_p[41] = syndrom == 103;
corrected_bit_p[40] = syndrom == 100;
corrected_bit_p[39] = syndrom == 98;
corrected_bit_p[38] = syndrom == 97;
corrected_bit_p[37] = syndrom == 93;
corrected_bit_p[36] = syndrom == 91;
corrected_bit_p[35] = syndrom == 88;
corrected_bit_p[34] = syndrom == 87;
corrected_bit_p[33] = syndrom == 84;
corrected_bit_p[32] = syndrom == 82;
corrected_bit_p[31] = syndrom == 81;
corrected_bit_p[30] = syndrom == 79;
corrected_bit_p[29] = syndrom == 76;
corrected_bit_p[28] = syndrom == 74;
corrected_bit_p[27] = syndrom == 73;
corrected_bit_p[26] = syndrom == 70;
corrected_bit_p[25] = syndrom == 69;
corrected_bit_p[24] = syndrom == 67;
corrected_bit_p[23] = syndrom == 61;
corrected_bit_p[22] = syndrom == 59;
corrected_bit_p[21] = syndrom == 56;
corrected_bit_p[20] = syndrom == 55;
corrected_bit_p[19] = syndrom == 52;
corrected_bit_p[18] = syndrom == 50;
corrected_bit_p[17] = syndrom == 49;
corrected_bit_p[16] = syndrom == 44;
corrected_bit_p[15] = syndrom == 42;
corrected_bit_p[14] = syndrom == 41;
corrected_bit_p[13] = syndrom == 38;
corrected_bit_p[12] = syndrom == 37;
corrected_bit_p[11] = syndrom == 35;
corrected_bit_p[10] = syndrom == 31;
corrected_bit_p[09] = syndrom == 28;
corrected_bit_p[08] = syndrom == 26;
corrected_bit_p[07] = syndrom == 25;
corrected_bit_p[06] = syndrom == 22;
corrected_bit_p[05] = syndrom == 21;
corrected_bit_p[04] = syndrom == 19;
corrected_bit_p[03] = syndrom == 14;
corrected_bit_p[02] = syndrom == 13;
corrected_bit_p[01] = syndrom == 11;
corrected_bit_p[00] = syndrom == 7;
end

//Output of decoded data (Correct Error Type 2'b01 only)
always	@(*)
  if (ecc_decoder_bypass) begin
    ecc_decoder_data_out = ecc_dec_in[526:0];
  end else begin
    ecc_decoder_data_out[526] = ecc_dec_in[526] ^ corrected_bit_p[526];
    ecc_decoder_data_out[525] = ecc_dec_in[525] ^ corrected_bit_p[525];
    ecc_decoder_data_out[524] = ecc_dec_in[524] ^ corrected_bit_p[524];
    ecc_decoder_data_out[523] = ecc_dec_in[523] ^ corrected_bit_p[523];
    ecc_decoder_data_out[522] = ecc_dec_in[522] ^ corrected_bit_p[522];
    ecc_decoder_data_out[521] = ecc_dec_in[521] ^ corrected_bit_p[521];
    ecc_decoder_data_out[520] = ecc_dec_in[520] ^ corrected_bit_p[520];
    ecc_decoder_data_out[519] = ecc_dec_in[519] ^ corrected_bit_p[519];
    ecc_decoder_data_out[518] = ecc_dec_in[518] ^ corrected_bit_p[518];
    ecc_decoder_data_out[517] = ecc_dec_in[517] ^ corrected_bit_p[517];
    ecc_decoder_data_out[516] = ecc_dec_in[516] ^ corrected_bit_p[516];
    ecc_decoder_data_out[515] = ecc_dec_in[515] ^ corrected_bit_p[515];
    ecc_decoder_data_out[514] = ecc_dec_in[514] ^ corrected_bit_p[514];
    ecc_decoder_data_out[513] = ecc_dec_in[513] ^ corrected_bit_p[513];
    ecc_decoder_data_out[512] = ecc_dec_in[512] ^ corrected_bit_p[512];
    ecc_decoder_data_out[511] = ecc_dec_in[511] ^ corrected_bit_p[511];
    ecc_decoder_data_out[510] = ecc_dec_in[510] ^ corrected_bit_p[510];
    ecc_decoder_data_out[509] = ecc_dec_in[509] ^ corrected_bit_p[509];
    ecc_decoder_data_out[508] = ecc_dec_in[508] ^ corrected_bit_p[508];
    ecc_decoder_data_out[507] = ecc_dec_in[507] ^ corrected_bit_p[507];
    ecc_decoder_data_out[506] = ecc_dec_in[506] ^ corrected_bit_p[506];
    ecc_decoder_data_out[505] = ecc_dec_in[505] ^ corrected_bit_p[505];
    ecc_decoder_data_out[504] = ecc_dec_in[504] ^ corrected_bit_p[504];
    ecc_decoder_data_out[503] = ecc_dec_in[503] ^ corrected_bit_p[503];
    ecc_decoder_data_out[502] = ecc_dec_in[502] ^ corrected_bit_p[502];
    ecc_decoder_data_out[501] = ecc_dec_in[501] ^ corrected_bit_p[501];
    ecc_decoder_data_out[500] = ecc_dec_in[500] ^ corrected_bit_p[500];
    ecc_decoder_data_out[499] = ecc_dec_in[499] ^ corrected_bit_p[499];
    ecc_decoder_data_out[498] = ecc_dec_in[498] ^ corrected_bit_p[498];
    ecc_decoder_data_out[497] = ecc_dec_in[497] ^ corrected_bit_p[497];
    ecc_decoder_data_out[496] = ecc_dec_in[496] ^ corrected_bit_p[496];
    ecc_decoder_data_out[495] = ecc_dec_in[495] ^ corrected_bit_p[495];
    ecc_decoder_data_out[494] = ecc_dec_in[494] ^ corrected_bit_p[494];
    ecc_decoder_data_out[493] = ecc_dec_in[493] ^ corrected_bit_p[493];
    ecc_decoder_data_out[492] = ecc_dec_in[492] ^ corrected_bit_p[492];
    ecc_decoder_data_out[491] = ecc_dec_in[491] ^ corrected_bit_p[491];
    ecc_decoder_data_out[490] = ecc_dec_in[490] ^ corrected_bit_p[490];
    ecc_decoder_data_out[489] = ecc_dec_in[489] ^ corrected_bit_p[489];
    ecc_decoder_data_out[488] = ecc_dec_in[488] ^ corrected_bit_p[488];
    ecc_decoder_data_out[487] = ecc_dec_in[487] ^ corrected_bit_p[487];
    ecc_decoder_data_out[486] = ecc_dec_in[486] ^ corrected_bit_p[486];
    ecc_decoder_data_out[485] = ecc_dec_in[485] ^ corrected_bit_p[485];
    ecc_decoder_data_out[484] = ecc_dec_in[484] ^ corrected_bit_p[484];
    ecc_decoder_data_out[483] = ecc_dec_in[483] ^ corrected_bit_p[483];
    ecc_decoder_data_out[482] = ecc_dec_in[482] ^ corrected_bit_p[482];
    ecc_decoder_data_out[481] = ecc_dec_in[481] ^ corrected_bit_p[481];
    ecc_decoder_data_out[480] = ecc_dec_in[480] ^ corrected_bit_p[480];
    ecc_decoder_data_out[479] = ecc_dec_in[479] ^ corrected_bit_p[479];
    ecc_decoder_data_out[478] = ecc_dec_in[478] ^ corrected_bit_p[478];
    ecc_decoder_data_out[477] = ecc_dec_in[477] ^ corrected_bit_p[477];
    ecc_decoder_data_out[476] = ecc_dec_in[476] ^ corrected_bit_p[476];
    ecc_decoder_data_out[475] = ecc_dec_in[475] ^ corrected_bit_p[475];
    ecc_decoder_data_out[474] = ecc_dec_in[474] ^ corrected_bit_p[474];
    ecc_decoder_data_out[473] = ecc_dec_in[473] ^ corrected_bit_p[473];
    ecc_decoder_data_out[472] = ecc_dec_in[472] ^ corrected_bit_p[472];
    ecc_decoder_data_out[471] = ecc_dec_in[471] ^ corrected_bit_p[471];
    ecc_decoder_data_out[470] = ecc_dec_in[470] ^ corrected_bit_p[470];
    ecc_decoder_data_out[469] = ecc_dec_in[469] ^ corrected_bit_p[469];
    ecc_decoder_data_out[468] = ecc_dec_in[468] ^ corrected_bit_p[468];
    ecc_decoder_data_out[467] = ecc_dec_in[467] ^ corrected_bit_p[467];
    ecc_decoder_data_out[466] = ecc_dec_in[466] ^ corrected_bit_p[466];
    ecc_decoder_data_out[465] = ecc_dec_in[465] ^ corrected_bit_p[465];
    ecc_decoder_data_out[464] = ecc_dec_in[464] ^ corrected_bit_p[464];
    ecc_decoder_data_out[463] = ecc_dec_in[463] ^ corrected_bit_p[463];
    ecc_decoder_data_out[462] = ecc_dec_in[462] ^ corrected_bit_p[462];
    ecc_decoder_data_out[461] = ecc_dec_in[461] ^ corrected_bit_p[461];
    ecc_decoder_data_out[460] = ecc_dec_in[460] ^ corrected_bit_p[460];
    ecc_decoder_data_out[459] = ecc_dec_in[459] ^ corrected_bit_p[459];
    ecc_decoder_data_out[458] = ecc_dec_in[458] ^ corrected_bit_p[458];
    ecc_decoder_data_out[457] = ecc_dec_in[457] ^ corrected_bit_p[457];
    ecc_decoder_data_out[456] = ecc_dec_in[456] ^ corrected_bit_p[456];
    ecc_decoder_data_out[455] = ecc_dec_in[455] ^ corrected_bit_p[455];
    ecc_decoder_data_out[454] = ecc_dec_in[454] ^ corrected_bit_p[454];
    ecc_decoder_data_out[453] = ecc_dec_in[453] ^ corrected_bit_p[453];
    ecc_decoder_data_out[452] = ecc_dec_in[452] ^ corrected_bit_p[452];
    ecc_decoder_data_out[451] = ecc_dec_in[451] ^ corrected_bit_p[451];
    ecc_decoder_data_out[450] = ecc_dec_in[450] ^ corrected_bit_p[450];
    ecc_decoder_data_out[449] = ecc_dec_in[449] ^ corrected_bit_p[449];
    ecc_decoder_data_out[448] = ecc_dec_in[448] ^ corrected_bit_p[448];
    ecc_decoder_data_out[447] = ecc_dec_in[447] ^ corrected_bit_p[447];
    ecc_decoder_data_out[446] = ecc_dec_in[446] ^ corrected_bit_p[446];
    ecc_decoder_data_out[445] = ecc_dec_in[445] ^ corrected_bit_p[445];
    ecc_decoder_data_out[444] = ecc_dec_in[444] ^ corrected_bit_p[444];
    ecc_decoder_data_out[443] = ecc_dec_in[443] ^ corrected_bit_p[443];
    ecc_decoder_data_out[442] = ecc_dec_in[442] ^ corrected_bit_p[442];
    ecc_decoder_data_out[441] = ecc_dec_in[441] ^ corrected_bit_p[441];
    ecc_decoder_data_out[440] = ecc_dec_in[440] ^ corrected_bit_p[440];
    ecc_decoder_data_out[439] = ecc_dec_in[439] ^ corrected_bit_p[439];
    ecc_decoder_data_out[438] = ecc_dec_in[438] ^ corrected_bit_p[438];
    ecc_decoder_data_out[437] = ecc_dec_in[437] ^ corrected_bit_p[437];
    ecc_decoder_data_out[436] = ecc_dec_in[436] ^ corrected_bit_p[436];
    ecc_decoder_data_out[435] = ecc_dec_in[435] ^ corrected_bit_p[435];
    ecc_decoder_data_out[434] = ecc_dec_in[434] ^ corrected_bit_p[434];
    ecc_decoder_data_out[433] = ecc_dec_in[433] ^ corrected_bit_p[433];
    ecc_decoder_data_out[432] = ecc_dec_in[432] ^ corrected_bit_p[432];
    ecc_decoder_data_out[431] = ecc_dec_in[431] ^ corrected_bit_p[431];
    ecc_decoder_data_out[430] = ecc_dec_in[430] ^ corrected_bit_p[430];
    ecc_decoder_data_out[429] = ecc_dec_in[429] ^ corrected_bit_p[429];
    ecc_decoder_data_out[428] = ecc_dec_in[428] ^ corrected_bit_p[428];
    ecc_decoder_data_out[427] = ecc_dec_in[427] ^ corrected_bit_p[427];
    ecc_decoder_data_out[426] = ecc_dec_in[426] ^ corrected_bit_p[426];
    ecc_decoder_data_out[425] = ecc_dec_in[425] ^ corrected_bit_p[425];
    ecc_decoder_data_out[424] = ecc_dec_in[424] ^ corrected_bit_p[424];
    ecc_decoder_data_out[423] = ecc_dec_in[423] ^ corrected_bit_p[423];
    ecc_decoder_data_out[422] = ecc_dec_in[422] ^ corrected_bit_p[422];
    ecc_decoder_data_out[421] = ecc_dec_in[421] ^ corrected_bit_p[421];
    ecc_decoder_data_out[420] = ecc_dec_in[420] ^ corrected_bit_p[420];
    ecc_decoder_data_out[419] = ecc_dec_in[419] ^ corrected_bit_p[419];
    ecc_decoder_data_out[418] = ecc_dec_in[418] ^ corrected_bit_p[418];
    ecc_decoder_data_out[417] = ecc_dec_in[417] ^ corrected_bit_p[417];
    ecc_decoder_data_out[416] = ecc_dec_in[416] ^ corrected_bit_p[416];
    ecc_decoder_data_out[415] = ecc_dec_in[415] ^ corrected_bit_p[415];
    ecc_decoder_data_out[414] = ecc_dec_in[414] ^ corrected_bit_p[414];
    ecc_decoder_data_out[413] = ecc_dec_in[413] ^ corrected_bit_p[413];
    ecc_decoder_data_out[412] = ecc_dec_in[412] ^ corrected_bit_p[412];
    ecc_decoder_data_out[411] = ecc_dec_in[411] ^ corrected_bit_p[411];
    ecc_decoder_data_out[410] = ecc_dec_in[410] ^ corrected_bit_p[410];
    ecc_decoder_data_out[409] = ecc_dec_in[409] ^ corrected_bit_p[409];
    ecc_decoder_data_out[408] = ecc_dec_in[408] ^ corrected_bit_p[408];
    ecc_decoder_data_out[407] = ecc_dec_in[407] ^ corrected_bit_p[407];
    ecc_decoder_data_out[406] = ecc_dec_in[406] ^ corrected_bit_p[406];
    ecc_decoder_data_out[405] = ecc_dec_in[405] ^ corrected_bit_p[405];
    ecc_decoder_data_out[404] = ecc_dec_in[404] ^ corrected_bit_p[404];
    ecc_decoder_data_out[403] = ecc_dec_in[403] ^ corrected_bit_p[403];
    ecc_decoder_data_out[402] = ecc_dec_in[402] ^ corrected_bit_p[402];
    ecc_decoder_data_out[401] = ecc_dec_in[401] ^ corrected_bit_p[401];
    ecc_decoder_data_out[400] = ecc_dec_in[400] ^ corrected_bit_p[400];
    ecc_decoder_data_out[399] = ecc_dec_in[399] ^ corrected_bit_p[399];
    ecc_decoder_data_out[398] = ecc_dec_in[398] ^ corrected_bit_p[398];
    ecc_decoder_data_out[397] = ecc_dec_in[397] ^ corrected_bit_p[397];
    ecc_decoder_data_out[396] = ecc_dec_in[396] ^ corrected_bit_p[396];
    ecc_decoder_data_out[395] = ecc_dec_in[395] ^ corrected_bit_p[395];
    ecc_decoder_data_out[394] = ecc_dec_in[394] ^ corrected_bit_p[394];
    ecc_decoder_data_out[393] = ecc_dec_in[393] ^ corrected_bit_p[393];
    ecc_decoder_data_out[392] = ecc_dec_in[392] ^ corrected_bit_p[392];
    ecc_decoder_data_out[391] = ecc_dec_in[391] ^ corrected_bit_p[391];
    ecc_decoder_data_out[390] = ecc_dec_in[390] ^ corrected_bit_p[390];
    ecc_decoder_data_out[389] = ecc_dec_in[389] ^ corrected_bit_p[389];
    ecc_decoder_data_out[388] = ecc_dec_in[388] ^ corrected_bit_p[388];
    ecc_decoder_data_out[387] = ecc_dec_in[387] ^ corrected_bit_p[387];
    ecc_decoder_data_out[386] = ecc_dec_in[386] ^ corrected_bit_p[386];
    ecc_decoder_data_out[385] = ecc_dec_in[385] ^ corrected_bit_p[385];
    ecc_decoder_data_out[384] = ecc_dec_in[384] ^ corrected_bit_p[384];
    ecc_decoder_data_out[383] = ecc_dec_in[383] ^ corrected_bit_p[383];
    ecc_decoder_data_out[382] = ecc_dec_in[382] ^ corrected_bit_p[382];
    ecc_decoder_data_out[381] = ecc_dec_in[381] ^ corrected_bit_p[381];
    ecc_decoder_data_out[380] = ecc_dec_in[380] ^ corrected_bit_p[380];
    ecc_decoder_data_out[379] = ecc_dec_in[379] ^ corrected_bit_p[379];
    ecc_decoder_data_out[378] = ecc_dec_in[378] ^ corrected_bit_p[378];
    ecc_decoder_data_out[377] = ecc_dec_in[377] ^ corrected_bit_p[377];
    ecc_decoder_data_out[376] = ecc_dec_in[376] ^ corrected_bit_p[376];
    ecc_decoder_data_out[375] = ecc_dec_in[375] ^ corrected_bit_p[375];
    ecc_decoder_data_out[374] = ecc_dec_in[374] ^ corrected_bit_p[374];
    ecc_decoder_data_out[373] = ecc_dec_in[373] ^ corrected_bit_p[373];
    ecc_decoder_data_out[372] = ecc_dec_in[372] ^ corrected_bit_p[372];
    ecc_decoder_data_out[371] = ecc_dec_in[371] ^ corrected_bit_p[371];
    ecc_decoder_data_out[370] = ecc_dec_in[370] ^ corrected_bit_p[370];
    ecc_decoder_data_out[369] = ecc_dec_in[369] ^ corrected_bit_p[369];
    ecc_decoder_data_out[368] = ecc_dec_in[368] ^ corrected_bit_p[368];
    ecc_decoder_data_out[367] = ecc_dec_in[367] ^ corrected_bit_p[367];
    ecc_decoder_data_out[366] = ecc_dec_in[366] ^ corrected_bit_p[366];
    ecc_decoder_data_out[365] = ecc_dec_in[365] ^ corrected_bit_p[365];
    ecc_decoder_data_out[364] = ecc_dec_in[364] ^ corrected_bit_p[364];
    ecc_decoder_data_out[363] = ecc_dec_in[363] ^ corrected_bit_p[363];
    ecc_decoder_data_out[362] = ecc_dec_in[362] ^ corrected_bit_p[362];
    ecc_decoder_data_out[361] = ecc_dec_in[361] ^ corrected_bit_p[361];
    ecc_decoder_data_out[360] = ecc_dec_in[360] ^ corrected_bit_p[360];
    ecc_decoder_data_out[359] = ecc_dec_in[359] ^ corrected_bit_p[359];
    ecc_decoder_data_out[358] = ecc_dec_in[358] ^ corrected_bit_p[358];
    ecc_decoder_data_out[357] = ecc_dec_in[357] ^ corrected_bit_p[357];
    ecc_decoder_data_out[356] = ecc_dec_in[356] ^ corrected_bit_p[356];
    ecc_decoder_data_out[355] = ecc_dec_in[355] ^ corrected_bit_p[355];
    ecc_decoder_data_out[354] = ecc_dec_in[354] ^ corrected_bit_p[354];
    ecc_decoder_data_out[353] = ecc_dec_in[353] ^ corrected_bit_p[353];
    ecc_decoder_data_out[352] = ecc_dec_in[352] ^ corrected_bit_p[352];
    ecc_decoder_data_out[351] = ecc_dec_in[351] ^ corrected_bit_p[351];
    ecc_decoder_data_out[350] = ecc_dec_in[350] ^ corrected_bit_p[350];
    ecc_decoder_data_out[349] = ecc_dec_in[349] ^ corrected_bit_p[349];
    ecc_decoder_data_out[348] = ecc_dec_in[348] ^ corrected_bit_p[348];
    ecc_decoder_data_out[347] = ecc_dec_in[347] ^ corrected_bit_p[347];
    ecc_decoder_data_out[346] = ecc_dec_in[346] ^ corrected_bit_p[346];
    ecc_decoder_data_out[345] = ecc_dec_in[345] ^ corrected_bit_p[345];
    ecc_decoder_data_out[344] = ecc_dec_in[344] ^ corrected_bit_p[344];
    ecc_decoder_data_out[343] = ecc_dec_in[343] ^ corrected_bit_p[343];
    ecc_decoder_data_out[342] = ecc_dec_in[342] ^ corrected_bit_p[342];
    ecc_decoder_data_out[341] = ecc_dec_in[341] ^ corrected_bit_p[341];
    ecc_decoder_data_out[340] = ecc_dec_in[340] ^ corrected_bit_p[340];
    ecc_decoder_data_out[339] = ecc_dec_in[339] ^ corrected_bit_p[339];
    ecc_decoder_data_out[338] = ecc_dec_in[338] ^ corrected_bit_p[338];
    ecc_decoder_data_out[337] = ecc_dec_in[337] ^ corrected_bit_p[337];
    ecc_decoder_data_out[336] = ecc_dec_in[336] ^ corrected_bit_p[336];
    ecc_decoder_data_out[335] = ecc_dec_in[335] ^ corrected_bit_p[335];
    ecc_decoder_data_out[334] = ecc_dec_in[334] ^ corrected_bit_p[334];
    ecc_decoder_data_out[333] = ecc_dec_in[333] ^ corrected_bit_p[333];
    ecc_decoder_data_out[332] = ecc_dec_in[332] ^ corrected_bit_p[332];
    ecc_decoder_data_out[331] = ecc_dec_in[331] ^ corrected_bit_p[331];
    ecc_decoder_data_out[330] = ecc_dec_in[330] ^ corrected_bit_p[330];
    ecc_decoder_data_out[329] = ecc_dec_in[329] ^ corrected_bit_p[329];
    ecc_decoder_data_out[328] = ecc_dec_in[328] ^ corrected_bit_p[328];
    ecc_decoder_data_out[327] = ecc_dec_in[327] ^ corrected_bit_p[327];
    ecc_decoder_data_out[326] = ecc_dec_in[326] ^ corrected_bit_p[326];
    ecc_decoder_data_out[325] = ecc_dec_in[325] ^ corrected_bit_p[325];
    ecc_decoder_data_out[324] = ecc_dec_in[324] ^ corrected_bit_p[324];
    ecc_decoder_data_out[323] = ecc_dec_in[323] ^ corrected_bit_p[323];
    ecc_decoder_data_out[322] = ecc_dec_in[322] ^ corrected_bit_p[322];
    ecc_decoder_data_out[321] = ecc_dec_in[321] ^ corrected_bit_p[321];
    ecc_decoder_data_out[320] = ecc_dec_in[320] ^ corrected_bit_p[320];
    ecc_decoder_data_out[319] = ecc_dec_in[319] ^ corrected_bit_p[319];
    ecc_decoder_data_out[318] = ecc_dec_in[318] ^ corrected_bit_p[318];
    ecc_decoder_data_out[317] = ecc_dec_in[317] ^ corrected_bit_p[317];
    ecc_decoder_data_out[316] = ecc_dec_in[316] ^ corrected_bit_p[316];
    ecc_decoder_data_out[315] = ecc_dec_in[315] ^ corrected_bit_p[315];
    ecc_decoder_data_out[314] = ecc_dec_in[314] ^ corrected_bit_p[314];
    ecc_decoder_data_out[313] = ecc_dec_in[313] ^ corrected_bit_p[313];
    ecc_decoder_data_out[312] = ecc_dec_in[312] ^ corrected_bit_p[312];
    ecc_decoder_data_out[311] = ecc_dec_in[311] ^ corrected_bit_p[311];
    ecc_decoder_data_out[310] = ecc_dec_in[310] ^ corrected_bit_p[310];
    ecc_decoder_data_out[309] = ecc_dec_in[309] ^ corrected_bit_p[309];
    ecc_decoder_data_out[308] = ecc_dec_in[308] ^ corrected_bit_p[308];
    ecc_decoder_data_out[307] = ecc_dec_in[307] ^ corrected_bit_p[307];
    ecc_decoder_data_out[306] = ecc_dec_in[306] ^ corrected_bit_p[306];
    ecc_decoder_data_out[305] = ecc_dec_in[305] ^ corrected_bit_p[305];
    ecc_decoder_data_out[304] = ecc_dec_in[304] ^ corrected_bit_p[304];
    ecc_decoder_data_out[303] = ecc_dec_in[303] ^ corrected_bit_p[303];
    ecc_decoder_data_out[302] = ecc_dec_in[302] ^ corrected_bit_p[302];
    ecc_decoder_data_out[301] = ecc_dec_in[301] ^ corrected_bit_p[301];
    ecc_decoder_data_out[300] = ecc_dec_in[300] ^ corrected_bit_p[300];
    ecc_decoder_data_out[299] = ecc_dec_in[299] ^ corrected_bit_p[299];
    ecc_decoder_data_out[298] = ecc_dec_in[298] ^ corrected_bit_p[298];
    ecc_decoder_data_out[297] = ecc_dec_in[297] ^ corrected_bit_p[297];
    ecc_decoder_data_out[296] = ecc_dec_in[296] ^ corrected_bit_p[296];
    ecc_decoder_data_out[295] = ecc_dec_in[295] ^ corrected_bit_p[295];
    ecc_decoder_data_out[294] = ecc_dec_in[294] ^ corrected_bit_p[294];
    ecc_decoder_data_out[293] = ecc_dec_in[293] ^ corrected_bit_p[293];
    ecc_decoder_data_out[292] = ecc_dec_in[292] ^ corrected_bit_p[292];
    ecc_decoder_data_out[291] = ecc_dec_in[291] ^ corrected_bit_p[291];
    ecc_decoder_data_out[290] = ecc_dec_in[290] ^ corrected_bit_p[290];
    ecc_decoder_data_out[289] = ecc_dec_in[289] ^ corrected_bit_p[289];
    ecc_decoder_data_out[288] = ecc_dec_in[288] ^ corrected_bit_p[288];
    ecc_decoder_data_out[287] = ecc_dec_in[287] ^ corrected_bit_p[287];
    ecc_decoder_data_out[286] = ecc_dec_in[286] ^ corrected_bit_p[286];
    ecc_decoder_data_out[285] = ecc_dec_in[285] ^ corrected_bit_p[285];
    ecc_decoder_data_out[284] = ecc_dec_in[284] ^ corrected_bit_p[284];
    ecc_decoder_data_out[283] = ecc_dec_in[283] ^ corrected_bit_p[283];
    ecc_decoder_data_out[282] = ecc_dec_in[282] ^ corrected_bit_p[282];
    ecc_decoder_data_out[281] = ecc_dec_in[281] ^ corrected_bit_p[281];
    ecc_decoder_data_out[280] = ecc_dec_in[280] ^ corrected_bit_p[280];
    ecc_decoder_data_out[279] = ecc_dec_in[279] ^ corrected_bit_p[279];
    ecc_decoder_data_out[278] = ecc_dec_in[278] ^ corrected_bit_p[278];
    ecc_decoder_data_out[277] = ecc_dec_in[277] ^ corrected_bit_p[277];
    ecc_decoder_data_out[276] = ecc_dec_in[276] ^ corrected_bit_p[276];
    ecc_decoder_data_out[275] = ecc_dec_in[275] ^ corrected_bit_p[275];
    ecc_decoder_data_out[274] = ecc_dec_in[274] ^ corrected_bit_p[274];
    ecc_decoder_data_out[273] = ecc_dec_in[273] ^ corrected_bit_p[273];
    ecc_decoder_data_out[272] = ecc_dec_in[272] ^ corrected_bit_p[272];
    ecc_decoder_data_out[271] = ecc_dec_in[271] ^ corrected_bit_p[271];
    ecc_decoder_data_out[270] = ecc_dec_in[270] ^ corrected_bit_p[270];
    ecc_decoder_data_out[269] = ecc_dec_in[269] ^ corrected_bit_p[269];
    ecc_decoder_data_out[268] = ecc_dec_in[268] ^ corrected_bit_p[268];
    ecc_decoder_data_out[267] = ecc_dec_in[267] ^ corrected_bit_p[267];
    ecc_decoder_data_out[266] = ecc_dec_in[266] ^ corrected_bit_p[266];
    ecc_decoder_data_out[265] = ecc_dec_in[265] ^ corrected_bit_p[265];
    ecc_decoder_data_out[264] = ecc_dec_in[264] ^ corrected_bit_p[264];
    ecc_decoder_data_out[263] = ecc_dec_in[263] ^ corrected_bit_p[263];
    ecc_decoder_data_out[262] = ecc_dec_in[262] ^ corrected_bit_p[262];
    ecc_decoder_data_out[261] = ecc_dec_in[261] ^ corrected_bit_p[261];
    ecc_decoder_data_out[260] = ecc_dec_in[260] ^ corrected_bit_p[260];
    ecc_decoder_data_out[259] = ecc_dec_in[259] ^ corrected_bit_p[259];
    ecc_decoder_data_out[258] = ecc_dec_in[258] ^ corrected_bit_p[258];
    ecc_decoder_data_out[257] = ecc_dec_in[257] ^ corrected_bit_p[257];
    ecc_decoder_data_out[256] = ecc_dec_in[256] ^ corrected_bit_p[256];
    ecc_decoder_data_out[255] = ecc_dec_in[255] ^ corrected_bit_p[255];
    ecc_decoder_data_out[254] = ecc_dec_in[254] ^ corrected_bit_p[254];
    ecc_decoder_data_out[253] = ecc_dec_in[253] ^ corrected_bit_p[253];
    ecc_decoder_data_out[252] = ecc_dec_in[252] ^ corrected_bit_p[252];
    ecc_decoder_data_out[251] = ecc_dec_in[251] ^ corrected_bit_p[251];
    ecc_decoder_data_out[250] = ecc_dec_in[250] ^ corrected_bit_p[250];
    ecc_decoder_data_out[249] = ecc_dec_in[249] ^ corrected_bit_p[249];
    ecc_decoder_data_out[248] = ecc_dec_in[248] ^ corrected_bit_p[248];
    ecc_decoder_data_out[247] = ecc_dec_in[247] ^ corrected_bit_p[247];
    ecc_decoder_data_out[246] = ecc_dec_in[246] ^ corrected_bit_p[246];
    ecc_decoder_data_out[245] = ecc_dec_in[245] ^ corrected_bit_p[245];
    ecc_decoder_data_out[244] = ecc_dec_in[244] ^ corrected_bit_p[244];
    ecc_decoder_data_out[243] = ecc_dec_in[243] ^ corrected_bit_p[243];
    ecc_decoder_data_out[242] = ecc_dec_in[242] ^ corrected_bit_p[242];
    ecc_decoder_data_out[241] = ecc_dec_in[241] ^ corrected_bit_p[241];
    ecc_decoder_data_out[240] = ecc_dec_in[240] ^ corrected_bit_p[240];
    ecc_decoder_data_out[239] = ecc_dec_in[239] ^ corrected_bit_p[239];
    ecc_decoder_data_out[238] = ecc_dec_in[238] ^ corrected_bit_p[238];
    ecc_decoder_data_out[237] = ecc_dec_in[237] ^ corrected_bit_p[237];
    ecc_decoder_data_out[236] = ecc_dec_in[236] ^ corrected_bit_p[236];
    ecc_decoder_data_out[235] = ecc_dec_in[235] ^ corrected_bit_p[235];
    ecc_decoder_data_out[234] = ecc_dec_in[234] ^ corrected_bit_p[234];
    ecc_decoder_data_out[233] = ecc_dec_in[233] ^ corrected_bit_p[233];
    ecc_decoder_data_out[232] = ecc_dec_in[232] ^ corrected_bit_p[232];
    ecc_decoder_data_out[231] = ecc_dec_in[231] ^ corrected_bit_p[231];
    ecc_decoder_data_out[230] = ecc_dec_in[230] ^ corrected_bit_p[230];
    ecc_decoder_data_out[229] = ecc_dec_in[229] ^ corrected_bit_p[229];
    ecc_decoder_data_out[228] = ecc_dec_in[228] ^ corrected_bit_p[228];
    ecc_decoder_data_out[227] = ecc_dec_in[227] ^ corrected_bit_p[227];
    ecc_decoder_data_out[226] = ecc_dec_in[226] ^ corrected_bit_p[226];
    ecc_decoder_data_out[225] = ecc_dec_in[225] ^ corrected_bit_p[225];
    ecc_decoder_data_out[224] = ecc_dec_in[224] ^ corrected_bit_p[224];
    ecc_decoder_data_out[223] = ecc_dec_in[223] ^ corrected_bit_p[223];
    ecc_decoder_data_out[222] = ecc_dec_in[222] ^ corrected_bit_p[222];
    ecc_decoder_data_out[221] = ecc_dec_in[221] ^ corrected_bit_p[221];
    ecc_decoder_data_out[220] = ecc_dec_in[220] ^ corrected_bit_p[220];
    ecc_decoder_data_out[219] = ecc_dec_in[219] ^ corrected_bit_p[219];
    ecc_decoder_data_out[218] = ecc_dec_in[218] ^ corrected_bit_p[218];
    ecc_decoder_data_out[217] = ecc_dec_in[217] ^ corrected_bit_p[217];
    ecc_decoder_data_out[216] = ecc_dec_in[216] ^ corrected_bit_p[216];
    ecc_decoder_data_out[215] = ecc_dec_in[215] ^ corrected_bit_p[215];
    ecc_decoder_data_out[214] = ecc_dec_in[214] ^ corrected_bit_p[214];
    ecc_decoder_data_out[213] = ecc_dec_in[213] ^ corrected_bit_p[213];
    ecc_decoder_data_out[212] = ecc_dec_in[212] ^ corrected_bit_p[212];
    ecc_decoder_data_out[211] = ecc_dec_in[211] ^ corrected_bit_p[211];
    ecc_decoder_data_out[210] = ecc_dec_in[210] ^ corrected_bit_p[210];
    ecc_decoder_data_out[209] = ecc_dec_in[209] ^ corrected_bit_p[209];
    ecc_decoder_data_out[208] = ecc_dec_in[208] ^ corrected_bit_p[208];
    ecc_decoder_data_out[207] = ecc_dec_in[207] ^ corrected_bit_p[207];
    ecc_decoder_data_out[206] = ecc_dec_in[206] ^ corrected_bit_p[206];
    ecc_decoder_data_out[205] = ecc_dec_in[205] ^ corrected_bit_p[205];
    ecc_decoder_data_out[204] = ecc_dec_in[204] ^ corrected_bit_p[204];
    ecc_decoder_data_out[203] = ecc_dec_in[203] ^ corrected_bit_p[203];
    ecc_decoder_data_out[202] = ecc_dec_in[202] ^ corrected_bit_p[202];
    ecc_decoder_data_out[201] = ecc_dec_in[201] ^ corrected_bit_p[201];
    ecc_decoder_data_out[200] = ecc_dec_in[200] ^ corrected_bit_p[200];
    ecc_decoder_data_out[199] = ecc_dec_in[199] ^ corrected_bit_p[199];
    ecc_decoder_data_out[198] = ecc_dec_in[198] ^ corrected_bit_p[198];
    ecc_decoder_data_out[197] = ecc_dec_in[197] ^ corrected_bit_p[197];
    ecc_decoder_data_out[196] = ecc_dec_in[196] ^ corrected_bit_p[196];
    ecc_decoder_data_out[195] = ecc_dec_in[195] ^ corrected_bit_p[195];
    ecc_decoder_data_out[194] = ecc_dec_in[194] ^ corrected_bit_p[194];
    ecc_decoder_data_out[193] = ecc_dec_in[193] ^ corrected_bit_p[193];
    ecc_decoder_data_out[192] = ecc_dec_in[192] ^ corrected_bit_p[192];
    ecc_decoder_data_out[191] = ecc_dec_in[191] ^ corrected_bit_p[191];
    ecc_decoder_data_out[190] = ecc_dec_in[190] ^ corrected_bit_p[190];
    ecc_decoder_data_out[189] = ecc_dec_in[189] ^ corrected_bit_p[189];
    ecc_decoder_data_out[188] = ecc_dec_in[188] ^ corrected_bit_p[188];
    ecc_decoder_data_out[187] = ecc_dec_in[187] ^ corrected_bit_p[187];
    ecc_decoder_data_out[186] = ecc_dec_in[186] ^ corrected_bit_p[186];
    ecc_decoder_data_out[185] = ecc_dec_in[185] ^ corrected_bit_p[185];
    ecc_decoder_data_out[184] = ecc_dec_in[184] ^ corrected_bit_p[184];
    ecc_decoder_data_out[183] = ecc_dec_in[183] ^ corrected_bit_p[183];
    ecc_decoder_data_out[182] = ecc_dec_in[182] ^ corrected_bit_p[182];
    ecc_decoder_data_out[181] = ecc_dec_in[181] ^ corrected_bit_p[181];
    ecc_decoder_data_out[180] = ecc_dec_in[180] ^ corrected_bit_p[180];
    ecc_decoder_data_out[179] = ecc_dec_in[179] ^ corrected_bit_p[179];
    ecc_decoder_data_out[178] = ecc_dec_in[178] ^ corrected_bit_p[178];
    ecc_decoder_data_out[177] = ecc_dec_in[177] ^ corrected_bit_p[177];
    ecc_decoder_data_out[176] = ecc_dec_in[176] ^ corrected_bit_p[176];
    ecc_decoder_data_out[175] = ecc_dec_in[175] ^ corrected_bit_p[175];
    ecc_decoder_data_out[174] = ecc_dec_in[174] ^ corrected_bit_p[174];
    ecc_decoder_data_out[173] = ecc_dec_in[173] ^ corrected_bit_p[173];
    ecc_decoder_data_out[172] = ecc_dec_in[172] ^ corrected_bit_p[172];
    ecc_decoder_data_out[171] = ecc_dec_in[171] ^ corrected_bit_p[171];
    ecc_decoder_data_out[170] = ecc_dec_in[170] ^ corrected_bit_p[170];
    ecc_decoder_data_out[169] = ecc_dec_in[169] ^ corrected_bit_p[169];
    ecc_decoder_data_out[168] = ecc_dec_in[168] ^ corrected_bit_p[168];
    ecc_decoder_data_out[167] = ecc_dec_in[167] ^ corrected_bit_p[167];
    ecc_decoder_data_out[166] = ecc_dec_in[166] ^ corrected_bit_p[166];
    ecc_decoder_data_out[165] = ecc_dec_in[165] ^ corrected_bit_p[165];
    ecc_decoder_data_out[164] = ecc_dec_in[164] ^ corrected_bit_p[164];
    ecc_decoder_data_out[163] = ecc_dec_in[163] ^ corrected_bit_p[163];
    ecc_decoder_data_out[162] = ecc_dec_in[162] ^ corrected_bit_p[162];
    ecc_decoder_data_out[161] = ecc_dec_in[161] ^ corrected_bit_p[161];
    ecc_decoder_data_out[160] = ecc_dec_in[160] ^ corrected_bit_p[160];
    ecc_decoder_data_out[159] = ecc_dec_in[159] ^ corrected_bit_p[159];
    ecc_decoder_data_out[158] = ecc_dec_in[158] ^ corrected_bit_p[158];
    ecc_decoder_data_out[157] = ecc_dec_in[157] ^ corrected_bit_p[157];
    ecc_decoder_data_out[156] = ecc_dec_in[156] ^ corrected_bit_p[156];
    ecc_decoder_data_out[155] = ecc_dec_in[155] ^ corrected_bit_p[155];
    ecc_decoder_data_out[154] = ecc_dec_in[154] ^ corrected_bit_p[154];
    ecc_decoder_data_out[153] = ecc_dec_in[153] ^ corrected_bit_p[153];
    ecc_decoder_data_out[152] = ecc_dec_in[152] ^ corrected_bit_p[152];
    ecc_decoder_data_out[151] = ecc_dec_in[151] ^ corrected_bit_p[151];
    ecc_decoder_data_out[150] = ecc_dec_in[150] ^ corrected_bit_p[150];
    ecc_decoder_data_out[149] = ecc_dec_in[149] ^ corrected_bit_p[149];
    ecc_decoder_data_out[148] = ecc_dec_in[148] ^ corrected_bit_p[148];
    ecc_decoder_data_out[147] = ecc_dec_in[147] ^ corrected_bit_p[147];
    ecc_decoder_data_out[146] = ecc_dec_in[146] ^ corrected_bit_p[146];
    ecc_decoder_data_out[145] = ecc_dec_in[145] ^ corrected_bit_p[145];
    ecc_decoder_data_out[144] = ecc_dec_in[144] ^ corrected_bit_p[144];
    ecc_decoder_data_out[143] = ecc_dec_in[143] ^ corrected_bit_p[143];
    ecc_decoder_data_out[142] = ecc_dec_in[142] ^ corrected_bit_p[142];
    ecc_decoder_data_out[141] = ecc_dec_in[141] ^ corrected_bit_p[141];
    ecc_decoder_data_out[140] = ecc_dec_in[140] ^ corrected_bit_p[140];
    ecc_decoder_data_out[139] = ecc_dec_in[139] ^ corrected_bit_p[139];
    ecc_decoder_data_out[138] = ecc_dec_in[138] ^ corrected_bit_p[138];
    ecc_decoder_data_out[137] = ecc_dec_in[137] ^ corrected_bit_p[137];
    ecc_decoder_data_out[136] = ecc_dec_in[136] ^ corrected_bit_p[136];
    ecc_decoder_data_out[135] = ecc_dec_in[135] ^ corrected_bit_p[135];
    ecc_decoder_data_out[134] = ecc_dec_in[134] ^ corrected_bit_p[134];
    ecc_decoder_data_out[133] = ecc_dec_in[133] ^ corrected_bit_p[133];
    ecc_decoder_data_out[132] = ecc_dec_in[132] ^ corrected_bit_p[132];
    ecc_decoder_data_out[131] = ecc_dec_in[131] ^ corrected_bit_p[131];
    ecc_decoder_data_out[130] = ecc_dec_in[130] ^ corrected_bit_p[130];
    ecc_decoder_data_out[129] = ecc_dec_in[129] ^ corrected_bit_p[129];
    ecc_decoder_data_out[128] = ecc_dec_in[128] ^ corrected_bit_p[128];
    ecc_decoder_data_out[127] = ecc_dec_in[127] ^ corrected_bit_p[127];
    ecc_decoder_data_out[126] = ecc_dec_in[126] ^ corrected_bit_p[126];
    ecc_decoder_data_out[125] = ecc_dec_in[125] ^ corrected_bit_p[125];
    ecc_decoder_data_out[124] = ecc_dec_in[124] ^ corrected_bit_p[124];
    ecc_decoder_data_out[123] = ecc_dec_in[123] ^ corrected_bit_p[123];
    ecc_decoder_data_out[122] = ecc_dec_in[122] ^ corrected_bit_p[122];
    ecc_decoder_data_out[121] = ecc_dec_in[121] ^ corrected_bit_p[121];
    ecc_decoder_data_out[120] = ecc_dec_in[120] ^ corrected_bit_p[120];
    ecc_decoder_data_out[119] = ecc_dec_in[119] ^ corrected_bit_p[119];
    ecc_decoder_data_out[118] = ecc_dec_in[118] ^ corrected_bit_p[118];
    ecc_decoder_data_out[117] = ecc_dec_in[117] ^ corrected_bit_p[117];
    ecc_decoder_data_out[116] = ecc_dec_in[116] ^ corrected_bit_p[116];
    ecc_decoder_data_out[115] = ecc_dec_in[115] ^ corrected_bit_p[115];
    ecc_decoder_data_out[114] = ecc_dec_in[114] ^ corrected_bit_p[114];
    ecc_decoder_data_out[113] = ecc_dec_in[113] ^ corrected_bit_p[113];
    ecc_decoder_data_out[112] = ecc_dec_in[112] ^ corrected_bit_p[112];
    ecc_decoder_data_out[111] = ecc_dec_in[111] ^ corrected_bit_p[111];
    ecc_decoder_data_out[110] = ecc_dec_in[110] ^ corrected_bit_p[110];
    ecc_decoder_data_out[109] = ecc_dec_in[109] ^ corrected_bit_p[109];
    ecc_decoder_data_out[108] = ecc_dec_in[108] ^ corrected_bit_p[108];
    ecc_decoder_data_out[107] = ecc_dec_in[107] ^ corrected_bit_p[107];
    ecc_decoder_data_out[106] = ecc_dec_in[106] ^ corrected_bit_p[106];
    ecc_decoder_data_out[105] = ecc_dec_in[105] ^ corrected_bit_p[105];
    ecc_decoder_data_out[104] = ecc_dec_in[104] ^ corrected_bit_p[104];
    ecc_decoder_data_out[103] = ecc_dec_in[103] ^ corrected_bit_p[103];
    ecc_decoder_data_out[102] = ecc_dec_in[102] ^ corrected_bit_p[102];
    ecc_decoder_data_out[101] = ecc_dec_in[101] ^ corrected_bit_p[101];
    ecc_decoder_data_out[100] = ecc_dec_in[100] ^ corrected_bit_p[100];
    ecc_decoder_data_out[99] = ecc_dec_in[99] ^ corrected_bit_p[99];
    ecc_decoder_data_out[98] = ecc_dec_in[98] ^ corrected_bit_p[98];
    ecc_decoder_data_out[97] = ecc_dec_in[97] ^ corrected_bit_p[97];
    ecc_decoder_data_out[96] = ecc_dec_in[96] ^ corrected_bit_p[96];
    ecc_decoder_data_out[95] = ecc_dec_in[95] ^ corrected_bit_p[95];
    ecc_decoder_data_out[94] = ecc_dec_in[94] ^ corrected_bit_p[94];
    ecc_decoder_data_out[93] = ecc_dec_in[93] ^ corrected_bit_p[93];
    ecc_decoder_data_out[92] = ecc_dec_in[92] ^ corrected_bit_p[92];
    ecc_decoder_data_out[91] = ecc_dec_in[91] ^ corrected_bit_p[91];
    ecc_decoder_data_out[90] = ecc_dec_in[90] ^ corrected_bit_p[90];
    ecc_decoder_data_out[89] = ecc_dec_in[89] ^ corrected_bit_p[89];
    ecc_decoder_data_out[88] = ecc_dec_in[88] ^ corrected_bit_p[88];
    ecc_decoder_data_out[87] = ecc_dec_in[87] ^ corrected_bit_p[87];
    ecc_decoder_data_out[86] = ecc_dec_in[86] ^ corrected_bit_p[86];
    ecc_decoder_data_out[85] = ecc_dec_in[85] ^ corrected_bit_p[85];
    ecc_decoder_data_out[84] = ecc_dec_in[84] ^ corrected_bit_p[84];
    ecc_decoder_data_out[83] = ecc_dec_in[83] ^ corrected_bit_p[83];
    ecc_decoder_data_out[82] = ecc_dec_in[82] ^ corrected_bit_p[82];
    ecc_decoder_data_out[81] = ecc_dec_in[81] ^ corrected_bit_p[81];
    ecc_decoder_data_out[80] = ecc_dec_in[80] ^ corrected_bit_p[80];
    ecc_decoder_data_out[79] = ecc_dec_in[79] ^ corrected_bit_p[79];
    ecc_decoder_data_out[78] = ecc_dec_in[78] ^ corrected_bit_p[78];
    ecc_decoder_data_out[77] = ecc_dec_in[77] ^ corrected_bit_p[77];
    ecc_decoder_data_out[76] = ecc_dec_in[76] ^ corrected_bit_p[76];
    ecc_decoder_data_out[75] = ecc_dec_in[75] ^ corrected_bit_p[75];
    ecc_decoder_data_out[74] = ecc_dec_in[74] ^ corrected_bit_p[74];
    ecc_decoder_data_out[73] = ecc_dec_in[73] ^ corrected_bit_p[73];
    ecc_decoder_data_out[72] = ecc_dec_in[72] ^ corrected_bit_p[72];
    ecc_decoder_data_out[71] = ecc_dec_in[71] ^ corrected_bit_p[71];
    ecc_decoder_data_out[70] = ecc_dec_in[70] ^ corrected_bit_p[70];
    ecc_decoder_data_out[69] = ecc_dec_in[69] ^ corrected_bit_p[69];
    ecc_decoder_data_out[68] = ecc_dec_in[68] ^ corrected_bit_p[68];
    ecc_decoder_data_out[67] = ecc_dec_in[67] ^ corrected_bit_p[67];
    ecc_decoder_data_out[66] = ecc_dec_in[66] ^ corrected_bit_p[66];
    ecc_decoder_data_out[65] = ecc_dec_in[65] ^ corrected_bit_p[65];
    ecc_decoder_data_out[64] = ecc_dec_in[64] ^ corrected_bit_p[64];
    ecc_decoder_data_out[63] = ecc_dec_in[63] ^ corrected_bit_p[63];
    ecc_decoder_data_out[62] = ecc_dec_in[62] ^ corrected_bit_p[62];
    ecc_decoder_data_out[61] = ecc_dec_in[61] ^ corrected_bit_p[61];
    ecc_decoder_data_out[60] = ecc_dec_in[60] ^ corrected_bit_p[60];
    ecc_decoder_data_out[59] = ecc_dec_in[59] ^ corrected_bit_p[59];
    ecc_decoder_data_out[58] = ecc_dec_in[58] ^ corrected_bit_p[58];
    ecc_decoder_data_out[57] = ecc_dec_in[57] ^ corrected_bit_p[57];
    ecc_decoder_data_out[56] = ecc_dec_in[56] ^ corrected_bit_p[56];
    ecc_decoder_data_out[55] = ecc_dec_in[55] ^ corrected_bit_p[55];
    ecc_decoder_data_out[54] = ecc_dec_in[54] ^ corrected_bit_p[54];
    ecc_decoder_data_out[53] = ecc_dec_in[53] ^ corrected_bit_p[53];
    ecc_decoder_data_out[52] = ecc_dec_in[52] ^ corrected_bit_p[52];
    ecc_decoder_data_out[51] = ecc_dec_in[51] ^ corrected_bit_p[51];
    ecc_decoder_data_out[50] = ecc_dec_in[50] ^ corrected_bit_p[50];
    ecc_decoder_data_out[49] = ecc_dec_in[49] ^ corrected_bit_p[49];
    ecc_decoder_data_out[48] = ecc_dec_in[48] ^ corrected_bit_p[48];
    ecc_decoder_data_out[47] = ecc_dec_in[47] ^ corrected_bit_p[47];
    ecc_decoder_data_out[46] = ecc_dec_in[46] ^ corrected_bit_p[46];
    ecc_decoder_data_out[45] = ecc_dec_in[45] ^ corrected_bit_p[45];
    ecc_decoder_data_out[44] = ecc_dec_in[44] ^ corrected_bit_p[44];
    ecc_decoder_data_out[43] = ecc_dec_in[43] ^ corrected_bit_p[43];
    ecc_decoder_data_out[42] = ecc_dec_in[42] ^ corrected_bit_p[42];
    ecc_decoder_data_out[41] = ecc_dec_in[41] ^ corrected_bit_p[41];
    ecc_decoder_data_out[40] = ecc_dec_in[40] ^ corrected_bit_p[40];
    ecc_decoder_data_out[39] = ecc_dec_in[39] ^ corrected_bit_p[39];
    ecc_decoder_data_out[38] = ecc_dec_in[38] ^ corrected_bit_p[38];
    ecc_decoder_data_out[37] = ecc_dec_in[37] ^ corrected_bit_p[37];
    ecc_decoder_data_out[36] = ecc_dec_in[36] ^ corrected_bit_p[36];
    ecc_decoder_data_out[35] = ecc_dec_in[35] ^ corrected_bit_p[35];
    ecc_decoder_data_out[34] = ecc_dec_in[34] ^ corrected_bit_p[34];
    ecc_decoder_data_out[33] = ecc_dec_in[33] ^ corrected_bit_p[33];
    ecc_decoder_data_out[32] = ecc_dec_in[32] ^ corrected_bit_p[32];
    ecc_decoder_data_out[31] = ecc_dec_in[31] ^ corrected_bit_p[31];
    ecc_decoder_data_out[30] = ecc_dec_in[30] ^ corrected_bit_p[30];
    ecc_decoder_data_out[29] = ecc_dec_in[29] ^ corrected_bit_p[29];
    ecc_decoder_data_out[28] = ecc_dec_in[28] ^ corrected_bit_p[28];
    ecc_decoder_data_out[27] = ecc_dec_in[27] ^ corrected_bit_p[27];
    ecc_decoder_data_out[26] = ecc_dec_in[26] ^ corrected_bit_p[26];
    ecc_decoder_data_out[25] = ecc_dec_in[25] ^ corrected_bit_p[25];
    ecc_decoder_data_out[24] = ecc_dec_in[24] ^ corrected_bit_p[24];
    ecc_decoder_data_out[23] = ecc_dec_in[23] ^ corrected_bit_p[23];
    ecc_decoder_data_out[22] = ecc_dec_in[22] ^ corrected_bit_p[22];
    ecc_decoder_data_out[21] = ecc_dec_in[21] ^ corrected_bit_p[21];
    ecc_decoder_data_out[20] = ecc_dec_in[20] ^ corrected_bit_p[20];
    ecc_decoder_data_out[19] = ecc_dec_in[19] ^ corrected_bit_p[19];
    ecc_decoder_data_out[18] = ecc_dec_in[18] ^ corrected_bit_p[18];
    ecc_decoder_data_out[17] = ecc_dec_in[17] ^ corrected_bit_p[17];
    ecc_decoder_data_out[16] = ecc_dec_in[16] ^ corrected_bit_p[16];
    ecc_decoder_data_out[15] = ecc_dec_in[15] ^ corrected_bit_p[15];
    ecc_decoder_data_out[14] = ecc_dec_in[14] ^ corrected_bit_p[14];
    ecc_decoder_data_out[13] = ecc_dec_in[13] ^ corrected_bit_p[13];
    ecc_decoder_data_out[12] = ecc_dec_in[12] ^ corrected_bit_p[12];
    ecc_decoder_data_out[11] = ecc_dec_in[11] ^ corrected_bit_p[11];
    ecc_decoder_data_out[10] = ecc_dec_in[10] ^ corrected_bit_p[10];
    ecc_decoder_data_out[9] = ecc_dec_in[9] ^ corrected_bit_p[9];
    ecc_decoder_data_out[8] = ecc_dec_in[8] ^ corrected_bit_p[8];
    ecc_decoder_data_out[7] = ecc_dec_in[7] ^ corrected_bit_p[7];
    ecc_decoder_data_out[6] = ecc_dec_in[6] ^ corrected_bit_p[6];
    ecc_decoder_data_out[5] = ecc_dec_in[5] ^ corrected_bit_p[5];
    ecc_decoder_data_out[4] = ecc_dec_in[4] ^ corrected_bit_p[4];
    ecc_decoder_data_out[3] = ecc_dec_in[3] ^ corrected_bit_p[3];
    ecc_decoder_data_out[2] = ecc_dec_in[2] ^ corrected_bit_p[2];
    ecc_decoder_data_out[1] = ecc_dec_in[1] ^ corrected_bit_p[1];
    ecc_decoder_data_out[0] = ecc_dec_in[0] ^ corrected_bit_p[0];
  end




//synopsys translate_off
parameter numOfCodewordBit = 538;
parameter numOfDataBit = 527;
parameter numOfParityBits = 11;
reg [(numOfParityBits-1):0] G [0:(numOfDataBit-1)] ;
reg [(numOfParityBits-1):0] GI [0:(numOfCodewordBit-1)] ;


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


task GenerateGIMatrix;
integer i;
begin
  for (i = 0; i < numOfDataBit; i= i+1) begin
    GI[i] = G[i];
  end
  for (i = numOfDataBit; i < numOfCodewordBit; i= i+1) begin
    GI[i] = 1 << (i - numOfDataBit );
  end
end
endtask

task read_ecc_task;
integer p, q;
input [(numOfCodewordBit - 1):0]  ecc_decoder_data_in;
output [(numOfDataBit - 1):0] ecc_decoder_data_out;
output [1:0] ecc_error_type;

reg [numOfParityBits -1 :0] syndrome;
reg [(numOfCodewordBit - 1):0]  G_col;

begin
  if (^ecc_decoder_data_in === 1'bx) $display("[%m]: <ERROR>[%0t]  UNKNOWN ecc_decoder_data_in = %b ", $time, ecc_decoder_data_in);
  else
  for (p = 0; p < numOfParityBits; p++)
  begin
    for (q = 0; q < numOfCodewordBit; q++)
    begin
      G_col[q] = GI[q][p];
    end
    syndrome[p] = ~^(G_col & ecc_decoder_data_in);
  end

  for (q = 0; q < numOfCodewordBit; q++)
  begin
    if (GI[q] == syndrome)
    begin
      ecc_decoder_data_in[q] = !ecc_decoder_data_in[q];
    end
  end

  ecc_decoder_data_out = ecc_decoder_data_in[(numOfDataBit - 1):0];
  
  ecc_error_type[0] =  |syndrome;
  ecc_error_type[1] = (|syndrome) && !(^syndrome);
  
end
endtask

task strip_ecc_task;
input [(numOfCodewordBit - 1):0] ecc_decoder_data_in;
output [(numOfDataBit - 1):0]  ecc_decoder_data_out;
begin
  ecc_decoder_data_out = ecc_decoder_data_in[(numOfDataBit - 1):0];
end
endtask

initial begin
  GenerateGMatrix;
  GenerateGIMatrix;
end
//synopsys translate_on


endmodule
