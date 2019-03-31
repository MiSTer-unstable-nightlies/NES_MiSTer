// Namco mappers

module N106(
	input clk,
	input ce,
	input reset,
	input [31:0] flags,
	input [15:0] prg_ain,
	output [21:0] prg_aout,
	input prg_read,
	input prg_write,                   // Read / write signals
	input [7:0] prg_din,
	output [7:0] prg_dout,
	output prg_allow,                  // Enable access to memory for the specified operation.
	input [13:0] chr_ain,
	output [21:0] chr_aout,
	output chr_allow,                  // Allow write
	output vram_a10,                   // Value for A10 address line
	output vram_ce,                    // True if the address should be routed to the internal 2kB VRAM.
	output irq,
	output [15:0] audio
);

wire nesprg_oe;
wire [7:0] neschrdout;
wire neschr_oe;
wire wram_oe;
wire wram_we;
wire prgram_we;
wire chrram_oe;
wire prgram_oe;
wire [18:13] ramprgaout;
wire exp6;
reg [7:0] m2;
wire m2_n = 1;//~ce;  //m2_n not used as clk.  Invert m2 (ce).

always @(posedge clk) begin
	m2[7:1] <= m2[6:0];
	m2[0] <= ce;
end

MAPN106 n106(m2[7], m2_n, clk, reset, prg_write, nesprg_oe, 0,
	1, prg_ain, chr_ain, prg_din, 8'b0, prg_dout,
	neschrdout, neschr_oe, chr_allow, chrram_oe, wram_oe, wram_we, prgram_we,
	prgram_oe, chr_aout[18:10], ramprgaout, irq, vram_ce, exp6,
	0, 7'b1111111, 6'b111111, flags[14], flags[16], flags[15],
	ce, (flags[7:0]==210), flags[24:21], audio[15:5]);

assign chr_aout[21:19] = 3'b100;
assign chr_aout[9:0] = chr_ain[9:0];
assign vram_a10 = chr_aout[10];
wire [21:13] prg_aout_tmp = {3'b00_0, ramprgaout};
wire [21:13] prg_ram = {9'b11_1100_000};
wire prg_is_ram = prg_ain >= 'h6000 && prg_ain < 'h8000;
assign prg_aout[21:13] = prg_is_ram ? prg_ram : prg_aout_tmp;
assign prg_aout[12:0] = prg_ain[12:0];
assign prg_allow = (prg_ain[15] && !prg_write) || prg_is_ram;
assign audio[4:0] = 4'b0;

endmodule


//Taken from Loopy's Power Pak mapper source mapN106.v
//fixme- sound ram is supposed to be readable (does this affect any games?)
module MAPN106(     //signal descriptions in powerpak.v
	input m2,
	input m2_n,
	input clk20,

	input reset,
	input nesprg_we,
	output nesprg_oe,
	input neschr_rd,
	input neschr_wr,
	input [15:0] prgain,
	input [13:0] chrain,
	input [7:0] nesprgdin,
	input [7:0] ramprgdin,
	output reg [7:0] nesprgdout,

	output [7:0] neschrdout,
	output neschr_oe,

	output reg chrram_we,
	output reg chrram_oe,
	output wram_oe,
	output wram_we,
	output prgram_we,
	output prgram_oe,
	output reg [18:10] ramchraout,
	output [18:13] ramprgaout,
	output irq,
	output reg ciram_ce,
	output exp6,

	input cfg_boot,
	input [18:12] cfg_chrmask,
	input [18:13] cfg_prgmask,
	input cfg_vertical,
	input cfg_fourscreen,
	input cfg_chrram,

	input ce,// add
	input mapper210,
	input [3:0] submapper,
	output [15:0] snd_level
);

assign exp6 = 0;

reg [1:0] chr_en;
reg [5:0] prg89,prgAB,prgCD;
reg [7:0] chr0,chr1,chr2,chr3,chr4,chr5,chr6,chr7,chr10,chr11,chr12,chr13;
reg [1:0] mirror;
wire submapper1 = (submapper == 1);

always@(posedge clk20) begin
	if (reset) begin
		mirror <= cfg_vertical ? 2'b01 : 2'b10;
	end else if(ce && nesprg_we)
		case(prgain[15:11])
			5'b10000: chr0<=nesprgdin;              //8000
			5'b10001: chr1<=nesprgdin;
			5'b10010: chr2<=nesprgdin;              //9000
			5'b10011: chr3<=nesprgdin;
			5'b10100: chr4<=nesprgdin;              //A000
			5'b10101: chr5<=nesprgdin;
			5'b10110: chr6<=nesprgdin;              //B000
			5'b10111: chr7<=nesprgdin;
			5'b11000: chr10<=nesprgdin;             //C000
			5'b11001: chr11<=nesprgdin;
			5'b11010: chr12<=nesprgdin;             //D000
			5'b11011: chr13<=nesprgdin;
			5'b11100: {mirror,prg89}<=nesprgdin;    //E000
			5'b11101: {chr_en,prgAB}<=nesprgdin;    //E800
			5'b11110: prgCD<=nesprgdin[5:0];        //F000
			//5'b11111:                             //F800 (sound)
		endcase
end

//IRQ
reg [15:0] count;
wire [15:0] count_next=count+1'd1;
wire countup=count[15] & ~&count[14:0];
reg timeout;
assign irq=timeout;
always@(posedge clk20) begin
if (ce) begin
	if(prgain[15:12]==4'b0101)
		timeout<=0;
	else if(count==16'hFFFF)
		timeout<=1;

	if(nesprg_we & prgain[15:11]==5'b01010)
		count[7:0]<=nesprgdin;
	else if(countup)
		count[7:0]<=count_next[7:0];

	if(nesprg_we & prgain[15:11]==5'b01011)
		count[15:8]<=nesprgdin;
	else if(countup)
		count[15:8]<=count_next[15:8];
	end
end

//PRG bank
reg [18:13] prgbankin;
always@* begin
	case(prgain[14:13])
		0:prgbankin=prg89;
		1:prgbankin=prgAB;
		2:prgbankin=prgCD;
		3:prgbankin=6'b111111;
	endcase
end

assign ramprgaout[18:13]=prgbankin[18:13] & cfg_prgmask & {4'b1111,{2{prgain[15]}}};

//CHR control
reg chrram;
reg [17:10] chrbank;
always@* begin
	case(chrain[13:10])
		0:chrbank=chr0;
		1:chrbank=chr1;
		2:chrbank=chr2;
		3:chrbank=chr3;
		4:chrbank=chr4;
		5:chrbank=chr5;
		6:chrbank=chr6;
		7:chrbank=chr7;
		8,12:chrbank=chr10;
		9,13:chrbank=chr11;
		10,14:chrbank=chr12;
		11,15:chrbank=chr13;
	endcase

	chrram=(~(chrain[12]?chr_en[1]:chr_en[0]))&(&chrbank[17:15]);   //ram/rom select

	if(!chrain[13]) begin
		ciram_ce=0;
		chrram_oe=neschr_rd;
		chrram_we=neschr_wr & chrram;
		ramchraout[10]=chrbank[10];
	end else begin
		ciram_ce=(&chrbank[17:15] | mirror[0]) | mapper210;
		chrram_oe=~ciram_ce & neschr_rd;
		chrram_we=~ciram_ce & neschr_wr & chrram;
		casez({mapper210,submapper1,mirror,cfg_vertical})
			5'b0?_?0_?: ramchraout[10] = chrbank[10];
			5'b0?_?1_?: ramchraout[10] = chrain[10];
			5'b10_00_?: ramchraout[10] = 1'b0;
			5'b10_01_?: ramchraout[10] = chrain[10];
			5'b10_10_?: ramchraout[10] = chrain[11];
			5'b10_11_?: ramchraout[10] = 1'b1;
			5'b11_??_0: ramchraout[10] = chrain[11];
			5'b11_??_1: ramchraout[10] = chrain[10];
		endcase
	end
	ramchraout[11]=chrbank[11];
	ramchraout[17:12]=chrbank[17:12] & cfg_chrmask[17:12];
	ramchraout[18]=chrram;
end

assign wram_oe=m2_n & ~nesprg_we & prgain[15:13]==3'b011;
assign wram_we=m2_n &  nesprg_we & prgain[15:13]==3'b011;

assign prgram_we=0;
assign prgram_oe= ~cfg_boot & m2_n & ~nesprg_we & prgain[15];

wire config_rd = 0;
//wire [7:0] gg_out;
//gamegenie gg(m2, reset, nesprg_we, prgain, nesprgdin, ramprgdin, gg_out, config_rd);

//PRG data out
wire counter_oe = m2_n & ~nesprg_we & prgain[15:12]=='b0101;
always @* begin
	case(prgain[15:11])
		5'b01010: nesprgdout=count[7:0];
		5'b01011: nesprgdout=count[15:8];
		default: nesprgdout=nesprgdin;
	endcase
end

assign nesprg_oe=wram_oe | prgram_oe | counter_oe | config_rd;

assign neschr_oe=0;
assign neschrdout=0;

//sound
wire [10:0] n106_out;
wire [9:0] saturated=n106_out[9:0] | {10{n106_out[10]}};    //this is still too quiet for the suggested 47k resistor, but more clipping will make some games sound bad

namco106_sound n106(ce, clk20, reset, nesprg_we, prgain, nesprgdin, n106_out);

//pdm #(10) pdm_mod(clk20, saturated, exp6);
assign snd_level = (mapper210 | mirror[0]) ? 16'b0 : {6'b0, saturated};

endmodule

module namco106_sound(
	input m2,
	input clk20,
	input reset,
	input wr,
	input [15:0] ain,
	input [7:0] din,
	output reg [10:0] out       //range is 0..0x708
);

reg carry;
reg autoinc;
reg [6:0] ram_ain;
reg [6:0] ram_aout;
wire [7:0] ram_dout;
reg [2:0] ch;
reg [7:0] cnt_L[7:0];
reg [7:0] cnt_M[7:0];
reg [1:0] cnt_H[7:0];
wire [2:0] sum_H=cnt_H[ch]+ram_dout[1:0]+carry;
reg [4:0] sample_pos[7:0];
reg [2:0] cycle;
reg [3:0] sample;
wire [7:0] chan_out=sample*ram_dout[3:0];   //sample*vol
reg [10:0] out_acc;
wire [10:0] sum=out_acc+chan_out;
reg addr_lsb;
wire [7:0] sample_addr=ram_dout+sample_pos[ch];

//ram in
always@(posedge clk20) begin
if (m2) begin
	if(wr & ain[15:11]==5'b11111)           //F800..FFFF
		{autoinc,ram_ain}<=din;
	else if(ain[15:11]==5'b01001 & autoinc) //4800..4FFF
		ram_ain<=ram_ain+1'd1;
	end
end

//mixer FSM
always @* begin
	case(cycle)
		0: ram_aout={1'b1,ch,3'd0};     //freq[7:0]
		1: ram_aout={1'b1,ch,3'd2};     //freq[15:8]
		2: ram_aout={1'b1,ch,3'd4};     //length, freq[17:16]
		3: ram_aout={1'b1,ch,3'd6};     //address
		4: ram_aout=sample_addr[7:1];   //sample address
		5: ram_aout={1'b1,ch,3'd7};     //volume
		default: ram_aout=7'bXXXXXXX;
	endcase
end

reg [3:0] count45,cnt45;
always@(posedge clk20)
	if (m2) begin
	count45<=(count45==14)?4'd0:count45+1'd1;
	end
always@(posedge clk20) begin
	cnt45<=count45;
	if(cnt45[1:0]==0) cycle<=0;             // this gives 45 21.4M clocks per channel
	else if(cycle!=7) cycle<=cycle+1'd1;
	case(cycle)
		1: {carry, cnt_L[ch]}<=cnt_L[ch][7:0]+ram_dout;
		2: {carry, cnt_M[ch]}<=cnt_M[ch][7:0]+ram_dout+carry;
		3: begin
			cnt_H[ch]<=sum_H[1:0];
			if(sum_H[2])
				sample_pos[ch]<=(sample_pos[ch]=={ram_dout[4:2]^3'b111,2'b11})?5'd0:(sample_pos[ch]+1'd1);
		end
		4: addr_lsb<=sample_addr[0];
		5: sample<=addr_lsb?ram_dout[7:4]:ram_dout[3:0];
		6: begin
			if(ch==7) begin
				ch<=~ram_dout[6:4];
				out_acc<=0;
				out<=sum;
			end else begin
				ch<=ch+1'd1;
				out_acc<=sum;
			end
		end
	endcase
end

dpram #(.widthad_a(7)) modtable
(
	.clock_a   (clk20),
	.address_a (ram_ain),
	.wren_a    (wr & ain[15:11]==5'b01001),
	.byteena_a (1),
	.data_a    (din),

	.clock_b   (clk20),
	.address_b (ram_aout),
	.wren_b    (0),
	.byteena_b (1),
	.data_b    (0),
	.q_b       (ram_dout)
);

endmodule
