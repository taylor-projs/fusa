module fifo_sync #(
parameter M = 2,  // fifo address width, depth = 2^M
          N = 32  // fifo data width.
		  ) (
   input               rst_n    
  ,input               clk      
  ,input               wr       
  ,input      [N-1:0]  d  
  ,output reg          ff      
  ,input               rdy      
  ,output reg          vld      
  ,output reg [N-1:0]  q  
);

parameter DEPTH = 1 << M;
reg  [M:0]   wptr, rptr;
reg  [N-1:0] mem[DEPTH-1:0];
wire fe ;
wire rd ;

integer i;

wire [M:0] wptr_ns     = wptr + wr;
wire [M:0] wptr_ns_pls = wptr_ns + 1;
always @( posedge clk or negedge rst_n ) begin
if( !rst_n ) begin
  wptr <= {M+1{1'b0}};
end else begin
  wptr <= wptr_ns;
end 
end

wire [M:0] rptr_ns = rptr + rd ;
always @( posedge clk or negedge rst_n ) begin
if( !rst_n ) begin
  rptr <= {M+1{1'b0}};
end else begin
  rptr <= rptr_ns;
end  
end 

wire ff_d = ( wptr_ns_pls == {~rptr_ns[M], rptr_ns[M-1:0]} );
always @( posedge clk or negedge rst_n ) begin
if( !rst_n ) begin
  ff <= 1'b0;
end else begin
  ff <= ff_d;
end
end

assign fe = ( wptr == rptr );
assign rd = ( wr & (~vld | (rdy & fe)) ) | ( vld & rdy & ~fe ); 
always @( posedge clk or negedge rst_n ) begin
if( !rst_n ) begin
  vld <= 1'b0;
end else if( wr | ~fe ) begin
  vld <= 1'b1;
end else if( rdy ) begin
  vld <= 1'b0;
end
end

always @( posedge clk or negedge rst_n ) begin
if( !rst_n ) begin
  q <= {N{1'b0}};
end else if( wr & (~vld | (rdy & fe)) ) begin
  q <= d ;
end else if( rd ) begin
  q <= mem[rptr[M-1:0]];
end
end

always @( posedge clk or negedge rst_n ) begin
if( !rst_n ) begin
  for( i=0; i< DEPTH; i=i+1 ) begin
    mem[i] <= {N{1'b0}};
  end
end else if( wr ) begin
  mem[wptr[M-1:0]] <= d;
end
end

`ifdef MONITOR
  wire [M:0] fifo_dbg = wptr - rptr ;
`endif

endmodule
