//
// coding convention dudy December 2018
// (c) Technion IIT, Department of Electrical Engineering 2025
// generating a number bitmap 



module NumbersBitMap	(	
					input		logic	clk,
					input		logic	resetN,
					input 	logic	[10:0] offsetX,// offset from top left  position 
					input 	logic	[10:0] offsetY,
					input		logic	InsideRectangle, //input that the pixel is within a bracket
					input 	logic	[7:0] digit, // two BCD digits to display: {tens[7:4], ones[3:0]}

					output	logic				drawingRequest, //output that the pixel should be dispalyed
					output	logic	[7:0]		RGBout
);


localparam logic[12:0] OBJECT_WIDTH_X = 6'd16;
localparam logic[12:0] OBJECT_WIDTH_Y = 6'd32;
localparam logic[12:0] digit_location_MIF = OBJECT_WIDTH_X*OBJECT_WIDTH_Y;

// generating a number bitmap from a MIF file
logic [12:0] address  ;
logic  color  ;

// Each digit is drawn double-size = 32 px wide.  The left 32 px of the box show
// the tens digit, the right 32 px show the ones digit.
logic [3:0]  curDigit ;
logic [10:0] localX ;
always_comb begin
	if (offsetX < 11'd32) begin
		curDigit = digit[7:4] ; // tens
		localX   = offsetX ;
	end
	else begin
		curDigit = digit[3:0] ; // ones
		localX   = offsetX - 11'd32 ;
	end
end

assign address = ((digit_location_MIF*curDigit)+((offsetY>>1)*OBJECT_WIDTH_X + (localX>>1))); //***Double size
//assign address = ((digit_location_MIF*digit)+((offsetY)*OBJECT_WIDTH_X + (offsetX))); //Origimal size of digit
	//***comment the previous line and adjust the square object to double size as the size of a double bitmap

parameter  logic	[7:0] digit_color = 8'hff ; //set the color of the digit 

lpm_rom #(
    .LPM_WIDTH(1),
    .LPM_WIDTHAD(13),
	 .LPM_NUMWORDS(8192),
    .LPM_FILE("RTL/numbers.mif"),
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
    .q(color)
);

// pipeline (ff) to get the pixel color from the array 	 

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		drawingRequest <=	1'b0;
		
	end
	
	else begin
		drawingRequest <=	1'b0;
	  	if (InsideRectangle == 1'b1 )
			drawingRequest <= (color == 1'b1) ? 1'b1 : 1'b0;
 	end 
end

assign RGBout = digit_color ; // this is a fixed color 


endmodule