
// game controller dudy Febriary 2020
// (c) Technion IIT, Department of Electrical Engineering 2021 
//updated --Eyal Lev 2021


module	game_controller	(	
			input	logic	clk,
			input	logic	resetN,
			input	logic	startOfFrame,  // short pulse every start of frame 30Hz 
			input	logic	drawing_request_smiley,
			input	logic	drawing_request_boarders,
			input logic drawing_request_number,

//---------------------#1-add input drawing request of number/box
		
		
		

//---------------------#1-end input drawing request of number/box


// drawing_request_smiley   -->  smiley
// drawing_request_boarders -->  brackets
// drawing_request_number   -->  number/box 

//---------------------#2-add  drawing request of hart

		input logic	drawing_request_hart,

//---------------------#2-end drawing request of hart		

			
			output logic collision, // active in case of collision between two objects
			
			output logic SingleHitPulse, // critical code, generating A single pulse in a frame 
			
			

//---------------------#3-add collision  smiley and hart   -------------------------------------

		   output logic collision_Smiley_Hart // active in case of collision between Smiley and hart

//---------------------#3-end collision  smiley and hart	--------------------------------------
			
);

logic flag ; // a semaphore to set the output only once per frame regardless of number of collisions 
logic collision_smiley_number; // collision between Smiley and number - is not output

assign collision_smiley_boarders = (drawing_request_smiley && drawing_request_boarders);// any collision --> comment after updating with #4 or #5 


//---------------------#4-update  collision  conditions - add collision between smiley and number   ----------------------------

assign collision_smiley_number = (drawing_request_smiley && drawing_request_number); //<collision of smiley and number>;
assign collision_before = (collision_smiley_boarders || collision_smiley_number); //<collision_before> +<collision of smiley and number>; // any collisio

//---------------------#4-end update  collision  conditions - add collision between smiley and number	-------------------------
	
					

//---------------------#5-update  collision  conditions - add collision between smiley and hart  ---------------------------------

assign collision = collision_before || ( drawing_request_smiley && drawing_request_hart ); 

//---------------------#5-end update  collision  conditions	- add collision between smiley and hart	-----------------------------
	

//-------------------------- #6-add colision between Smiley and hart-----------------

assign collision_Smiley_Hart = ( drawing_request_smiley && drawing_request_hart ) ;

//---------------------------#6-end colision betweenand Smiley and hart-----------------



always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN)
	begin 
		flag	<= 1'b0;
		SingleHitPulse <= 1'b0 ; 
		
	end 
	else begin 
	
			SingleHitPulse <= 1'b0 ; // default 
			if(startOfFrame) 
				flag <= 1'b0 ; // reset for next time 
				
//	----#7 - change the collision condition below to collision_smiley_number ---------

if ( collision_smiley_number  && (flag == 1'b0)) begin 
			flag	<= 1'b1; // to enter only once 
			SingleHitPulse <= 1'b1 ; 
		end ; 
 
	end 
end

endmodule

//// game controller dudy Febriary 2020
//// (c) Technion IIT, Department of Electrical Engineering 2021 
////updated --Eyal Lev 2021
//
//
//module	game_controller	(	
//			input	logic	clk,
//			input	logic	resetN,
//			input	logic	startOfFrame,  // short pulse every start of frame 30Hz 
//			input	logic	drawing_request_smiley,
//			input	logic	drawing_request_boarders,
//
////---------------------#1-add input drawing request of box/number
//		
//		
//
////---------------------#1-end input drawing request of box/number
//
//
//
//
////---------------------#2-add  drawing request of hart
//
//		
//
////---------------------#2-end drawing request of hart		
//
//			
//			output logic collision, // active in case of collision between two objects
//			
//			output logic SingleHitPulse, // critical code, generating A single pulse in a frame 
//			
//			
//
////---------------------#3-add collision  smiley and hart   -------------------------------------
//
//
//		//	output logic collision_Smiley_Hart // active in case of collision between Smiley and hart
//
//
////---------------------#3-end collision  smiley and hart	--------------------------------------
//			
//
//
//);
//logic collision_smiley_number; // collision between Smiley and number - is not output
//
//// drawing_request_smiley   -->  smiley
//// drawing_request_boarders -->  brackets
//// drawing_request_number   -->  number/box 
//
////assign collision = (drawing_request_smiley && drawing_request_boarders);// any collision --> comment after updating with #4 or #5 
//
////---------------------#4-update  collision  conditions - add collision between smiley and number   ----------------------------
//
////assign collision = <collision_before> +<collision smiley and number>;
//
//
////---------------------#4-end update  collision  conditions	 - add collision between smiley and number	-------------------------
//	
//					
//						
//
////---------------------#5-update  collision  sconditions - add collision between smiley and hart  ---------------------------------
//
////assign collision = <collision_before> +( drawing_request_smiley && drawing_request_hart ); 
//	assign collision = (( drawing_request_smiley && ( drawing_request_boarders || drawing_request_number )) || 
//						( drawing_request_boarders && drawing_request_number )||( drawing_request_smiley && drawing_request_hart )); 
//
//
////---------------------#5-end update  collision  conditions	- add collision between smiley and hart	-----------------------------
//	
//
//
//
////-------------------------- #6-add colision between Smiley and hart-----------------
//
//assign collision_Smiley_Hart = ( drawing_request_smiley && drawing_request_hart ) ;
//assign collision_smiley_number = ( drawing_request_smiley &&  drawing_request_number ); // collision of number and smiley
//
////---------------------------#6-end colision betweenand Smiley and hart-----------------
//
//
//
//logic flag ; // a semaphore to set the output only once per frame regardless of number of collisions 
//
//
//always_ff@(posedge clk or negedge resetN)
//begin
//	if(!resetN)
//	begin 
//		flag	<= 1'b0;
//		SingleHitPulse <= 1'b0 ; 
//		
//	end 
//	else begin 
//	
////-------------------------- #7-add colision between Smiley and number-----------------
//
//
//
////-------------------------- #7-end colision between Smiley and number-----------------	
//		
//		
//			SingleHitPulse <= 1'b0 ; // default 
//			if(startOfFrame) 
//				flag <= 1'b0 ; // reset for next time 
//				
////	---#7 - change the condition below to collision between Smiley and number ---------
//
//if ( collision_smiley_number  && (flag == 1'b0)) begin 
//			flag	<= 1'b1; // to enter only once 
//			SingleHitPulse <= 1'b1 ; 
//		end ; 
// 
//	end 
//end
//
//endmodule
//
////// game controller dudy Febriary 2020
////// (c) Technion IIT, Department of Electrical Engineering 2025 
//////updated --Eyal Lev 2021
////
////
////module	game_controller	(	
////			input	logic	clk,
////			input	logic	resetN,
////			input	logic	startOfFrame,  // short pulse every start of frame 30Hz 
////			input	logic	drawing_request_smiley,
////			input	logic	drawing_request_boarders,
////			input	logic	drawing_request_number,
////			input	logic	drawing_request_hart,
////       // add the box here 
////			
////			output logic collision, // active in case of collision between two objects
////			
////			output logic SingleHitPulse, // critical code, generating A single pulse in a frame 
////			output logic collision_Smiley_Hart // active in case of collision between two objects
////			
////);
////
////
////logic collision_smiley_number;
////
////assign collision = (( drawing_request_smiley && ( drawing_request_boarders || drawing_request_number )) || 
////						( drawing_request_boarders && drawing_request_number )||( drawing_request_smiley && drawing_request_hart )); 
////						
////						
////assign collision_Smiley_Hart = ( drawing_request_smiley &&  drawing_request_hart ) ;
////assign collision_smiley_number = ( drawing_request_smiley &&  drawing_request_number ); // collision of number and smiley
////
////
////// add colision between number and Smiley
//////_______________________________________________________
////
////
////logic flag ; // a semaphore to set the output only once per frame / regardless of the number of collisions 
////
////
////always_ff@(posedge clk or negedge resetN)
////begin
////	if(!resetN)
////	begin 
////		flag	<= 1'b0;
////		SingleHitPulse <= 1'b0 ; 
////	end 
////	else begin 
////			SingleHitPulse <= 1'b0 ; // default 
////			if(startOfFrame) 
////				flag <= 1'b0 ; // reset for next time 
////				
//////		change the section below  to collision between number and smiley
////
////
////if ( collision_smiley_number  && (flag == 1'b0)) begin 
////			flag	<= 1'b1; // to enter only once 
////			SingleHitPulse <= 1'b1 ; 
////		end ; 
////
////	end 
////end
////
////endmodule
