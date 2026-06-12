
// (c) Technion IIT, Department of Electrical Engineering 2025 
//-- Alex Grinshpun Apr 2017
//-- Dudy Nov 13 2017
// SystemVerilog version Alex Grinshpun May 2018
// coding convention dudy December 2018

//-- Eyal Lev 31 Jan 2021

// ===========================================================================
// Pixel compositor (objects_mux).  Several drawing layers each say "this pixel
// is mine" (a *DrawingRequest) and offer a color (*RGB); this module picks the
// winner by fixed priority and outputs the final pixel color RGBOut.
//
// PORT GLOSSARY (names are kept from the skeleton; here is what they mean now):
//   smileyDrawingRequest / smileyRGB : DEAD layer (the old bouncing smiley was
//                                      removed) - kept only so the schematic
//                                      wiring does not need to change.
//   BoxDrawingRequest    / BoxRGB    : the SCORE NUMBER box (top-left digits).
//   HartDrawingRequest   / hartRGB   : the SNAKE BOARD (snake + apples + cake).
//   BGDrawingRequest     / backGroundRGB : the drawn background layer.
//   RGB_MIF                          : background image from ROM (last resort).
//
// Priority (highest first): score number > snake board > background > ROM image.
// ===========================================================================

module	objects_mux	(
//		--------	Clock Input
					input		logic	clk,
					input		logic	resetN,
		   // smiley (dead layer - kept for schematic compatibility)
					input		logic	smileyDrawingRequest,
					input		logic	[7:0] smileyRGB,

		  // score-number box
					input		logic	BoxDrawingRequest,
					input		logic	[7:0] BoxRGB,



		  ////////////////////////
		  // snake board + background
					input    logic HartDrawingRequest, // snake board layer
					input		logic	[7:0] hartRGB,
					input		logic	[7:0] backGroundRGB,
					input		logic	BGDrawingRequest,
					input		logic	[7:0] RGB_MIF,

				   output	logic	[7:0] RGBOut
);

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
			RGBOut	<= 8'b0;
	end
	
	else begin
		if (1'b0)   // smiley removed (deprecated) - dead branch, kept to preserve the port
			RGBOut <= smileyRGB;

		else if (BoxDrawingRequest == 1'b1 )
			RGBOut <= BoxRGB;       // 1st priority: the score number

		else if (HartDrawingRequest == 1'b1)
			RGBOut <= hartRGB;      // 2nd priority: the snake board
		else if (BGDrawingRequest == 1'b1)
			RGBOut <= backGroundRGB ;// 3rd priority: drawn background
		else RGBOut <= RGB_MIF ;    // last priority: background ROM image
		end ; 
	end

endmodule


