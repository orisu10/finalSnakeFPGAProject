// HartsMatrixBitMap File 
// A two level bitmap. dosplaying harts on the screen Feb 2025 
//(c) Technion IIT, Department of Electrical Engineering 2025 



module	HartsMatrixBitMap	(	
					input	logic	clk,
					input	logic	resetN,
					input logic	[10:0] offsetX,// offset from top left  position 
					input logic	[10:0] offsetY,
					input	logic	InsideRectangle, //input that the pixel is within a bracket 
					input logic random_hart,
					input logic collision_Smiley_Hart,

					output	logic	drawingRequest, //output that the pixel should be dispalyed 
					output	logic	[7:0] RGBout  //rgb value from the bitmap 
 ) ;
 

localparam logic [7:0] TRANSPARENT_ENCODING = 8'hFF ;// RGB value in the bitmap representing a transparent pixel 


localparam  logic [9:0] TILE_NUMBER_OF_X_BITS = 5;  // 2^5 = 32  everu object 
localparam  logic [9:0] TILE_NUMBER_OF_Y_BITS = 5;  // 2^5 = 32 

localparam  int MAZE_NUMBER_OF__X_BITS = 4;  // 2^4 = 16 / /the maze of the objects 
localparam  int MAZE_NUMBER_OF__Y_BITS = 3;  // 2^3 = 8 

//-----

localparam  logic [9:0] TILE_WIDTH_X = 10'b1 << TILE_NUMBER_OF_X_BITS ;
localparam  logic [9:0] TILE_HEIGHT_Y = 1'b1 <<  TILE_NUMBER_OF_Y_BITS ;
localparam  logic [10:0] MAZE_WIDTH_X = 11'b1 << MAZE_NUMBER_OF__X_BITS ;
localparam  logic [10:0] MAZE_HEIGHT_Y = 11'b1 << MAZE_NUMBER_OF__Y_BITS ;


 logic [9:0] offsetX_LSB  ;
 logic [9:0] offsetY_LSB  ; 
 logic [10:0] offsetX_MSB ;
 logic [10:0] offsetY_MSB  ;
 logic [9:0] address  ;
 logic [0:1][7:0] color  ;

 assign offsetX_LSB  = offsetX[(TILE_NUMBER_OF_X_BITS-1):0] ; // get lower bits 
 assign offsetY_LSB  = offsetY[(TILE_NUMBER_OF_Y_BITS-1):0] ; // get lower bits 
 assign offsetX_MSB  = offsetX[(TILE_NUMBER_OF_X_BITS + MAZE_NUMBER_OF__X_BITS -1 ):TILE_NUMBER_OF_X_BITS] ; // get higher bits 
 assign offsetY_MSB  = offsetY[(TILE_NUMBER_OF_Y_BITS + MAZE_NUMBER_OF__Y_BITS -1 ):TILE_NUMBER_OF_Y_BITS] ; // get higher bits 
 assign address = (offsetY_LSB*TILE_WIDTH_X + offsetX_LSB);



 
// the screen is 640*480  or  20 * 15 squares of 32*32  bits ,  we wiil round up to 8 *16 
// this is the bitmap  of the maze , if there is a specific value  the  whole 32*32 rectange will be drawn on the screen
// there are  16 options of differents kinds of 32*32 squares 
// all numbers here are hard coded to simplify the understanding 


logic [0:(MAZE_HEIGHT_Y-1)][0:(MAZE_WIDTH_X-1)] [3:0]  MazeBitMapMask ;  

logic [0:(MAZE_HEIGHT_Y-1)][0:(MAZE_WIDTH_X-1)] [3:0]   MazeDefaultBitMapMask= // defult table to load on reset 
{{64'h1001110000011100},
 {64'h0010001101100010},
 {64'h0001000010000100},
 {64'h0020100000001200},
 {64'h0000010000010000},
 {64'h0000001000100000},
 {64'h0000000101000000},
 {64'h0000000010000000}};

lpm_rom #(
    .LPM_WIDTH(8),
    .LPM_WIDTHAD(10),
	 .LPM_NUMWORDS(1024),
    .LPM_FILE("RTL/heart1.mif"),
	   .LPM_TYPE               ("LPM_ROM"),
      .LPM_ADDRESS_CONTROL    ("REGISTERED"), 
		.LPM_OUTDATA            ("UNREGISTERED"), 
		.AUTO_CARRY_CHAINS      ("ON"),
		.AUTO_CASCADE_BUFFERS   ("ON"),
	   .INTENDED_DEVICE_FAMILY ("Cyclone V")  
) rom_inst (
    .address(address),
	 .inclock(clk),
	// .outclock(clk),
    .q(color[0])
);

 
lpm_rom #(
    .LPM_WIDTH(8),
    .LPM_WIDTHAD(10),
	 .LPM_NUMWORDS(1024),
    .LPM_FILE("RTL/heart2.mif"),
	   .LPM_TYPE               ("LPM_ROM"),
      .LPM_ADDRESS_CONTROL    ("REGISTERED"), 
		.LPM_OUTDATA            ("UNREGISTERED"), 
		.AUTO_CARRY_CHAINS      ("ON"),
		.AUTO_CASCADE_BUFFERS   ("ON"),
	   .INTENDED_DEVICE_FAMILY ("Cyclone V")  
) rom_inst2 (
    .address(address),
	 .inclock(clk),
	// .outclock(clk),
    .q(color[1])
); 

 

//==----------------------------------------------------------------------------------------------------------------=
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		RGBout <=	8'h00;
		MazeBitMapMask  <=  MazeDefaultBitMapMask ;  //  copy default tabel 
	end
	else begin
		RGBout <= TRANSPARENT_ENCODING ; // default 
		if (collision_Smiley_Hart)
			MazeBitMapMask[offsetY_MSB][offsetX_MSB] <= 4'h00;  // clear entry 
		
		if (InsideRectangle == 1'b1 )	
			begin 
		   	case (MazeBitMapMask[offsetY_MSB][offsetX_MSB])
					 4'h0 : RGBout <= TRANSPARENT_ENCODING ;
			   	 4'h1 : RGBout <= color[random_hart]; 
					 4'h2 : RGBout <= color[1] ; 
					 default:  RGBout <= TRANSPARENT_ENCODING ; 
				endcase
			end 

	end 
end

//==----------------------------------------------------------------------------------------------------------------=
// decide if to draw the pixel or not 
assign drawingRequest = (RGBout != TRANSPARENT_ENCODING ) ? 1'b1 : 1'b0 ; // get optional transparent command from the bitmpap   
endmodule

