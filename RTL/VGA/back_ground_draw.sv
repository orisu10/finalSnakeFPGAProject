//-- feb 2021 add all colors square 
// (c) Technion IIT, Department of Electrical Engineering 2025


module	back_ground_draw	(	

					input	logic	clk,
					input	logic	resetN,
					input 	logic	[10:0]	pixelX,
					input 	logic	[10:0]	pixelY,
					input 	logic	[18:0]	address,

					output	logic	[7:0]	BG_RGB,
					output	logic		boardersDrawReq, 
					output	logic	[7:0] MIF_VGA
);

const int	xFrameSize	=	635;
const int	yFrameSize	=	475;
const int	bracketOffset =	32;
//const int   COLOR_MARTIX_SIZE  = 16*8 ; // 128 

logic [2:0] redBits;
logic [2:0] greenBits;
logic [1:0] blueBits;
logic [10:0] shift_pixelX;


localparam logic [2:0] DARK_COLOR = 3'b111 ;// bitmap of a dark color
localparam logic [2:0] LIGHT_COLOR = 3'b000 ;// bitmap of a light color

 
localparam  int RED_TOP_Y  = 156 ;
localparam  int RED_LEFT_X  = 256 ;
localparam  int GREEN_RIGHT_X  = 32 ;
localparam  int BLUE_BOTTOM_Y  = 300 ;
localparam  int BLUE_RIGHT_X  = 200 ;
 
parameter  logic [10:0] COLOR_MATRIX_TOP_Y  = 100 ; 
parameter  logic [10:0] COLOR_MATRIX_LEFT_X = 100 ;

 lpm_rom #(
    .LPM_WIDTH(8),
    .LPM_WIDTHAD(19),
	 .LPM_NUMWORDS(307200),
    .LPM_FILE("RTL/VGA_BG.mif"),
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
    .q(MIF_VGA)
);

// this is a block to generate the background 
//it has four sub modules : 

	// 1. draw the yellow borders
	// 2. draw four lines with "bracketOffset" offset from the border 
	// 3. draw a matrix of 256  rectangles with all the colors, each rectangle 16 *2 pixels    	

 
 
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
				redBits <= DARK_COLOR ;	
				greenBits <= DARK_COLOR  ;	
				blueBits <= DARK_COLOR[1:0] ;	 
	end 
	else begin

	// defaults 
		greenBits <= 3'b111 ; 
		redBits <= 3'b000 ;
		blueBits <= 2'b11;//LIGHT_COLOR;
		boardersDrawReq <= 	1'b0 ; 
		
		if (   
		// 1. draw the yellow borders
						((pixelX <= bracketOffset) && (pixelX >=(bracketOffset- bracketOffset/4))) ||
						((pixelY <= bracketOffset) && (pixelY >= (bracketOffset- bracketOffset/4))) ||
						
		// 2. draw four lines with "bracketOffset" offset from the border 
						((pixelX >= (xFrameSize-bracketOffset))&&(pixelX <= (xFrameSize-(bracketOffset- bracketOffset/4)))) || 
						((pixelY >= (yFrameSize-bracketOffset))&&(pixelY <= (yFrameSize-(bracketOffset- bracketOffset/4))))) 
			begin 
					redBits <= LIGHT_COLOR ;	
					greenBits <= DARK_COLOR  ;	
					blueBits <= DARK_COLOR[1:0] ;
					 boardersDrawReq <= 	1'b1;
					//boardersDrawReq <= 	1'b1 ; // pulse if drawing the boarders 
			end
	
				

	// 3. draw a matrix of 16*16 rectangles with all the colors, each rectsangle 8*8 pixels  	
   // ---------------------------------------------------------------------------------------
		if (( pixelY > 4 ) && (pixelY < 20 ) && (pixelX >30 )&& (pixelX <542 ))
		 begin
		        shift_pixelX<= pixelX-11'd29;

             blueBits <= shift_pixelX[8:7] ; 
				 greenBits <= shift_pixelX[3:1] ; 
				 redBits <= shift_pixelX[6:4];       
				 boardersDrawReq <= 	1'b1;
	
				
		 end 
		
		
	BG_RGB <=  { blueBits, redBits, greenBits } ; //collect color nibbles to an 8 bit word		


	end; 	
end 
endmodule

