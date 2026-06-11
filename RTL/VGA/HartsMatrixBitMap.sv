// ===========================================================================
// Snake board  (Slimming Snake project, Spring 2026)            STEP 6
// ---------------------------------------------------------------------------
// Board: 20 x 15 grid of 32x32 px tiles (20*32=640, 15*32=480).
//
// Data model:
//   * snakeCol[i]/snakeRow[i] + length : the ordered body (a shift register).
//   * foodGrid  : apple / cake cells (separate from the snake).
//   * snakeGrid : head / body type per cell, for rendering & collision.
//
// Control: 8 = up, 2 = down, 4 = left, 6 = right; 180-degree turns rejected.
//
// Food: ONE apple (eat -> score +1, snake SLIMS, new apple at a random free
//       cell via LFSR); cakes start at one and slowly accumulate (eat -> GROW).
//
// STEP 6 additions:
//   * SPEED-UP: the step interval shrinks a little with every apple eaten, so
//     the snake gradually gets faster (down to a floor).
//   * WIN: slimming down to the minimum length wins the game.
//   * TWO-DIGIT score on the `score[7:0]` output ({tens, ones}).
//   * soundCode[2:0] tells the audio block which of 4 sounds to play:
//       1 = apple, 2 = cake, 3 = die, 4 = win   (0 = silent).
//
// Game FSM: INIT -> PLAY -> {OVER | WIN} -> auto-restart.
//
// (c) Technion IIT, Department of Electrical Engineering 2026
// ===========================================================================

module	HartsMatrixBitMap	(
					input	logic	clk,
					input	logic	resetN,
					input	logic	[10:0] offsetX,
					input	logic	[10:0] offsetY,
					input	logic	InsideRectangle,
					input	logic	random_hart,            // unused (interface compatibility)
					input	logic	collision_Smiley_Hart,  // unused (interface compatibility)
					input	logic	[3:0] keyPad,           // last number key (8/2/4/6 steer)

					output	logic	[7:0] score,            // {tens[7:4], ones[3:0]} for the display
					output	logic	[3:0] soundSelect,      // melody index for the AUDIO block (per event)
					output	logic	soundTrigger,           // short pulse = "start that melody"
					output	logic	drawingRequest,
					output	logic	[7:0] RGBout
 ) ;

localparam logic [7:0] TRANSPARENT_ENCODING = 8'hFF ;

// ---- board geometry --------------------------------------------------------
localparam int TILE_BITS = 5 ;
localparam int NUM_COLS  = 20 ;
localparam int NUM_ROWS  = 15 ;

// ---- snake sizing ----------------------------------------------------------
localparam int MAX_LEN   = 40 ;
localparam int INIT_LEN  = 8  ;
localparam int MIN_LEN   = 2  ; // slimming down to here = WIN

// ---- timing (clk = 31.5 MHz pixel clock) -----------------------------------
localparam int TICK_BASE        = 6_000_000   ; // ~5 steps/s at the start
localparam int TICK_STEP        = 400_000     ; // faster by this much per apple
localparam int TICK_MIN         = 1_500_000   ; // speed floor (~21 steps/s)
localparam int RESTART_DELAY    = 45_000_000  ; // ~1.5 s frozen on game over
localparam int WIN_HOLD         = 90_000_000  ; // ~3 s win screen
localparam int CAKE_SPAWN_DELAY = 200_000_000 ; // ~6.3 s between new cakes
localparam int MAX_CAKES        = 6           ;
localparam int TRIG_WIDTH       = 4096        ; // start-melody pulse width (~0.13 ms)

// ---- encodings -------------------------------------------------------------
localparam logic [1:0] F_EMPTY = 2'd0, F_APPLE = 2'd1, F_CAKE = 2'd2 ;
localparam logic [1:0] S_EMPTY = 2'd0, S_HEAD  = 2'd1, S_BODY = 2'd2 ;
localparam logic [1:0] DIR_RIGHT = 2'd0, DIR_DOWN = 2'd1, DIR_LEFT = 2'd2, DIR_UP = 2'd3 ;
localparam logic [1:0] ST_INIT = 2'd0, ST_PLAY = 2'd1, ST_OVER = 2'd2, ST_WIN = 2'd3 ;
// melody indices into songs.mif (any 4 distinct songs give 4 distinct sounds)
localparam logic [3:0] MEL_APPLE = 4'd1, MEL_CAKE = 4'd2, MEL_DIE = 4'd3, MEL_WIN = 4'd4 ;

// ---- tile colors: RED = bits[7:5], GREEN = bits[4:2], BLUE = bits[1:0] ------
localparam logic [7:0] COLOR_APPLE = 8'hE0 ; // red
localparam logic [7:0] COLOR_CAKE  = 8'hE3 ; // magenta
localparam logic [7:0] COLOR_HEAD  = 8'hFC ; // yellow
localparam logic [7:0] COLOR_BODY  = 8'h1C ; // green
localparam logic [7:0] COLOR_DEAD  = 8'h92 ; // gray  (crashed snake)
localparam logic [7:0] COLOR_WIN   = 8'h1F ; // cyan  (winning snake)

// ---- state -----------------------------------------------------------------
logic [1:0]  foodGrid  [0:NUM_ROWS-1][0:NUM_COLS-1] ;
logic [1:0]  snakeGrid [0:NUM_ROWS-1][0:NUM_COLS-1] ;
logic [4:0]  snakeCol  [0:MAX_LEN-1] ;
logic [3:0]  snakeRow  [0:MAX_LEN-1] ;
logic [5:0]  length ;
logic [1:0]  dir ;
logic [1:0]  gameState ;
logic [3:0]  scoreOnes, scoreTens ;
logic [22:0] tickCnt ;
logic [22:0] tickThreshold ;     // current step interval (shrinks as you eat apples)
logic [26:0] holdCnt ;           // game-over / win freeze timer
logic [27:0] cakeSpawnCnt ;
logic [3:0]  cakeCount ;
logic        applePending, cakeSpawnPending ;
logic [15:0] lfsr ;
logic [12:0] trigCnt ;

assign score = {scoreTens, scoreOnes} ;

// ---- which cell does the current pixel fall in -----------------------------
logic [4:0] colIdx ;
logic [3:0] rowIdx ;
assign colIdx = offsetX[TILE_BITS+4 : TILE_BITS] ;
assign rowIdx = offsetY[TILE_BITS+3 : TILE_BITS] ;

// ---- keypad -> requested direction (with anti-reverse) ---------------------
logic [1:0] reqDir ;
logic       reqIsDir ;
always_comb begin
	reqIsDir = 1'b1 ;
	unique case (keyPad)
		4'd8    : reqDir = DIR_UP ;
		4'd2    : reqDir = DIR_DOWN ;
		4'd4    : reqDir = DIR_LEFT ;
		4'd6    : reqDir = DIR_RIGHT ;
		default : begin reqDir = dir ; reqIsDir = 1'b0 ; end
	endcase
end
logic isReverse ;
always_comb begin
	isReverse = (reqDir == DIR_UP    && dir == DIR_DOWN ) ||
	            (reqDir == DIR_DOWN  && dir == DIR_UP   ) ||
	            (reqDir == DIR_LEFT  && dir == DIR_RIGHT) ||
	            (reqDir == DIR_RIGHT && dir == DIR_LEFT ) ;
end
logic [1:0] newDir ;
assign newDir = (reqIsDir && !isReverse) ? reqDir : dir ;

// ---- next head cell + collisions -------------------------------------------
logic [4:0] nextCol ;
logic [3:0] nextRow ;
logic       wallHit, selfHit, collision ;
always_comb begin
	nextCol = snakeCol[0] ;
	nextRow = snakeRow[0] ;
	unique case (newDir)
		DIR_RIGHT : nextCol = (snakeCol[0] == NUM_COLS-1) ? snakeCol[0] : snakeCol[0] + 5'd1 ;
		DIR_LEFT  : nextCol = (snakeCol[0] == 5'd0)       ? snakeCol[0] : snakeCol[0] - 5'd1 ;
		DIR_DOWN  : nextRow = (snakeRow[0] == NUM_ROWS-1) ? snakeRow[0] : snakeRow[0] + 4'd1 ;
		DIR_UP    : nextRow = (snakeRow[0] == 4'd0)       ? snakeRow[0] : snakeRow[0] - 4'd1 ;
	endcase
end
always_comb begin
	wallHit = (newDir == DIR_RIGHT && snakeCol[0] == NUM_COLS-1) ||
	          (newDir == DIR_LEFT  && snakeCol[0] == 5'd0)       ||
	          (newDir == DIR_DOWN  && snakeRow[0] == NUM_ROWS-1) ||
	          (newDir == DIR_UP    && snakeRow[0] == 4'd0)       ;
	selfHit = !wallHit &&
	          (snakeGrid[nextRow][nextCol] == S_BODY) &&
	          !(nextCol == snakeCol[length-1] && nextRow == snakeRow[length-1]) ;
	collision = wallHit || selfHit ;
end

logic eatApple, eatCake ;
assign eatApple = (foodGrid[nextRow][nextCol] == F_APPLE) ;
assign eatCake  = (foodGrid[nextRow][nextCol] == F_CAKE) ;

// ---- event pulses (combinational, true for the one movement clock) ---------
logic tickNow, appleEatNow, cakeEatNow, dieNow, winNow ;
assign tickNow     = (gameState == ST_PLAY) && (tickCnt >= tickThreshold - 23'd1) ;
assign appleEatNow = tickNow && !collision && eatApple ;
assign cakeEatNow  = tickNow && !collision && eatCake ;
assign dieNow      = tickNow && collision ;
assign winNow      = appleEatNow && (length == 6'(MIN_LEN + 1)) ; // this apple reaches the minimum

// ---- random free cell from the LFSR ----------------------------------------
logic [4:0] candCol, candColSafe ;
logic [3:0] candRow, candRowSafe ;
logic       candValid ;
assign candCol     = lfsr[4:0] ;
assign candRow     = lfsr[11:8] ;
assign candColSafe = (candCol < NUM_COLS) ? candCol : 5'd0 ;
assign candRowSafe = (candRow < NUM_ROWS) ? candRow : 4'd0 ;
assign candValid   = (candCol < NUM_COLS) && (candRow < NUM_ROWS) &&
                     (snakeGrid[candRowSafe][candColSafe] == S_EMPTY) &&
                     (foodGrid [candRowSafe][candColSafe] == F_EMPTY) ;

// ===========================================================================
// Game update
// ===========================================================================
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		gameState <= ST_INIT ;
		tickCnt   <= 23'd0 ;
		holdCnt   <= 27'd0 ;
		dir       <= DIR_RIGHT ;
		lfsr         <= 16'hACE1 ;
		soundSelect  <= 4'd0 ;
		soundTrigger <= 1'b0 ;
		trigCnt      <= 13'd0 ;
	end
	else begin
		lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]} ;

		// ---- pick the melody on an event and emit a short start pulse -------
		// soundSelect is HELD (changes only on a new event) so it stays stable
		// while the chosen melody plays; soundTrigger is a short start pulse.
		if      (winNow)      begin soundSelect <= MEL_WIN ;   soundTrigger <= 1'b1 ; trigCnt <= 13'(TRIG_WIDTH) ; end
		else if (dieNow)      begin soundSelect <= MEL_DIE ;   soundTrigger <= 1'b1 ; trigCnt <= 13'(TRIG_WIDTH) ; end
		else if (appleEatNow) begin soundSelect <= MEL_APPLE ; soundTrigger <= 1'b1 ; trigCnt <= 13'(TRIG_WIDTH) ; end
		else if (cakeEatNow)  begin soundSelect <= MEL_CAKE ;  soundTrigger <= 1'b1 ; trigCnt <= 13'(TRIG_WIDTH) ; end
		else if (trigCnt != 13'd0) trigCnt <= trigCnt - 13'd1 ;
		else soundTrigger <= 1'b0 ;

		case (gameState)

		// -- load the starting board ----------------------------------------
		ST_INIT : begin
			tickCnt          <= 23'd0 ;
			holdCnt          <= 27'd0 ;
			cakeSpawnCnt     <= 28'd0 ;
			dir              <= DIR_RIGHT ;
			length           <= 6'(INIT_LEN) ;
			tickThreshold    <= 23'(TICK_BASE) ;
			scoreOnes        <= 4'd0 ;
			scoreTens        <= 4'd0 ;
			cakeCount        <= 4'd1 ;
			applePending     <= 1'b0 ;
			cakeSpawnPending <= 1'b0 ;

			for (int rr = 0 ; rr < NUM_ROWS ; rr++)
				for (int cc = 0 ; cc < NUM_COLS ; cc++) begin
					foodGrid[rr][cc]  <= F_EMPTY ;
					snakeGrid[rr][cc] <= S_EMPTY ;
				end
			foodGrid[5][15] <= F_APPLE ;
			foodGrid[10][5] <= F_CAKE  ;
			for (int i = 0 ; i < MAX_LEN ; i++) begin
				snakeCol[i] <= (i < INIT_LEN) ? 5'(10 - i) : 5'd3 ;
				snakeRow[i] <= 4'd7 ;
			end
			for (int i = 0 ; i < INIT_LEN ; i++)
				snakeGrid[7][10 - i] <= (i == 0) ? S_HEAD : S_BODY ;

			gameState <= ST_PLAY ;
		end

		// -- play -----------------------------------------------------------
		ST_PLAY : begin
			if (cakeSpawnCnt >= CAKE_SPAWN_DELAY) begin
				cakeSpawnCnt <= 28'd0 ;
				if (cakeCount < MAX_CAKES) cakeSpawnPending <= 1'b1 ;
			end
			else cakeSpawnCnt <= cakeSpawnCnt + 28'd1 ;

			if (tickNow) begin
				tickCnt <= 23'd0 ;
				if (collision) begin
					gameState <= ST_OVER ;
					holdCnt   <= 27'd0 ;
				end
				else begin
					dir <= newDir ;

					if (eatApple) begin
						foodGrid[nextRow][nextCol] <= F_EMPTY ;
						applePending <= 1'b1 ;
						// two-digit score++
						if (scoreOnes == 4'd9) begin
							scoreOnes <= 4'd0 ;
							if (scoreTens < 4'd9) scoreTens <= scoreTens + 4'd1 ;
						end
						else scoreOnes <= scoreOnes + 4'd1 ;
						// gradual speed-up
						if (tickThreshold > 23'(TICK_MIN + TICK_STEP))
							tickThreshold <= tickThreshold - 23'(TICK_STEP) ;
						else
							tickThreshold <= 23'(TICK_MIN) ;
					end
					else if (eatCake) begin
						foodGrid[nextRow][nextCol] <= F_EMPTY ;
						cakeCount <= cakeCount - 4'd1 ;
					end

					// old head -> body
					snakeGrid[snakeRow[0]][snakeCol[0]] <= S_BODY ;
					// shift the body
					for (int i = MAX_LEN-1 ; i > 0 ; i--) begin
						snakeCol[i] <= snakeCol[i-1] ;
						snakeRow[i] <= snakeRow[i-1] ;
					end
					snakeCol[0] <= nextCol ;
					snakeRow[0] <= nextRow ;

					// tail handling depends on what was eaten
					if (eatCake && length < MAX_LEN) begin
						length <= length + 6'd1 ;                       // grow
					end
					else if (eatApple && length > MIN_LEN) begin
						length <= length - 6'd1 ;                       // slim
						snakeGrid[snakeRow[length-1]][snakeCol[length-1]] <= S_EMPTY ;
						snakeGrid[snakeRow[length-2]][snakeCol[length-2]] <= S_EMPTY ;
						if (length == 6'(MIN_LEN + 1)) begin            // reached minimum -> WIN
							gameState <= ST_WIN ;
							holdCnt   <= 27'd0 ;
						end
					end
					else begin
						snakeGrid[snakeRow[length-1]][snakeCol[length-1]] <= S_EMPTY ;
					end

					snakeGrid[nextRow][nextCol] <= S_HEAD ; // wins any overlap
				end
			end
			else begin
				tickCnt <= tickCnt + 23'd1 ;
				// resolve random food placement between steps
				if (applePending && candValid) begin
					foodGrid[candRowSafe][candColSafe] <= F_APPLE ;
					applePending <= 1'b0 ;
				end
				else if (cakeSpawnPending && candValid) begin
					foodGrid[candRowSafe][candColSafe] <= F_CAKE ;
					cakeCount        <= cakeCount + 4'd1 ;
					cakeSpawnPending <= 1'b0 ;
				end
			end
		end

		// -- game over (gray) -----------------------------------------------
		ST_OVER : begin
			if (holdCnt >= RESTART_DELAY) gameState <= ST_INIT ;
			else                          holdCnt   <= holdCnt + 27'd1 ;
		end

		// -- win (cyan) -----------------------------------------------------
		ST_WIN : begin
			if (holdCnt >= WIN_HOLD) gameState <= ST_INIT ;
			else                     holdCnt   <= holdCnt + 27'd1 ;
		end

		default : gameState <= ST_INIT ;
		endcase
	end
end

// ===========================================================================
// Render
// ===========================================================================
logic [7:0] snakeColor ;
always_comb begin
	unique case (gameState)
		ST_OVER : snakeColor = COLOR_DEAD ;
		ST_WIN  : snakeColor = COLOR_WIN ;
		default : snakeColor = COLOR_BODY ;
	endcase
end

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		RGBout <= 8'h00 ;
	end
	else begin
		RGBout <= TRANSPARENT_ENCODING ;
		if (InsideRectangle) begin
			if      (snakeGrid[rowIdx][colIdx] == S_HEAD)
				RGBout <= (gameState == ST_PLAY || gameState == ST_INIT) ? COLOR_HEAD : snakeColor ;
			else if (snakeGrid[rowIdx][colIdx] == S_BODY)
				RGBout <= snakeColor ;
			else if (foodGrid [rowIdx][colIdx] == F_APPLE) RGBout <= COLOR_APPLE ;
			else if (foodGrid [rowIdx][colIdx] == F_CAKE)  RGBout <= COLOR_CAKE ;
			else                                           RGBout <= TRANSPARENT_ENCODING ;
		end
	end
end

assign drawingRequest = (RGBout != TRANSPARENT_ENCODING) ? 1'b1 : 1'b0 ;

endmodule
